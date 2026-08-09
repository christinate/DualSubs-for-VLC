# DualSubs Update Manager

This file is the source-of-truth playbook for updating DualSubs to a newer VLC release.

Important reality check:

- DualSubs is not a drop-in VLC plugin in the usual sense.
- DualSubs is a VLC source patch plus platform packaging/install scripts.
- When VLC upstream changes, we have to port the patch forward, rebuild VLC for each platform, and then rebuild the platform packaging around those binaries.
- The Git-tracked VLC customizations now live under `source-overlay/vlc-3.0.23/`.
- Local working trees under `upstream/` are generated build inputs and are intentionally kept out of Git.

## Current Baseline

- DualSubs feature baseline: `VLC 3.0.23`
- Windows installer target that was validated: `C:\Program Files\VideoLAN\VLC\vlc.exe`
- Windows deliverable: NSIS overlay installer that patches an existing VLC install
- macOS deliverable: unsigned Apple `pkg` overlay installer that patches `/Applications/VLC.app`
- Linux deliverable: separate `vlc-dualsubs` Debian package that installs under `/opt/vlc-dualsubs`
- macOS builder used: `ssh macbook1`
- Linux builder used: `ssh mint`
- Direct macOS builder fallback: `ssh -i "C:\Users\Nate Fowler\.ssh\id_ed25519" natefowler@192.168.10.109`
- Direct Linux builder fallback: `ssh -i "C:\Users\Nate Fowler\.ssh\id_ed25519" nate@192.168.10.107`
- First-pass subtitle scope: text subtitle formats only

## What Must Be Preserved

Behavior that defines DualSubs:

- A top-level `DualSubs` menu appears in VLC.
- The user can check up to two subtitle tracks from the current media.
- Subtitles do not display until exactly two tracks are selected.
- The first selected track renders above the second selected track.
- Both tracks stay bottom-aligned.
- Authored subtitle colors are preserved when present.
- Fallback colors differ when authored colors are absent.
- ASS/SSA positioning is intentionally ignored in DualSubs mode so stacking remains correct.
- The normal VLC subtitle menu should continue to exist for single-track behavior.

Current fallback colors in code:

- Track 1: `0xFFE082`
- Track 2: `0x80DEEA`

## Shared Feature Patch Files

These are the main DualSubs feature files that must be reviewed and ported first whenever VLC changes:

- `source-overlay/vlc-3.0.23/src/input/var.c`
- `source-overlay/vlc-3.0.23/src/input/es_out.c`
- `source-overlay/vlc-3.0.23/src/input/decoder.c`
- `source-overlay/vlc-3.0.23/modules/codec/substext.h`
- `source-overlay/vlc-3.0.23/modules/codec/libass.c`
- `source-overlay/vlc-3.0.23/modules/gui/qt/menus.hpp`
- `source-overlay/vlc-3.0.23/modules/gui/qt/menus.cpp`
- `source-overlay/vlc-3.0.23/modules/gui/macosx/VLCMainMenu.m`

Copy these tracked files onto a local `upstream/vlc-3.0.23/` working tree before building.

What each file is responsible for:

- `src/input/var.c`
  Creates the input variables `dualsubs-es`, `dualsubs-track-1`, and `dualsubs-track-2`.
- `src/input/es_out.c`
  Participates in selecting and managing subtitle elementary streams.
- `src/input/decoder.c`
  Maps each selected subtitle track to a DualSubs slot and applies fallback styling when the subtitle text does not already define color.
- `modules/codec/substext.h`
  Shared subtitle text structures needed by the rendering path.
- `modules/codec/libass.c`
  Forces DualSubs subtitles into a bottom-stacked layout and ignores authored positional height in DualSubs mode.
- `modules/gui/qt/menus.hpp`
  Qt menu declarations for Windows and Linux.
- `modules/gui/qt/menus.cpp`
  Adds the `DualSubs` top menu and enforces the two-track selection behavior.
- `modules/gui/macosx/VLCMainMenu.m`
  Adds the native macOS `DualSubs` top menu and the same two-track selection behavior.

## Platform-Specific Build Patches

These are not the feature itself. They are the platform-specific changes and wrappers that were needed to make the builds succeed.

### Windows

Build-related patch:

- `upstream/vlc-3.0.23/extras/package/win32/configure.sh`

Why it exists:

- It contains `fix_windows_libtool_paths()`.
- That function patches `libtool` after configure so MinGW C++ runtime search paths survive workspace layouts with spaces in the path.
- This was important for this workspace because the project lives under `C:\Users\Nate Fowler\Documents\VLC Plugin`.

Packaging and installer files:

- `packaging/windows/build-dualsubs-installer.ps1`
- `packaging/windows/DualSubsOverlay.nsi`
- `packaging/windows/Install-DualSubs.ps1`
- `packaging/windows/Uninstall-DualSubs.ps1`
- `packaging/windows/test-dualsubs-installer.ps1`
- `smoke-test/run_dualsubs_smoke.ps1`
- `smoke-test/check_dualsubs_menu.ps1`
- `smoke-test/check_dualsubs_tracks.py`

What the Windows overlay installer ships:

- `libvlc.dll`
- `libvlccore.dll`
- `plugins/gui/libqt_plugin.dll`
- `plugins/codec/liblibass_plugin.dll`
- `plugins/codec/libsubsdec_plugin.dll`
- `plugins/codec/libsubstx3g_plugin.dll`
- `plugins/codec/libttml_plugin.dll`
- `plugins/codec/libwebvtt_plugin.dll`

Windows install/uninstall behavior:

- Installs only the changed VLC files over an existing VLC installation.
- Uses NSIS for the user-facing installer shell.
- Defaults the folder chooser to the normal VLC install path and also lets the user point at a different existing VLC folder.
- Validates that the selected folder already contains `vlc.exe` before patching.
- Stores backups under `VLC\DualSubs\backup\`.
- Stores install state in `VLC\DualSubs\install-manifest.json`.
- Restores originals only when the current file hash still matches the DualSubs-installed file hash.
- Leaves later user-updated or VLC-updated files alone instead of blindly overwriting them during uninstall.
- Writes `Uninstall DualSubs.exe` into the target VLC folder and registers that uninstaller in Windows uninstall metadata.

Branding assets:

- `assets/branding/dualsubs-logo.png`
- `assets/branding/dualsubs-icon.png`
- `assets/branding/dualsubs-icon.ico`

Installer note:

- The original Windows overlay flow used `IExpress` earlier in development.
- The validated shipping flow is now `NSIS` via `makensis.exe`.

### macOS

Build wrapper:

- `packaging/macos/build-dualsubs-macos.sh`
- `packaging/macos/build-dualsubs-pkg.sh`
- `packaging/macos/Install-DualSubs.sh`
- `packaging/macos/Uninstall-DualSubs.sh`
- `packaging/macos/Uninstall DualSubs.command`

Upstream macOS packaging script that was locally adjusted:

- `upstream/vlc-3.0.23/extras/package/macosx/build.sh`

What changed there:

- Host architecture handling was tightened with `CONFIGURE_HOST_ARCH`.
- The configure host triplet was made explicit with `CONFIGURE_HOST_TRIPLET`.
- The configure invocation passes `--host=$CONFIGURE_HOST_TRIPLET`.
- The configure invocation passes `--with-contrib=...`.
- `--disable-sparkle` was added to avoid that dependency during the build.

Why it exists:

- The stock VLC 3.0.23 macOS build flow needed clearer host/contrib wiring on the builder we used.
- Disabling Sparkle kept the build path simpler and more repeatable.

macOS installer behavior:

- The package is intentionally unsigned for now.
- The package installs its support files under `/Library/Application Support/DualSubs for VLC`.
- Its postinstall step runs `Install-DualSubs.sh`, which patches `/Applications/VLC.app` by default.
- It backs up original files under `/Library/Application Support/DualSubs for VLC/State/backup`.
- It records install state in `/Library/Application Support/DualSubs for VLC/State/install-manifest.tsv`.
- The packaged uninstaller entry point is `/Library/Application Support/DualSubs for VLC/Uninstall DualSubs.command`.
- The uninstaller only restores files when the current file still matches the DualSubs-installed hash.

macOS payload file map that was validated:

- `Contents/MacOS/VLC`
- `Contents/MacOS/lib/libvlc.5.dylib`
- `Contents/MacOS/lib/libvlccore.9.dylib`
- `Contents/MacOS/plugins/libmacosx_plugin.dylib`
- `Contents/MacOS/plugins/liblibass_plugin.dylib`
- `Contents/MacOS/plugins/libsubsdec_plugin.dylib`
- `Contents/MacOS/plugins/libsubstx3g_plugin.dylib`
- `Contents/MacOS/plugins/libttml_plugin.dylib`
- `Contents/MacOS/plugins/libwebvtt_plugin.dylib`
- `Contents/MacOS/plugins/plugins.dat`

### Linux

Build wrapper:

- `packaging/linux/build-dualsubs-linux.sh`
- `packaging/linux/build-dualsubs-deb.sh`

Linux-specific compat or build fixes that were needed:

- `upstream/vlc-3.0.23/contrib/src/fontconfig/rules.mak`
- `upstream/vlc-3.0.23/contrib/src/zvbi/rules.mak`
- `upstream/vlc-3.0.23/contrib/src/xcb-proto/rules.mak`
- `upstream/vlc-3.0.23/contrib/src/xcb/rules.mak`

Why they existed:

- `fontconfig/rules.mak`
  Helped old VLC contrib logic survive on a modern minimal builder, including gperf-related friction.
- `zvbi/rules.mak`
  Helped autoreconf/autopoint steps succeed on the builder.
- `xcb-proto/rules.mak`
  Updated old Python 2 assumptions so legacy xcbgen content could run with Python 3.
- `xcb/rules.mak`
  Added more Python compatibility and explicit `PYTHONPATH`, plus a pthread-stubs related shim.

Linux configure/build flags that mattered:

- Contrib bootstrap:
  `--host="$HOST_TRIPLET" --disable-x264 --disable-x26410b"`
- Configure:
  `--with-contrib="$CONTRIB_INSTALL_DIR" --enable-qt --disable-alsa --disable-vnc --disable-vcd --disable-chromaprint`

Linux environment fixes that mattered:

- Build `extras/tools` first.
- Ensure `pkg.m4` exists in the built aclocal path.
- Export `PKG_CONFIG_PATH` to the contrib install tree.
- Export full static `GNUTLS_LIBS` if configure does not surface private crypto dependencies.
- Export full static `SRT_LIBS` for the same reason.

Why those Linux flags were needed on the validated builder:

- `--disable-alsa`
  The Mint builder was missing ALSA development headers.
- `qmake6` had to be installed
  Qt 6 tooling was required for the Qt UI build.
- `--disable-vnc`
  Avoided a VNC plugin link failure caused by a GnuTLS/nettle dependency chain.
- `--disable-vcd`
  Avoided a CDDA/VCD plugin link failure involving `@LIBICONV@`.
- `GNUTLS_LIBS` and `SRT_LIBS`
  Prevented static-link failures when private library dependencies were omitted by configure.
- `--disable-chromaprint`
  Avoided a non-PIC FFmpeg/chromaprint link failure.

Linux package behavior:

- Linux does not patch the system VLC install.
- The Debian package installs a separate DualSubs-enabled app under `/opt/vlc-dualsubs`.
- It adds a launcher at `/usr/bin/vlc-dualsubs`.
- It adds a desktop entry at `/usr/share/applications/vlc-dualsubs.desktop`.
- It installs the app icon as `/usr/share/icons/hicolor/512x512/apps/vlc-dualsubs.png`.
- The launcher exports `LD_LIBRARY_PATH`, `VLC_PLUGIN_PATH`, `VLC_DATA_PATH`, and `XDG_DATA_DIRS` so the separate install is self-contained.

Linux packaging quirk that must be preserved:

- `make install` had to stage into a temporary `/usr/local` tree first because VLC/libtool refused direct installation into `/opt/vlc-dualsubs`.
- After staging, that `/usr/local` tree was relocated into `/opt/vlc-dualsubs` inside the Debian package payload.

## Validated Build Entry Points

### Windows

Windows source build:

- Build VLC from the patched source tree using VLC's Windows build system under `extras/package/win32/`.
- Keep the `fix_windows_libtool_paths()` patch in `extras/package/win32/configure.sh` if the new build still runs from a workspace path with spaces.

Windows overlay installer build:

```powershell
.\packaging\windows\build-dualsubs-installer.ps1 -RuntimeRoot .\runtime\VLC-DualSubs -VlcVersion 3.0.23 -DualSubsVersion 0.1.0
```

Windows overlay installer test:

```powershell
.\packaging\windows\test-dualsubs-installer.ps1
```

Expected output:

- `packaging/windows/dist/DualSubs-for-VLC-<vlc-version>-x64-Overlay.exe`

Validated Windows artifact:

- `C:\Users\Nate Fowler\Documents\VLC Plugin\packaging\windows\dist\DualSubs-for-VLC-3.0.23-x64-Overlay.exe`

### macOS

Run on the Mac builder:

```bash
./packaging/macos/build-dualsubs-macos.sh
```

Optional architecture override:

```bash
ARCH=aarch64 ./packaging/macos/build-dualsubs-macos.sh
ARCH=x86_64 ./packaging/macos/build-dualsubs-macos.sh
```

Validated remote host:

- `ssh macbook1`
- or `ssh -i "C:\Users\Nate Fowler\.ssh\id_ed25519" natefowler@192.168.10.109`

Validated macOS output from the baseline build:

- `~/dualsubs-build/upstream/vlc-3.0.23/build-macos-dualsubs-aarch64/VLC.app`

macOS package build:

```bash
./packaging/macos/build-dualsubs-pkg.sh
```

Validated macOS package outputs:

- remote: `/Users/natefowler/dualsubs-build/packaging/macos/dist/DualSubs-for-VLC-3.0.23-macOS-Overlay.pkg`
- local: `C:\Users\Nate Fowler\Documents\VLC Plugin\packaging\macos\dist\DualSubs-for-VLC-3.0.23-macOS-Overlay.pkg`

### Linux

Run on the Linux builder:

```bash
./packaging/linux/build-dualsubs-linux.sh
```

Validated remote host:

- `ssh mint`
- or `ssh -i "C:\Users\Nate Fowler\.ssh\id_ed25519" nate@192.168.10.107`

Validated Linux outputs from the baseline build:

- `/home/nate/dualsubs-build/upstream/vlc-3.0.23/build-linux-dualsubs/bin/vlc`
- `/home/nate/dualsubs-build/upstream/vlc-3.0.23/build-linux-dualsubs/modules/.libs/libqt_plugin.so`
- `/home/nate/dualsubs-build/upstream/vlc-3.0.23/build-linux-dualsubs/lib/.libs/libvlc.so.5.6.1`
- `/home/nate/dualsubs-build/upstream/vlc-3.0.23/build-linux-dualsubs/src/.libs/libvlccore.so.9.0.1`

Linux package build:

```bash
./packaging/linux/build-dualsubs-deb.sh
```

Validated Linux package outputs:

- remote: `/home/nate/dualsubs-build/packaging/linux/dist/vlc-dualsubs_3.0.23+dualsubs0.1.0-1_amd64.deb`
- local: `C:\Users\Nate Fowler\Documents\VLC Plugin\packaging\linux\dist\vlc-dualsubs_3.0.23+dualsubs0.1.0-1_amd64.deb`

## Installer Artifacts

Validated installer artifacts currently in this workspace:

- Windows: `C:\Users\Nate Fowler\Documents\VLC Plugin\packaging\windows\dist\DualSubs-for-VLC-3.0.23-x64-Overlay.exe`
- macOS: `C:\Users\Nate Fowler\Documents\VLC Plugin\packaging\macos\dist\DualSubs-for-VLC-3.0.23-macOS-Overlay.pkg`
- Linux: `C:\Users\Nate Fowler\Documents\VLC Plugin\packaging\linux\dist\vlc-dualsubs_3.0.23+dualsubs0.1.0-1_amd64.deb`

## Cross-Version Update Workflow

Use this every time VLC releases a new version.

1. Add a fresh source tree under `upstream/vlc-X.Y.Z`.
2. Port the shared DualSubs feature files first.
3. Re-apply only the platform build patches that are still necessary.
4. Update version strings in packaging scripts and docs.
5. Rebuild Windows.
6. Rebuild macOS on `ssh macbook1`.
7. Rebuild Linux on `ssh mint`.
8. Rebuild the Windows NSIS overlay installer.
9. Rebuild the macOS unsigned `pkg` installer.
10. Rebuild the Linux `vlc-dualsubs` `.deb`.
11. If the remote workspaces are stale, upload the updated packaging scripts first.
12. Run smoke tests and manual feature verification.
13. Record any newly required platform workarounds back into this file.

## Porting Checklist For A New VLC Version

When moving from `3.0.23` to a newer VLC version:

1. Diff each file in the old patched tree against the same file in the new VLC version.
2. Re-port the DualSubs behavior, not just the old line numbers.
3. Check whether VLC changed subtitle track variable handling, decoder ownership, libass rendering flow, or Qt/macOS menu APIs.
4. Re-test that `dualsubs-track-1` is still the upper subtitle and `dualsubs-track-2` is still the lower subtitle.
5. Re-test that authored colors still win over fallback colors.
6. Re-test that ASS/SSA authored positioning is still overridden only in DualSubs mode.
7. Re-test that a single checked DualSubs track still does not render.
8. Re-test that unchecking back to fewer than two tracks hides subtitles again.
9. Re-check whether any Linux contrib compatibility patches can be dropped because upstream VLC or the builder environment no longer needs them.
10. Re-check whether the macOS `--disable-sparkle` and explicit host triplet wiring are still required.
11. Re-check whether the Windows `fix_windows_libtool_paths()` patch is still required.

## Platform Requirements To Remember

### Windows

- Existing VLC install present, currently expected at `C:\Program Files\VideoLAN\VLC`
- Admin rights when patching `Program Files`
- `NSIS` installed with `makensis.exe` available
- Validated path: `C:\Program Files (x86)\NSIS\makensis.exe`
- `vlc-cache-gen.exe` available in the installed VLC tree for plugin cache refresh

### macOS

- Native macOS build machine
- Xcode or Command Line Tools
- Apple SDK and normal macOS build chain
- Access to the configured builder alias `macbook1`
- Or direct SSH access to `natefowler@192.168.10.109` with `id_ed25519`
- `pkgbuild` available
- Built `VLC.app` already present before running `build-dualsubs-pkg.sh`

### Linux

- Native Linux build machine
- Access to the configured builder alias `mint`
- Or direct SSH access to `nate@192.168.10.107` with `id_ed25519`
- Compiler toolchain and autotools
- Qt 6 tooling including `qmake6`
- Python 3
- Enough build dependencies for VLC contribs
- Debian packaging tools including `dpkg-deb`
- Branding asset available at `assets/branding/dualsubs-icon.png`

## Verification Checklist

Run this on every rebuilt platform:

1. Open media with at least two text subtitle tracks.
2. Confirm the top menu includes `DualSubs`.
3. Check only one track and confirm subtitles stay hidden.
4. Check a second track and confirm both tracks appear.
5. Confirm the first selected track is above the second selected track.
6. Confirm both tracks remain bottom-aligned.
7. Uncheck back to one or zero and confirm subtitles hide again.
8. Confirm only two tracks can be selected at once.
9. Confirm fallback colors differ when no subtitle color is authored.
10. Confirm authored subtitle colors are preserved when present.

## Future One-Prompt Template

When a new VLC version is released, the next prompt can be a single request like this:

```text
Read C:\Users\Nate Fowler\Documents\VLC Plugin\Update.md and use it as the source of truth. Upgrade DualSubs from VLC 3.0.23 to VLC X.Y.Z. Port the shared DualSubs source patch into upstream/vlc-X.Y.Z, re-apply only the platform-specific build fixes that are still needed, update all version strings and packaging metadata, rebuild the Windows runtime, rebuild the Windows NSIS overlay installer, rebuild macOS on ssh macbook1, rebuild the macOS unsigned pkg installer, rebuild Linux on ssh mint, rebuild the Linux vlc-dualsubs deb package, run the available smoke tests and feature verification checks, and then update Update.md with any new platform-specific requirements, removed workarounds, final artifact paths, and blockers. If any old workaround is no longer necessary on VLC X.Y.Z, remove it and explain why.
```

If you want the next run to be even more explicit, use this version:

```text
Read C:\Users\Nate Fowler\Documents\VLC Plugin\Update.md first and follow it exactly. Upgrade DualSubs to VLC X.Y.Z. Preserve these behaviors: top-level DualSubs menu, exactly two selected subtitle tracks required before display, track 1 above track 2, bottom alignment for both tracks, authored subtitle colors preserved, fallback colors different when no authored colors exist, and ASS/SSA positional height ignored in DualSubs mode. Port the source changes to the new upstream tree, rebuild Windows locally including the NSIS overlay installer and uninstall-safe backup/restore behavior, rebuild macOS on ssh macbook1 and regenerate the unsigned pkg overlay installer, rebuild Linux on ssh mint and regenerate the separate vlc-dualsubs deb package under /opt/vlc-dualsubs, run the smoke tests and manual verification checklist, then write back any new build quirks to Update.md and report the exact output artifact paths.
```

## Maintenance Rule

Every successful rebuild for a new VLC version should end with an `Update.md` refresh so the next upgrade is easier than the last one.
