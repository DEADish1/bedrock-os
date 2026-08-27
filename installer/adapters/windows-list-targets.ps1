param(
    [string]$FixturePath
)

$ErrorActionPreference = "Stop"

if ($FixturePath) {
    $disks = @(Get-Content -Raw -LiteralPath $FixturePath | ConvertFrom-Json)
} else {
    if (-not (Get-Command Get-Disk -ErrorAction SilentlyContinue)) {
        throw "Get-Disk is required on Windows"
    }
    $disks = @(Get-Disk | ForEach-Object {
        $disk = $_
        $mounted = $false
        try {
            $mounted = @(
                Get-Partition -DiskNumber $disk.Number -ErrorAction Stop |
                    Where-Object { $_.DriveLetter -or @($_.AccessPaths).Count -gt 0 }
            ).Count -gt 0
        } catch {
            # Unknown mount state is unsafe.
            $mounted = $true
        }
        [pscustomobject]@{
            number = [int]$disk.Number
            model = [string]$disk.FriendlyName
            size_bytes = [int64]$disk.Size
            bus_type = [string]$disk.BusType
            is_boot = [bool]$disk.IsBoot
            is_system = [bool]$disk.IsSystem
            read_only = [bool]$disk.IsReadOnly
            mounted = [bool]$mounted
        }
    })
}

$systemKnown = @($disks | Where-Object { $_.is_boot -or $_.is_system }).Count -gt 0
$targets = @($disks | ForEach-Object {
    $path = "\\.\PhysicalDrive$($_.number)"
    $model = if ([string]::IsNullOrWhiteSpace($_.model)) { "Unknown removable drive" } else { $_.model.Trim() }
    $identity = "$path|$model|$($_.size_bytes)"
    $bytes = [Text.Encoding]::UTF8.GetBytes($identity)
    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
        $hash = ([BitConverter]::ToString($sha256.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()
    } finally {
        $sha256.Dispose()
    }
    $removable = @("USB", "SD", "MMC") -contains ([string]$_.bus_type).ToUpperInvariant()
    [ordered]@{
        id = "windows:$hash"
        path = $path
        model = $model
        size_bytes = [int64]$_.size_bytes
        removable = [bool]$removable
        system = if ($systemKnown) { [bool]($_.is_boot -or $_.is_system) } else { $true }
        mounted = [bool]$_.mounted
        read_only = [bool]$_.read_only
    }
})

[ordered]@{
    schema = 1
    generated_at = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    targets = $targets
} | ConvertTo-Json -Depth 5 -Compress
