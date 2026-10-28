# FluxLinux — personal fork

This repository is a fork of
[`zenithblue-oss/fluxlinux`](https://github.com/zenithblue-oss/fluxlinux)
by Abhay Raj, licensed under **GPL-3.0**. The `LICENSE` file and all upstream
copyright notices are kept as-is.

Upstream: https://github.com/zenithblue-oss/fluxlinux
Fork:     https://github.com/Dmr255/fluxlinux

## Changes in this fork

### Touch input defaults to "simulated touchscreen"

Upstream defaults to **trackpad** mode (mode `1`), where the screen behaves
like a laptop touchpad and the cursor moves relative to your finger. This fork
defaults to **simulated touchscreen** (mode `2`), so a tap clicks at the point
you touched and a drag drags at that point — much closer to a phone-native UI.

The three available modes (unchanged from upstream, in
`termux-x11/.../input/TouchInputHandler.java`) are:

| Value | Mode | Behaviour |
|-------|------|-----------|
| `1` | Trackpad | relative cursor, tap-to-click |
| `2` | Simulated touchscreen | absolute click/drag at the touched point |
| `3` | Direct touch | raw XI2 `TouchBegin/Update/End` events |

Mode `2` is the practical default for XFCE4: the desktop and most GTK apps
react correctly to pointer events at an absolute position, while raw touch
events (mode `3`) are only consumed by XI2-touch-aware toolkits.

### New "Touch mode" selector in the app UI

`X11SettingsScreen` now exposes the mode as a segmented selector instead of
requiring the user to open the embedded Lorie preferences. It writes the same
`touchMode` preference key and broadcasts `ACTION_PREFERENCES_CHANGED`, so a
running display switches immediately.

### Files touched

- `termux-x11/src/main/java/com/termux/x11/Prefs.java`
  — default `touchMode` `"1"` → `"2"`
- `termux-x11/src/main/res/xml/preferences.xml`
  — default `touchMode` `"1"` → `"2"`
- `termux-x11/src/main/res/values/arrays.xml`
  — clearer mode labels
- `app/src/main/kotlin/com/ivarna/fluxlinux/core/utils/TermuxX11Preferences.kt`
  — `getTouchMode()` / `setTouchMode()`, default `"2"`
- `app/src/main/kotlin/com/ivarna/fluxlinux/ui/screens/X11SettingsScreen.kt`
  — `PrefChoice` composable + "Touch mode" card

No native code, no rootfs, and no `applicationId` changes are included, so the
existing `ivarna` / `zenithblue` bootstrap archives still apply unchanged.

## Building

The repo ships two `applicationId` flavours that can coexist on one device:

- `ivarna` → `com.ivarna.fluxlinux`
- `zenithblue` → `com.zenithblue.fluxlinux`

Build one specific flavour (a bare `assembleDebug` will fail because a flavour
must be selected):

```bash
./gradlew :app:assembleIvarnaDebug
# or, to install next to an existing FluxLinux build:
./gradlew :app:assembleZenithblueDebug
```

Host bootstrap assets are staged per flavour by:

```bash
./scripts/package_host_assets.sh --all
```

Requirements: JDK 17+, Android SDK with `compileSdk 36` / build-tools `36.0.0`.
`native/termux-packages` is a git submodule and is only needed when rebuilding
the host binaries from source.