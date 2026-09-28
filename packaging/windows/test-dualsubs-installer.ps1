[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
$buildRoot = Join-Path $PSScriptRoot 'build'
$testRoot = Join-Path $PSScriptRoot 'test-install'
$testInstallDir = Join-Path $testRoot 'VLC'
$stockRoot = 'C:\Program Files\VideoLAN\VLC'
$stageRoot = Join-Path $buildRoot 'stage'
$payloadManifestPath = Join-Path $stageRoot 'payload-manifest.json'
$installManifestPath = Join-Path $testInstallDir 'DualSubs\install-manifest.json'
$errorReportPath = Join-Path $stageRoot 'Install-DualSubs-error.txt'

function Get-FileSha256 {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Reset-TestInstallTree {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }

    New-Item -ItemType Directory -Path $testInstallDir -Force | Out-Null

    foreach ($relativePath in $testFiles) {
        $sourcePath = Join-Path $stockRoot $relativePath
        $destPath = Join-Path $testInstallDir $relativePath
        New-Item -ItemType Directory -Path (Split-Path -Path $destPath -Parent) -Force | Out-Null
        Copy-Item -LiteralPath $sourcePath -Destination $destPath -Force
    }
}

function Get-OriginalHashMap {
    $hashes = @{}
    foreach ($relativePath in $testFiles | Where-Object { $_ -ne 'vlc.exe' -and $_ -ne 'vlc-cache-gen.exe' }) {
        $hashes[$relativePath.Replace('\', '/')] = Get-FileSha256 -Path (Join-Path $testInstallDir $relativePath)
    }

    return $hashes
}

function Assert-PayloadHashes {
    param([object]$Manifest)

    foreach ($fileEntry in $Manifest.files) {
        $targetPath = Join-Path $testInstallDir ([string]$fileEntry.relativePath).Replace('/', '\')
        $currentHash = Get-FileSha256 -Path $targetPath
        if ($currentHash -ne [string]$fileEntry.sha256) {
            throw "Install verification failed for $($fileEntry.relativePath)"
        }
    }
}

function Assert-UninstallRestored {
    param([hashtable]$OriginalHashes)

    foreach ($relativePath in $OriginalHashes.Keys) {
        $targetPath = Join-Path $testInstallDir $relativePath.Replace('/', '\')
        $restoredHash = Get-FileSha256 -Path $targetPath
        if ($restoredHash -ne $OriginalHashes[$relativePath]) {
            throw "Uninstall restore verification failed for $relativePath"
        }
    }

    if (Test-Path -LiteralPath (Join-Path $testInstallDir 'DualSubs')) {
        throw 'DualSubs state directory should have been removed during uninstall.'
    }
}

$testFiles = @(
    'vlc.exe',
    'vlc-cache-gen.exe',
    'libvlc.dll',
    'libvlccore.dll',
    'plugins\gui\libqt_plugin.dll',
    'plugins\codec\liblibass_plugin.dll',
    'plugins\codec\libsubsdec_plugin.dll',
    'plugins\codec\libsubstx3g_plugin.dll',
    'plugins\codec\libttml_plugin.dll',
    'plugins\codec\libwebvtt_plugin.dll'
)

& (Join-Path $PSScriptRoot 'build-dualsubs-installer.ps1') -SkipCompile

Reset-TestInstallTree
$originalHashes = Get-OriginalHashMap

& (Join-Path $stageRoot 'Install-DualSubs.ps1') `
    -InstallDir $testInstallDir `
    -PayloadZip (Join-Path $stageRoot 'DualSubs-Payload.zip') `
    -PayloadManifestPath $payloadManifestPath `
    -SkipRegistry `
    -SkipCacheRefresh `
    -Quiet

$payloadManifest = Get-Content -LiteralPath $payloadManifestPath -Raw | ConvertFrom-Json
Assert-PayloadHashes -Manifest $payloadManifest

$installManifest = Get-Content -LiteralPath $installManifestPath -Raw | ConvertFrom-Json
foreach ($fileEntry in $installManifest.files) {
    if ($fileEntry.originalHash -ne $originalHashes[[string]$fileEntry.relativePath]) {
        throw "Backup verification failed for $($fileEntry.relativePath)"
    }
}

& (Join-Path $stageRoot 'Uninstall-DualSubs.ps1') `
    -InstallDir $testInstallDir `
    -SkipRegistry `
    -SkipCacheRefresh `
    -Quiet

Assert-UninstallRestored -OriginalHashes $originalHashes

Reset-TestInstallTree
$originalHashes = Get-OriginalHashMap

& (Join-Path $stageRoot 'Install-DualSubs.ps1') `
    -InstallDir $testInstallDir `
    -PayloadZip (Join-Path $stageRoot 'DualSubs-Payload.zip') `
    -PayloadManifestPath $payloadManifestPath `
    -SkipRegistry `
    -SkipCacheRefresh `
    -Quiet

$partialFiles = @(
    'libvlc.dll',
    'plugins\codec\liblibass_plugin.dll'
)

foreach ($relativePath in $partialFiles) {
    $backupPath = Join-Path $testInstallDir ('DualSubs\backup\' + $relativePath)
    $targetPath = Join-Path $testInstallDir $relativePath
    Copy-Item -LiteralPath $backupPath -Destination $targetPath -Force
}

Remove-Item -LiteralPath $installManifestPath -Force
Remove-Item -LiteralPath (Join-Path $testInstallDir 'DualSubs\Uninstall-DualSubs.ps1') -Force
Remove-Item -LiteralPath (Join-Path $testInstallDir 'DualSubs\Uninstall DualSubs.cmd') -Force

$preflightMessage = & (Join-Path $stageRoot 'Install-DualSubs.ps1') `
    -InstallDir $testInstallDir `
    -PayloadZip (Join-Path $stageRoot 'DualSubs-Payload.zip') `
    -PayloadManifestPath $payloadManifestPath `
    -SkipRegistry `
    -SkipCacheRefresh `
    -PreflightOnly `
    -Quiet

if ($preflightMessage -notmatch 'partial DualSubs patch state') {
    throw "Expected partial patch preflight message, but saw: $preflightMessage"
}

& (Join-Path $stageRoot 'Install-DualSubs.ps1') `
    -InstallDir $testInstallDir `
    -PayloadZip (Join-Path $stageRoot 'DualSubs-Payload.zip') `
    -PayloadManifestPath $payloadManifestPath `
    -SkipRegistry `
    -SkipCacheRefresh `
    -Quiet

Assert-PayloadHashes -Manifest $payloadManifest
if (-not (Test-Path -LiteralPath $installManifestPath)) {
    throw 'Install manifest should have been recreated after resuming a partial patch.'
}

& (Join-Path $stageRoot 'Uninstall-DualSubs.ps1') `
    -InstallDir $testInstallDir `
    -SkipRegistry `
    -SkipCacheRefresh `
    -Quiet

Assert-UninstallRestored -OriginalHashes $originalHashes

Reset-TestInstallTree
$originalHashes = Get-OriginalHashMap
$stagedUninstallCmd = Join-Path $stageRoot 'Uninstall DualSubs.cmd'
$stagedUninstallCmdBackup = Join-Path $testRoot 'Uninstall DualSubs.cmd.bak'
Copy-Item -LiteralPath $stagedUninstallCmd -Destination $stagedUninstallCmdBackup -Force
Remove-Item -LiteralPath $stagedUninstallCmd -Force

try {
    & (Join-Path $stageRoot 'Install-DualSubs.ps1') `
        -InstallDir $testInstallDir `
        -PayloadZip (Join-Path $stageRoot 'DualSubs-Payload.zip') `
        -PayloadManifestPath $payloadManifestPath `
        -SkipRegistry `
        -SkipCacheRefresh `
        -Quiet

    $generatedUninstallCmd = Join-Path $testInstallDir 'DualSubs\Uninstall DualSubs.cmd'
    if (-not (Test-Path -LiteralPath $generatedUninstallCmd)) {
        throw 'Install should generate Uninstall DualSubs.cmd when the staged helper file is missing.'
    }

    $generatedUninstallCmdContent = Get-Content -LiteralPath $generatedUninstallCmd -Raw
    if ($generatedUninstallCmdContent -notmatch 'Uninstall-DualSubs\.ps1') {
        throw 'Generated uninstall launcher does not point to Uninstall-DualSubs.ps1.'
    }

    Assert-PayloadHashes -Manifest $payloadManifest

    & (Join-Path $stageRoot 'Uninstall-DualSubs.ps1') `
        -InstallDir $testInstallDir `
        -SkipRegistry `
        -SkipCacheRefresh `
        -Quiet

    Assert-UninstallRestored -OriginalHashes $originalHashes
} finally {
    Copy-Item -LiteralPath $stagedUninstallCmdBackup -Destination $stagedUninstallCmd -Force
}

Reset-TestInstallTree
$versionMismatchManifestPath = Join-Path $stageRoot 'payload-manifest-version-mismatch.json'
$versionMismatchManifest = Get-Content -LiteralPath $payloadManifestPath -Raw | ConvertFrom-Json
$versionMismatchManifest.vlcVersion = '0.0.0'
$versionMismatchManifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $versionMismatchManifestPath -Encoding UTF8

if (Test-Path -LiteralPath $errorReportPath) {
    Remove-Item -LiteralPath $errorReportPath -Force
}

$versionMismatchOutput = & (Join-Path $stageRoot 'Install-DualSubs.ps1') `
    -InstallDir $testInstallDir `
    -PayloadZip (Join-Path $stageRoot 'DualSubs-Payload.zip') `
    -PayloadManifestPath $versionMismatchManifestPath `
    -SkipRegistry `
    -SkipCacheRefresh `
    -PreflightOnly `
    -Quiet

if ($LASTEXITCODE -eq 0) {
    throw 'Version mismatch preflight should have failed.'
}

if (($versionMismatchOutput -join [Environment]::NewLine) -notmatch 'targets VLC 0\.0\.0') {
    throw "Unexpected version mismatch output: $($versionMismatchOutput -join [Environment]::NewLine)"
}

if (-not (Test-Path -LiteralPath $errorReportPath)) {
    throw 'Version mismatch should have produced an installer-readable error report.'
}

$errorReport = Get-Content -LiteralPath $errorReportPath -Raw
if ($errorReport -notmatch 'targets VLC 0\.0\.0') {
    throw "Unexpected installer-readable error report: $errorReport"
}

Write-Host 'DualSubs installer install/uninstall test passed.'
