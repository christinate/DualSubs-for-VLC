# Releasing DualSubs

This file explains how to publish a DualSubs release on GitHub.

Important:

- GitHub does not build VLC for this repository automatically.
- A GitHub Release is a versioned page where we upload the installers that were already built.
- The normal workflow is:
  1. commit and push source changes
  2. build the Windows, macOS, and Linux installers
  3. create a Git tag
  4. create a GitHub Release from that tag
  5. upload the installers as release assets

## Release Checklist

1. Confirm the source repo is clean:

```powershell
git status --short
```

2. Make sure the current source commit is pushed to GitHub.

3. Rebuild or verify the platform installers:

- `packaging/windows/dist/DualSubs-for-VLC-<vlc-version>-x64-Overlay.exe`
- `packaging/macos/dist/DualSubs-for-VLC-<vlc-version>-macOS-Overlay.pkg`
- `packaging/linux/dist/vlc-dualsubs_<vlc-version>+dualsubs<dualsubs-version>-1_amd64.deb`

4. Compute checksums for the release assets:

```powershell
Get-FileHash packaging\windows\dist\*.exe -Algorithm SHA256
Get-FileHash packaging\macos\dist\*.pkg -Algorithm SHA256
Get-FileHash packaging\linux\dist\*.deb -Algorithm SHA256
```

5. Create and push a release tag. Example:

```powershell
git tag -a v0.1.0 -m "DualSubs 0.1.0 for VLC 3.0.23"
git push origin v0.1.0
```

6. On GitHub, open the repository and create a new Release from that tag.

Suggested release title format:

- `DualSubs 0.1.0 for VLC 3.0.23`

Suggested release notes checklist:

- state the VLC base version
- state that Windows is an overlay installer
- state that macOS is an unsigned overlay pkg
- state that Linux installs as separate `vlc-dualsubs`
- include SHA256 checksums for every uploaded asset

7. Upload the built assets to the GitHub Release page:

- `.exe`
- `.pkg`
- `.deb`

8. After the release is live, download at least one asset from GitHub and verify it matches the local SHA256 checksum.

## Current Release Asset Set

As of August 9, 2026, the validated local release assets are:

- `packaging/windows/dist/DualSubs-for-VLC-3.0.23-x64-Overlay.exe`
  SHA256: `FC9CEF026D77FD5CFA1B8523DBE4F2D67B688309BED85D2077BBF1F811133497`
- `packaging/macos/dist/DualSubs-for-VLC-3.0.23-macOS-Overlay.pkg`
  SHA256: `FBB3117F625BFF19E045C111C94F50B2E5F59378E4BED74E0D977122A30DD0A8`
- `packaging/linux/dist/vlc-dualsubs_3.0.23+dualsubs0.1.0-1_amd64.deb`
  SHA256: `2B09BDD96C606546E8A17AAD0E48B5CF14BC5B439D37D886B806B9D6D89EE32C`

## What Not To Do

- Do not commit built installers into normal Git history.
- Do not commit `upstream/`, `runtime/`, temp folders, or toolchain installs.
- Do not create a release from a source tree that has local-only edits.
- Do not delete an old release asset until the replacement has been uploaded and checksum-verified.
