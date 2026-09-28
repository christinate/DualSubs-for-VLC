[CmdletBinding()]
param(
    [string]$OverlayRoot = (Join-Path $PSScriptRoot '..\source-overlay\vlc-3.0.24'),
    [string]$TargetRoot = (Join-Path $PSScriptRoot '..\upstream\vlc-3.0.24')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$overlayRoot = (Resolve-Path -LiteralPath $OverlayRoot).Path
$targetRoot = [IO.Path]::GetFullPath($TargetRoot)

if (-not (Test-Path -LiteralPath $targetRoot)) {
    throw "Target VLC tree not found: $targetRoot"
}

$files = Get-ChildItem -LiteralPath $overlayRoot -Recurse -File
foreach ($file in $files) {
    $relativePath = $file.FullName.Substring($overlayRoot.Length + 1)
    $destPath = Join-Path $targetRoot $relativePath
    New-Item -ItemType Directory -Force -Path (Split-Path -Path $destPath -Parent) | Out-Null
    Copy-Item -LiteralPath $file.FullName -Destination $destPath -Force
    Write-Host "Applied $relativePath"
}

Write-Host ("Applied {0} overlay files into {1}" -f $files.Count, $targetRoot)
