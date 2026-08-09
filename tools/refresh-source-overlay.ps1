[CmdletBinding()]
param(
    [string]$WorkingRoot = (Join-Path $PSScriptRoot '..\upstream\vlc-3.0.23'),
    [string]$OverlayRoot = (Join-Path $PSScriptRoot '..\source-overlay\vlc-3.0.23')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workingRoot = [IO.Path]::GetFullPath($WorkingRoot)
$overlayRoot = (Resolve-Path -LiteralPath $OverlayRoot).Path

if (-not (Test-Path -LiteralPath $workingRoot)) {
    throw "Working VLC tree not found: $workingRoot"
}

$files = Get-ChildItem -LiteralPath $overlayRoot -Recurse -File
foreach ($file in $files) {
    $relativePath = $file.FullName.Substring($overlayRoot.Length + 1)
    $sourcePath = Join-Path $workingRoot $relativePath
    if (-not (Test-Path -LiteralPath $sourcePath)) {
        throw "Expected working-tree file is missing: $sourcePath"
    }
    Copy-Item -LiteralPath $sourcePath -Destination $file.FullName -Force
    Write-Host "Refreshed $relativePath"
}

Write-Host ("Refreshed {0} overlay files from {1}" -f $files.Count, $workingRoot)
