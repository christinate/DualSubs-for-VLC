# Source Overlay

This folder contains the Git-tracked copy of every VLC file that DualSubs changes or depends on for the current `3.0.23` baseline.

The repo tracks this overlay instead of the full unpacked VLC source tree so Git stays small and reviewable.

## Normal Workflow

1. Extract pristine VLC source under `upstream/vlc-3.0.23/`.
2. Apply this overlay into that working tree:

```powershell
.\tools\apply-source-overlay.ps1
```

3. Build from the local `upstream/vlc-3.0.23/` tree by following [../Update.md](../Update.md).
4. If you edit the working tree, copy those changes back here before staging:

```powershell
.\tools\refresh-source-overlay.ps1
```

If a future VLC port needs an additional tracked file, add it here and update your local Git whitelist in the same change.
