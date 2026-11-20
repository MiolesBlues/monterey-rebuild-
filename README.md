# Monterey — Phase 2

Rainmeter Monterey with the existing widget designs, settings and native plugins.
Phase 3.1 startup audit, native source reconciliation and latency measurements are
documented in `docs/phase3.1-report.md`.
Phase 2 stabilizes worker lifecycles, asynchronous slider responses, music
animations and weather caching. See `docs/phase2-report.md` for the audit,
changed-file manifest, measured results and remaining hardware acceptance tests.
The event-driven update policy and polling fallbacks are documented in
`docs/event-driven-updates.md`.

Build the x64 Release plugins with
`Monterey\@Resources\Native\build.cmd`. CMake, Visual Studio 2022 C++ Build
Tools and a Windows SDK are required. The native README gives the tested versions.
The build runs three CTest tests and does not install anything automatically.

For Lua tests, install `tests/requirements.txt` in a virtual environment and run
`python tests/test_lua.py`. It explicitly uses Lua 5.1 through lupa. No GUI or
hardware writes are used by the automated tests. `probe_plugins.py` performs
read-only DLL lifecycle checks. `profile_rainmeter.ps1` samples a running process.

For installation, stop Rainmeter, copy changed skin files into its Monterey skin
directory and both x64 custom DLLs into its Plugins directory, then restart.
Preserve the user's Variables files. The one repaired persisted value is the
Auto Low Power result: it is now numeric, rather than the invalid literal formula
`(1-PowerState)`. Existing Auto/None/Pinned and fallback settings are retained.

This package has not passed physical sleep, radio toggling, DPI-change or
multi-monitor brightness acceptance tests. It does not include Phase 3.
