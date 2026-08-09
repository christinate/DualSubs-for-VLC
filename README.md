# DualSubs for VLC

DualSubs is a VLC source patch plus packaging/install tooling that adds a top-level `DualSubs` menu and allows two text subtitle tracks to render at the same time.

Important:

- This is not a standalone VLC plugin DLL or Lua extension.
- VLC `3.0.23` required source changes in the input, subtitle, and desktop UI layers.
- The Git repository should track source overlays, packaging scripts, assets, and tests.
- Built installers should be published as GitHub Release assets, not committed into normal source history.

## Behavior

- The user can check up to two subtitle tracks from the current media.
- Subtitles stay hidden until exactly two tracks are selected.
- Track 1 renders above track 2.
- Both tracks stay bottom-aligned.
- Authored subtitle colors are preserved when present.
- Fallback colors differ when authored colors are absent.
- ASS/SSA positioning is intentionally ignored in DualSubs mode so stacking remains correct.

## Repository Layout

- `source-overlay/vlc-3.0.23/`
  The Git-tracked copy of the VLC source files and helper patches changed by DualSubs.
- `packaging/`
  Windows NSIS, macOS pkg, and Linux deb packaging scripts.
- `assets/branding/`
  DualSubs icons, logo, and branding source files.
- `smoke-test/`
  Basic verification helpers and sample subtitle fixtures.
- `Update.md`
  The platform-by-platform rebuild and update playbook.

## Build Overview

1. Download and extract the official VLC `3.0.23` source locally under `upstream/vlc-3.0.23/`.
2. Apply the tracked DualSubs overlay:

```powershell
.\tools\apply-source-overlay.ps1
```

3. Follow [Update.md](Update.md) and the platform packaging READMEs.
4. Build installers locally and on the remote builders as documented.
5. Publish the finished `.exe`, `.pkg`, and `.deb` files as GitHub Release assets.

## Release Model

GitHub will store the source and docs in the repository, but it will not build VLC for us automatically just by pushing code. If we want downloadable installers on GitHub, we upload the already-built artifacts to a GitHub Release after the source commit is pushed.
