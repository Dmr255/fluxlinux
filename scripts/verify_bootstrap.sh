#!/usr/bin/env bash
# Verify a FluxLinux native bootstrap.tar for an applicationId.
# Usage: verify_bootstrap.sh <applicationId> [bootstrap.tar]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="${1:?usage: $0 <applicationId> [bootstrap.tar]}"
TAR="${2:-$ROOT/native/bootstrap/$PKG/bootstrap.tar}"
EXPECT_SNIP="/data/data/${PKG}/files/usr"

if [[ ! -f "$TAR" ]]; then
  echo "error: bootstrap not found: $TAR" >&2
  exit 1
fi

echo "[*] tar: $TAR ($(du -h "$TAR" | awk '{print $1}'))"
echo "[*] expect prefix snippet: $EXPECT_SNIP"

required=(
  "usr/bin/bash"
  "usr/bin/python"
  "usr/bin/proot"
  "usr/bin/proot-distro"
  "usr/bin/pulseaudio"
  "usr/lib/libsoxr.so"
  "usr/lib/libandroid-execinfo.so"
  "usr/lib/libFLAC.so"
  "usr/lib/libmp3lame.so"
  "usr/lib/pulseaudio/modules/module-aaudio-sink.so"
  "usr/lib/pulseaudio/modules/module-sles-sink.so"
  "usr/lib/pulseaudio/modules/module-native-protocol-tcp.so"
  "usr/libexec/termux-x11/loader.apk"
)

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
tar -tf "$TAR" > "$tmp"

fail=0
for rel in "${required[@]}"; do
  if grep -qx "$rel" "$tmp" || grep -qE "^${rel}\$" "$tmp"; then
    echo "  [OK] $rel"
  else
    # tar may list without leading ./
    if grep -qE "(^|/)${rel}\$" "$tmp"; then
      echo "  [OK] $rel"
    else
      echo "  [MISSING] $rel"
      fail=1
    fi
  fi
done

# Stock path strings should not appear in path names
if grep -q 'com\.termux' "$tmp"; then
  echo "  [FAIL] tar member paths contain com.termux"
  grep 'com\.termux' "$tmp" | head -10
  fail=1
else
  echo "  [OK] no com.termux in member paths"
fi

# jniLibs
jni="$ROOT/native/bootstrap/$PKG/jniLibs/arm64-v8a"
for so in libbash.so libproot.so libloader.so libloader32.so libpulseaudio.so libpactl.so; do
  if [[ -f "$jni/$so" ]]; then
    echo "  [OK] jniLibs $so"
  else
    echo "  [MISSING] jniLibs $so"
    fail=1
  fi
done

# ELF NEEDED closure: every shared library a bundled binary links against must
# be present in the prefix (or be an Android system lib). Shipping gawk without
# libmpfr.so made every `awk` fail with "CANNOT LINK EXECUTABLE", which broke
# both distro install (sha256sum|awk) and the host Pulse scripts.
elf_root="$ROOT/native/bootstrap/$PKG/root/data/data/$PKG/files"
if [[ -d "$elf_root/usr" ]] && command -v readelf >/dev/null 2>&1; then
  echo "[*] ELF NEEDED closure under $elf_root"
  while IFS= read -r line; do
    echo "  [MISSING LIB] $line"
    fail=1
  done < <(python3 - "$elf_root" <<'PY'
import os, re, subprocess, sys

root = sys.argv[1]
usr = os.path.join(root, "usr")

# Library names shipped in the prefix (resolved by RUNPATH, not by us).
have = set()
for dp, _, fs in os.walk(usr):
    for f in fs:
        have.add(f)

# Android platform libraries are resolved from /system/lib64 at runtime.
SYSTEM = {
    "libc.so", "libm.so", "libdl.so", "liblog.so", "libandroid.so", "libz.so",
    "libOpenSLES.so", "libaaudio.so", "libEGL.so", "libGLESv2.so", "libvulkan.so",
    "libnativewindow.so", "libjnigraphics.so", "libmediandk.so", "libOpenMAXAL.so",
    "libneuralnetworks.so", "libsync.so", "libc++_shared.so",
}

for sub in ("bin", "libexec", "lib/pulseaudio/modules"):
    d = os.path.join(usr, sub)
    if not os.path.isdir(d):
        continue
    for f in sorted(os.listdir(d)):
        p = os.path.join(d, f)
        if not os.path.isfile(p):
            continue
        try:
            if open(p, "rb").read(4) != b"\x7fELF":
                continue
            out = subprocess.run(
                ["readelf", "-d", p], capture_output=True, text=True, timeout=15
            ).stdout
        except Exception:
            continue
        for m in re.finditer(r"Shared library: \[([^\]]+)\]", out):
            lib = m.group(1)
            if lib in have or lib in SYSTEM:
                continue
            print(f"{os.path.relpath(p, root)} needs {lib}")
PY
)
else
  echo "  [SKIP] ELF closure (no extracted root or no readelf)"
fi

# Optional: strings on extracted bash if extract root still present
root_bash="$ROOT/native/bootstrap/$PKG/root/data/data/$PKG/files/usr/bin/bash"
if [[ -f "$root_bash" ]] && command -v readelf >/dev/null 2>&1; then
  rpath="$(readelf -d "$root_bash" 2>/dev/null | grep -E 'RPATH|RUNPATH' || true)"
  echo "  rpath bash: $rpath"
  if echo "$rpath" | grep -q "/data/data/${PKG}/files/usr"; then
    echo "  [OK] bash RUNPATH matches package"
  elif [[ -n "$rpath" ]] && echo "$rpath" | grep -q com.termux; then
    echo "  [FAIL] bash RUNPATH is stock termux"
    fail=1
  fi
fi

if (( fail )); then
  echo "FAIL"
  exit 1
fi
echo "PASS"
