[CmdletBinding()]
param(
    [string]$InstallDir,
    [switch]$SkipRegistry,
    [switch]$SkipCacheRefresh,
    [switch]$Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Status {
    param([string]$Message)
    if (-not $Quiet) {
        Write-Host $Message
    }
}

function Get-FileSha256OrNull {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Test-IsAdministrator {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($currentIdentity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Ensure-ElevationIfNeeded {
    param(
        [string]$ResolvedInstallDir,
        [switch]$RegistryChangesNeeded
    )

    if (Test-IsAdministrator) {
        return
    }

    $programFilesRoots = @(
        [Environment]::GetFolderPath('ProgramFiles'),
        ${env:ProgramFiles(x86)}
    ) | Where-Object { $_ }

    $needsAdmin = $RegistryChangesNeeded
    if (-not $needsAdmin) {
        foreach ($root in $programFilesRoots) {
            if ($ResolvedInstallDir.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
                $needsAdmin = $true
                break
            }
        }
    }

    if (-not $needsAdmin) {
        return
    }

    Write-Status 'Requesting elevation for Program Files and uninstall registration cleanup...'

    $argumentList = @(
        '-ExecutionPolicy', 'Bypass',
        '-File', ('"{0}"' -f $PSCommandPath),
        '-InstallDir', ('"{0}"' -f $ResolvedInstallDir)
    )

    if ($SkipRegistry) { $argumentList += '-SkipRegistry' }
    if ($SkipCacheRefresh) { $argumentList += '-SkipCacheRefresh' }
    if ($Quiet) { $argumentList += '-Quiet' }

    $child = Start-Process -FilePath 'powershell.exe' -ArgumentList $argumentList -Verb RunAs -Wait -PassThru
    exit $child.ExitCode
}

function Assert-VlcClosed {
    param([string]$ResolvedInstallDir)

    $running = Get-Process -Name vlc -ErrorAction SilentlyContinue | Where-Object {
        $_.Path -and ((Split-Path -Path $_.Path -Parent).TrimEnd('\') -ieq $ResolvedInstallDir.TrimEnd('\'))
    }

    if ($running) {
        throw 'VLC is currently running from the target install directory. Close VLC before uninstalling DualSubs.'
    }
}

function Update-PluginCache {
    param([string]$ResolvedInstallDir)

    if ($SkipCacheRefresh) {
        Write-Status 'Skipping plugin cache refresh.'
        return
    }

    $cacheGen = Join-Path $ResolvedInstallDir 'vlc-cache-gen.exe'
    $pluginsDir = Join-Path $ResolvedInstallDir 'plugins'
    if (-not (Test-Path -LiteralPath $cacheGen) -or -not (Test-Path -LiteralPath $pluginsDir)) {
        Write-Status 'Skipping plugin cache refresh because vlc-cache-gen.exe or plugins/ is missing.'
        return
    }

    Write-Status 'Refreshing VLC plugin cache...'
    & $cacheGen $pluginsDir | Out-Null
}

$resolvedInstallDir = if ($InstallDir) {
    (Resolve-Path -LiteralPath $InstallDir).Path
} else {
    Split-Path -Path $PSScriptRoot -Parent
}

Ensure-ElevationIfNeeded -ResolvedInstallDir $resolvedInstallDir -RegistryChangesNeeded:(-not $SkipRegistry)
Assert-VlcClosed -ResolvedInstallDir $resolvedInstallDir

$stateDir = Join-Path $resolvedInstallDir 'DualSubs'
$installManifestPath = Join-Path $stateDir 'install-manifest.json'
if (-not (Test-Path -LiteralPath $installManifestPath)) {
    throw "DualSubs install manifest not found at $installManifestPath"
}

$installManifest = Get-Content -LiteralPath $installManifestPath -Raw | ConvertFrom-Json
$warnings = New-Object System.Collections.Generic.List[string]

foreach ($fileEntry in $installManifest.files) {
    $relativePath = [string]$fileEntry.relativePath
    $targetPath = Join-Path $resolvedInstallDir $relativePath
    $backupPath = Join-Path $stateDir ([string]$fileEntry.backupRelativePath).Replace('/', '\')
    $currentHash = Get-FileSha256OrNull -Path $targetPath

    if (-not (Test-Path -LiteralPath $backupPath)) {
        $warnings.Add("Backup missing for $relativePath; skipped restore.")
        continue
    }

    if ($currentHash -eq [string]$fileEntry.installedHash) {
        Write-Status ("Restoring {0}" -f $relativePath)
        Copy-Item -LiteralPath $backupPath -Destination $targetPath -Force
        $restoredHash = Get-FileSha256OrNull -Path $targetPath
        if ($restoredHash -ne [string]$fileEntry.originalHash) {
            throw "Post-uninstall verification failed for $relativePath"
        }
        continue
    }

    if ($currentHash -eq [string]$fileEntry.originalHash) {
        Write-Status ("Already restored {0}" -f $relativePath)
        continue
    }

    $warnings.Add(
        "Skipped $relativePath because the current file does not match the DualSubs payload. The file was left untouched."
    )
}

Update-PluginCache -ResolvedInstallDir $resolvedInstallDir

if (-not $SkipRegistry) {
    Remove-Item -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\DualSubs for VLC' -Recurse -Force -ErrorAction SilentlyContinue
}

if ($warnings.Count -gt 0) {
    $reportPath = Join-Path $resolvedInstallDir 'DualSubs-uninstall-report.txt'
    $warnings | Set-Content -LiteralPath $reportPath -Encoding UTF8
    Write-Status ("DualSubs uninstalled with warnings. Report saved to {0}" -f $reportPath)
} else {
    Write-Status 'DualSubs files restored cleanly.'
}

if (Test-Path -LiteralPath $stateDir) {
    Remove-Item -LiteralPath $stateDir -Recurse -Force
}
