#!/bin/bash
# Build every APJ-OS release asset in one go, on the Pi.
#
#     tools/make-release.sh [-s master.img] [-m prebuilt-emulator] [--disk-only]
#
#   -s FILE      curated Atari boot disk     default ~/dkimages/apj-os-dev.img
#   -m FILE      prebuilt ./emulator for the SD image instead of a 30+ minute
#                build (must be built from PISTORM_REF)
#   --disk-only  just the boot disk (no sudo, two minutes)
#
# Run as your normal user from the apj-os tree, emulator stopped. Produces
# in ~/apj-os-release/<version>/:
#
#   apj-os-boot-<v>.img.xz (+.sha256, .txt report)   Atari drive C:
#   apj-os-<v>.img.xz      (+.sha256, .txt report)   the SD-card image
#   release-notes-<v>.md                             draft for gh release
#   SHA256SUMS
#
# The version and every component pin come from VERSIONS. Order matters:
# tag the component repos first (docs/RELEASING.md), then run this.

set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../VERSIONS
source "$here/VERSIONS"

master="$HOME/dkimages/apj-os-dev.img"
prebuilt=""
disk_only=0
while [ $# -gt 0 ]; do
    case "$1" in
        -s) master="$2"; shift 2 ;;
        -m) prebuilt="$2"; shift 2 ;;
        --disk-only) disk_only=1; shift ;;
        *) sed -n '2,20p' "$0"; exit 2 ;;
    esac
done

emu="$HOME/pistorm-atari-jit"
out="$HOME/apj-os-release/$APJOS_VERSION"
say()  { printf '\n\033[1;35m[release]\033[0m %s\n' "$*"; }
fail() { printf '\n\033[1;31m[release]\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" != 0 ] || fail "run as your normal user - sudo is used for the SD image step"

say "APJ-OS $APJOS_VERSION"
git -C "$emu" fetch -q --tags origin 2>/dev/null || true
git -C "$emu" rev-parse -q --verify "$PISTORM_REF^{commit}" >/dev/null \
    || fail "emulator tag $PISTORM_REF missing in $emu (docs/RELEASING.md step 1)"
if ! git -C "$here" diff --quiet HEAD; then
    say "WARNING: apj-os has uncommitted changes - the SD image clones the COMMITTED tree"
fi

# the emulator tag must carry the GEM programs install-full.sh names
missing=""
for f in $(git -C "$emu" show "$PISTORM_REF:install-full.sh" \
           | awk '/^GEM_APPS="/,/"$/' | tr -d '"\\' | sed 's/GEM_APPS=//'); do
    git -C "$emu" cat-file -e "$PISTORM_REF:configs/gem-binaries/$f" 2>/dev/null \
        || missing="$missing $f"
done
[ -z "$missing" ] || say "WARNING: not in configs/gem-binaries at $PISTORM_REF:$missing"

say "1/3 boot disk"
"$here/tools/make-bootdisk.sh" -s "$master" -e "$emu" -o "$out"
bootimg="$out/apj-os-boot-$APJOS_VERSION.img"

if [ "$disk_only" = 0 ]; then
    say "2/3 SD-card image (sudo)"
    args=(-b "$bootimg" -e "$emu" -o "$out")
    [ -z "$prebuilt" ] || args+=(-m "$prebuilt")
    sudo WEB="${WEB:-1}" SAMBA="${SAMBA:-1}" "$here/tools/build-sd-image.sh" "${args[@]}"
fi

say "3/3 notes + checksums"
notes="$out/release-notes-$APJOS_VERSION.md"
sd="apj-os-$APJOS_VERSION.img.xz"
{
    echo "# APJ-OS $APJOS_VERSION"
    echo
    echo "## Install"
    echo
    echo "**SD card (easiest):** flash \`$sd\` to a 16 GB+ card with Raspberry Pi"
    echo "Imager (*Use custom image*; Imager's OS customisation is untested - skip it) or"
    echo "\`xzcat $sd | sudo dd of=/dev/sdX bs=4M conv=fsync status=progress\`."
    echo "For Wi-Fi, edit \`wifi.txt\` on the card's boot partition before first boot."
    echo "First boot expands the card; the PiStorm setup page then boots APJ-OS."
    echo
    echo "Login (console/ssh): \`pistorm\` / \`pistorm\` - **change it** with \`passwd\`."
    echo
    echo "**Existing Raspberry Pi OS Lite (64-bit, trixie):** \`git clone"
    echo "https://github.com/gotaproblem/apj-os.git && cd apj-os && ./install.sh\`"
    echo
    echo "## Components"
    echo
    echo "| Component | Repository | Tag |"
    echo "|---|---|---|"
    echo "| Emulator | gotaproblem/pistorm-atari-jit | \`$PISTORM_REF\` ($(git -C "$emu" rev-parse --short "$PISTORM_REF^{commit}")) |"
    echo "| AES (XaAES) + FreeMiNT | gotaproblem/freemint | \`$FREEMINT_REF\` |"
    echo "| Desktop (Bespoke / TeraDesk) | gotaproblem/teradesk | \`$TERADESK_REF\` |"
    echo "| Terminal (TosWin2) | gotaproblem/toswin2 | \`$TOSWIN2_REF\` |"
    echo "| GEM apps | gotaproblem/apj-os-tools | \`$APJTOOLS_REF\` |"
    echo
    echo "Boot-disk binaries (md5):"
    echo
    echo '```'
    sed -n '/^== key components/,/^$/p' "$out/apj-os-boot-$APJOS_VERSION.txt" | sed '1d;/^$/d'
    echo '```'
    echo
    echo "## What's new"
    echo
    echo "_(fill in)_"
    echo
    echo "## Upgrading from 0.1.0"
    echo
    echo "_(fill in: reflash, or git pull + install-full.sh + new apj-os.img)_"
    echo
    echo "## Known issues"
    echo
    echo "_(fill in)_"
} > "$notes"
( cd "$out" && sha256sum ./*.img.xz | sed 's| \./| |' > SHA256SUMS )

say "Assets in $out:"
ls -l "$out"/*.xz "$out"/*.md "$out"/SHA256SUMS
cat <<EOF

Next (docs/RELEASING.md step 4): edit $notes, boot-test the SD image, then
    cd $here
    git tag -a v$APJOS_VERSION -m "APJ-OS $APJOS_VERSION" && git push origin v$APJOS_VERSION
    gh release create v$APJOS_VERSION $out/*.img.xz $out/SHA256SUMS \\
        --title "APJ-OS $APJOS_VERSION" --notes-file $notes
EOF
