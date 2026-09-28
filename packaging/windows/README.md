# DualSubs Windows Packaging

This folder builds a Windows NSIS overlay installer for the DualSubs-enabled VLC 3.0.24 runtime.

What it does:

- ships only the eight VLC binaries changed by DualSubs
- overlays those files onto an existing VLC install
- backs up the original VLC files before replacement
- restores originals on uninstall when the current file still matches the DualSubs-installed version
- avoids rolling back files that were changed later by a VLC update or manual replacement

Primary scripts:

- `build-dualsubs-windows.ps1` builds the patched VLC source and stages the eight changed binaries
- `build-dualsubs-installer.ps1` builds the payload, writes the manifest, and compiles the installer with `makensis.exe`
- `DualSubsOverlay.nsi` is the NSIS installer definition
- `Install-DualSubs.ps1` performs the overlay install
- `Uninstall-DualSubs.ps1` restores backed-up originals
- `test-dualsubs-installer.ps1` runs a workspace-safe install/uninstall restore test against a copied VLC tree

Usage:

```powershell
.\packaging\windows\build-dualsubs-windows.ps1
.\packaging\windows\build-dualsubs-installer.ps1
.\packaging\windows\test-dualsubs-installer.ps1
```

The default payload source is `runtime/VLC-DualSubs-3.0.24`. Build VLC first,
then stage the eight changed binaries there before creating or testing the installer.

The source build intentionally compiles only `libvlc`, `libvlccore`, the Qt UI,
and the six subtitle plugins shipped by the overlay. Pass a prepared VLC
`x86_64-w64-mingw32` contrib tree inside this workspace with `-ContribRoot` on
a clean build machine. The workspace-local path is required by the temporary
`V:` alias used to keep MinGW paths free of spaces.
This avoids rebuilding unrelated codecs and keeps the overlay compatible with
the stock VLC 3.0.24 installation it patches.

The packaged installer is written to `packaging/windows/dist/`.
