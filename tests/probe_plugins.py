"""Read-only native plugin lifecycle/latency probe, never changes brightness."""
import argparse
import ctypes as c
import json
import statistics
import time
from pathlib import Path
import psutil

def run(path,cycles,idle_seconds=0):
    process=psutil.Process()
    library=c.CDLL(str(path.resolve()))
    library.Initialize.argtypes=[c.POINTER(c.c_void_p),c.c_void_p]
    library.Update.argtypes=[c.c_void_p]; library.Update.restype=c.c_double
    library.GetString.argtypes=[c.c_void_p]; library.GetString.restype=c.c_wchar_p
    library.Finalize.argtypes=[c.c_void_p]
    init_times=[]; final_times=[]; latencies=[]; thread_samples=[]
    initial_threads=process.num_threads()
    cpu_before=process.cpu_times(); memory_before=process.memory_info(); io_before=process.io_counters()
    start=time.perf_counter(); rows=0
    for cycle in range(cycles):
        measures=[]
        for _ in range(6 if 'Bluetooth' in path.name else 1):
            data=c.c_void_p(); begin=time.perf_counter()
            library.Initialize(c.byref(data),None)
            init_times.append((time.perf_counter()-begin)*1000)
            assert data.value; measures.append(data)
        time.sleep(0.2 if cycles>1 else 3)
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
            if 'Bluetooth' in path.name:
                assert raw.startswith('OK:'),raw[:30]
                ids=[row.split(',')[0] for row in raw[3:].split(';') if row]
                assert len(ids)==len(set(ids)); rows=len(ids)
        begin=time.perf_counter()
        for data in reversed(measures): library.Finalize(data)
        final_times.append((time.perf_counter()-begin)*1000)
    # Let OS / WinRT thread-pool workers settle; counts include their pools.
    time.sleep(0.5)
    elapsed=time.perf_counter()-start
    memory_after=process.memory_info(); io_after=process.io_counters(); cpu_after=process.cpu_times()
    return {'plugin':path.name,'cycles':cycles,'measure_instances_per_cycle':6 if 'Bluetooth' in path.name else 1,
            'seconds':elapsed,'cpu_seconds':(cpu_after.user+cpu_after.system)-(cpu_before.user+cpu_before.system),
            'working_set_before':memory_before.rss,'working_set_after':memory_after.rss,
            'private_before':memory_before.private,'private_after':memory_after.private,
            'threads_before':initial_threads,'threads_peak_sample':max(thread_samples),'threads_after':process.num_threads(),
            'io_read_bytes':io_after.read_bytes-io_before.read_bytes,'io_write_bytes':io_after.write_bytes-io_before.write_bytes,
            'initialize_max_ms':max(init_times),'finalize_max_ms':max(final_times),
            'callback_pair_median_ms':statistics.median(latencies),'callback_pair_max_ms':max(latencies),
            'snapshot_rows':rows,'hardware_writes':0,'idle':idle}

if __name__=='__main__':
    parser=argparse.ArgumentParser(); parser.add_argument('dll',type=Path); parser.add_argument('--cycles',type=int,default=10)
    parser.add_argument('--idle-seconds',type=float,default=0)
    args=parser.parse_args(); print(json.dumps(run(args.dll,args.cycles,args.idle_seconds),indent=2))
