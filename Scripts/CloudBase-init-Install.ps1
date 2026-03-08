# Cloudbase-init MSI install (silent) + copy config files
$MsiUrl = "http://192.168.1.9:8080/drivers/CloudbaseInitSetup_1_1_6_x64.msi" 



$SourceDir = "C:\\Windows\\Temp\\cloudbase-init-conf"
$DestDir = "C:\Program Files\Cloudbase Solutions\Cloudbase-Init\conf"  # change if needed

$FilesToCopy = @(
    "cloudbase-init-unattend.conf",
    "cloudbase-init.conf"
)

$Username = "Admin"
$UseMetadataPassword = $true
$UserGroups = "Administrators"
$SerialPort = ""  # empty = disabled
$RunServiceAsLocalSystem = $false

$TempDir = Join-Path $env:TEMP "cloudbase-init"
$MsiPath = Join-Path $TempDir "cloudbase-init.msi"

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

try {
    Invoke-WebRequest -Uri $MsiUrl -OutFile $MsiPath

    $MsiProperties = @(
        "USERNAME=`"$Username`"",
        "GROUPS=`"$UserGroups`""
    )

    $MsiProperties += if ($UseMetadataPassword) {
        "USE_METADATA_PASSWORD=1"
    } else {
        "USE_METADATA_PASSWORD=0"
    }

    $MsiProperties += if ($RunServiceAsLocalSystem) {
        "RUN_SERVICE_AS_LOCAL_SYSTEM=1"
    } else {
        "RUN_SERVICE_AS_LOCAL_SYSTEM=0"
    }

    if (-not [string]::IsNullOrWhiteSpace($SerialPort)) {
        $MsiProperties += "SERIAL_PORT=$SerialPort"
    }

    $Args = "/i `"$MsiPath`" /qn /norestart " + ($MsiProperties -join " ")
    $Process = Start-Process -FilePath "msiexec.exe" -ArgumentList $Args -Wait -PassThru

    if ($Process.ExitCode -ne 0) {
        throw "MSI install failed with exit code $($Process.ExitCode)."
    }

    if (-not (Test-Path -Path $DestDir)) {
        New-Item -ItemType Directory -Path $DestDir -Force | Out-Null
    }

    foreach ($File in $FilesToCopy) {
        $Src = Join-Path $SourceDir $File
        $Dst = Join-Path $DestDir $File

        if (-not (Test-Path -Path $Src)) {
            throw "Missing source file: $Src"
        }

        Copy-Item -Path $Src -Destination $Dst -Force
    }
} finally {
    Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
}