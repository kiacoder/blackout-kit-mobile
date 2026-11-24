# Run manually before committing. Does not install hooks or modify source.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
function Invoke-Checked {
    param([string]$Program, [string[]]$Arguments)
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Program failed ($LASTEXITCODE)" }
}
Push-Location $Root
try {
    Invoke-Checked python @('tool/verify_supply_chain.py')
    Invoke-Checked python @('-m', 'ruff', 'check', 'tool')
    Invoke-Checked flutter @('analyze', '--no-fatal-infos')
    Invoke-Checked cargo @('clippy', '--locked', '--all-targets', '--manifest-path', 'native/blackout-core/Cargo.toml')
    Invoke-Checked cargo @('test', '--locked', '--manifest-path', 'native/blackout-core/Cargo.toml')
    $files = @('ffi.rs','jni.rs','lib.rs','netstack/device.rs','netstack/mod.rs','netstack/packet.rs','netstack/tests.rs') | ForEach-Object { "native/blackout-core/src/$_" }
    Invoke-Checked rustfmt (@('--edition','2021','--check','--config','skip_children=true') + $files)
    Write-Host 'Quality checks passed.'
} finally {
    Pop-Location
}
