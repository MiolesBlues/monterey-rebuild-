# Phase 3.1 — Fast Startup & Async Initialization

Date: 20 November 2026.

## Source audit

The Phase 2 report describes a shared Bluetooth worker, COM ownership on that
worker, a Brightness source tree, and three native tests. The current repository
instead contained an older `MontereyBluetooth.cpp`, no native build files or
Brightness sources, and older plugin DLLs. The installed DLLs matched the
repository DLLs, not the Phase 2 report hashes. The Phase 2 delivery archive
(`Monterey-Phase2.zip`) contained the missing native sources and tests; these
were restored to the repository as the starting point for this phase.

The restored Bluetooth source already moves COM initialization, watcher creation,
and SetupAPI scans to one shared worker. `Initialize` allocates a measure,
publishes an empty valid snapshot, and starts that worker once. `Reload` only
sets the measure range. A lifecycle mutex serializes first and last users;
the last `Finalize` signals, joins, stops both watchers, and releases COM on
the worker. The initial event coalescing window is 5 ms; subsequent events
retain the existing 100 ms window and battery polling remains a 15 s fallback.

## Other startup paths

- The installed Brightness DLL was left unchanged. Its read-only probe showed
  fast `Initialize` and `Reload`, with the first valid value arriving later from
  the backend. The restored Phase 2 Brightness source also creates the hardware
  backend inside its existing controller thread. Its provenance does not prove
  byte-for-byte correspondence with the installed DLL.
- `BrightnessWorker.ps1` remains the separate fallback backend. Current
  Brightness configuration uses `NativeBrightness=1`; no launcher for the
  PowerShell fallback is referenced by the current skin. It was not started
  or replaced. Its PowerShell syntax parses without errors.
- Music keeps its small metadata and cached cover restore for the first frame.
  Cover files are now size checked before reading; metadata changes and animations
  still use `OnChangeAction` and `ActionTimer`.
- Weather keeps the cached first frame and asynchronous WebParser request. Its
  cache is now size checked before reading. The existing retry path remains.
- Monitor starts from configured fallback cells and applies Bluetooth data when
  the generation changes. CPU, RAM, disk and network use existing change actions;
  the animation timer runs only when values change. Other widget initializers
  were inspected and did not perform synchronous network or hardware queries.

## Read-only measurements

`tests/probe_plugins.py` now measures every `Initialize`, `Reload` and
`Finalize`, plus elapsed time from first Initialize to a nonempty Bluetooth
snapshot or a valid brightness value. A timeout is reported explicitly when
there is no device or usable brightness source. It does not write hardware.

| Bluetooth, three warm independent runs | Before | Phase 3.1 candidate |
|---|---:|---:|
| First Initialize | 31–36 ms | 0.12–0.18 ms |
| First nonempty snapshot | 42–46 ms | 51–52 ms |
| Last Finalize | 0.4–0.5 ms | 33–43 ms |

The initialization work moves to the worker; the final join waits for clean
unload. Snapshot time is an observation on this machine, not a hardware latency
guarantee. A 50-cycle/300-measure Bluetooth probe had no snapshot timeouts;
median first snapshot was 42 ms. The installed Brightness DLL measured a
maximum Initialize of 0.11 ms, Reload of 0.008 ms and median first valid value
of 31 ms over three cycles.

## Verification and limits

- Native CTest: 3/3 pass, including 50 Bluetooth lifecycle cycles in a
  separately loaded DLL.
- Four focused Lua tests pass; all Lua scripts compile as Lua 5.1. Python probe
  compiles and the fallback PowerShell script parses.
- The repository-wide Lua suite still has pre-existing inconsistencies with
  the Phase 2 report and current sources (17 failures, 2 errors), including
  missing `WeatherJSON.lua` and tests for code absent from this checkout.
  The Phase 3.1 changes do not replace those unrelated widget implementations.
- Physical disconnects, sleep, slow drivers, and a long-running soak test were
  not performed. `Finalize` still joins the worker because unloading a live
  DeviceWatcher would risk callbacks into an unloaded DLL.
