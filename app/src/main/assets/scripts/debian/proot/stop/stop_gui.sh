#!/usr/bin/env bash
# Derive the app id from a /data/data/<pkg>/... path without forking any
# external binary: sed/grep/dirname under $PREFIX/bin are ELF files in
# app_data_file, which targetSdk 36 W^X refuses to exec (EACCES).
_flux_pkg_from_prefix() {
  _p=$1
  _p=${_p#*"/data/data/"}
  case "$_p" in
    "$1") printf '' ;;
    *) printf '%s' "${_p%%/*}" ;;
  esac
}
# stop_gui.sh - Stop XFCE4 Desktop Environment in PRoot Distro
# Paths: TermuxHostPaths via fluxlinux-host.env (SSOT)

DISTRO=${1:-debian}
PKG="${TERMUX_APP__PACKAGE_NAME:-$(_flux_pkg_from_prefix "${TERMUX__PREFIX:-$0}")}"
_HOST_ENV="${TERMUX__PREFIX:-/data/data/${PKG}/files/usr}/etc/fluxlinux-host.env"
[ -r "$_HOST_ENV" ] && . "$_HOST_ENV"

export TERMUX_APP__PACKAGE_NAME="${TERMUX_APP__PACKAGE_NAME:-$PKG}"
export TERMUX__PREFIX="${TERMUX__PREFIX:-/data/data/${TERMUX_APP__PACKAGE_NAME}/files/usr}"
export TERMUX__HOME="${TERMUX__HOME:-/data/data/${TERMUX_APP__PACKAGE_NAME}/files/home}"
export HOME="${HOME:-$TERMUX__HOME}"
# Never call dirname here: PATH puts $PREFIX/bin first and those are ELF
# binaries under app_data_file (targetSdk 36 W^X => EACCES), which makes
# dirname return empty and PROOT_TMP_DIR collapse to "/proot-tmp" (denied).
export PROOT_TMP_DIR="${PROOT_TMP_DIR:-${TERMUX__PREFIX%/*}/proot-tmp}"
mkdir -p "$PROOT_TMP_DIR" 2>/dev/null || true
PKG="$TERMUX_APP__PACKAGE_NAME"

echo "========================================"
echo "FluxLinux: Stopping GUI for $DISTRO"
echo "========================================"

# Step 1: Kill XFCE inside the guest (targeted login — does NOT pkill proot).
# Host-only pkill often misses proot-namespaced guest DE processes.
echo "[1/4] Stopping XFCE4 in guest ($DISTRO)..."
if command -v python >/dev/null 2>&1 && [ -x "$TERMUX__PREFIX/bin/proot-distro" ] || [ -f "$TERMUX__PREFIX/bin/proot-distro" ]; then
  python "$TERMUX__PREFIX/bin/proot-distro" login "$DISTRO" -- \
    /bin/bash -c 'killall -9 xfce4-session xfwm4 xfdesktop xfce4-panel startxfce4 plasmashell kwin_x11 startplasma-x11 plasma_session ksmserver 2>/dev/null; true' \
    >/dev/null 2>&1 || true
fi
# Best-effort host-side names too (some proot trees expose them)
pkill -9 -f "xfce4-session" 2>/dev/null || true
pkill -9 -f "xfwm4" 2>/dev/null || true
pkill -9 -f "xfdesktop" 2>/dev/null || true
pkill -9 -f "xfce4-panel" 2>/dev/null || true
pkill -9 -f "startxfce4" 2>/dev/null || true
pkill -9 -f "plasmashell|kwin_x11|startplasma-x11|plasma_session|ksmserver|kded6" 2>/dev/null || true
pkill -9 -f "dbus-daemon.*--session" 2>/dev/null || true

# Step 2: Leave proot-distro / generic proot shells alone
echo "[2/4] Skipping proot shell kill (terminal sessions stay alive)"

# Step 3: Stop Termux X11 server
echo "[3/4] Stopping Termux X11..."
# Restore write permissions to allow clean updates/deployments
chmod 0700 "$TERMUX__PREFIX/libexec/termux-x11" 2>/dev/null || true
chmod 0600 "$TERMUX__PREFIX/libexec/termux-x11/loader.apk" 2>/dev/null || true
# Send ACTION_STOP broadcast to close the X11 activity in our app
am broadcast -a com.termux.x11.ACTION_STOP -p "$PKG" >/dev/null 2>&1

# Kill only THIS app's X server. Its cmdline is
# `app_process / --nice-name=termux-x11 com.termux.x11.Loader ...` and carries
# no package id, so a "$PKG" pattern never matches. Pin the UID explicitly
# rather than relying on Android's cross-UID EPERM.
_our_uid="${UID:-$(/system/bin/id -u 2>/dev/null)}"
kill_our_x11() {
  [ -n "$_our_uid" ] || return 0
  pkill "-$1" -U "$_our_uid" -f "termux-x11" 2>/dev/null || true
}
kill_our_x11 9
killall -9 Xwayland 2>/dev/null || true

# Step 4: Stop VirGL only. Host Pulse stays up so CLI / next desktop has audio.
echo "[4/4] Stopping VirGL (Pulse stays running)..."
pkill -f "virgl_test_server" 2>/dev/null || true

echo ""
echo "✅ GUI stopped successfully!"
echo "========================================"
exit 0
