# DualSubs Windows Packaging

This folder builds a Windows NSIS overlay installer for the DualSubs-enabled VLC 3.0.23 runtime.

What it does:

- ships only the eight VLC binaries changed by DualSubs
- overlays those files onto an existing VLC install
- backs up the original VLC files before replacement
- restores originals on uninstall when the current file still matches the DualSubs-installed version
- avoids rolling back files that were changed later by a VLC update or manual replacement

Primary scripts:

- `build-dualsubs-installer.ps1` builds the payload, writes the manifest, and compiles the installer with `makensis.exe`
- `DualSubsOverlay.nsi` is the NSIS installer definition
- `Install-DualSubs.ps1` performs the overlay install
- `Uninstall-DualSubs.ps1` restores backed-up originals
- `test-dualsubs-installer.ps1` runs a workspace-safe install/uninstall restore test against a copied VLC tree

Usage:

```powershell
.\packaging\windows\build-dualsubs-installer.ps1
.\packaging\windows\test-dualsubs-installer.ps1
```

The packaged installer is written to `packaging/windows/dist/`.
