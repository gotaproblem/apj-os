#!/bin/bash
# APJ-OS bootstrap installer.
#
# Run on a fresh Raspberry Pi OS Lite (64-bit) as your normal user:
#     ./install.sh
#
# What it does, in order:
#   1. sanity checks (64-bit, Pi 4 family)
#   2. clones the emulator at the version pinned in VERSIONS
#   3. hands over to the emulator's own install-full.sh (dependencies,
#      boot-firmware settings, optional build + autostart) - that script is
#      idempotent and has the canonical knowledge of Pi-side setup
#   4. downloads the APJ Atari boot-disk image into dkimages/dk0.img
#
# Re-running is safe: existing clones are updated to the pinned ref, the
# disk image is only downloaded if missing (your Atari drive C: lives in it -
# it is never overwritten once present).

set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=VERSIONS
source "$here/VERSIONS"

say()  { printf '\n\033[1m[apj-os]\033[0m %s\n' "$*"; }
fail() { printf '\n\033[1;31m[apj-os]\033[0m %s\n' "$*" >&2; exit 1; }

# --- 1. sanity ---------------------------------------------------------------

[ "$(uname -m)" = "aarch64" ] || fail "64-bit OS required (found $(uname -m)). \
Re-flash with Raspberry Pi OS Lite 64-bit."

if [ -r /proc/device-tree/model ]; then
    model="$(tr -d '\0' < /proc/device-tree/model)"
    case "$model" in
        *"Pi 4"*|*"Pi 400"*|*"Compute Module 4"*) : ;;
        *) say "WARNING: '$model' is not a Pi 4 - the JIT is only validated on Pi 4/400/CM4." ;;
    esac
fi

[ "$(id -u)" != 0 ] || fail "Run as your normal user, not root (sudo is called where needed)."

command -v git >/dev/null || { say "Installing git..."; sudo apt-get update && sudo apt-get install -y git; }

# --- 2. emulator at the pinned version ---------------------------------------

emudir="$HOME/pistorm-atari-jit"

if [ -d "$emudir/.git" ]; then
    say "Emulator clone exists - fetching and checking out $PISTORM_REF"
    git -C "$emudir" fetch --all --tags
else
    say "Cloning emulator ($PISTORM_REF)"
    git clone "$PISTORM_REPO" "$emudir"
fi
git -C "$emudir" checkout "$PISTORM_REF"
git -C "$emudir" pull --ff-only 2>/dev/null || true   # no-op for tags/hashes

# --- 3. the emulator's own installer does the Pi-side work -------------------

say "Handing over to the emulator's install-full.sh"
say "(it will ask about building, autostart and network shares)"
( cd "$emudir" && chmod +x install-full.sh && ./install-full.sh )

# --- 4. Atari boot-disk image ------------------------------------------------

dkdir="$emudir/dkimages"
mkdir -p "$dkdir"

if [ -e "$dkdir/dk0.img" ]; then
    say "dk0.img already present - leaving your Atari drive C: untouched."
else
    say "Downloading the APJ Atari boot disk ($ATARI_DISK_ASSET)"
    tmp="$dkdir/.$ATARI_DISK_ASSET.part"
    curl -fL --retry 3 -o "$tmp" "$ATARI_DISK_URL" \
        || fail "Download failed - check the release exists: $ATARI_DISK_URL"
    say "Unpacking"
    xz -dc "$tmp" > "$dkdir/dk0.img"
    rm -f "$tmp"
fi

# --- done --------------------------------------------------------------------

say "APJ-OS $APJOS_VERSION installed."
say "Next: sudo reboot - then power up the Atari."
say "Docs: $emudir/README.md and $emudir/INSTALL-README.md"
