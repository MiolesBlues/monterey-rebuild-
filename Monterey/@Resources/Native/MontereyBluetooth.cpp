#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Devices.Bluetooth.h>
#include <winrt/Windows.Devices.Enumeration.h>
#include <windows.h>
#include <setupapi.h>
#define INITGUID
#include <devpkey.h>
#include <algorithm>
#include <condition_variable>
#include <map>
#include <mutex>
#include <string>
#include <thread>
#include <vector>
#include <memory>
#include <cstring>
#include <cwctype>
#include "DeviceMerge.hpp"

using namespace winrt;
using namespace Windows::Devices::Bluetooth;
using namespace Windows::Devices::Enumeration;
using namespace Windows::Foundation;
using namespace Windows::Foundation::Collections;

namespace {
std::mutex lifecycleGuard;
bool accepting=false, snapshotDirty=false;
std::mutex snapshotGuard;
std::map<std::wstring, Device> devices;
std::map<std::wstring, Device> logicalDevices;
std::wstring snapshot=L"OK:";
uint64_t generation=0;
int users=0;
DeviceWatcher le{nullptr}, classic{nullptr};
event_token leAdded{}, leUpdated{}, leRemoved{}, classicAdded{}, classicUpdated{}, classicRemoved{};
std::mutex workerGuard;
std::condition_variable workerWake;
std::thread worker;
bool workerStop=false, workerPending=false, metadataPending=false;
struct Metadata { int battery=-1; std::wstring category; };

std::wstring hex(std::wstring const& value) {
    int n=WideCharToMultiByte(CP_UTF8,0,value.c_str(),(int)value.size(),nullptr,0,nullptr,nullptr);
    std::string bytes(n,'\0');
    if(n) WideCharToMultiByte(CP_UTF8,0,value.c_str(),(int)value.size(),bytes.data(),n,nullptr,nullptr);
    static wchar_t const* digits=L"0123456789ABCDEF";
    std::wstring result; result.reserve(bytes.size()*2);
    for(unsigned char b:bytes) { result.push_back(digits[b>>4]); result.push_back(digits[b&15]); }
    return result;
}

std::wstring property(IMapView<hstring, IInspectable> const& props, wchar_t const* key) {
    try { if(props.HasKey(key)) {
        auto box=props.Lookup(key);
        if(auto value=box.try_as<IReference<guid>>()) return to_hstring(value.Value()).c_str();
        if(auto value=box.try_as<IReference<hstring>>()) return value.Value().c_str();
        if(auto values=box.try_as<IVectorView<hstring>>()) {
            std::wstring result; for(auto const& v:values) { if(!result.empty()) result+=L","; result+=v.c_str(); } return result;
        }
        return unbox_value<hstring>(box).c_str();
    } } catch(...) {}
    return L"";
}
bool connected(IMapView<hstring, IInspectable> const& props) {
    try {
        if(props.HasKey(L"System.Devices.Aep.IsPresent") &&
           !unbox_value<bool>(props.Lookup(L"System.Devices.Aep.IsPresent"))) return false;
        if(props.HasKey(L"System.Devices.Aep.IsConnected"))
            return unbox_value<bool>(props.Lookup(L"System.Devices.Aep.IsConnected"));
    } catch(...) {}
    return false;
}
int battery(IMapView<hstring, IInspectable> const& props) {
    for(auto key:{L"{104EA319-6EE2-4701-BD47-8DDBF425BBE5} 2"}) {
        try {
            if(!props.HasKey(key)) continue;
            auto box=props.Lookup(key);
            int value=-1;
            if(auto v=box.try_as<IReference<uint8_t>>()) value=v.Value();
            else if(auto integer=box.try_as<IReference<int32_t>>()) value=integer.Value();
            if(value>=0 && value<=100) return value;
        } catch(...) {}
    }
    return -1;
}
std::wstring category(IMapView<hstring, IInspectable> const& props) {
    auto value=property(props,L"System.Devices.Aep.Category");
    if(value.find(L"Phone")!=std::wstring::npos) return L"Phone";
    if(value.find(L"Mouse")!=std::wstring::npos) return L"Mouse";
    if(value.find(L"Head")!=std::wstring::npos) return L"Headphones";
    return L"Bluetooth";
}
std::wstring normalizedCategory(std::wstring const& value) {
    if(value.find(L"Phone")!=std::wstring::npos) return L"Phone";
    if(value.find(L"Mouse")!=std::wstring::npos) return L"Mouse";
    if(value.find(L"Head")!=std::wstring::npos || value.find(L"Audio")!=std::wstring::npos) return L"Headphones";
    return L"Bluetooth";
}
std::wstring containerKey(std::wstring key) {
    std::transform(key.begin(),key.end(),key.begin(),[](wchar_t c){return (wchar_t)towlower(c);});
    if(key==L"{00000000-0000-0000-0000-000000000000}") key.clear();
    return key;
}
void requestRefresh(bool metadata=false) {
    { std::lock_guard lock(workerGuard); workerPending=true; metadataPending|=metadata; }
    workerWake.notify_one();
}
struct PnPDeleter { void operator()(void* set) const noexcept { SetupDiDestroyDeviceInfoList(set); } };
std::map<std::wstring,Metadata> readPnP() {
    std::map<std::wstring,Metadata> result;
    GUID bluetoothClass={0xe0cbf06c,0xcd8b,0x4647,{0xbb,0x8a,0x26,0x3b,0x43,0xf0,0xf9,0x74}};
    HDEVINFO set=SetupDiGetClassDevsW(&bluetoothClass,nullptr,nullptr,DIGCF_PRESENT);
    if(set==INVALID_HANDLE_VALUE) return result;
    std::unique_ptr<void,PnPDeleter> cleanup(set);
    DEVPROPKEY levelKey={ {0x104ea319,0x6ee2,0x4701,{0xbd,0x47,0x8d,0xdb,0xf4,0x25,0xbb,0xe5}}, 2 };
    SP_DEVINFO_DATA info{}; info.cbSize=sizeof(info);
    for(DWORD i=0;SetupDiEnumDeviceInfo(set,i,&info);++i) {
        wchar_t id[512]{};
        if(!SetupDiGetDeviceInstanceIdW(set,&info,id,512,nullptr)) continue;
        if(wcsncmp(id,L"BTHLE\\DEV_",10)!=0 && wcsncmp(id,L"BTHENUM\\DEV_",12)!=0) continue;
        GUID container{}; DEVPROPTYPE type=0;
        if(!SetupDiGetDevicePropertyW(set,&info,&DEVPKEY_Device_ContainerId,&type,reinterpret_cast<BYTE*>(&container),sizeof(container),nullptr,0)) continue;
        auto key=containerKey(to_hstring(container).c_str());
        if(key.empty()) continue;
        auto& meta=result[key];
        BYTE level[8]{};
        if(SetupDiGetDevicePropertyW(set,&info,&levelKey,&type,level,sizeof(level),nullptr,0)) {
            uint32_t number=0; std::memcpy(&number,level,sizeof(number));
            int n=type==DEVPROP_TYPE_BYTE?level[0]:type==DEVPROP_TYPE_UINT32?static_cast<int>(number):-1;
            if(n>=0 && n<=100) meta.battery=n;
        }
        wchar_t cats[512]{};
        if(SetupDiGetDevicePropertyW(set,&info,&DEVPKEY_DeviceContainer_Category,&type,reinterpret_cast<BYTE*>(cats),sizeof(cats),nullptr,0)) {
            auto c=normalizedCategory(cats);
            if(c!=L"Bluetooth") meta.category=c;
        }
    }
    return result;
}
void rebuild() {
    // Only a positive AEP connection property may claim an active connection.
    // Container IDs merge Classic and BLE endpoints of the same physical device.
    auto merged=mergeDevices(devices);
    logicalDevices=merged;
    std::wstring next=L"OK:";
    for(auto const& [id,d]:merged) {
        if(d.name.empty()) continue;
        next+=hex(d.id)+L","+hex(d.name)+L","+hex(d.category)+L","+(d.connected?L"1":L"0")+L","+std::to_wstring(d.connected?d.battery:-1)+L";";
    }
    if(next!=snapshot) { snapshot=std::move(next); ++generation; }
}
void added(DeviceInformation const& info) {
    auto p=info.Properties();
    Device d;
    d.id=info.Id().c_str(); d.name=info.Name().c_str();
    d.container=containerKey(property(p,L"System.Devices.Aep.ContainerId"));
    d.category=category(p); d.connected=connected(p); d.battery=d.reportedBattery=battery(p);
    try { if(p.HasKey(L"System.Devices.Aep.IsPresent")) d.present=unbox_value<bool>(p.Lookup(L"System.Devices.Aep.IsPresent")); } catch(...) {}
    if(!d.present) d.connected=false;
    bool needsMetadata=d.connected;
    { std::lock_guard lock(snapshotGuard);
      if(!accepting) return;
      devices[d.id]=std::move(d); snapshotDirty=true; }
    requestRefresh(needsMetadata);
}
void updated(DeviceInformationUpdate const& info) {
    std::lock_guard lock(snapshotGuard);
    if(!accepting) return;
    auto it=devices.find(info.Id().c_str()); if(it==devices.end()) return;
    auto p=info.Properties();
    bool wasConnected=it->second.connected;
    try { if(p.HasKey(L"System.Devices.Aep.IsPresent")) it->second.present=unbox_value<bool>(p.Lookup(L"System.Devices.Aep.IsPresent")); } catch(...) {}
    if(p.HasKey(L"System.Devices.Aep.IsConnected")) it->second.connected=connected(p);
    if(!it->second.present) it->second.connected=false;
    if(p.HasKey(L"{104EA319-6EE2-4701-BD47-8DDBF425BBE5} 2")) it->second.battery=it->second.reportedBattery=battery(p);
    if(p.HasKey(L"System.Devices.Aep.ContainerId")) it->second.container=containerKey(property(p,L"System.Devices.Aep.ContainerId"));
    if(p.HasKey(L"System.Devices.Aep.Category")) it->second.category=category(p);
    if(!it->second.connected) it->second.battery=-1;
    auto name=property(p,L"System.ItemNameDisplay"); if(!name.empty()) it->second.name=name;
    snapshotDirty=true;
    requestRefresh(!wasConnected && it->second.connected);
}
void removed(DeviceInformationUpdate const& info) {
    std::lock_guard lock(snapshotGuard);
    if(!accepting) return;
    // Keep offline devices pin-able for the duration of this Rainmeter session.
    auto it=devices.find(info.Id().c_str()); if(it!=devices.end()) { it->second.connected=false; it->second.battery=-1; snapshotDirty=true; requestRefresh(); }
}
void start() {
    auto props=single_threaded_vector<hstring>({L"System.Devices.Aep.IsConnected",L"System.Devices.Aep.IsPresent",L"System.Devices.Aep.ContainerId",L"System.Devices.Aep.Category",L"{104EA319-6EE2-4701-BD47-8DDBF425BBE5} 2"});
    le=DeviceInformation::CreateWatcher(BluetoothLEDevice::GetDeviceSelector(),props,DeviceInformationKind::AssociationEndpoint);
    classic=DeviceInformation::CreateWatcher(BluetoothDevice::GetDeviceSelector(),props,DeviceInformationKind::AssociationEndpoint);
    leAdded=le.Added([](auto const&, auto const& x){try { added(x); } catch(...) {}});
    leUpdated=le.Updated([](auto const&, auto const& x){try { updated(x); } catch(...) {}});
    leRemoved=le.Removed([](auto const&, auto const& x){try { removed(x); } catch(...) {}});
    classicAdded=classic.Added([](auto const&, auto const& x){try { added(x); } catch(...) {}});
    classicUpdated=classic.Updated([](auto const&, auto const& x){try { updated(x); } catch(...) {}});
    classicRemoved=classic.Removed([](auto const&, auto const& x){try { removed(x); } catch(...) {}});
    le.Start(); classic.Start();
}
// Stop is asynchronous. Drain watcher callbacks before the module can unload.
void stopWatcher(DeviceWatcher& watcher,event_token a,event_token u,event_token r) {
    if(!watcher) return;
    watcher.Added(a); watcher.Updated(u); watcher.Removed(r);
    auto status=watcher.Status();
    if(status==DeviceWatcherStatus::Started || status==DeviceWatcherStatus::EnumerationCompleted) watcher.Stop();
    while(watcher.Status()==DeviceWatcherStatus::Stopping)
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
    watcher=nullptr;
}
void stop() {
    { std::lock_guard lock(snapshotGuard); accepting=false; }
    stopWatcher(le,leAdded,leUpdated,leRemoved);
    stopWatcher(classic,classicAdded,classicUpdated,classicRemoved);
}
bool healthy(DeviceWatcher const& watcher) {
    if(!watcher) return false;
    auto status=watcher.Status();
    return status==DeviceWatcherStatus::Started || status==DeviceWatcherStatus::EnumerationCompleted;
}
void workerLoop() {
    // Apartment, watchers and SetupAPI all belong to this single shared worker.
    try {
        init_apartment(apartment_type::multi_threaded);
        struct Apartment {
            ~Apartment(){
                // Cached activation factories cannot outlive the last COM
                // apartment when Rainmeter repeatedly unloads/reloads the DLL.
                clear_factory_cache();
                uninit_apartment();
            }
        } apartment;
        struct WatcherShutdown {
            ~WatcherShutdown(){try {stop();} catch(...) {}}
        } shutdown;
        auto nextMetadata=std::chrono::steady_clock::time_point::min();
        bool firstSnapshotPublished=false;
        for(;;) {
            bool scanMetadata=false, active=false;
            { std::lock_guard lock(workerGuard); if(workerStop) break;
              workerPending=false; scanMetadata=metadataPending; metadataPending=false; }
            try {
                if(!healthy(le) || !healthy(classic)) {
                    stop();
                    { std::lock_guard lock(snapshotGuard);
                      for(auto& [id,d]:devices) { d.connected=false; d.battery=-1; }
                      rebuild(); accepting=true; }
                    start();
                }
                { std::lock_guard lock(snapshotGuard); for(auto const& [id,d]:devices) active|=d.connected; }
                // Events request fresh metadata; polling is only a battery
                // fallback for connected devices whose driver sends no level event.
                if(active && (scanMetadata || std::chrono::steady_clock::now()>=nextMetadata)) {
                    auto metadata=readPnP();
                    nextMetadata=std::chrono::steady_clock::now()+std::chrono::seconds(15);
                    std::lock_guard lock(snapshotGuard);
                    bool changed=false;
                    for(auto& [id,d]:devices) {
                        auto it=metadata.find(d.container);
                        int level=!d.connected?-1:it!=metadata.end() && it->second.battery>=0?it->second.battery:d.reportedBattery;
                        // Do not discard a valid AEP level when SetupAPI has none.
                        if(d.battery!=level) {d.battery=level; changed=true;}
                        if(it!=metadata.end() && !it->second.category.empty() && d.category!=it->second.category) {
                            d.category=it->second.category; changed=true;
                        }
                    }
                    if(changed) snapshotDirty=true;
                }
                { std::lock_guard lock(snapshotGuard); if(snapshotDirty) {
                    rebuild(); snapshotDirty=false;
                    firstSnapshotPublished=firstSnapshotPublished || !devices.empty();
                } }
            } catch(winrt::hresult_error const& e) {
                stop();
                std::lock_guard lock(snapshotGuard);
                for(auto& [id,d]:devices) {d.connected=false; d.battery=-1;}
                rebuild();
                active=false;
                OutputDebugStringW(e.message().c_str());
            }
            std::unique_lock lock(workerGuard);
            auto nextWake=std::chrono::steady_clock::now()+std::chrono::seconds(15);
            if(active && nextMetadata<nextWake) nextWake=nextMetadata;
            workerWake.wait_until(lock,nextWake,[]{return workerStop || workerPending;});
            if(workerStop) break;
            // Coalesce connection bursts without losing a shutdown notification.
            if(workerPending) workerWake.wait_for(lock,
                std::chrono::milliseconds(firstSnapshotPublished ? 100 : 5),[]{return workerStop;});
            if(workerStop) break;
        }
        stop();
    } catch(...) {
        try {stop();} catch(...) {}
        std::lock_guard lock(snapshotGuard);
        for(auto& [id,d]:devices) {d.connected=false;d.battery=-1;}
        rebuild();
    }
}
struct Measure { std::wstring output; void* skin=nullptr; uint64_t copied=UINT64_MAX; };
std::wstring safe(std::wstring value) {
    for(auto& ch:value) if(ch==L'"') ch=L'\''; else if(ch==L'[') ch=L'('; else if(ch==L']') ch=L')';
    return value;
}
void setOption(void* rm,std::wstring const& meter,std::wstring const& field,std::wstring const& value) {
    using Execute=void(*)(void*,wchar_t const*);
    static auto execute=reinterpret_cast<Execute>(GetProcAddress(GetModuleHandleW(L"Rainmeter.dll"),"RmExecute"));
    if(execute) {
        auto bang=L"!SetOption \""+meter+L"\" \""+field+L"\" \""+safe(value)+L"\"";
        execute(rm,bang.c_str());
    }
}
}

extern "C" __declspec(dllexport) void Initialize(void** data, void* rm) {
    using Get=void*(*)(void*,int);
    static auto get=reinterpret_cast<Get>(GetProcAddress(GetModuleHandleW(L"Rainmeter.dll"),"RmGet"));
    *data=nullptr;
    try {*data=new Measure{L"",get?get(rm,1):nullptr};} catch(...) {return;}
    std::lock_guard lifecycle(lifecycleGuard);
    if(users++==0) {
        { std::lock_guard lock(snapshotGuard); devices.clear(); logicalDevices.clear(); snapshot=L"OK:"; ++generation; }
        { std::lock_guard lock(workerGuard); workerStop=false; workerPending=false; metadataPending=false; }
        try { worker=std::thread(workerLoop); }
        catch(...) {std::lock_guard lock(snapshotGuard); snapshot=L"ERROR:thread"; ++generation;}
    }
}
extern "C" __declspec(dllexport) void Reload(void*, void*, double* maxValue) { *maxValue=100; }
extern "C" __declspec(dllexport) double Update(void*) { std::lock_guard lock(snapshotGuard); return (double)generation; }
extern "C" __declspec(dllexport) wchar_t const* GetString(void* data) {
    if(!data) return L"OK:";
    auto* m=static_cast<Measure*>(data); std::lock_guard lock(snapshotGuard); if(m->copied!=generation) {m->output=snapshot; m->copied=generation;} return m->output.c_str();
}
extern "C" __declspec(dllexport) void ExecuteBang(void* data, wchar_t const* args) {
    auto* measure=static_cast<Measure*>(data); if(!measure || !measure->skin || !args) return;
    std::wstring command(args);
    auto first=command.find(L'|'); if(first==std::wstring::npos) return;
    auto second=command.find(L'|',first+1); if(second==std::wstring::npos) return;
    auto third=command.find(L'|',second+1);
    auto operation=command.substr(0,first);
    auto slot=command.substr(first+1,second-first-1);
    auto id=command.substr(second+1,third==std::wstring::npos?std::wstring::npos:third-second-1);
    auto suffix=third==std::wstring::npos?L"":command.substr(third+1);
    if(slot.size()!=1 || slot[0]<L'1' || slot[0]>L'6') return;
    Device d;
    { std::lock_guard lock(snapshotGuard); auto it=logicalDevices.find(id); if(it==logicalDevices.end()) return; d=it->second; }
    if(operation==L"MAIN") {
        setOption(measure->skin,L"Option"+slot+L"Title",L"Text",L"Resource "+slot+L"    "+d.name+L" -> "+suffix);
    } else if(operation==L"PICK") {
        setOption(measure->skin,L"Option3Title",L"Text",L"Pinned device    "+d.name);
    } else if(operation==L"NAME" || operation==L"DETAIL") {
        auto status=d.connected?L"Connected":L"Disconnected";
        auto level=d.connected && d.battery>=0?std::to_wstring(d.battery)+L"%":L"Battery unavailable";
        auto info=d.name+L" | "+d.category+L" | "+status+L" | "+level;
        if(!suffix.empty()) info+=L" | Resource "+suffix;
        auto compact=d.category+L" | "+(d.connected?L"Connected":L"Offline")+L" | "+(d.connected && d.battery>=0?std::to_wstring(d.battery)+L"%":L"--");
        if(!suffix.empty()) compact+=L" | R"+suffix;
        setOption(measure->skin,L"Option"+slot+L"Title",L"Text",operation==L"NAME"?d.name:compact);
        setOption(measure->skin,L"Option"+slot+L"Title",L"ToolTipText",info);
        setOption(measure->skin,L"Option"+slot+L"Value",L"ToolTipText",info);
    } else if(operation==L"CELL") {
        auto info=d.name+(d.battery<0?L", battery unavailable":L", "+std::to_wstring(d.battery)+L"%");
        for(auto prefix:{L"MeterImage",L"MeterMeter",L"MeterText",L"MeterValue"})
            setOption(measure->skin,std::wstring(prefix)+slot,L"ToolTipText",info);
        setOption(measure->skin,L"MeterText"+slot,L"Text",d.name);
    }
}
extern "C" __declspec(dllexport) void Finalize(void* data) {
    if(!data) return;
    delete static_cast<Measure*>(data);
    std::lock_guard lifecycle(lifecycleGuard);
    if(--users==0) {
        { std::lock_guard lock(workerGuard); workerStop=true; }
        workerWake.notify_all();
        if(worker.joinable()) worker.join();
    }
}
