# init_extra_disks.ps1
# Initialize RAW disks and ensure they are mounted at drive letter F:.

$logPath = "C:\Program Files\Cloudbase Solutions\Cloudbase-Init\LocalScripts\init_extra_disks.log"

function Write-Log {
    param([string]$Message)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts : $Message" | Out-File -FilePath $logPath -Append -Encoding utf8
}

Write-Log "===== Script started ====="

# Desired fixed letter
$desiredLetter = "Z"

# Check if Z: is already in use
if (Get-Volume -DriveLetter $desiredLetter -ErrorAction SilentlyContinue) {
    Write-Log "Drive letter $desiredLetter already exists, skipping assignment."
    exit 0
}

# --- Part 0: Bring offline disks online ---
$offlineDisks = Get-Disk | Where-Object { $_.OperationalStatus -eq 'Offline' }
foreach ($disk in $offlineDisks) {
    try {
        Write-Log "Found offline disk #$($disk.Number), attempting to bring it online"
        
        # Clear read-only flag if set by administrator policy
        if ($disk.IsReadOnly) {
            Write-Log "Disk #$($disk.Number) is read-only, clearing flag"
            Set-Disk -Number $disk.Number -IsReadOnly $false
        }
        
        # Bring disk online
        Set-Disk -Number $disk.Number -IsOffline $false
        Write-Log "Disk #$($disk.Number) is now online"
    }
    catch {
        Write-Log "Error bringing disk #$($disk.Number) online: $_"
    }
}

# --- Part 1: Handle RAW disks ---
$rawDisks = Get-Disk | Where-Object { $_.PartitionStyle -eq 'RAW' -and $_.OperationalStatus -eq 'Online' }
foreach ($disk in $rawDisks) {
    try {
        Write-Log "Initializing RAW disk #$($disk.Number)"
        Initialize-Disk -Number $disk.Number -PartitionStyle GPT -PassThru | Out-Null

        Write-Log "Creating partition on disk #$($disk.Number)"
        $partition = New-Partition -DiskNumber $disk.Number -UseMaximumSize

        Write-Log "Formatting partition on disk #$($disk.Number) with NTFS"
        Format-Volume -Partition $partition -FileSystem NTFS -NewFileSystemLabel "ExtraDisk$($disk.Number)" -Confirm:$false

        Write-Log "Assigning drive letter $desiredLetter"
        Set-Partition -DiskNumber $disk.Number -PartitionNumber $partition.PartitionNumber -NewDriveLetter $desiredLetter
        exit 0
    }
    catch {
        Write-Log "Error processing RAW disk #$($disk.Number): $_"
    }
}

# --- Part 2: Volumes with FS but no drive letter ---
$volumesNoLetter = Get-Volume | Where-Object { $_.DriveLetter -eq $null -and $_.FileSystem -ne $null -and $_.FileSystem -ne '' }
foreach ($vol in $volumesNoLetter) {
    try {
        Write-Log "Found volume without drive letter: Label='$($vol.FileSystemLabel)', Size=$([math]::Round($vol.Size/1GB,2)) GB"
        $parts = Get-Partition | Where-Object { $_.DiskNumber -eq $vol.DriveNumber -and $_.DriveLetter -eq $null }
        foreach ($part in $parts) {
            Write-Log "Assigning drive letter $desiredLetter to partition #$($part.PartitionNumber) on disk #$($part.DiskNumber)"
            Set-Partition -DiskNumber $part.DiskNumber -PartitionNumber $part.PartitionNumber -NewDriveLetter $desiredLetter
            exit 0
        }
    }
    catch {
        Write-Log "Error assigning drive letter: $_"
    }
}

Write-Log "No suitable disk/volume found for assignment."
Write-Log "===== Script completed ====="