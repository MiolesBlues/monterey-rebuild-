param([Parameter(Mandatory=$true)][string]$Directory)
$ErrorActionPreference = 'Stop'
$request = Join-Path $Directory 'slider-request.txt'
$status = Join-Path $Directory 'slider-status.txt'
$ack = 0
$last = -1
$nextPoll = [DateTime]::MinValue

# WMI handles internal displays; use Windows' DDC/CI API as a fallback.
$source = @'
using System;
using System.Runtime.InteropServices;
public static class MontereyBrightness {
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
    struct Physical { public IntPtr Handle; [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string Description; }
    delegate bool EnumProc(IntPtr monitor, IntPtr dc, IntPtr rect, IntPtr data);
    [DllImport("user32.dll")] static extern bool EnumDisplayMonitors(IntPtr dc, IntPtr clip, EnumProc callback, IntPtr data);
    [DllImport("dxva2.dll")] static extern bool GetNumberOfPhysicalMonitorsFromHMONITOR(IntPtr h, out uint count);
    [DllImport("dxva2.dll")] static extern bool GetPhysicalMonitorsFromHMONITOR(IntPtr h, uint count, [Out] Physical[] items);
    [DllImport("dxva2.dll")] static extern bool DestroyPhysicalMonitors(uint count, [In] Physical[] items);
    [DllImport("dxva2.dll")] static extern bool GetMonitorBrightness(IntPtr h, out uint min, out uint current, out uint max);
    [DllImport("dxva2.dll")] static extern bool SetMonitorBrightness(IntPtr h, uint value);
    public static int Access(int requested) {
        int result = -1;
        EnumProc callback = delegate(IntPtr h, IntPtr dc, IntPtr rect, IntPtr data) {
            uint count;
            if (!GetNumberOfPhysicalMonitorsFromHMONITOR(h, out count) || count == 0 || count > 32) return true;
            Physical[] items = new Physical[count];
            if (!GetPhysicalMonitorsFromHMONITOR(h, count, items)) return true;
            try {
                foreach (Physical item in items) {
                    uint min, cur, max;
                    if (!GetMonitorBrightness(item.Handle, out min, out cur, out max) || max <= min) continue;
                    if (requested >= 0) {
                        uint v = min + (uint)Math.Round((max-min)*requested/100.0);
                        if (!SetMonitorBrightness(item.Handle, v)) continue;
                        result = requested;
                    } else result = (int)Math.Round(100.0*(cur-min)/(max-min));
                    return false;
                }
            } finally { DestroyPhysicalMonitors(count, items); }
            return true;
        };
        EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, callback, IntPtr.Zero);
        GC.KeepAlive(callback);
        return result;
    }
}
'@
$ddc = $false
$backend = ''
function Access-Brightness([int]$Value) {
    if ($script:backend -ne 'DDC') { try {
        $display = Get-CimInstance -Namespace root/wmi -ClassName WmiMonitorBrightness -ErrorAction Stop | Where-Object Active | Select-Object -First 1
        if ($null -ne $display) {
            $script:backend = 'WMI'
            if ($Value -lt 0) { return [int]$display.CurrentBrightness }
            $method = Get-CimInstance -Namespace root/wmi -ClassName WmiMonitorBrightnessMethods | Where-Object { $_.InstanceName -eq $display.InstanceName } | Select-Object -First 1
            if ($null -ne $method) {
                $result = Invoke-CimMethod -InputObject $method -MethodName WmiSetBrightness -Arguments @{Timeout=[uint32]0;Brightness=[byte]$Value}
                if ($result.ReturnValue -eq 0) { return $Value }
            }
        }
    } catch {} }
    if ($script:backend -eq 'WMI') { return -1 }
    try {
        if (-not $script:ddc) { Add-Type -TypeDefinition $source; $script:ddc = $true }
        $result = [MontereyBrightness]::Access($Value)
        if ($result -ge 0) { $script:backend = 'DDC' }
        return $result
    } catch { return -1 }
}

while ($true) {
    try {
        if (Test-Path -LiteralPath $request) {
            $line = [IO.File]::ReadAllText($request).Trim()
            if ($line -match '^(\d+)\s+(\d+)$') {
                $seq = [long]$Matches[1]; $value = [int]$Matches[2]
                if ($seq -gt $ack) {
                    $last = Access-Brightness ([Math]::Max(5,[Math]::Min(100,$value)))
                    $ack = $seq
                    $nextPoll = [DateTime]::UtcNow.AddSeconds(1)
                    [IO.File]::WriteAllText($status, "$ack $last")
                }
            }
        }
        if ([DateTime]::UtcNow -ge $nextPoll) {
            $last = Access-Brightness -1
            [IO.File]::WriteAllText($status, "$ack $last")
            $nextPoll = [DateTime]::UtcNow.AddSeconds(2)
        }
    } catch {}
    Start-Sleep -Milliseconds 100
}
