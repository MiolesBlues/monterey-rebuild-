# Phase 3.2 — Persistent State Cache

Weather keeps its existing six-hour TTL, `Latitude|Longitude|Units` key and 900-second WebParser interval. `WeatherSync.lua` now limits startup reads to 1,049,088 bytes per file, validates the JSON before publishing values, and tries `.previous` when the primary cache is invalid. A valid backup is promoted on the next successful response. Writes use `.tmp` and preserve a recoverable copy across a failed rename. Identical responses do not write or redraw again. `WeatherJSON.lua` is the bounded Lua 5.1 decoder from the Phase 2 artifact; the current project had a reference to it but lacked the file.

Music keeps its existing cover cache and metadata format. The saved artwork and colors are applied only after the active process reports the same title and artist. A delayed thumbnail from the preceding track is not persisted under the new track's metadata. Saved metadata reads are capped at 8 KiB and image reads retain the existing 20 MB bound. Identical artwork skips cache writes and color sampling.

`WeatherReliable.inc`, Bluetooth snapshots and settings, real-time metrics, UI and animation settings were not changed.

Verification: 24 targeted Lua 5.1 compilation, weather-cache and event-update tests pass. The full suite retains 15 failures and one error in unrelated slider, adaptive monitor, anchor, contrast and music control tests; these failures were already present before this phase.
