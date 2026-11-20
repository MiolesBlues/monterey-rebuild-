#include "Controller.hpp"
#include <atomic>
#undef NDEBUG
#include <cassert>
#include <iostream>
using namespace std::chrono_literals;
struct Mock {
    static inline std::atomic<int> applied{45}, writes{0};
    static inline std::atomic<bool> fail{false}, stale{false}, unavailable{false};
    static inline std::atomic<int> staleValue{45};
    int read(){return unavailable?-1:stale?staleValue.load():applied.load();}
    int set(int n){++writes;std::this_thread::sleep_for(180ms);if(fail)return -1;applied=n;return n;}
};
int main(){
    Controller<Mock> ctl;
    for(int i=0;i<100&&ctl.get()!=45;++i)std::this_thread::sleep_for(10ms);
    assert(ctl.get()==45);
    ctl.set(48);std::this_thread::sleep_for(20ms);
    for(int i=50;i<=90;i+=2){ctl.set(i);assert(ctl.get()==i);}
    std::this_thread::sleep_for(850ms);assert(ctl.get()==90&&Mock::applied==90&&Mock::writes<=3);
    Mock::fail=true;ctl.set(70);assert(ctl.get()==70);
    std::this_thread::sleep_for(1100ms);assert(ctl.get()==-1);
    Mock::fail=false;ctl.set(64);std::this_thread::sleep_for(500ms);assert(ctl.get()==64&&Mock::applied==64);
    Mock::stale=true;ctl.set(88,42);
    for(int i=0;i<35;++i){std::this_thread::sleep_for(100ms);assert(ctl.snapshot()==std::make_pair(42ULL,88));}
    Mock::stale=false;std::this_thread::sleep_for(400ms);assert(ctl.get()==88);
    Mock::applied=31;std::this_thread::sleep_for(2300ms);assert(ctl.get()==31);
    ctl.set(55,43); ctl.set(12,42); assert(ctl.snapshot()==std::make_pair(43ULL,55));
    std::this_thread::sleep_for(600ms); assert(Mock::applied==55);
    Mock::unavailable=true; std::this_thread::sleep_for(2300ms); assert(ctl.get()==-1);
    Mock::unavailable=false; std::this_thread::sleep_for(2300ms); assert(ctl.get()==55);
    // Regression: a slow driver still reports 100 for more than five seconds
    // after rapid wheel input down to 60. The slider must never show 100 again.
    Mock::applied=100; std::this_thread::sleep_for(2300ms); assert(ctl.get()==100);
    Mock::staleValue=100; Mock::stale=true;
    unsigned long long wheelId=100;
    for(int n=98;n>=60;n-=2) ctl.set(n,++wheelId);
    for(int i=0;i<70;++i){
        std::this_thread::sleep_for(100ms);
        assert(ctl.get()!=100);
    }
    Mock::stale=false;
    for(int i=0;i<30 && ctl.get()!=60;++i) std::this_thread::sleep_for(100ms);
    assert(ctl.get()==60);
    Mock::fail=true;
    ctl.set(40,++wheelId);
    std::this_thread::sleep_for(1100ms);
    assert(ctl.get()!=100 && ctl.get()!=60);
    Mock::fail=false;
    ctl.set(38,++wheelId);
    for(int i=0;i<30 && ctl.get()!=38;++i) std::this_thread::sleep_for(100ms);
    assert(ctl.get()==38);
    std::cout<<"PASS: immediate input, coalescing, stale acknowledgement, retry and recovery\n";
}
