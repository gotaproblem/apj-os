#!/bin/bash
# Build the APJ-OS release boot disk (Atari drive C:) from your curated
# development disk.
#
#     tools/make-bootdisk.sh [-s master.img] [-e emulator-dir] [-o outdir]
#
#   -s  the curated disk           default ~/dkimages/apj-os-dev.img
#   -e  emulator git tree          default ~/pistorm-atari-jit
#   -o  where the result goes      default ~/apj-os-release/<version>
#
# Produces, in outdir:
#   apj-os-boot-<v>.img        the release disk (the SD-image build uses it)
#   apj-os-boot-<v>.img.xz     the release asset
#   apj-os-boot-<v>.txt        report: every change, md5 of XaAES/TeraDesk/
#                              TosWin2/FreeMiNT/fVDI, full file list
#
# The master is only ever READ - all work is on a copy. Steps:
#   1. copy the master; cut its FAT partition out into a scratch file
#   2. fsck.fat -a  (clears the dirty bit the emulator leaves, syncs FATs)
#   3. atariclean   (Mac litter with long names: ._*, .DS_Store, .Trashes)
#   4. bootdisk.py  (orphaned AppleDouble 8.3 files, tools/bootdisk.manifest
#                    rm/put lines, zero all free clusters, report)
#   5. fsck.fat -n  must come back clean; partition goes back; xz -9
#
# `put` sources come from the emulator tree AT PISTORM_REF (git show), not
# from whatever is checked out, so the disk carries that release's ACCs.
# Needs: mtools dosfstools xz-utils python3 git (installed if missing).

set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../VERSIONS
source "$here/VERSIONS"

master="$HOME/dkimages/apj-os-dev.img"
emu="$HOME/pistorm-atari-jit"
out="$HOME/apj-os-release/$APJOS_VERSION"
while getopts "s:e:o:h" o; do
    case "$o" in
        s) master="$OPTARG" ;;
        e) emu="$OPTARG" ;;
        o) out="$OPTARG" ;;
        *) sed -n '2,30p' "$0"; exit 2 ;;
    esac
done

say()  { printf '\033[1;36m[bootdisk]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[bootdisk]\033[0m %s\n' "$*" >&2; exit 1; }

need=""
for t in mdir:mtools fsck.fat:dosfstools xz:xz-utils python3:python3 git:git; do
    command -v "${t%%:*}" >/dev/null || need="$need ${t#*:}"
done
if [ -n "$need" ]; then
    say "Installing:$need"
    sudo apt-get install -y $need
fi
export MTOOLS_SKIP_CHECK=1

[ -f "$master" ] || fail "no master disk at $master (use -s)"
[ -d "$emu/.git" ] || fail "no emulator git tree at $emu (use -e)"
git -C "$emu" rev-parse -q --verify "$PISTORM_REF^{commit}" >/dev/null \
    || fail "$PISTORM_REF (PISTORM_REF in VERSIONS) is not in $emu - tag it or git fetch --tags"

# the emulator writes the disk while it runs: a copy taken mid-write can
# be torn. The master is in psctrl.cfg as a bare name, so just look for
# any running emulator.
if pgrep -x emulator >/dev/null && [ "${FORCE:-0}" != 1 ]; then
    fail "the emulator is running - shut APJ-OS down first (FORCE=1 to copy anyway)"
fi

name="apj-os-boot-$APJOS_VERSION"
mkdir -p "$out"
work="$(mktemp -d "$out/.bootdisk.XXXX")"
trap 'rm -rf "$work"' EXIT

say "Master  $master"
say "Version $APJOS_VERSION, emulator files from $PISTORM_REF ($(git -C "$emu" rev-parse --short "$PISTORM_REF^{commit}"))"
cp --sparse=always "$master" "$work/$name.img"
chmod u+w "$work/$name.img"

# --- 1. the FAT partition: first MBR entry ---------------------------------
read -r pstart psize < <(python3 - "$work/$name.img" <<'PY'
import struct, sys
b = open(sys.argv[1], "rb").read(512)
if b[510:512] != b"\x55\xaa":
    sys.exit("no MBR signature - not an MBR-partitioned disk")
for i in range(4):
    e = b[446 + 16*i: 462 + 16*i]
    if e[4] in (0x01, 0x04, 0x06, 0x0b, 0x0c, 0x0e):
        print(*struct.unpack("<II", e[8:16])); break
else:
    sys.exit("no FAT partition in the MBR")
PY
)
say "Partition at sector $pstart, $psize sectors"
part="$work/part.fat"
dd if="$work/$name.img" of="$part" bs=512 skip="$pstart" count="$psize" status=none

# --- 2. fsck ---------------------------------------------------------------
say "fsck.fat -a (dirty bit, FAT copies)"
rc=0; fsck.fat -a "$part" > "$work/fsck.log" 2>&1 || rc=$?
sed 's/^/    /' "$work/fsck.log"
[ "$rc" -le 1 ] || fail "fsck.fat could not repair the partition (exit $rc) - check the master"

# --- 3. Mac litter with long names ------------------------------------------
say "atariclean"
git -C "$emu" show "$PISTORM_REF:tools/atariclean/atariclean.py" > "$work/atariclean.py"
python3 "$work/atariclean.py" -d "$part" | tail -1 | sed 's/^/    /'

# --- 4. manifest, orphans, zero fill -----------------------------------------
say "bootdisk.py (manifest: tools/bootdisk.manifest)"
src="$work/src"
mkdir -p "$src"
awk '$1=="put"{print $2}' "$here/tools/bootdisk.manifest" | while read -r f; do
    mkdir -p "$src/$(dirname "$f")"
    git -C "$emu" show "$PISTORM_REF:$f" > "$src/$f" 2>/dev/null || rm -f "$src/$f"
done
python3 "$here/tools/bootdisk.py" "$part" "$here/tools/bootdisk.manifest" \
    "$src" "$out/$name.txt"

# --- 5. verify, put back, compress ----------------------------------------------
say "fsck.fat -n (must be clean)"
rc=0; fsck.fat -n "$part" > "$work/fsck.log" 2>&1 || rc=$?
sed 's/^/    /' "$work/fsck.log"
[ "$rc" -eq 0 ] || fail "the cleaned partition does not fsck clean (exit $rc) - nothing written"
dd if="$part" of="$work/$name.img" bs=512 seek="$pstart" conv=notrunc status=none

mv -f "$work/$name.img" "$out/$name.img"
say "xz -9 (all cores)"
xz -9 -T0 -k -f "$out/$name.img"
( cd "$out" && sha256sum "$name.img.xz" > "$name.img.xz.sha256" )

say "Done:"
ls -l "$out/$name.img" "$out/$name.img.xz" | sed 's/^/    /'
say "Report: $out/$name.txt   (check the 'changes' section before releasing)"
