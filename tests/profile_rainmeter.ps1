param([int]$Seconds=30,[string]$Output='rainmeter-profile.json')
$ErrorActionPreference='Stop'
$process=Get-Process Rainmeter -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $process) { throw 'Rainmeter is not running; no measurements were taken.' }
$firstCpu=$process.TotalProcessorTime.TotalSeconds
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class MontereyPhase2IO {
    [StructLayout(LayoutKind.Sequential)]
    public struct Counters { public ulong ReadOps,WriteOps,OtherOps,ReadBytes,WriteBytes,OtherBytes; }
    [DllImport("kernel32.dll")] public static extern bool GetProcessIoCounters(IntPtr process,out Counters counters);
}
'@
$started=[Diagnostics.Stopwatch]::StartNew()
$rows=@()
while ($started.Elapsed.TotalSeconds -lt $Seconds) {
    $process.Refresh()
    if ($process.HasExited) { break }
    $io=[MontereyPhase2IO+Counters]::new()
    $ioAvailable=[MontereyPhase2IO]::GetProcessIoCounters($process.Handle,[ref]$io)
    $rows += [pscustomobject]@{
        Seconds=$started.Elapsed.TotalSeconds
        CPUSeconds=$process.TotalProcessorTime.TotalSeconds-$firstCpu
        WorkingSet=$process.WorkingSet64
        PrivateMemory=$process.PrivateMemorySize64
        Threads=$process.Threads.Count
        PowerShellProcesses=@(Get-Process powershell,pwsh -ErrorAction SilentlyContinue).Count
        IOAvailable=$ioAvailable
        ReadBytes=$io.ReadBytes
        WriteBytes=$io.WriteBytes
        ReadOperations=$io.ReadOps
        WriteOperations=$io.WriteOps
    }
    Start-Sleep -Milliseconds 1000
}
$rows | ConvertTo-Json | Set-Content -LiteralPath $Output -Encoding utf8
Write-Output "Saved $($rows.Count) process samples to $Output. Counts include all PowerShell processes, including this profiler."
