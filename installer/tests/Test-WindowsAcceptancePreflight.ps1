$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$fixture = Join-Path $root "installer/tests/windows-disks.json"
$adapter = Join-Path $root "installer/adapters/windows-list-targets.ps1"
$preflight = Join-Path $root "installer/acceptance/Prepare-WindowsRealDevice.ps1"
$inventory = & $adapter -FixturePath $fixture | ConvertFrom-Json
$target = @($inventory.targets | Where-Object { $_.path -ceq '\\.\PhysicalDrive2' })[0]
$temporaryRoot = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [IO.Path]::GetTempPath() }
$plan = Join-Path $temporaryRoot "bedrock-windows-acceptance-plan.json"
$confirmation = "ERASE $($target.model) — $($target.path) — $($target.size_bytes)"
& $preflight -FixturePath $fixture -TargetId $target.id -Confirmation $confirmation `
    -TargetPath $target.path -TargetSize $target.size_bytes `
    -OptInSentence "I ACCEPT PERMANENT DATA LOSS ON THIS DISPOSABLE DRIVE" -PlanPath $plan | Out-Null
$result = Get-Content -Raw -LiteralPath $plan | ConvertFrom-Json
if ($result.mode -cne "fixture" -or $result.platform -cne "windows" -or $result.ready_for_writer -ne $false) {
    throw "Windows acceptance plan is invalid"
}
try {
    & $preflight -FixturePath $fixture -TargetId $target.id -Confirmation $confirmation `
        -TargetPath '\\.\PhysicalDrive0' -TargetSize $target.size_bytes `
        -OptInSentence "I ACCEPT PERMANENT DATA LOSS ON THIS DISPOSABLE DRIVE" -PlanPath $plan | Out-Null
    throw "Windows preflight accepted a mismatched physical-drive path"
} catch {
    if ($_.Exception.Message -eq "Windows preflight accepted a mismatched physical-drive path") { throw }
}
Write-Output "Windows disposable-drive acceptance preflight is valid."
