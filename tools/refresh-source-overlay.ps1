[CmdletBinding()]
param(
    [string]$WorkingRoot = (Join-Path $PSScriptRoot '..\upstream\vlc-3.0.24'),
    [string]$OverlayRoot = (Join-Path $PSScriptRoot '..\source-overlay\vlc-3.0.24'),
    [string[]]$InitializePaths = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workingRoot = [IO.Path]::GetFullPath($WorkingRoot)
$overlayRoot = [IO.Path]::GetFullPath($OverlayRoot)

if (-not (Test-Path -LiteralPath $workingRoot)) {
    throw "Working VLC tree not found: $workingRoot"
}

if ($InitializePaths.Count -gt 0) {
    $relativePaths = $InitializePaths
} elseif (Test-Path -LiteralPath $overlayRoot) {
    $relativePaths = Get-ChildItem -LiteralPath $overlayRoot -Recurse -File | ForEach-Object {
        $_.FullName.Substring($overlayRoot.Length + 1)
    }
} else {
    throw "Overlay root not found and no -InitializePaths were provided: $overlayRoot"
}

foreach ($relativePath in $relativePaths) {
    $sourcePath = Join-Path $workingRoot $relativePath
    if (-not (Test-Path -LiteralPath $sourcePath)) {
        throw "Expected working-tree file is missing: $sourcePath"
    }
    $destinationPath = Join-Path $overlayRoot $relativePath
    New-Item -ItemType Directory -Path (Split-Path -Path $destinationPath -Parent) -Force | Out-Null
    Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Force
    Write-Host "Refreshed $relativePath"
}

Write-Host ("Refreshed {0} overlay files from {1}" -f $relativePaths.Count, $workingRoot)
