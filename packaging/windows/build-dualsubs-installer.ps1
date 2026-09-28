[CmdletBinding()]
param(
    [string]$RuntimeRoot,
    [string]$OutputRoot,
    [string]$DualSubsVersion = '0.2.0',
    [string]$VlcVersion = '3.0.24',
    [string]$MakensisPath,
    [switch]$SkipCompile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $RuntimeRoot) {
    $RuntimeRoot = Join-Path $PSScriptRoot '..\..\runtime\VLC-DualSubs-3.0.24'
}
if (-not $OutputRoot) {
    $OutputRoot = Join-Path $PSScriptRoot 'dist'
}

$runtimeRoot = (Resolve-Path -LiteralPath $RuntimeRoot).Path
$outputRoot = [IO.Path]::GetFullPath($OutputRoot)
$projectRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
$buildRoot = Join-Path $PSScriptRoot 'build'
$stageRoot = Join-Path $buildRoot 'stage'
$payloadRoot = Join-Path $stageRoot 'payload'
$payloadZip = Join-Path $stageRoot 'DualSubs-Payload.zip'
$payloadManifestPath = Join-Path $stageRoot 'payload-manifest.json'
$installerConfigPath = Join-Path $buildRoot 'installer-config.nsh'
$nsisScriptPath = Join-Path $PSScriptRoot 'DualSubsOverlay.nsi'
$installerPath = Join-Path $outputRoot ('DualSubs-for-VLC-' + $VlcVersion + '-x64-Overlay.exe')

$payloadMap = @(
    'libvlc.dll',
    'libvlccore.dll',
    'plugins\gui\libqt_plugin.dll',
    'plugins\codec\liblibass_plugin.dll',
    'plugins\codec\libsubsdec_plugin.dll',
    'plugins\codec\libsubstx3g_plugin.dll',
    'plugins\codec\libttml_plugin.dll',
    'plugins\codec\libwebvtt_plugin.dll'
)

function Get-FileSha256 {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Resolve-MakensisPath {
    param([string]$ExplicitPath)

    $candidates = New-Object System.Collections.Generic.List[string]

    if ($ExplicitPath) {
        $candidates.Add($ExplicitPath)
    }

    $command = Get-Command makensis.exe -ErrorAction SilentlyContinue
    if ($command) {
        $candidates.Add($command.Source)
    }

    foreach ($candidate in @(
        'C:\Program Files (x86)\NSIS\makensis.exe',
        'C:\Program Files\NSIS\makensis.exe'
    )) {
        $candidates.Add($candidate)
    }

    foreach ($candidate in $candidates) {
        if (-not $candidate) {
            continue
        }

        if (Test-Path -LiteralPath $candidate) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    return $null
}

function ConvertTo-NsisString {
    param([string]$Value)

    return $Value.Replace('\', '\\').Replace('$', '$$')
}

if (-not (Test-Path -LiteralPath $nsisScriptPath)) {
    throw "NSIS script is missing: $nsisScriptPath"
}

if (Test-Path -LiteralPath $buildRoot) {
    Remove-Item -LiteralPath $buildRoot -Recurse -Force
}

New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
New-Item -ItemType Directory -Path $payloadRoot -Force | Out-Null
New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null

foreach ($scriptName in @(
    'Install-DualSubs.ps1',
    'Uninstall-DualSubs.ps1',
    'Install DualSubs.cmd',
    'Uninstall DualSubs.cmd'
)) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $scriptName) -Destination (Join-Path $stageRoot $scriptName) -Force
}

$brandingIcon = Join-Path $projectRoot 'assets\branding\dualsubs-icon.ico'
if (Test-Path -LiteralPath $brandingIcon) {
    Copy-Item -LiteralPath $brandingIcon -Destination (Join-Path $stageRoot 'dualsubs-icon.ico') -Force
}

$payloadManifestFiles = New-Object System.Collections.Generic.List[object]
foreach ($relativePath in $payloadMap) {
    $sourcePath = Join-Path $runtimeRoot $relativePath
    if (-not (Test-Path -LiteralPath $sourcePath)) {
        throw "Runtime payload source is missing: $sourcePath"
    }

    $destPath = Join-Path $payloadRoot $relativePath
    New-Item -ItemType Directory -Path (Split-Path -Path $destPath -Parent) -Force | Out-Null
    Copy-Item -LiteralPath $sourcePath -Destination $destPath -Force

    $item = Get-Item -LiteralPath $destPath
    $payloadManifestFiles.Add([ordered]@{
        relativePath = $relativePath.Replace('\', '/')
        sha256 = Get-FileSha256 -Path $destPath
        fileVersion = $item.VersionInfo.FileVersion
        length = [int64]$item.Length
    })
}

$payloadManifest = [ordered]@{
    dualSubsVersion = $DualSubsVersion
    vlcVersion = $VlcVersion
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    files = $payloadManifestFiles
}

$payloadManifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $payloadManifestPath -Encoding UTF8
Compress-Archive -Path (Join-Path $payloadRoot '*') -DestinationPath $payloadZip -Force

$iconPath = Join-Path $stageRoot 'dualsubs-icon.ico'
if (-not (Test-Path -LiteralPath $iconPath)) {
    throw "Branding icon is missing from the staged payload: $iconPath"
}

$configLines = @(
    ('!define DUALSUBS_VERSION "{0}"' -f (ConvertTo-NsisString -Value $DualSubsVersion)),
    ('!define VLC_VERSION "{0}"' -f (ConvertTo-NsisString -Value $VlcVersion)),
    ('!define STAGE_ROOT "{0}"' -f (ConvertTo-NsisString -Value $stageRoot)),
    ('!define INSTALLER_OUTPUT "{0}"' -f (ConvertTo-NsisString -Value $installerPath)),
    ('!define BRANDING_ICON "{0}"' -f (ConvertTo-NsisString -Value $iconPath))
)
$configLines | Set-Content -LiteralPath $installerConfigPath -Encoding ASCII

$resolvedMakensisPath = Resolve-MakensisPath -ExplicitPath $MakensisPath
if (-not $resolvedMakensisPath) {
    if ($SkipCompile) {
        Write-Host 'Staged NSIS installer inputs, but skipped compilation because makensis.exe is not installed.'
        Write-Host ("Stage directory: {0}" -f $stageRoot)
        Write-Host ("Expected output: {0}" -f $installerPath)
        return
    }

    throw 'Unable to locate makensis.exe. Install NSIS or re-run with -MakensisPath. The staged inputs were still generated under packaging\windows\build\.'
}

if ($SkipCompile) {
    Write-Host ("Staged NSIS installer inputs at {0}" -f $stageRoot)
    Write-Host ("makensis.exe found at {0}, but compilation was skipped by request." -f $resolvedMakensisPath)
    return
}

Push-Location $PSScriptRoot
try {
    & $resolvedMakensisPath $nsisScriptPath | Out-Null
} finally {
    Pop-Location
}

if (-not (Test-Path -LiteralPath $installerPath)) {
    throw "NSIS did not produce the expected installer at $installerPath"
}

Write-Host ("Created {0}" -f $installerPath)
Write-Host ("Stage directory: {0}" -f $stageRoot)
