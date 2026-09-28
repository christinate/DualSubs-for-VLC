[CmdletBinding()]
param(
    [string]$SourceRoot,
    [string]$ContribRoot,
    [string]$MsysRoot,
    [string]$RuntimeRoot,
    [int]$Jobs = [Environment]::ProcessorCount,
    [switch]$Clean
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
if (-not $SourceRoot) {
    $SourceRoot = Join-Path $projectRoot 'upstream\vlc-3.0.24'
}
if (-not $MsysRoot) {
    $MsysRoot = Join-Path $projectRoot 'tools\msys64'
}
if (-not $RuntimeRoot) {
    $RuntimeRoot = Join-Path $projectRoot 'runtime\VLC-DualSubs-3.0.24'
}

$sourceRoot = (Resolve-Path -LiteralPath $SourceRoot).Path
$msysRoot = (Resolve-Path -LiteralPath $MsysRoot).Path
$runtimeRoot = [IO.Path]::GetFullPath($RuntimeRoot)
$projectRoot = (Resolve-Path -LiteralPath $projectRoot).Path
$buildRoot = Join-Path $sourceRoot 'win64'

if (-not $ContribRoot) {
    $contribCandidates = @(
        (Join-Path $sourceRoot 'extras\package\win32\contrib\x86_64-w64-mingw32'),
        (Join-Path $projectRoot 'upstream\vlc-3.0.23\extras\package\win32\contrib\x86_64-w64-mingw32')
    )
    $ContribRoot = $contribCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}
if (-not $ContribRoot -or -not (Test-Path -LiteralPath $ContribRoot)) {
    throw 'A built x86_64-w64-mingw32 VLC contrib tree is required. Pass its path with -ContribRoot.'
}
$contribRoot = (Resolve-Path -LiteralPath $ContribRoot).Path

foreach ($path in @($sourceRoot, $msysRoot, $contribRoot)) {
    if (-not $path.StartsWith($projectRoot + [IO.Path]::DirectorySeparatorChar)) {
        throw "Windows builds require source, MSYS2, and contrib paths under the workspace alias: $path"
    }
}

function ConvertTo-MsysWorkspacePath {
    param([string]$Path)

    $relative = $Path.Substring($projectRoot.Length).TrimStart('\', '/')
    return '/v/' + $relative.Replace('\', '/')
}

$substOutput = (& $env:ComSpec /c subst 2>&1) -join [Environment]::NewLine
$vDriveMapped = $substOutput -match '(?im)^V:\\: => '
if (-not $vDriveMapped) {
    & $env:ComSpec /c "subst V: `"$projectRoot`""
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to create the temporary V: workspace alias.'
    }
} elseif ($substOutput -notmatch [regex]::Escape($projectRoot)) {
    throw "V: is already mapped to a different location: $substOutput"
}

if ($Clean -and (Test-Path -LiteralPath $buildRoot)) {
    $resolvedBuildRoot = (Resolve-Path -LiteralPath $buildRoot).Path
    if (-not $resolvedBuildRoot.StartsWith($sourceRoot + [IO.Path]::DirectorySeparatorChar)) {
        throw "Refusing to clean an unsafe build path: $resolvedBuildRoot"
    }
    Remove-Item -LiteralPath $resolvedBuildRoot -Recurse -Force
}

$sourceMsys = ConvertTo-MsysWorkspacePath -Path $sourceRoot
$contribMsys = ConvertTo-MsysWorkspacePath -Path $contribRoot
$msysMsys = ConvertTo-MsysWorkspacePath -Path $msysRoot
$bashPath = Join-Path $msysRoot 'usr\bin\bash.exe'
if (-not (Test-Path -LiteralPath $bashPath)) {
    throw "MSYS2 bash was not found: $bashPath"
}

$bashCommand = @"
set -euo pipefail
export PATH="$msysMsys/mingw64/bin:$msysMsys/usr/bin:`$PATH"
cd "$sourceMsys"
mkdir -p win64
cd win64
if [ ! -f Makefile ]; then
  BUILDCC=cc LD=/mingw64/x86_64-w64-mingw32/bin/ld.exe ../extras/package/win32/configure.sh \
    --build=x86_64-pc-cygwin \
    --host=x86_64-w64-mingw32 \
    --with-contrib="$contribMsys" \
    --enable-qt --enable-skins2 --enable-dvdread --enable-caca \
    --disable-nls --disable-dbus --disable-dxva2 --disable-d3d11va \
    --disable-crystalhd --disable-chromecast
fi
make -C src -j$Jobs libvlccore.la
make -C modules -j$Jobs \
  libqt_plugin.la \
  liblibass_plugin.la \
  libsubsdec_plugin.la \
  libsubstx3g_plugin.la \
  libttml_plugin.la \
  libwebvtt_plugin.la
make -C lib -j$Jobs libvlc.la
"@

$env:MSYSTEM = 'MINGW64'
$env:CHERE_INVOKING = '1'
$env:MSYS2_PATH_TYPE = 'inherit'
& $bashPath -lc $bashCommand
if ($LASTEXITCODE -ne 0) {
    throw "VLC Windows build failed with exit code $LASTEXITCODE."
}

$payloadMap = [ordered]@{
    'libvlc.dll' = 'lib\.libs\libvlc.dll'
    'libvlccore.dll' = 'src\.libs\libvlccore.dll'
    'plugins\gui\libqt_plugin.dll' = 'modules\.libs\libqt_plugin.dll'
    'plugins\codec\liblibass_plugin.dll' = 'modules\.libs\liblibass_plugin.dll'
    'plugins\codec\libsubsdec_plugin.dll' = 'modules\.libs\libsubsdec_plugin.dll'
    'plugins\codec\libsubstx3g_plugin.dll' = 'modules\.libs\libsubstx3g_plugin.dll'
    'plugins\codec\libttml_plugin.dll' = 'modules\.libs\libttml_plugin.dll'
    'plugins\codec\libwebvtt_plugin.dll' = 'modules\.libs\libwebvtt_plugin.dll'
}

foreach ($entry in $payloadMap.GetEnumerator()) {
    $sourcePath = Join-Path $buildRoot $entry.Value
    if (-not (Test-Path -LiteralPath $sourcePath)) {
        throw "Expected Windows build output is missing: $sourcePath"
    }
    $destinationPath = Join-Path $runtimeRoot $entry.Key
    New-Item -ItemType Directory -Path (Split-Path -Path $destinationPath -Parent) -Force | Out-Null
    Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Force
}

Write-Host "Windows build completed and staged at $runtimeRoot"
