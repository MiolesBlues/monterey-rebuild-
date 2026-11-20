"""Read-only native plugin lifecycle/latency probe, never changes brightness."""
import argparse
import ctypes as c
import json
import statistics
import time
from pathlib import Path
import psutil

def summary(values):
    if not values:
        return {'count':0,'median_ms':None,'max_ms':None}
    return {'count':len(values),'median_ms':statistics.median(values),'max_ms':max(values)}

def run(path,cycles,idle_seconds=0,snapshot_timeout=2):
    if cycles<1 or snapshot_timeout<0:
        raise ValueError('cycles must be positive and snapshot timeout nonnegative')
    process=psutil.Process()
    library=c.CDLL(str(path.resolve()))
    library.Initialize.argtypes=[c.POINTER(c.c_void_p),c.c_void_p]
    library.Reload.argtypes=[c.c_void_p,c.c_void_p,c.POINTER(c.c_double)]
    library.Update.argtypes=[c.c_void_p]; library.Update.restype=c.c_double
    library.GetString.argtypes=[c.c_void_p]; library.GetString.restype=c.c_wchar_p
    library.Finalize.argtypes=[c.c_void_p]
    init_times=[]; first_init_times=[]; reload_times=[]; final_times=[]; last_final_times=[]
    first_snapshot_times=[]; first_generation_times=[]; latencies=[]; thread_samples=[]
    snapshot_timeouts=0
    bluetooth='Bluetooth' in path.name
    initial_threads=process.num_threads()
    cpu_before=process.cpu_times(); memory_before=process.memory_info(); io_before=process.io_counters()
    start=time.perf_counter(); rows=0
    for cycle in range(cycles):
        measures=[]
        cycle_start=time.perf_counter()
        for index in range(6 if bluetooth else 1):
            data=c.c_void_p(); begin=time.perf_counter()
            library.Initialize(c.byref(data),None)
            elapsed_ms=(time.perf_counter()-begin)*1000
            init_times.append(elapsed_ms)
            if index==0: first_init_times.append(elapsed_ms)
            assert data.value; measures.append(data)
            max_value=c.c_double()
            begin=time.perf_counter(); library.Reload(data,None,c.byref(max_value))
            reload_times.append((time.perf_counter()-begin)*1000)
            assert max_value.value==100
        initial_generation=library.Update(measures[0]) if bluetooth else None
        deadline=time.perf_counter()+snapshot_timeout
        ready=False; generation_seen=False
        while True:
            value=library.Update(measures[0]); raw=library.GetString(measures[0])
            assert raw is not None
            if bluetooth:
                assert raw.startswith('OK:'),raw[:30]
                current_rows=sum(bool(row) for row in raw[3:].split(';'))
                if value!=initial_generation and not generation_seen:
                    first_generation_times.append((time.perf_counter()-cycle_start)*1000)
                    generation_seen=True
                ready=current_rows>0
                if ready: rows=current_rows
            else:
                ready=value>=0
            if ready:
                first_snapshot_times.append((time.perf_counter()-cycle_start)*1000)
                break
            if time.perf_counter()>=deadline:
                snapshot_timeouts+=1
                break
            time.sleep(0.01)
        idle=None
        if idle_seconds:
            warm_cpu=process.cpu_times(); warm_memory=process.memory_info(); warm_threads=process.num_threads()
            begin=time.perf_counter()
            while time.perf_counter()-begin<idle_seconds:
                library.Update(measures[0]); library.GetString(measures[0]); time.sleep(0.1)
            end_cpu=process.cpu_times(); end_memory=process.memory_info()
            idle={'seconds':time.perf_counter()-begin,'cpu_seconds':end_cpu.user+end_cpu.system-warm_cpu.user-warm_cpu.system,
                  'working_set_start':warm_memory.rss,'working_set_end':end_memory.rss,
                  'private_start':warm_memory.private,'private_end':end_memory.private,
                  'threads_start':warm_threads,'threads_end':process.num_threads()}
        thread_samples.append(process.num_threads())
        for _ in range(100):
            begin=time.perf_counter()
            library.Update(measures[0]); raw=library.GetString(measures[0])
            latencies.append((time.perf_counter()-begin)*1000)
            assert raw is not None
            if bluetooth:
                assert raw.startswith('OK:'),raw[:30]
                ids=[row.split(',')[0] for row in raw[3:].split(';') if row]
                assert len(ids)==len(set(ids)); rows=len(ids)
        for index,data in enumerate(reversed(measures)):
            begin=time.perf_counter(); library.Finalize(data)
            elapsed_ms=(time.perf_counter()-begin)*1000
            final_times.append(elapsed_ms)
            if index==len(measures)-1: last_final_times.append(elapsed_ms)
    # Let OS / WinRT thread-pool workers settle; counts include their pools.
    time.sleep(0.5)
    elapsed=time.perf_counter()-start
    memory_after=process.memory_info(); io_after=process.io_counters(); cpu_after=process.cpu_times()
    return {'plugin':path.name,'cycles':cycles,'measure_instances_per_cycle':6 if bluetooth else 1,
            'seconds':elapsed,'cpu_seconds':(cpu_after.user+cpu_after.system)-(cpu_before.user+cpu_before.system),
            'working_set_before':memory_before.rss,'working_set_after':memory_after.rss,
            'private_before':memory_before.private,'private_after':memory_after.private,
            'threads_before':initial_threads,'threads_peak_sample':max(thread_samples),'threads_after':process.num_threads(),
            'io_read_bytes':io_after.read_bytes-io_before.read_bytes,'io_write_bytes':io_after.write_bytes-io_before.write_bytes,
            'initialize_max_ms':max(init_times),'finalize_max_ms':max(final_times),
            'initialize':summary(init_times),'first_initialize':summary(first_init_times),
            'reload':summary(reload_times),
            'finalize':summary(final_times),'last_finalize':summary(last_final_times),
            'first_actual_snapshot':summary(first_snapshot_times),'first_generation_change':summary(first_generation_times),
            'snapshot_timeout_seconds':snapshot_timeout,'snapshot_timeouts':snapshot_timeouts,
            'callback_pair_median_ms':statistics.median(latencies),'callback_pair_max_ms':max(latencies),
            'snapshot_rows':rows,'hardware_writes':0,'idle':idle}

if __name__=='__main__':
    parser=argparse.ArgumentParser(); parser.add_argument('dll',type=Path); parser.add_argument('--cycles',type=int,default=10)
    parser.add_argument('--idle-seconds',type=float,default=0)
    parser.add_argument('--snapshot-timeout',type=float,default=2,
                        help='seconds to wait for a nonempty Bluetooth snapshot or available brightness value')
    args=parser.parse_args(); print(json.dumps(run(args.dll,args.cycles,args.idle_seconds,args.snapshot_timeout),indent=2))
