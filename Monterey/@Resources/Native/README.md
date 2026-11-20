# Monterey native plugins — Phase 2

Build: Visual Studio 2022 Build Tools, MSVC 14.44, Windows SDK 10.0.26100.0,
CMake 3.24 or newer. Run `build.cmd` from a terminal; an optional first argument
selects the build directory. The script configures Windows x64, builds Release
with the static MSVC runtime, and runs CTest. There is no automatic installation.

For an explicitly selected SDK/toolset, configure with:

```
cmake -S . -B build-x64 -G "Visual Studio 17 2022" -A x64 -T version=14.44 -DCMAKE_SYSTEM_VERSION=10.0.26100.0
cmake --build build-x64 --config Release
ctest --test-dir build-x64 -C Release --output-on-failure
```

Only copy `Release/MontereyBluetooth.dll` and `Release/MontereyBrightness.dll`
to the Rainmeter Plugins directory while Rainmeter is stopped. These are x64
DLLs. Third-party plugins are not rebuilt. `/Brepro` removes time-based linker
timestamps; repeatability must be checked using the same toolchain and source.
PDBs are retained in the build directory for diagnosing worker failures.

Bluetooth keeps the existing Classic/BLE DeviceWatchers and container-based
identity. There is one shared worker per loaded DLL. Initialization only starts
the worker; callbacks publish cached snapshots. SetupAPI runs off the Rainmeter
thread, at most every 15 seconds for battery refresh, or after a new connection.
Data events are coalesced for 100ms without forcing another SetupAPI scan.
Last-user finalization joins the worker, drains watcher callbacks, releases the
WinRT factory cache and uninitializes COM. Offline identities remain available
until the last measure unloads, preserving pinning semantics.

Brightness source provenance: recovered from the user's existing
`Downloads/Monterey_NativeBrightness_ScrollFix` developer bundle. Its sequence-ID
protocol matches the installed Phase 1 DLL and Lua. The original binary's source
identity cannot be proved from its hash alone. The original controller regression
test was retained and extended. All WMI/DDC operations stay on the controller
worker; Update/GetString access cached state. The last requested value replaces
pending work; obsolete command IDs are ignored. The internal panel remains the
preferred target. DDC writes stay on the selected monitor and cannot spill to
another monitor after a write failure; reads may rediscover a disconnected target.

Unloading waits for in-flight Windows hardware calls. Neither WMI nor DDC offers
a general cancellation guarantee here; finalization latency depends on the
driver. Do not force-terminate a worker that may still execute DLL code.

Tests: `brightness_controller` uses a simulated backend (no hardware writes),
`device_merge` tests pure endpoint logic, and `plugin_lifecycle` loads the real
Bluetooth DLL for 50 cycles / 300 measure instances and calls FreeLibrary.
These tests do not simulate sleep, radio toggles, or physical reconnection.
