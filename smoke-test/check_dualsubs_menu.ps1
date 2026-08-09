[CmdletBinding()]
param(
    [string]$Runtime = (Join-Path $PSScriptRoot '..\\runtime\\VLC-DualSubs'),
    [string]$Media = (Join-Path $PSScriptRoot 'colorbars.rv24'),
    [string]$Sub1 = (Join-Path $PSScriptRoot 'english.srt'),
    [string]$Sub2 = (Join-Path $PSScriptRoot 'spanish.srt'),
    [string]$Screenshot = (Join-Path $PSScriptRoot '..\\runtime\\dualsubs-menu-proof.png')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;

public static class DualSubsWin32 {
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hwnd);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hwnd, out RECT rect);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hwnd, IntPtr hDC, uint flags);
  public delegate bool EnumWindowsProc(IntPtr hwnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr hwnd, EnumWindowsProc cb, IntPtr lParam);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hwnd, System.Text.StringBuilder lpString, int nMaxCount);
  [DllImport("oleacc.dll")] public static extern int AccessibleObjectFromWindow(IntPtr hwnd, uint dwId, ref Guid riid, [In, Out, MarshalAs(UnmanagedType.Interface)] ref object ppvObject);
}

public struct RECT {
  public int Left;
  public int Top;
  public int Right;
  public int Bottom;
}
'@

function Get-DualSubsMenuHandle {
    param([IntPtr]$MainWindowHandle)

    $script:menuHandle = [IntPtr]::Zero
    $callback = [DualSubsWin32+EnumWindowsProc]{
        param($hwnd, $lParam)
        $text = New-Object System.Text.StringBuilder 256
        [DualSubsWin32]::GetWindowText($hwnd, $text, $text.Capacity) | Out-Null
        if ([DualSubsWin32]::IsWindowVisible($hwnd) -and $text.ToString() -eq 'QMenuBarClassWindow') {
            $script:menuHandle = $hwnd
            return $false
        }
        return $true
    }

    [DualSubsWin32]::EnumChildWindows($MainWindowHandle, $callback, [IntPtr]::Zero) | Out-Null
    return $script:menuHandle
}

function Save-WindowScreenshot {
    param(
        [IntPtr]$WindowHandle,
        [string]$Path
    )

    $rect = New-Object RECT
    [DualSubsWin32]::GetWindowRect($WindowHandle, [ref]$rect) | Out-Null

    $bitmap = New-Object System.Drawing.Bitmap ($rect.Right - $rect.Left), ($rect.Bottom - $rect.Top)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $hdc = $graphics.GetHdc()
    [DualSubsWin32]::PrintWindow($WindowHandle, $hdc, 0) | Out-Null
    $graphics.ReleaseHdc($hdc)
    $graphics.Dispose()
    $bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    $bitmap.Dispose()
}

$runtimePath = (Resolve-Path $Runtime).Path
$mediaPath = (Resolve-Path $Media).Path
$sub1Path = (Resolve-Path $Sub1).Path
$sub2Path = (Resolve-Path $Sub2).Path
$menuNames = @()

$startInfo = [System.Diagnostics.ProcessStartInfo]::new()
$startInfo.FileName = Join-Path $runtimePath 'vlc.exe'
$startInfo.Arguments = [string]::Join(' ', @(
    '--intf=qt',
    '--no-qt-privacy-ask',
    '--no-one-instance',
    '--no-started-from-file',
    '--no-one-instance-when-started-from-file',
    '--demux=rawvideo',
    '--rawvid-fps=1',
    '--rawvid-width=320',
    '--rawvid-height=180',
    '--rawvid-chroma=RV24',
    ('"--input-slave=' + $sub1Path + '#' + $sub2Path + '"'),
    ('"' + $mediaPath + '"')
))
$startInfo.WorkingDirectory = $runtimePath
$startInfo.UseShellExecute = $false
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError = $true
$startInfo.Environment['VLC_PLUGIN_PATH'] = Join-Path $runtimePath 'plugins'
$startInfo.Environment['PATH'] = $runtimePath + ';' + [System.Environment]::GetEnvironmentVariable('PATH')

$proc = [System.Diagnostics.Process]::Start($startInfo)
if (-not $proc) {
    throw 'Failed to launch VLC runtime.'
}

try {
    $deadline = (Get-Date).AddSeconds(30)
    do {
        Start-Sleep -Milliseconds 500
        $proc.Refresh()
        if ($proc.HasExited) {
            break
        }
    } while ($proc.MainWindowHandle -eq 0 -and (Get-Date) -lt $deadline)

    if ($proc.HasExited) {
        throw "VLC exited early with code $($proc.ExitCode)."
    }

    [DualSubsWin32]::ShowWindow($proc.MainWindowHandle, 9) | Out-Null
    Start-Sleep -Milliseconds 1000

    $menuHandle = Get-DualSubsMenuHandle -MainWindowHandle $proc.MainWindowHandle
    if ($menuHandle -eq [IntPtr]::Zero) {
        throw 'Could not find the Qt menu bar window.'
    }

    $iid = [Guid]'618736E0-3C3D-11CF-810C-00AA00389B71'
    $menuObject = $null
    $hr = [DualSubsWin32]::AccessibleObjectFromWindow(
        $menuHandle,
        [uint32]4294967292,
        [ref]$iid,
        [ref]$menuObject
    )
    if ($hr -ne 0 -or -not $menuObject) {
        throw "AccessibleObjectFromWindow failed with HRESULT $hr."
    }

    for ($i = 1; $i -le $menuObject.accChildCount; $i++) {
        $menuNames += [string]$menuObject.accName($i)
    }

    Save-WindowScreenshot -WindowHandle $proc.MainWindowHandle -Path $Screenshot

    $result = [ordered]@{
        ok = $menuNames -contains 'DualSubs'
        menuNames = $menuNames
        screenshot = (Resolve-Path $Screenshot).Path
    }

    $result | ConvertTo-Json -Depth 4

    if (-not $result.ok) {
        exit 1
    }
} finally {
    if ($proc -and -not $proc.HasExited) {
        $proc.CloseMainWindow() | Out-Null
        Start-Sleep -Seconds 2
        if (-not $proc.HasExited) {
            Stop-Process -Id $proc.Id -Force
        }
    }
}
