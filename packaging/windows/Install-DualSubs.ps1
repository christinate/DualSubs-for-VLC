[CmdletBinding()]
param(
    [string]$InstallDir,
    [string]$PayloadZip = (Join-Path $PSScriptRoot 'DualSubs-Payload.zip'),
    [string]$PayloadManifestPath = (Join-Path $PSScriptRoot 'payload-manifest.json'),
    [switch]$PreflightOnly,
    [switch]$SkipRegistry,
    [switch]$SkipCacheRefresh,
    [switch]$Force,
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

function Write-FailureReport {
    param(
        [string]$ReportPath,
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    $message = $ErrorRecord.Exception.Message
    if ([string]::IsNullOrWhiteSpace($message)) {
        $message = $ErrorRecord.ToString()
    }

    $message = ($message -replace '\r?\n', ' ').Trim()
    if ([string]::IsNullOrWhiteSpace($message)) {
        $message = 'DualSubs installation failed for an unknown reason.'
    }

    Set-Content -LiteralPath $ReportPath -Value $message -Encoding UTF8
    Write-Output $message
}

function Ensure-UninstallLauncher {
    param(
        [string]$SourcePath,
        [string]$DestinationPath
    )

    if (Test-Path -LiteralPath $SourcePath) {
        Copy-Item -LiteralPath $SourcePath -Destination $DestinationPath -Force
        return
    }

    $launcherContent = @'
@echo off
setlocal
powershell.exe -ExecutionPolicy Bypass -File "%~dp0Uninstall-DualSubs.ps1" %*
exit /b %ERRORLEVEL%
'@
    Set-Content -LiteralPath $DestinationPath -Value $launcherContent -Encoding ASCII
}

function Get-FileSha256 {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Get-FileVersionOrNull {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    $item = Get-Item -LiteralPath $Path
    return $item.VersionInfo.FileVersion
}

function New-RelativePathMap {
    param([object[]]$FileEntries)

    $map = @{}
    if (-not $FileEntries) {
        return $map
    }

    foreach ($fileEntry in $FileEntries) {
        $map[[string]$fileEntry.relativePath] = $fileEntry
    }

    return $map
}

function Get-OverlayState {
    param(
        [string]$ResolvedInstallDir,
        [string]$ExpandedPayloadDir,
        [string]$BackupRoot,
        [object]$PayloadManifest,
        [hashtable]$ExistingManifestMap
    )

    $conflicts = New-Object System.Collections.Generic.List[string]
    $patchedWithoutBackup = New-Object System.Collections.Generic.List[string]
    $patchedCount = 0
    $pendingCount = 0
    $totalCount = @($PayloadManifest.files).Count

    foreach ($fileEntry in $PayloadManifest.files) {
        $relativePath = [string]$fileEntry.relativePath
        $targetPath = Join-Path $ResolvedInstallDir $relativePath
        $payloadPath = Join-Path $ExpandedPayloadDir $relativePath
        $backupPath = Join-Path $BackupRoot $relativePath
        $manifestFile = $ExistingManifestMap[$relativePath]
        $recordedOriginalHash = if ($manifestFile) { [string]$manifestFile.originalHash } else { $null }
        $recordedInstalledHash = if ($manifestFile) { [string]$manifestFile.installedHash } else { $null }

        if (-not (Test-Path -LiteralPath $payloadPath)) {
            throw "Payload entry is missing: $relativePath"
        }
        if (-not (Test-Path -LiteralPath $targetPath)) {
            throw "Expected VLC file is missing from the target install: $targetPath"
        }

        $payloadHash = Get-FileSha256 -Path $payloadPath
        if ($payloadHash -ne [string]$fileEntry.sha256) {
            throw "Payload hash mismatch for $relativePath"
        }

        $currentHash = Get-FileSha256 -Path $targetPath
        $backupExists = Test-Path -LiteralPath $backupPath
        $backupHash = $null
        if ($backupExists) {
            $backupHash = Get-FileSha256 -Path $backupPath
            if ($recordedOriginalHash -and $backupHash -ne $recordedOriginalHash) {
                $conflicts.Add(
                    "{0} (saved backup hash does not match the original hash recorded by DualSubs)" -f $relativePath
                )
                continue
            }
        }

        if ($currentHash -eq $payloadHash) {
            $patchedCount++
            if (-not $backupExists) {
                $patchedWithoutBackup.Add(
                    "{0} (already matches the DualSubs payload but no original backup was found)" -f $relativePath
                )
            }
            continue
        }

        if ($backupExists) {
            if ($currentHash -eq $backupHash) {
                $pendingCount++
                continue
            }
            if ($recordedInstalledHash -and $currentHash -eq $recordedInstalledHash) {
                $pendingCount++
                continue
            }

            $conflicts.Add(
                "{0} (current file does not match the saved backup or the expected DualSubs payload)" -f $relativePath
            )
            continue
        }

        if ($recordedInstalledHash -and $currentHash -eq $recordedInstalledHash) {
            $patchedWithoutBackup.Add(
                "{0} (matches a previous DualSubs payload but the original backup is missing)" -f $relativePath
            )
            continue
        }

        if ($recordedOriginalHash) {
            if ($currentHash -eq $recordedOriginalHash) {
                $pendingCount++
                continue
            }

            $conflicts.Add(
                "{0} (backup is missing and the current file no longer matches the original hash from the previous DualSubs state)" -f $relativePath
            )
            continue
        }

        $pendingCount++
    }

    foreach ($problem in $patchedWithoutBackup) {
        $conflicts.Add($problem)
    }

    $state = 'ReadyToPatch'
    if ($conflicts.Count -gt 0) {
        $state = 'Conflict'
    } elseif ($patchedCount -eq $totalCount) {
        $state = 'AlreadyPatched'
    } elseif ($patchedCount -gt 0) {
        $state = 'ResumePartial'
    }

    return [pscustomobject]@{
        State = $state
        PatchedCount = $patchedCount
        PendingCount = $pendingCount
        TotalCount = $totalCount
        HasExistingManifest = ($ExistingManifestMap.Count -gt 0)
        Conflicts = $conflicts
    }
}

function Get-OverlayStateMessage {
    param(
        [object]$OverlayState,
        [string]$ResolvedInstallDir,
        [string]$DetectedVlcVersion
    )

    switch ([string]$OverlayState.State) {
        'AlreadyPatched' {
            return "DualSubs is already fully applied to VLC $DetectedVlcVersion at $ResolvedInstallDir. The installer will refresh its state files and uninstaller."
        }
        'ResumePartial' {
            return "Detected a partial DualSubs patch state for VLC $DetectedVlcVersion at $ResolvedInstallDir. $($OverlayState.PatchedCount) of $($OverlayState.TotalCount) patched files already match the DualSubs payload. The installer will verify file hashes and complete the remaining files."
        }
        default {
            if ($OverlayState.HasExistingManifest) {
                return "Detected existing DualSubs state data for VLC $DetectedVlcVersion at $ResolvedInstallDir. The installer will verify file hashes and refresh the overlay."
            }

            return "Ready to patch VLC $DetectedVlcVersion at $ResolvedInstallDir."
        }
    }
}

function Test-IsAdministrator {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($currentIdentity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Resolve-VlcInstallDir {
    param([string]$ExplicitInstallDir)

    if ($ExplicitInstallDir) {
        $candidatePath = [IO.Path]::GetFullPath($ExplicitInstallDir)
        if (-not (Test-Path -LiteralPath $candidatePath -PathType Container)) {
            throw "The selected VLC installation folder does not exist: $candidatePath"
        }

        return (Resolve-Path -LiteralPath $candidatePath).Path
    }

    $registryKeys = @(
        'HKLM:\SOFTWARE\VideoLAN\VLC',
        'HKLM:\SOFTWARE\WOW6432Node\VideoLAN\VLC',
        'HKCU:\SOFTWARE\VideoLAN\VLC',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\VLC media player',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\VLC media player'
    )

    foreach ($key in $registryKeys) {
        if (-not (Test-Path -LiteralPath $key)) {
            continue
        }

        $props = Get-ItemProperty -LiteralPath $key
        if ($props.InstallDir) {
            return $props.InstallDir
        }
        if ($props.InstallLocation) {
            return $props.InstallLocation
        }
    }

    $defaultPath = 'C:\Program Files\VideoLAN\VLC'
    if (Test-Path -LiteralPath $defaultPath) {
        return $defaultPath
    }

    throw 'Unable to locate an existing VLC installation. Install VLC first, or rerun DualSubs and choose the folder that contains vlc.exe.'
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

    Write-Status 'Requesting elevation for Program Files and uninstall registration updates...'

    $argumentList = @(
        '-ExecutionPolicy', 'Bypass',
        '-File', ('"{0}"' -f $PSCommandPath),
        '-InstallDir', ('"{0}"' -f $ResolvedInstallDir),
        '-PayloadZip', ('"{0}"' -f (Resolve-Path -LiteralPath $PayloadZip).Path),
        '-PayloadManifestPath', ('"{0}"' -f (Resolve-Path -LiteralPath $PayloadManifestPath).Path)
    )

    if ($SkipRegistry) { $argumentList += '-SkipRegistry' }
    if ($SkipCacheRefresh) { $argumentList += '-SkipCacheRefresh' }
    if ($Force) { $argumentList += '-Force' }
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
        throw 'VLC is currently running from the target install directory. Close VLC before installing DualSubs.'
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

function Register-Uninstaller {
    param(
        [string]$ResolvedInstallDir,
        [string]$StateDir,
        [string]$DualSubsVersion
    )

    if ($SkipRegistry) {
        Write-Status 'Skipping uninstall registry registration.'
        return
    }

    $keyPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\DualSubs for VLC'
    $uninstallPs1 = Join-Path $StateDir 'Uninstall-DualSubs.ps1'
    $displayIconPath = Join-Path $StateDir 'dualsubs-icon.ico'
    if (-not (Test-Path -LiteralPath $displayIconPath)) {
        $displayIconPath = Join-Path $ResolvedInstallDir 'vlc.exe'
    }
    $uninstallString = 'powershell.exe -ExecutionPolicy Bypass -File "{0}"' -f $uninstallPs1
    $quietUninstallString = $uninstallString + ' -Quiet'

    New-Item -Path $keyPath -Force | Out-Null
    Set-ItemProperty -Path $keyPath -Name DisplayName -Value 'DualSubs for VLC'
    Set-ItemProperty -Path $keyPath -Name DisplayVersion -Value $DualSubsVersion
    Set-ItemProperty -Path $keyPath -Name Publisher -Value 'DualSubs Open Source Contributors'
    Set-ItemProperty -Path $keyPath -Name InstallLocation -Value $ResolvedInstallDir
    Set-ItemProperty -Path $keyPath -Name DisplayIcon -Value $displayIconPath
    Set-ItemProperty -Path $keyPath -Name UninstallString -Value $uninstallString
    Set-ItemProperty -Path $keyPath -Name QuietUninstallString -Value $quietUninstallString
    Set-ItemProperty -Path $keyPath -Name NoModify -Type DWord -Value 1
    Set-ItemProperty -Path $keyPath -Name NoRepair -Type DWord -Value 1
}

$errorReportPath = Join-Path $PSScriptRoot 'Install-DualSubs-error.txt'
if (Test-Path -LiteralPath $errorReportPath) {
    Remove-Item -LiteralPath $errorReportPath -Force
}

try {
    $resolvedInstallDir = Resolve-VlcInstallDir -ExplicitInstallDir $InstallDir
    $payloadManifestPath = (Resolve-Path -LiteralPath $PayloadManifestPath).Path
    $payloadZip = (Resolve-Path -LiteralPath $PayloadZip).Path

    if (-not (Test-Path -LiteralPath $payloadManifestPath)) {
        throw "Missing payload manifest at $payloadManifestPath"
    }
    if (-not (Test-Path -LiteralPath $payloadZip)) {
        throw "Missing payload archive at $payloadZip"
    }

    $vlcExePath = Join-Path $resolvedInstallDir 'vlc.exe'
    if (-not (Test-Path -LiteralPath $vlcExePath)) {
        throw "No VLC executable found at $vlcExePath"
    }

    $payloadManifest = Get-Content -LiteralPath $payloadManifestPath -Raw | ConvertFrom-Json
    $detectedVlcVersion = (Get-Item -LiteralPath $vlcExePath).VersionInfo.FileVersion
    if (-not $Force -and $detectedVlcVersion -ne $payloadManifest.vlcVersion) {
        throw "This DualSubs overlay targets VLC $($payloadManifest.vlcVersion), but the detected VLC version is $detectedVlcVersion."
    }

    Assert-VlcClosed -ResolvedInstallDir $resolvedInstallDir

    if (-not $PreflightOnly) {
        Ensure-ElevationIfNeeded -ResolvedInstallDir $resolvedInstallDir -RegistryChangesNeeded:(-not $SkipRegistry)
    }

    $stateDir = Join-Path $resolvedInstallDir 'DualSubs'
    $backupRoot = Join-Path $stateDir 'backup'
    $installManifestPath = Join-Path $stateDir 'install-manifest.json'
    $uninstallScriptTarget = Join-Path $stateDir 'Uninstall-DualSubs.ps1'
    $uninstallCmdTarget = Join-Path $stateDir 'Uninstall DualSubs.cmd'

    $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('DualSubs-Install-' + [guid]::NewGuid().ToString('N'))
    $expandedPayloadDir = Join-Path $tempRoot 'payload'

    New-Item -ItemType Directory -Path $expandedPayloadDir -Force | Out-Null
    Expand-Archive -LiteralPath $payloadZip -DestinationPath $expandedPayloadDir -Force

    try {
        $existingManifest = $null
        if (Test-Path -LiteralPath $installManifestPath) {
            $existingManifest = Get-Content -LiteralPath $installManifestPath -Raw | ConvertFrom-Json
        }

        $existingManifestFiles = @()
        if ($existingManifest -and $existingManifest.files) {
            $existingManifestFiles = @($existingManifest.files)
        }

        $existingManifestMap = New-RelativePathMap -FileEntries $existingManifestFiles
        $overlayState = Get-OverlayState `
            -ResolvedInstallDir $resolvedInstallDir `
            -ExpandedPayloadDir $expandedPayloadDir `
            -BackupRoot $backupRoot `
            -PayloadManifest $payloadManifest `
            -ExistingManifestMap $existingManifestMap

        if ([string]$overlayState.State -eq 'Conflict') {
            throw (
                "DualSubs found an incomplete or modified patch state in $resolvedInstallDir that cannot be resumed safely. " +
                "First problem: $($overlayState.Conflicts[0])"
            )
        }

        $overlayStateMessage = Get-OverlayStateMessage `
            -OverlayState $overlayState `
            -ResolvedInstallDir $resolvedInstallDir `
            -DetectedVlcVersion $detectedVlcVersion

        if ($PreflightOnly) {
            Write-Output $overlayStateMessage
            return
        }

        New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
        New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null

        Write-Status $overlayStateMessage

        $installedFiles = New-Object System.Collections.Generic.List[object]

        foreach ($fileEntry in $payloadManifest.files) {
            $relativePath = [string]$fileEntry.relativePath
            $targetPath = Join-Path $resolvedInstallDir $relativePath
            $payloadPath = Join-Path $expandedPayloadDir $relativePath
            $backupPath = Join-Path $backupRoot $relativePath
            $existingManifestFile = $existingManifestMap[$relativePath]
            $recordedOriginalHash = if ($existingManifestFile) { [string]$existingManifestFile.originalHash } else { $null }
            $recordedInstalledHash = if ($existingManifestFile) { [string]$existingManifestFile.installedHash } else { $null }

            if (-not (Test-Path -LiteralPath $payloadPath)) {
                throw "Payload entry is missing: $relativePath"
            }
            if (-not (Test-Path -LiteralPath $targetPath)) {
                throw "Expected VLC file is missing from the target install: $targetPath"
            }

            $payloadHash = Get-FileSha256 -Path $payloadPath
            if ($payloadHash -ne [string]$fileEntry.sha256) {
                throw "Payload hash mismatch for $relativePath"
            }

            $currentHash = Get-FileSha256 -Path $targetPath
            $backupExists = Test-Path -LiteralPath $backupPath

            if ($backupExists) {
                $backupHash = Get-FileSha256 -Path $backupPath
                if ($recordedOriginalHash -and $backupHash -ne $recordedOriginalHash) {
                    throw "Cannot safely use the saved backup for $relativePath because its hash no longer matches the original hash recorded by DualSubs."
                }
                if (
                    $currentHash -ne $payloadHash -and
                    $currentHash -ne $backupHash -and
                    (-not $recordedInstalledHash -or $currentHash -ne $recordedInstalledHash)
                ) {
                    throw "Cannot safely replace $relativePath because a backup already exists but the current file no longer matches either the stock backup or the DualSubs payload."
                }
            } else {
                if ($currentHash -eq $payloadHash) {
                    throw "Cannot safely replace $relativePath because it already matches the DualSubs payload but no original backup was found."
                }
                if ($recordedInstalledHash -and $currentHash -eq $recordedInstalledHash) {
                    throw "Cannot safely replace $relativePath because it matches a previous DualSubs payload but the original backup is missing."
                }
                New-Item -ItemType Directory -Path (Split-Path -Path $backupPath -Parent) -Force | Out-Null
                Copy-Item -LiteralPath $targetPath -Destination $backupPath -Force
                $backupHash = Get-FileSha256 -Path $backupPath
                if ($recordedOriginalHash -and $backupHash -ne $recordedOriginalHash) {
                    throw "Cannot safely recreate the backup for $relativePath because the current file does not match the original hash recorded by a previous DualSubs install."
                }
            }

            $originalHash = Get-FileSha256 -Path $backupPath
            $originalVersion = Get-FileVersionOrNull -Path $backupPath

            if ($currentHash -ne $payloadHash) {
                Write-Status ("Patching {0}" -f $relativePath)
                Copy-Item -LiteralPath $payloadPath -Destination $targetPath -Force
            } else {
                Write-Status ("Already patched {0}" -f $relativePath)
            }

            $installedHash = Get-FileSha256 -Path $targetPath
            if ($installedHash -ne $payloadHash) {
                throw "Post-install verification failed for $relativePath"
            }

            $installedFiles.Add([ordered]@{
                relativePath = $relativePath
                backupRelativePath = [IO.Path]::Combine('backup', $relativePath).Replace('\', '/')
                originalHash = $originalHash
                originalVersion = $originalVersion
                installedHash = $payloadHash
                installedVersion = Get-FileVersionOrNull -Path $targetPath
            })
        }

        Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Uninstall-DualSubs.ps1') -Destination $uninstallScriptTarget -Force
        Ensure-UninstallLauncher `
            -SourcePath (Join-Path $PSScriptRoot 'Uninstall DualSubs.cmd') `
            -DestinationPath $uninstallCmdTarget
        Copy-Item -LiteralPath $payloadManifestPath -Destination (Join-Path $stateDir 'payload-manifest.json') -Force
        $brandingIconSource = Join-Path $PSScriptRoot 'dualsubs-icon.ico'
        if (Test-Path -LiteralPath $brandingIconSource) {
            Copy-Item -LiteralPath $brandingIconSource -Destination (Join-Path $stateDir 'dualsubs-icon.ico') -Force
        }

        $installManifest = [ordered]@{
            dualSubsVersion = [string]$payloadManifest.dualSubsVersion
            vlcVersion = [string]$payloadManifest.vlcVersion
            installDir = $resolvedInstallDir
            installedAt = [DateTimeOffset]::UtcNow.ToString('o')
            files = $installedFiles
        }

        $installManifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $installManifestPath -Encoding UTF8

        Update-PluginCache -ResolvedInstallDir $resolvedInstallDir
        Register-Uninstaller -ResolvedInstallDir $resolvedInstallDir -StateDir $stateDir -DualSubsVersion ([string]$payloadManifest.dualSubsVersion)

        Write-Status 'DualSubs overlay installation completed successfully.'
    } finally {
        if (Test-Path -LiteralPath $tempRoot) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }
} catch {
    Write-FailureReport -ReportPath $errorReportPath -ErrorRecord $_
    exit 1
}
