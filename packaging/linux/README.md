# DualSubs Linux Build Notes

The DualSubs feature itself is already wired into Linux-relevant VLC code paths:

- core input/subtitle handling in `src/input/*`
- subtitle rendering changes in `modules/codec/libass.c`
- Qt menu integration in `modules/gui/qt/menus.*`

That means Linux does **not** need a separate UI patch beyond building the modified VLC source.

Build entry point:

```bash
./packaging/linux/build-dualsubs-linux.sh
```

Installer packaging entry point:

```bash
./packaging/linux/build-dualsubs-deb.sh
```

Installer behavior:

- Builds a separate Debian package named `vlc-dualsubs`.
- The package installs under `/opt/vlc-dualsubs`.
- The stock system VLC install is left untouched.
- A launcher is added at `/usr/bin/vlc-dualsubs`.

Validated builder:

- `ssh mint`

Validated outputs:

- built VLC tree: `/home/nate/dualsubs-build/upstream/vlc-3.0.23/build-linux-dualsubs`
- packaged installer: `/home/nate/dualsubs-build/packaging/linux/dist/vlc-dualsubs_3.0.23+dualsubs0.1.0-1_amd64.deb`
