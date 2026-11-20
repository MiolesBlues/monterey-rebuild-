$ErrorActionPreference = 'Stop'

$window = Get-Process -Name AppleMusic -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero } |
    Select-Object -First 1
if (-not $window) { exit 0 }

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class MontereyWindow {
    [DllImport("user32.dll")]
    public static extern bool ShowWindowAsync(IntPtr window, int command);
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32.dll")]
    public static extern bool BringWindowToTop(IntPtr window);
    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);
    [DllImport("kernel32.dll")]
    public static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")]
    public static extern bool AttachThreadInput(uint source, uint target, bool attach);
}
'@

[MontereyWindow]::ShowWindowAsync($window.MainWindowHandle, 3) | Out-Null
$foreground = [MontereyWindow]::GetForegroundWindow()
$foregroundProcess = [uint32]0
$foregroundThread = [MontereyWindow]::GetWindowThreadProcessId($foreground, [ref]$foregroundProcess)
$currentThread = [MontereyWindow]::GetCurrentThreadId()
$attached = $false
if ($foregroundThread -ne 0 -and $foregroundThread -ne $currentThread) {
    $attached = [MontereyWindow]::AttachThreadInput($currentThread, $foregroundThread, $true)
}
try {
    [MontereyWindow]::BringWindowToTop($window.MainWindowHandle) | Out-Null
    [MontereyWindow]::SetForegroundWindow($window.MainWindowHandle) | Out-Null
} finally {
    if ($attached) {
        [MontereyWindow]::AttachThreadInput($currentThread, $foregroundThread, $false) | Out-Null
    }
}
