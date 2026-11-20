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

using namespace winrt;
using namespace Windows::Devices::Bluetooth;
using namespace Windows::Devices::Enumeration;
using namespace Windows::Foundation;
using namespace Windows::Foundation::Collections;

namespace {
struct Device { std::wstring id, container, name, category; bool connected=false; int battery=-1; };
std::mutex guard;
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
bool workerStop=false;
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
    try { if(props.HasKey(L"System.Devices.Aep.IsConnected"))
        return unbox_value<bool>(props.Lookup(L"System.Devices.Aep.IsConnected")); } catch(...) {}
    return false;
}
int battery(IMapView<hstring, IInspectable> const& props) {
    for(auto key:{L"{104EA319-6EE2-4701-BD47-8DDBF425BBE5} 2"}) {
        try {
            if(!props.HasKey(key)) continue;
            auto box=props.Lookup(key);
            int value=-1;
            if(auto v=box.try_as<IReference<uint8_t>>()) value=v.Value();
            else if(auto v=box.try_as<IReference<int32_t>>()) value=v.Value();
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
std::map<std::wstring,Metadata> readPnP() {
    std::map<std::wstring,Metadata> result;
    GUID bluetoothClass={0xe0cbf06c,0xcd8b,0x4647,{0xbb,0x8a,0x26,0x3b,0x43,0xf0,0xf9,0x74}};
    HDEVINFO set=SetupDiGetClassDevsW(&bluetoothClass,nullptr,nullptr,0);
    if(set==INVALID_HANDLE_VALUE) return result;
    DEVPROPKEY levelKey={ {0x104ea319,0x6ee2,0x4701,{0xbd,0x47,0x8d,0xdb,0xf4,0x25,0xbb,0xe5}}, 2 };
    SP_DEVINFO_DATA info{}; info.cbSize=sizeof(info);
    for(DWORD i=0;SetupDiEnumDeviceInfo(set,i,&info);++i) {
        wchar_t id[512]{};
        if(!SetupDiGetDeviceInstanceIdW(set,&info,id,512,nullptr)) continue;
        if(wcsncmp(id,L"BTHLE\\DEV_",10)!=0 && wcsncmp(id,L"BTHENUM\\DEV_",12)!=0) continue;
        GUID container{}; DEVPROPTYPE type=0;
        if(!SetupDiGetDevicePropertyW(set,&info,&DEVPKEY_Device_ContainerId,&type,reinterpret_cast<BYTE*>(&container),sizeof(container),nullptr,0)) continue;
        auto key=std::wstring(to_hstring(container).c_str());
        auto& meta=result[key];
        BYTE level[8]{};
        if(SetupDiGetDevicePropertyW(set,&info,&levelKey,&type,level,sizeof(level),nullptr,0)) {
            int n=type==DEVPROP_TYPE_BYTE?level[0]:type==DEVPROP_TYPE_UINT32?*reinterpret_cast<uint32_t*>(level):-1;
            if(n>=0 && n<=100) meta.battery=n;
        }
        wchar_t cats[512]{};
        if(SetupDiGetDevicePropertyW(set,&info,&DEVPKEY_DeviceContainer_Category,&type,reinterpret_cast<BYTE*>(cats),sizeof(cats),nullptr,0)) {
            auto c=normalizedCategory(cats);
            if(c!=L"Bluetooth") meta.category=c;
        }
    }
    SetupDiDestroyDeviceInfoList(set);
    return result;
}
void rebuild() {
    // Only a positive AEP connection property may claim an active connection.
    // Container IDs merge Classic and BLE endpoints of the same physical device.
    std::map<std::wstring,Device> merged;
    for(auto const& [id,d]:devices) {
        auto key=d.container.empty()?d.id:d.container;
        auto& out=merged[key];
        if(out.id.empty()) out=d;
        else {
            out.connected|=d.connected;
            if(out.name.empty() && !d.name.empty()) out.name=d.name;
            if(out.battery<0 && d.battery>=0) out.battery=d.battery;
            if(out.category==L"Bluetooth" && d.category!=L"Bluetooth") out.category=d.category;
        }
        out.id=key;
    }
    logicalDevices=merged;
    std::wstring next=L"OK:";
    for(auto const& [id,d]:merged) {
        if(d.name.empty()) continue;
        next+=hex(d.id)+L","+hex(d.name)+L","+hex(d.category)+L","+(d.connected?L"1":L"0")+L","+std::to_wstring(d.connected?d.battery:-1)+L";";
    }
    if(next!=snapshot) { snapshot=std::move(next); ++generation; }
}
void added(DeviceInformation const& info) {
    std::lock_guard lock(guard);
    auto p=info.Properties();
    Device d;
    d.id=info.Id().c_str(); d.name=info.Name().c_str();
    d.container=property(p,L"System.Devices.Aep.ContainerId");
    d.category=category(p); d.connected=connected(p); d.battery=battery(p);
    bool isConnected=d.connected;
    devices[d.id]=std::move(d); rebuild();
    if(isConnected) workerWake.notify_one();
}
void updated(DeviceInformationUpdate const& info) {
    std::lock_guard lock(guard);
    auto it=devices.find(info.Id().c_str()); if(it==devices.end()) return;
    auto p=info.Properties();
    bool wasConnected=it->second.connected;
    if(p.HasKey(L"System.Devices.Aep.IsConnected")) it->second.connected=connected(p);
    if(p.HasKey(L"{104EA319-6EE2-4701-BD47-8DDBF425BBE5} 2")) it->second.battery=battery(p);
    auto name=property(p,L"System.ItemNameDisplay"); if(!name.empty()) it->second.name=name;
    rebuild();
    if(!wasConnected && it->second.connected) workerWake.notify_one();
}
void removed(DeviceInformationUpdate const& info) {
    std::lock_guard lock(guard);
    // Keep offline devices pin-able for the duration of this Rainmeter session.
    auto it=devices.find(info.Id().c_str()); if(it!=devices.end()) { it->second.connected=false; it->second.battery=-1; rebuild(); }
}
void start() {
    try { init_apartment(apartment_type::multi_threaded); }
    catch(winrt::hresult_error const& e) { if(e.code().value!=RPC_E_CHANGED_MODE) throw; }
    auto props=single_threaded_vector<hstring>({L"System.Devices.Aep.IsConnected",L"System.Devices.Aep.ContainerId",L"System.Devices.Aep.Category",L"{104EA319-6EE2-4701-BD47-8DDBF425BBE5} 2"});
    le=DeviceInformation::CreateWatcher(BluetoothLEDevice::GetDeviceSelector(),props,DeviceInformationKind::AssociationEndpoint);
    classic=DeviceInformation::CreateWatcher(BluetoothDevice::GetDeviceSelector(),props,DeviceInformationKind::AssociationEndpoint);
    leAdded=le.Added([](auto const&, auto const& x){added(x);});
    leUpdated=le.Updated([](auto const&, auto const& x){updated(x);});
    leRemoved=le.Removed([](auto const&, auto const& x){removed(x);});
    classicAdded=classic.Added([](auto const&, auto const& x){added(x);});
    classicUpdated=classic.Updated([](auto const&, auto const& x){updated(x);});
    classicRemoved=classic.Removed([](auto const&, auto const& x){removed(x);});
    le.Start(); classic.Start();
}
void stop() {
    if(le) { le.Stop(); le.Added(leAdded); le.Updated(leUpdated); le.Removed(leRemoved); le=nullptr; }
    if(classic) { classic.Stop(); classic.Added(classicAdded); classic.Updated(classicUpdated); classic.Removed(classicRemoved); classic=nullptr; }
}
void workerLoop() {
    while(true) {
        auto metadata=readPnP();
        {
            std::lock_guard lock(guard);
            bool changed=false;
            for(auto& [id,d]:devices) {
                auto it=metadata.find(d.container);
                if(it==metadata.end()) continue;
                int level=d.connected?it->second.battery:-1;
                if(d.battery!=level) {d.battery=level; changed=true;}
                if(!it->second.category.empty() && d.category!=it->second.category) {d.category=it->second.category; changed=true;}
            }
            if(changed) rebuild();
        }
        std::unique_lock lock(workerGuard);
        workerWake.wait_for(lock,std::chrono::seconds(15));
        if(workerStop) break;
    }
}
struct Measure { std::wstring output; void* skin=nullptr; };
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
    *data=new Measure{L"",get?get(rm,1):nullptr};
    std::lock_guard lock(guard);
    if(users++==0) { try { start(); workerStop=false; worker=std::thread(workerLoop); } catch(winrt::hresult_error const& e) { snapshot=L"ERROR:"+std::to_wstring(e.code().value)+L":"+std::wstring(e.message().c_str()); ++generation; } catch(...) { snapshot=L"ERROR:unknown"; ++generation; } }
}
extern "C" __declspec(dllexport) void Reload(void*, void*, double* maxValue) { *maxValue=100; }
extern "C" __declspec(dllexport) double Update(void*) { std::lock_guard lock(guard); return (double)generation; }
extern "C" __declspec(dllexport) wchar_t const* GetString(void* data) {
    auto* m=static_cast<Measure*>(data); std::lock_guard lock(guard); m->output=snapshot; return m->output.c_str();
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
    { std::lock_guard lock(guard); auto it=logicalDevices.find(id); if(it==logicalDevices.end()) return; d=it->second; }
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
    delete static_cast<Measure*>(data);
    bool last=false;
    { std::lock_guard lock(guard); last=--users==0; }
    if(last) {
        { std::lock_guard lock(workerGuard); workerStop=true; }
        workerWake.notify_all();
        if(worker.joinable()) worker.join();
        stop();
    }
}
