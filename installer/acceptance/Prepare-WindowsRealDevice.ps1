param(
    [Parameter(Mandatory = $true)][string]$TargetId,
    [Parameter(Mandatory = $true)][string]$Confirmation,
    [Parameter(Mandatory = $true)][string]$TargetPath,
    [Parameter(Mandatory = $true)][Int64]$TargetSize,
    [Parameter(Mandatory = $true)][string]$OptInSentence,
    [Parameter(Mandatory = $true)][string]$PlanPath,
    [string]$FixturePath,
    [string]$LargeDriveAttestation
)

$ErrorActionPreference = "Stop"
if ($OptInSentence -cne "I ACCEPT PERMANENT DATA LOSS ON THIS DISPOSABLE DRIVE") {
    throw "Windows acceptance requires the exact destructive opt-in sentence"
}
$fixture = -not [string]::IsNullOrWhiteSpace($FixturePath)
if (-not $fixture) {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Physical acceptance requires administrator authority"
    }
}

$adapter = Join-Path $PSScriptRoot "../adapters/windows-list-targets.ps1"
$inventory = if ($fixture) { & $adapter -FixturePath $FixturePath | ConvertFrom-Json } else { & $adapter | ConvertFrom-Json }
$matches = @($inventory.targets | Where-Object { $_.id -ceq $TargetId })
if ($matches.Count -ne 1) { throw "Target identity is missing or ambiguous" }
$target = $matches[0]
if (-not $target.removable -or $target.system -or $target.mounted -or $target.read_only) {
    throw "Selected Windows target is not safe and eligible"
}
if ([Int64]$target.size_bytes -lt 8589934592) { throw "Selected Windows target is too small" }
$expected = "ERASE $($target.model) — $($target.path) — $($target.size_bytes)"
if ($Confirmation -cne $expected) { throw "Confirmation does not exactly identify the Windows target" }
if ($TargetPath -cne [string]$target.path -or $TargetSize -ne [Int64]$target.size_bytes) {
    throw "Fresh Windows identity does not match the path/capacity attestation"
}
if ($TargetPath -cnotmatch '^\\\\\.\\PhysicalDrive[0-9]+$') {
    throw "Windows target is not an exact whole physical-drive path"
}
if ($TargetSize -gt 274877906944 -and $LargeDriveAttestation -cne "I CONFIRM THIS LARGE DRIVE IS DISPOSABLE") {
    throw "Drives over 256 GiB require the additional large-drive attestation"
}

$plan = [ordered]@{
    schema = 1
    mode = if ($fixture) { "fixture" } else { "physical" }
    platform = "windows"
    ready_for_writer = $false
    target = [ordered]@{
        id = $target.id; path = $target.path; model = $target.model
        size_bytes = [Int64]$target.size_bytes; disposable = $true
    }
    checks = [ordered]@{
        fresh_inventory = $true; exact_confirmation = $true; whole_device = $true
        removable = $true; unmounted = $true; writable = $true
    }
}
$parent = Split-Path -Parent $PlanPath
if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
$plan | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $PlanPath -Encoding UTF8
Write-Output "Windows disposable-drive preflight passed; physical writing remains disabled: $PlanPath"
