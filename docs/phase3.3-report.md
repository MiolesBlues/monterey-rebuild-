# Phase 3.3 — Lazy Loading

Active widgets retain their existing measures, animation timers, device watcher and fallback behavior. The auxiliary configurations are already separate Rainmeter skins: global Settings loads only the selected `SettingsTab` include, slider settings open from their widget context actions, and MusicPreview activates on hover or fullscreen. Preview and Fullscreen use `Update=-1` and are deactivated when closed. No additional process or preloader is needed.

Monitor settings now keep their Bluetooth measure idle until the device menu or a pinned cell needs it. Opening the list requests the latest snapshot once, builds the connected-device list, and then responds to watcher generation changes. Leaving the list releases its parsed data; the active Monitor's shared DeviceWatcher remains untouched. `AdaptiveSettings` is updated on refresh and watcher changes rather than every second. A guard prevents a manual snapshot request and its `OnChangeAction` from drawing the menu twice.

Sidebar and widget context actions now activate global Settings once. Their former `ToggleConfig` followed by `ActivateConfig` could load it twice. Window position, ZPos, ClickThrough, theme and layout includes remain unchanged.

Verification: 17 targeted Lua 5.1 and event-update tests pass, including first and repeated device-menu opening, pinned-cell sampling, resource release, reentrant watcher callbacks, and MusicPreview deactivation after hover. The full suite retains 14 previously known unrelated failures and one error.
