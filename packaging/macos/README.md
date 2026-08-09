# DualSubs macOS Build Notes

The macOS-specific menu integration for DualSubs is already implemented in:

- `modules/gui/macosx/VLCMainMenu.m`

The shared DualSubs core and subtitle-rendering changes also apply to macOS:

- `src/input/var.c`
- `src/input/decoder.c`
- `src/input/es_out.c`
- `modules/codec/libass.c`

Build entry point:

```bash
./packaging/macos/build-dualsubs-macos.sh
```

That wrapper delegates to VLC's existing macOS packaging script:

- `extras/package/macosx/build.sh`

Installer packaging entry point:

```bash
./packaging/macos/build-dualsubs-pkg.sh
```

Installer behavior:

- Builds an unsigned Apple `pkg` for now.
- The package installs support files under `/Library/Application Support/DualSubs for VLC`.
- The package postinstall script patches `/Applications/VLC.app` by default.
- The packaged uninstaller entry point is `Uninstall DualSubs.command`.

Validated builder:

- `ssh macbook1`

Validated outputs:

- built app bundle: `~/dualsubs-build/upstream/vlc-3.0.23/build-macos-dualsubs-aarch64/VLC.app`
- packaged installer: `~/dualsubs-build/packaging/macos/dist/DualSubs-for-VLC-3.0.23-macOS-Overlay.pkg`
