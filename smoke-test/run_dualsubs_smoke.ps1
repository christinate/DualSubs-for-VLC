[CmdletBinding()]
param(
    [string]$Runtime = (Join-Path $PSScriptRoot '..\\runtime\\VLC-DualSubs')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$runtimePath = (Resolve-Path $Runtime).Path
$trackScript = Join-Path $PSScriptRoot 'check_dualsubs_tracks.py'
$menuScript = Join-Path $PSScriptRoot 'check_dualsubs_menu.ps1'
$mediaPath = Join-Path $PSScriptRoot 'colorbars.rv24'
$sub1Path = Join-Path $PSScriptRoot 'english.srt'
$sub2Path = Join-Path $PSScriptRoot 'spanish.srt'

Write-Host 'Running DualSubs subtitle-track smoke test...'
& python $trackScript `
    --runtime $runtimePath `
    --media $mediaPath `
    --sub1 $sub1Path `
    --sub2 $sub2Path
if ($LASTEXITCODE -ne 0) {
    throw "Subtitle-track smoke test failed with exit code $LASTEXITCODE."
}

Write-Host 'Running DualSubs Qt menu smoke test...'
& $menuScript `
    -Runtime $runtimePath `
    -Media $mediaPath `
    -Sub1 $sub1Path `
    -Sub2 $sub2Path
if ($LASTEXITCODE -ne 0) {
    throw "Qt menu smoke test failed with exit code $LASTEXITCODE."
}

Write-Host 'DualSubs smoke tests passed.'
