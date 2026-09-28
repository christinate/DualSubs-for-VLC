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

VLC 3.0.24's contrib preparation requires Git and `gperf`. If they cannot be
installed system-wide, the wrapper accepts rootless package extractions at
`.build-tools/git` and `.build-tools/gperf`. The top-level contrib build is
serialized to avoid stale GNU make jobserver descriptors in VLC's bundled
Ninja, while nested CMake projects still use `CMAKE_BUILD_PARALLEL_LEVEL`.
Unused x264, SDL/SDL_image, and zvbi contribs are disabled so the headless
text-subtitle build does not require unavailable video or teletext dependencies.
The tracked libgpg-error contrib rule sets `AUTOPOINT=true` because NLS is
disabled for that dependency and the validated Mint builder has no `autopoint`.
Tracked xcb-proto and libxcb rules normalize their Python generators for Python
3.12 and skip xcb-proto's obsolete `imp`-based bytecode helper during install.

Installer packaging entry point:

```bash
./packaging/linux/build-dualsubs-deb.sh
```

Installer behavior:

- Builds a separate Debian package named `vlc-dualsubs`.
- The package installs under `/opt/vlc-dualsubs`.
- The stock system VLC install is left untouched.
- A launcher is added at `/usr/bin/vlc-dualsubs`.
- Runtime dependencies are derived from every packaged ELF file with
  `dpkg-shlibdeps`; install `dpkg-dev` and `file` on the packaging host.
- Dependency generation uses the package's private library paths, fails the
  build on unresolved errors, and excludes only bundled `libvlc`/`libvlccore`.

Validated builder:

- `ssh mint`

Validated outputs:

- built VLC tree: `/home/nate/dualsubs-build/upstream/vlc-3.0.24/build-linux-dualsubs`
- packaged installer: `/home/nate/dualsubs-build/packaging/linux/dist/vlc-dualsubs_3.0.24+dualsubs0.2.0-1_amd64.deb`
