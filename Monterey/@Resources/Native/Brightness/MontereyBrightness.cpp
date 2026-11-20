#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <wbemidl.h>
#include <oleauto.h>
#include <wrl/client.h>
#include <physicalmonitorenumerationapi.h>
#include <highlevelmonitorconfigurationapi.h>
#include <cwchar>
#include <string>
#include <vector>
#include "Controller.hpp"
using Microsoft::WRL::ComPtr;

struct Bstr {
    BSTR p;
    explicit Bstr(const wchar_t* s):p(SysAllocString(s)){}
    ~Bstr(){SysFreeString(p);}
    operator BSTR() const {return p;}
};
struct Var {
    VARIANT v;
    Var(){VariantInit(&v);}
    ~Var(){VariantClear(&v);}
    int number() const {
        switch(v.vt){case VT_UI1:return v.bVal;case VT_I4:return v.lVal;case VT_UI4:return static_cast<int>(v.ulVal);case VT_I2:return v.iVal;case VT_UI2:return v.uiVal;default:return -1;}
    }
};
class Backend {
    HRESULT apartment = CoInitializeEx(nullptr,COINIT_MULTITHREADED);
    ComPtr<IWbemServices> svc;
    ComPtr<IWbemClassObject> input;
    std::wstring brightnessPath, methodPath;
    bool ddc = false;
    bool internalSelected = false;
    HMONITOR selectedMonitor = nullptr;
    ComPtr<IWbemClassObject> first(const wchar_t* query, const std::wstring* instance=nullptr) {
        ComPtr<IEnumWbemClassObject> rows;
        if(FAILED(svc->ExecQuery(Bstr(L"WQL"),Bstr(query),WBEM_FLAG_FORWARD_ONLY|WBEM_FLAG_RETURN_IMMEDIATELY,nullptr,rows.GetAddressOf())))return {};
        for(;;){
            ComPtr<IWbemClassObject> row; ULONG count=0;
            if(FAILED(rows->Next(1000,1,row.GetAddressOf(),&count))||!count)return {};
            if(!instance)return row;
            Var name; if(SUCCEEDED(row->Get(L"InstanceName",0,&name.v,nullptr,nullptr))&&name.v.vt==VT_BSTR&&name.v.bstrVal&&*instance==name.v.bstrVal)return row;
        }
    }
    static std::wstring str(IWbemClassObject* obj,const wchar_t* key){
        Var v; if(!obj||FAILED(obj->Get(key,0,&v.v,nullptr,nullptr))||v.v.vt!=VT_BSTR||!v.v.bstrVal)return {};return v.v.bstrVal;
    }
    void reset(){input.Reset();svc.Reset();brightnessPath.clear();methodPath.clear();}
    bool connect(){
        if(svc&&input)return true;
        reset(); if(FAILED(apartment))return false;
        ComPtr<IWbemLocator> loc;
        if(FAILED(CoCreateInstance(CLSID_WbemLocator,nullptr,CLSCTX_INPROC_SERVER,IID_PPV_ARGS(loc.GetAddressOf()))))return false;
        if(FAILED(loc->ConnectServer(Bstr(L"ROOT\\WMI"),nullptr,nullptr,nullptr,WBEM_FLAG_CONNECT_USE_MAX_WAIT,nullptr,nullptr,svc.GetAddressOf())))return false;
        if(FAILED(CoSetProxyBlanket(svc.Get(),RPC_C_AUTHN_WINNT,RPC_C_AUTHZ_NONE,nullptr,RPC_C_AUTHN_LEVEL_CALL,RPC_C_IMP_LEVEL_IMPERSONATE,nullptr,EOAC_NONE)))return false;
        auto display=first(L"SELECT * FROM WmiMonitorBrightness WHERE Active = TRUE");
        if(!display)return false;
        auto name=str(display.Get(),L"InstanceName"); brightnessPath=str(display.Get(),L"__RELPATH");
        if(name.empty()||brightnessPath.empty())return false;
        auto method=first(L"SELECT * FROM WmiMonitorBrightnessMethods",&name);
        methodPath=str(method.Get(),L"__RELPATH"); if(methodPath.empty())return false;
        ComPtr<IWbemClassObject> cls,signature;
        if(FAILED(svc->GetObject(Bstr(L"WmiMonitorBrightnessMethods"),0,nullptr,cls.GetAddressOf(),nullptr)))return false;
        if(FAILED(cls->GetMethod(L"WmiSetBrightness",0,signature.GetAddressOf(),nullptr)))return false;
        return SUCCEEDED(signature->SpawnInstance(0,input.GetAddressOf()));
    }
    int wmi(int value){
        if(!connect())return -1;
        if(value<0){ComPtr<IWbemClassObject> obj; Var current;
            if(FAILED(svc->GetObject(Bstr(brightnessPath.c_str()),0,nullptr,obj.GetAddressOf(),nullptr))||FAILED(obj->Get(L"CurrentBrightness",0,&current.v,nullptr,nullptr)))return -1;
            return current.number();}
        Var timeout, brightness, result; timeout.v.vt=VT_I4; timeout.v.lVal=0; brightness.v.vt=VT_UI1; brightness.v.bVal=static_cast<BYTE>(value);
        if(FAILED(input->Put(L"Timeout",0,&timeout.v,0))||FAILED(input->Put(L"Brightness",0,&brightness.v,0)))return -1;
        ComPtr<IWbemClassObject> output;
        if(FAILED(svc->ExecMethod(Bstr(methodPath.c_str()),Bstr(L"WmiSetBrightness"),0,nullptr,input.Get(),output.GetAddressOf(),nullptr))||!output||FAILED(output->Get(L"ReturnValue",0,&result.v,nullptr,nullptr)))return -1;
        return result.number()==0?value:-1;
    }
    struct DdcRequest {int value,result=-1; HMONITOR selected=nullptr,found=nullptr;};
    static BOOL CALLBACK enumerate(HMONITOR h,HDC,LPRECT,LPARAM data){
        auto& r=*reinterpret_cast<DdcRequest*>(data); DWORD count=0;
        if(r.selected && h!=r.selected) return TRUE;
        if(!GetNumberOfPhysicalMonitorsFromHMONITOR(h,&count)||!count||count>32)return TRUE;
        std::vector<PHYSICAL_MONITOR> monitors(count);
        if(!GetPhysicalMonitorsFromHMONITOR(h,count,monitors.data()))return TRUE;
        struct PhysicalHandles {
            std::vector<PHYSICAL_MONITOR>& items;
            ~PhysicalHandles(){DestroyPhysicalMonitors(static_cast<DWORD>(items.size()),items.data());}
        } cleanup{monitors};
        for(auto& m:monitors){DWORD lo,cur,hi;
            if(!GetMonitorBrightness(m.hPhysicalMonitor,&lo,&cur,&hi)||hi<=lo)continue;
            if(r.value<0){r.result=static_cast<int>(100.0*(cur-lo)/(hi-lo)+0.5);break;}
            DWORD scaled=lo+static_cast<DWORD>((hi-lo)*r.value/100.0+0.5);
            if(SetMonitorBrightness(m.hPhysicalMonitor,scaled)){r.result=r.value;break;}
        }
        if(r.result>=0) r.found=h;
        return r.result<0;
    }
    int access(int value){
        // Preserve internal-panel priority. Once selected, do not switch to an external monitor on a transient write error.
        if(!ddc){int result=wmi(value);if(result>=0){internalSelected=true;return result;}reset();if(internalSelected)return -1;
            if(value>=0)return -1;}
        DdcRequest r{value,-1,selectedMonitor};
        EnumDisplayMonitors(nullptr,nullptr,enumerate,reinterpret_cast<LPARAM>(&r));
        // Re-select on a read after topology changes. A failed write must never
        // spill onto a different physical monitor.
        if(r.result<0 && value<0 && selectedMonitor) {
            r.selected=nullptr;
            EnumDisplayMonitors(nullptr,nullptr,enumerate,reinterpret_cast<LPARAM>(&r));
        }
        if(r.result>=0){ddc=true;selectedMonitor=r.found;}
        return r.result;
    }
public:
    ~Backend(){reset();if(SUCCEEDED(apartment))CoUninitialize();}
    int read(){return access(-1);}
    int set(int value){return access(value);}
};
using PluginController=Controller<Backend>;
struct Measure { PluginController controller; std::wstring snapshot=L"0 -1"; std::pair<unsigned long long,int> previous{0,-1}; };
extern "C" {
__declspec(dllexport) void Initialize(void** data,void*){*data=nullptr;try{*data=new Measure;}catch(...){}}
__declspec(dllexport) void Reload(void*,void*,double* maxValue){*maxValue=100;}
__declspec(dllexport) double Update(void* data){if(!data)return -1;auto& m=*static_cast<Measure*>(data);auto s=m.controller.snapshot();if(s!=m.previous){m.snapshot=std::to_wstring(s.first)+L" "+std::to_wstring(s.second);m.previous=s;}return s.second;}
__declspec(dllexport) const wchar_t* GetString(void* data){return data?static_cast<Measure*>(data)->snapshot.c_str():L"0 -1";}
__declspec(dllexport) void ExecuteBang(void* data,const wchar_t* args){if(!data||!args||wcsncmp(args,L"Set ",4)!=0)return;wchar_t* end=nullptr;auto id=wcstoull(args+4,&end,10);if(end==args+4||*end!=L' ')return;const wchar_t* start=end+1;long n=wcstol(start,&end,10);if(end==start||*end||n<0||n>100)return;static_cast<Measure*>(data)->controller.set(static_cast<int>(n),id);}
__declspec(dllexport) void Finalize(void* data){delete static_cast<Measure*>(data);}
}
