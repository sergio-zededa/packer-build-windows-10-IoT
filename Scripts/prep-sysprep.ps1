# Deletes recovery partitions and shrinks C: to minimum supported size.
# Run from an elevated PowerShell session.

$ErrorActionPreference = "Stop"

$enableShrink = $true

function Get-RecoveryPartitions {
    $recoveryGptType = "{DE94BBA4-06D1-4D40-A16A-BFD50179D6AC}"
    $parts = Get-Partition | Where-Object {
        ($_.GptType -eq $recoveryGptType) -or
        ($_.Type -eq "Recovery") -or
        ($_.MbrType -eq "0x27")
    }

    return $parts
}

$recoveryParts = Get-RecoveryPartitions

foreach ($part in $recoveryParts) {
    try {
        # Make sure hidden/read-only flags do not block removal.
        Set-Partition -DiskNumber $part.DiskNumber -PartitionNumber $part.PartitionNumber -IsReadOnly $false -IsHidden $false -ErrorAction SilentlyContinue | Out-Null
        Remove-Partition -DiskNumber $part.DiskNumber -PartitionNumber $part.PartitionNumber -Confirm:$false
    } catch {
        Write-Error "Failed to remove recovery partition on disk $($part.DiskNumber), partition $($part.PartitionNumber): $($_.Exception.Message)"
        throw
    }
}

# Shrink C: to minimum supported size.
if ($enableShrink) {
    $osPartition = Get-Partition -DriveLetter C
    $supported = Get-PartitionSupportedSize -DriveLetter C
    if ($osPartition.Size -gt $supported.SizeMin) {
        Resize-Partition -DriveLetter C -Size $supported.SizeMin
    }
}

# Additional cleanup to reduce QCOW2 export size.
powercfg /hibernate off | Out-Null

Dism.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase | Out-Null

Remove-Item -Path "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
# Keep Windows Temp so Packer's shutdown command scripts remain available.

# Zero free space so the QCOW2 export can sparsify it.
cipher /w:C | Out-Null
