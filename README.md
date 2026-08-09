# DualSubs for VLC 3.0.23

DualSubs is a VLC source patch for `3.0.23` that adds a new top-level desktop menu named `DualSubs`.

DualSubs lets you:

- choose up to two subtitle tracks from the current media
- keep VLC's normal `Subtitle` menu working as a single-track selector
- render the first checked track above the second checked track
- wait until exactly two tracks are checked before showing any subtitles
- use different fallback colors per track when the subtitle text does not already define its own color
- preserve authored subtitle colors when they are present

## Installation

Download the VLC version 3.0.23 for your operating system and install. If they have since updated, the archive is here https://download.videolan.org/pub/videolan/vlc/3.0.23/
Then download the release installer for your OS and install from here:
https://github.com/christinate/DualSubs-for-VLC/releases
Tada! 


## What Was Changed

This repository tracks the DualSubs source overlay in:

- `source-overlay/vlc-3.0.23/`

Main DualSubs feature files:

- `src/input/var.c`
- `src/input/es_out.c`
- `src/input/decoder.c`
- `modules/codec/substext.h`
- `modules/codec/libass.c`
- `modules/gui/qt/menus.hpp`
- `modules/gui/qt/menus.cpp`
- `modules/gui/macosx/VLCMainMenu.m`

## Behavior Notes

- This is a VLC source patch, not a Lua extension or standalone drop-in binary plugin.
- Qt desktop VLC gets the `DualSubs` menu for Windows and Linux.
- Native macOS VLC gets the same `DualSubs` top-level menu.
- Text subtitle focus is implemented first: `SRT`, `ASS/SSA`, `WebVTT`, and other text-decoded subtitle paths that flow through VLC's text subtitle stack.
- `ASS/SSA` is forced into bottom-stacked DualSubs placement when used through the new menu, so authored positioning is intentionally ignored in DualSubs mode.
- Bitmap subtitle formats such as `PGS` and `VobSub` are not part of this first pass.

## Build your own

1. Download and extract the official VLC `3.0.23` source locally under `upstream/vlc-3.0.23/`.
2. Apply the tracked DualSubs overlay:

```powershell
.\tools\apply-source-overlay.ps1
```

3. Build VLC from that patched working tree.
4. Use the platform packaging scripts under `packaging/windows`, `packaging/macos`, and `packaging/linux`.

High-level packaging flow:

- Windows builds an overlay installer for an existing VLC install.
- macOS builds an unsigned overlay `pkg` for an existing `/Applications/VLC.app`.
- Linux builds a separate `vlc-dualsubs` package under `/opt/vlc-dualsubs`.

