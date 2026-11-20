#pragma once
#include <algorithm>
#include <chrono>
#include <condition_variable>
#include <mutex>
#include <thread>
#include <utility>

// Backend instances live exclusively on the hardware thread.
template<class Backend> class Controller {
    using Clock = std::chrono::steady_clock;
    std::mutex mutex;
    std::condition_variable cv;
    bool stop = false, dirty = false;
    int desired = -1, visible = -1, confirmed = -1;
    unsigned long long generation = 0;
    unsigned long long commandId = 0;
    std::thread thread;
    void run() {
        using namespace std::chrono_literals;
        Backend backend;
        auto next = Clock::now();
        auto settleUntil = Clock::time_point::min();
        bool settling = false;
        std::unique_lock<std::mutex> lock(mutex);
        while (!stop) {
            cv.wait_until(lock, next, [&]{ return stop || dirty; });
            if (stop) break;
            const bool setting = dirty;
            const auto version = generation;
            const int value = desired;
            dirty = false;
            lock.unlock();
            int result = -1;
            if (setting) {
                for (int attempt=0; attempt<3; ++attempt) {
                    result = backend.set(value);
                    if (result >= 0) break;
                    lock.lock();
                    if (cv.wait_for(lock, 120ms, [&]{return stop || generation != version;})) { lock.unlock(); break; }
                    lock.unlock();
                }
            } else result = backend.read();
            lock.lock();
            if (generation == version) {
                if (setting) {
                    // Even a failed write must not resurrect the value from
                    // before the newest wheel gesture. A later read can only
                    // confirm the requested value; otherwise report unknown.
                    settling = true;
                    settleUntil = Clock::now() + 5s;
                    if (result < 0) visible = -1;
                } else if (result >= 0) {
                    // A successful write may take longer than the settling window
                    // to appear in driver reads. Never republish the old value.
                    if (!settling || result == desired) {
                        confirmed = visible = result;
                        settling = false;
                    } else if (Clock::now() >= settleUntil) {
                        visible = -1;
                    }
                } else if (settling && Clock::now() >= settleUntil) {
                    visible = -1;
                } else if (!settling) {
                    visible = -1;
                }
            }
            next = Clock::now() + (settling ? 200ms : 2s);
            // Coalesce wheel events while hardware is busy; never queue obsolete values.
            if (setting && !stop) {
                auto deadline = Clock::now()+60ms;
                cv.wait_until(lock, deadline, [&]{ return stop; });
            }
        }
    }
public:
    Controller():thread([this]{run();}){}
    ~Controller(){ {std::lock_guard<std::mutex> lock(mutex); stop=true;} cv.notify_one(); thread.join(); }
    void set(int value, unsigned long long id=0) {
        std::lock_guard<std::mutex> lock(mutex);
        if (id && id <= commandId) return;
        desired=visible=std::clamp(value,5,100); ++generation; commandId=id; dirty=true; cv.notify_one();
    }
    int get(){std::lock_guard<std::mutex> lock(mutex); return visible;}
    std::pair<unsigned long long,int> snapshot(){std::lock_guard<std::mutex> lock(mutex);return {commandId,visible};}
};
