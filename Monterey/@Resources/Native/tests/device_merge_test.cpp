#include "DeviceMerge.hpp"
#undef NDEBUG
#include <cassert>
#include <iostream>
int main() {
    std::map<std::wstring,Device> endpoints;
    endpoints[L"a"]={L"a",L"container",L"Headset",L"Bluetooth",false,77};
    endpoints[L"b"]={L"b",L"container",L"Headset",L"Headphones",true,-1};
    auto merged=mergeDevices(endpoints);
    assert(merged.size()==1 && merged.at(L"container").connected);
    assert(merged.at(L"container").battery==-1);
    assert(merged.at(L"container").category==L"Headphones");
    endpoints[L"b"].battery=0;
    merged=mergeDevices(endpoints);
    assert(merged.at(L"container").battery==0);
    endpoints[L"b"].connected=false;
    assert(mergeDevices(endpoints).at(L"container").battery==-1);
    endpoints[L"c"]={L"c",L"",L"Mouse",L"Mouse",true,51};
    assert(mergeDevices(endpoints).size()==2);
    endpoints[L"b"].connected=true;
    endpoints[L"b"].present=false;
    assert(!mergeDevices(endpoints).at(L"container").connected);
    std::cout << "PASS: endpoint merge, offline battery, zero charge, categories, missing container\n";
}
