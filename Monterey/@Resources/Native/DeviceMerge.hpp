#pragma once
#include <map>
#include <string>

struct Device {
    std::wstring id, container, name, category;
    bool connected=false;
    int battery=-1;
    int reportedBattery=-1;
    bool present=true;
};

inline std::map<std::wstring,Device> mergeDevices(std::map<std::wstring,Device> const& devices) {
    std::map<std::wstring,Device> merged;
    for(auto const& [id,d]:devices) {
        auto key=d.container.empty()?d.id:d.container;
        auto [it,inserted]=merged.try_emplace(key,d);
        auto& out=it->second;
        if(inserted) {
            out.id=key;
            if(!d.connected || !d.present) {out.connected=false;out.battery=-1;}
            continue;
        }
        // An offline endpoint must never supply a stale battery for an active
        // endpoint sharing its container. Prefer an available connected value.
        if(d.present && d.connected && d.battery>=0 && (out.battery<0 || !out.connected)) out.battery=d.battery;
        out.connected|=d.present && d.connected;
        if(out.name.empty() && !d.name.empty()) out.name=d.name;
        if((out.category.empty() || out.category==L"Bluetooth") && !d.category.empty()) out.category=d.category;
    }
    return merged;
}
