#!/system/bin/sh
# stop_debian13_gui.sh — root: stop XFCE in Debian chroot + host X11 sockets
# Does NOT pkill proot (proot stop is stop_gui.sh only).

DEBIANPATH="${DEBIANPATH:-/data/local/tmp/chrootDebian13}"
if [ -z "${TARGET_PREFIX:-}" ]; then
  if [ -n "${FLUX_PREFIX:-}" ]; then
    TARGET_PREFIX="$FLUX_PREFIX"
  elif [ -n "${FLUX_PACKAGE:-}" ]; then
    TARGET_PREFIX="/data/data/${FLUX_PACKAGE}/files/usr"
  fi
fi

# Derive the package from an already-exported prefix, else from the host env
# file that only FluxLinux writes. Never hardcode another flavor's app id.
_flux_pkg_from_prefix() {
  _p=$1
  _p=${_p#*"/data/data/"}
  case "$_p" in
    "$1") printf '' ;;
    *) printf '%s' "${_p%%/*}" ;;
  esac
}
if [ -z "${FLUX_PACKAGE:-}" ]; then
  FLUX_PACKAGE="$(_flux_pkg_from_prefix "${TARGET_PREFIX:-${TERMUX__PREFIX:-$0}}")"
fi
if [ -z "${FLUX_PACKAGE:-}" ]; then
  for _h in /data/data/*/files/usr/etc/fluxlinux-host.env; do
    [ -r "$_h" ] || continue
    FLUX_PACKAGE="$(_flux_pkg_from_prefix "$_h")"
    [ -n "$FLUX_PACKAGE" ] && break
  done
fi
if [ -z "${TARGET_PREFIX:-}" ] && [ -n "${FLUX_PACKAGE:-}" ]; then
  TARGET_PREFIX="/data/data/${FLUX_PACKAGE}/files/usr"
fi

echo "========================================"
echo "FluxLinux: Stopping Chroot XFCE"
echo "========================================"

# resolve root BusyBox (manager built-in; NDK module not required)
_rr=""
for _c in \
  "${FLUX_RESOLVE_BB:-}" \
  "$(dirname "$0")/resolve_bb.sh" \
  /data/local/tmp/fluxlinux_resolve_bb.sh
do
  [ -n "$_c" ] && [ -f "$_c" ] && _rr="$_c" && break
done
if [ -n "$_rr" ]; then
  # shellcheck disable=SC1090
  . "$_rr"
  resolve_bb || true
fi
if [ -z "${BB:-}" ]; then
  # sidecar missing (desktop/uninstall/staged setup) — same B1 walk as resolve_bb
  if [ -n "${FLUX_BB:-}" ] && [ -x "$FLUX_BB" ] &&
     "$FLUX_BB" --list >/dev/null 2>&1; then BB="$FLUX_BB"; fi
  if [ -z "${BB:-}" ] && [ -x /data/local/tmp/flux_busybox ] &&
     /data/local/tmp/flux_busybox --list >/dev/null 2>&1; then
    BB=/data/local/tmp/flux_busybox
  fi
  if [ -z "${BB:-}" ]; then
    for path in \
      /data/adb/ksu/bin/busybox \
      /data/adb/ap/bin/busybox \
      /data/adb/magisk/busybox \
      /data/adb/modules/busybox-ndk/system/xbin/busybox \
      /data/adb/modules/busybox-ndk/system/bin/busybox \
      /debug_ramdisk/busybox \
      /sbin/busybox \
      /system/xbin/busybox \
      /system/bin/busybox
    do
      if [ -x "$path" ]; then BB="$path"; break; fi
    done
  fi
fi
if [ -z "${BB:-}" ]; then
  echo "FluxLinux: ERROR — root-capable busybox not found" >&2
  exit 1
fi


echo "[1/4] Kill XFCE in chroot..."
if [ -n "$BB" ] && [ -d "$DEBIANPATH" ]; then
  $BB chroot "$DEBIANPATH" /bin/su - root -c \
    "killall -9 xfce4-session xfwm4 xfdesktop xfce4-panel plasmashell kwin_x11 startplasma-x11 plasma_session ksmserver dbus-launch dbus-daemon 2>/dev/null; true" \
    >/dev/null 2>&1
fi

echo "[2/4] Stop Termux X11 host processes..."
# Restore loader write bits for redeploy
chmod 0700 "$TARGET_PREFIX/libexec/termux-x11" 2>/dev/null || true
chmod 0600 "$TARGET_PREFIX/libexec/termux-x11/loader.apk" 2>/dev/null || true
# This script runs as ROOT, so a bare `pkill -f termux-x11` would also kill the
# X server of any other FluxLinux app id installed side by side (same cmdline
# `app_process / --nice-name=termux-x11 ...`, no package id in it). Scope the
# kill to this package's UID, derived from its own prefix directory.
_target_uid=""
if [ -n "${TARGET_PREFIX:-}" ] && [ -d "$TARGET_PREFIX" ]; then
  _target_uid="$(stat -c %u "$TARGET_PREFIX" 2>/dev/null || true)"
fi
if [ -n "${_target_uid:-}" ]; then
  # `pkill -U` is available in toybox and busybox. No `killall Xwayland` here:
  # the embedded X server is in-process (EmbeddedX11), and a global killall
  # would hit another FluxLinux app's Xwayland.
  pkill -9 -U "$_target_uid" -f "termux-x11" 2>/dev/null || true
else
  echo "[2/4] WARN: cannot resolve app uid for '$TARGET_PREFIX'; leaving host X11 alone"
fi
rm -rf "$TARGET_PREFIX/tmp/.X11-unix" "$TARGET_PREFIX/tmp/.X0-lock" "$TARGET_PREFIX/tmp/.X1-lock" 2>/dev/null || true

echo "[3/4] Unmount chroot binds (best-effort)..."
if [ -n "$BB" ] && [ -d "$DEBIANPATH" ]; then
  for m in \
    "$DEBIANPATH/tmp/.X11-unix" \
    "$DEBIANPATH/mnt/host-tmp" \
    "$DEBIANPATH/sdcard" \
    "$DEBIANPATH/dev/shm" \
    "$DEBIANPATH/dev/pts" \
    "$DEBIANPATH/proc" \
    "$DEBIANPATH/sys" \
    "$DEBIANPATH/dev"
  do
    $BB umount "$m" 2>/dev/null || $BB umount -l "$m" 2>/dev/null || true
  done
fi

echo "[4/4] Done (PulseAudio stopped from app-uid wrapper if used)"
echo "========================================"
exit 0
