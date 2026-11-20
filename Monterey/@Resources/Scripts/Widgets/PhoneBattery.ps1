$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try {
    $phones = @{}
    foreach ($device in Get-PnpDevice -PresentOnly -Class Bluetooth) {
        if ($device.InstanceId -notlike 'BTHLE\DEV_*') { continue }
        $address = ($device.InstanceId -replace '^BTHLE\\DEV_([0-9a-fA-F]{12}).*','$1').ToLowerInvariant()
        $p = @{}
        Get-PnpDeviceProperty -InstanceId $device.InstanceId -ErrorAction SilentlyContinue | ForEach-Object { $p[$_.KeyName] = $_.Data }
        $category = @($p['DEVPKEY_DeviceContainer_Category'])
        $kind = 'B'
        if ('Communication.Phone' -in $category -or $device.FriendlyName -match 'iPhone') { $kind = 'P' }
        elseif (($category -join ',') -match 'Mouse' -or $device.FriendlyName -match 'SABRE RGB PRO|\bmouse\b') { $kind = 'M' }
        $level = $p['{104EA319-6EE2-4701-BD47-8DDBF425BBE5} 2']
        if ($null -eq $level -or $level -lt 0 -or $level -gt 100) { continue }
        $id = [string]$p['DEVPKEY_Device_ContainerId']
        if (-not $id -or $id -eq [guid]::Empty.ToString()) { $id = $address }
        $phones[$id] = $kind + [string][int]$level
    }
    # ASCII protocol: no device names, paths, or user-controlled Rainmeter commands.
    $values = @($phones.GetEnumerator() | Sort-Object @{Expression={switch ($_.Value.Substring(0,1)) {'P'{0} 'M'{1} default{2}}}}, Name | Select-Object -First 6 | ForEach-Object { $_.Value })
    Write-Output ('OK:' + ($values -join ','))
} catch {
    Write-Output 'ERROR'
}
