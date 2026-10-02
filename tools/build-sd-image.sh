#!/bin/bash
# Build the APJ-OS SD-card image from stock Raspberry Pi OS Lite - no
# golden-master card, no card swapping, the same result every time.
#
#     sudo tools/build-sd-image.sh -b apj-os-boot-<v>.img [options]
#
#   -b FILE   the release boot disk from make-bootdisk.sh (required)
#   -i FILE   a Raspberry Pi OS Lite arm64 .img or .img.xz to start from
#             (default: download raspios_lite_arm64_latest and check its
#             sha256 - the file name goes in the report, so it is pinned)
#   -e DIR    emulator git tree to clone from    default ~<you>/pistorm-atari-jit
#   -o DIR    output directory                    default ~<you>/apj-os-release/<v>
#   -u NAME   the image's user                    default pistorm
#   -p PASS   that user's password                default pistorm
#   -m FILE   copy this prebuilt ./emulator in instead of building (it must
#             be built from PISTORM_REF on trixie arm64). Without -m, a binary
#             cached by an earlier run of the same commit is reused.
#   -k        keep the uncompressed image as well
#
# Environment: WEB=0 leaves the browser engine out (default 1), SAMBA=0
# the [pistorm] share (default 1), MAKE_JOBS=n the compile jobs (default 2).
#
# Run it ON A PI 4 with a 64-bit OS: the image is arm64, so the chroot runs
# natively - no qemu. Stop the emulator first (sudo systemctl stop pistorm):
# the build compiles on all cores. Needs ~8 GB free.
#
# What happens:
#   1. stock image -> grown by 6 GB -> loop-mounted, chroot prepared
#   2. user created with the image's own userconf (what Raspberry Pi Imager
#      does), ssh enabled
#   3. emulator cloned at PISTORM_REF and apj-os cloned from this tree,
#      both with origin pointed back at GitHub
#   4. install-full.sh runs unattended in the chroot: BUILD SERVICE CADGUARD
#      MACFIX SAMBA WEB, and APJOS_VERSION -> atari-share/APJOS.VER (S:)
#   5. the boot disk -> ~/dkimages/apj-os.img (psctrl.cfg's [apj-os] boots it)
#   6. scrub (apt cache, histories, ssh host keys, the build's sudo rule),
#      shrink to contents + 1 GB, xz -9 -> apj-os-<v>.img.xz + .sha256
#
# Stock first-boot expansion is left exactly as Raspberry Pi ships it (the
# image has never been booted). ALWAYS boot-test the flashed result before
# publishing: first boot expands the card, the next reaches the desktop.

set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../VERSIONS
source "$here/VERSIONS"

[ "$(id -u)" = 0 ] || { echo "Run with sudo."; exit 1; }
[ "$(uname -m)" = aarch64 ] || { echo "Run on a 64-bit Pi (arm64 chroot, no emulation)."; exit 1; }

owner="${SUDO_USER:-pistorm}"
ohome="$(getent passwd "$owner" | cut -d: -f6)"
bootdisk=""; base=""
emu="$ohome/pistorm-atari-jit"
out="$ohome/apj-os-release/$APJOS_VERSION"
user=pistorm; pass=pistorm; prebuilt=""; keep=0
while getopts "b:i:e:o:u:p:m:kh" o; do
    case "$o" in
        b) bootdisk="$OPTARG" ;;
        i) base="$OPTARG" ;;
        e) emu="$OPTARG" ;;
        o) out="$OPTARG" ;;
        u) user="$OPTARG" ;;
        p) pass="$OPTARG" ;;
        m) prebuilt="$OPTARG" ;;
        k) keep=1 ;;
        *) sed -n '2,42p' "$0"; exit 2 ;;
    esac
done
WEB="${WEB:-1}"
SAMBA="${SAMBA:-1}"

say()  { printf '\n\033[1;36m[sd-image]\033[0m %s\n' "$*"; }
fail() { printf '\n\033[1;31m[sd-image]\033[0m %s\n' "$*" >&2; exit 1; }

[ -f "$bootdisk" ] || fail "-b: no boot disk '$bootdisk' (tools/make-bootdisk.sh makes it)"
[ -d "$emu/.git" ] || fail "-e: no emulator git tree at $emu"
git config --global --add safe.directory '*' 2>/dev/null || true
git -C "$emu" rev-parse -q --verify "$PISTORM_REF^{commit}" >/dev/null \
    || fail "$PISTORM_REF is not in $emu - tag it (or git fetch --tags)"
[ -z "$prebuilt" ] || [ -x "$prebuilt" ] || fail "-m: $prebuilt is not an executable"
if pgrep -x emulator >/dev/null; then
    fail "the emulator is running - sudo systemctl stop pistorm (the build needs the cores and the RAM)"
fi

need=""
for t in parted:parted resize2fs:e2fsprogs xz:xz-utils curl:curl losetup:mount sfdisk:fdisk openssl:openssl; do
    command -v "${t%%:*}" >/dev/null || need="$need ${t#*:}"
done
if [ -n "$need" ]; then
    say "Installing:$need"
    # shellcheck disable=SC2086
    apt-get install -y $need
fi

mkdir -p "$out"
name="apj-os-$APJOS_VERSION"
img="$out/$name.img"
R="$out/.root"
report="$out/$name.txt"
: > "$report"
log() { echo "$*" | tee -a "$report"; }

# --- 1. base image -------------------------------------------------------------
if [ -z "$base" ]; then
    url="https://downloads.raspberrypi.com/raspios_lite_arm64_latest"
    real="$(curl -fsIL -o /dev/null -w '%{url_effective}' "$url")"
    base="$out/$(basename "$real")"
    if [ ! -f "$base" ]; then
        say "Downloading $(basename "$real")"
        curl -fL --retry 3 -o "$base.part" "$real"
        mv "$base.part" "$base"
    fi
    say "Checking sha256"
    want="$(curl -fsL "$real.sha256" | awk '{print $1}')"
    have="$(sha256sum "$base" | awk '{print $1}')"
    { [ -n "$want" ] && [ "$want" = "$have" ]; } \
        || fail "sha256 mismatch for $base (want '$want', have '$have')"
fi
log "base image: $(basename "$base")  sha256 $(sha256sum "$base" | awk '{print $1}')"

say "Unpacking the base image"
# shellcheck disable=SC2216  # cp reads the pipe via /dev/stdin
case "$base" in
    # sparse: the stock image is mostly empty space; don't spend SD on zeros
    *.xz) xz -dc -T0 "$base" | cp --sparse=always /dev/stdin "$img" ;;
    *)    cp --sparse=always "$base" "$img" ;;
esac

say "Growing the root partition by 6 GB for the build"
truncate -s +6G "$img"
echo ", +" | sfdisk -q -N 2 "$img"

loop=""
done_ok=0
cleanup() {
    set +e
    for m in dev/pts dev proc sys etc/resolv.conf boot/firmware ""; do
        mountpoint -q "${R:?}/$m" 2>/dev/null && umount -l "${R:?}/$m"
    done
    [ -n "$loop" ] && losetup -d "$loop" 2>/dev/null
    if [ "$keep" != 1 ] && [ "$done_ok" != 1 ]; then rm -f "$img"; fi
}
trap cleanup EXIT

loop="$(losetup -fP --show "$img")"
rc=0; e2fsck -fy "${loop}p2" >/dev/null || rc=$?
[ "$rc" -le 1 ] || fail "e2fsck on the base image failed ($rc)"
resize2fs "${loop}p2" >/dev/null

mkdir -p "$R"
mount "${loop}p2" "$R"
mount "${loop}p1" "$R/boot/firmware"
mount --bind /dev "$R/dev"
mount --bind /dev/pts "$R/dev/pts"
mount --bind /proc "$R/proc"
mount --bind /sys "$R/sys"
# name resolution for apt/git: borrow the host's, put the image's back after
if [ -L "$R/etc/resolv.conf" ] || [ -e "$R/etc/resolv.conf" ]; then
    mv -f "$R/etc/resolv.conf" "$R/etc/resolv.conf.apj"
fi
touch "$R/etc/resolv.conf"
mount --bind /etc/resolv.conf "$R/etc/resolv.conf"

ch()  { chroot "$R" "$@"; }
asu() { chroot "$R" runuser -l "$user" -c "$*"; }

log "cmdline.txt (stock): $(cat "$R/boot/firmware/cmdline.txt")"

# nothing apt installs may start a daemon in here
printf '#!/bin/sh\nexit 101\n' > "$R/usr/sbin/policy-rc.d"
chmod 755 "$R/usr/sbin/policy-rc.d"

# systemd is not running in here and `systemctl enable --now` refuses
# outright instead of just enabling. install-full.sh's own chroot check
# can't see the chroot (it runs as the user, and /proc/1/root is root-only),
# so a build-time systemctl in front of the real one drops --now: units
# are enabled here and start at the card's first boot. sudo's secure_path
# finds /usr/local/sbin first. Removed again in the scrub.
mkdir -p "$R/usr/local/sbin"
cat > "$R/usr/local/sbin/systemctl" <<'SHIM'
#!/bin/sh
for a in "$@"; do shift; [ "$a" = --now ] || set -- "$@" "$a"; done
exec /usr/bin/systemctl "$@"
SHIM
chmod 755 "$R/usr/local/sbin/systemctl"

# --- 2. user ---------------------------------------------------------------------
say "Creating user '$user'"
hash="$(openssl passwd -6 "$pass")"
if [ -x "$R/usr/lib/userconf-pi/userconf" ] && ch getent passwd 1000 >/dev/null; then
    # what Raspberry Pi Imager's userconf.txt does at first boot: renames
    # uid 1000, sets the password, cancels the first-boot user dialog
    ch /usr/lib/userconf-pi/userconf "$user" "$hash"
else
    ch useradd -m -s /bin/bash -G sudo,video,render,audio,input,gpio,plugdev,netdev "$user"
    echo "$user:$hash" | ch chpasswd -e
fi
ch id "$user" >/dev/null || fail "user $user was not created"
[ "$(ch id -u "$user")" = 1000 ] || fail "user $user is not uid 1000 - the file ownership below assumes it"
echo "$user ALL=(ALL) NOPASSWD: ALL" > "$R/etc/sudoers.d/zz-apj-build"
chmod 440 "$R/etc/sudoers.d/zz-apj-build"
ch systemctl enable ssh >/dev/null 2>&1 || true
uhome="/home/$user"

# --- 3. sources -----------------------------------------------------------------------
say "apt update + git"
ch apt-get update
ch apt-get install -y git

say "Cloning the emulator at $PISTORM_REF"
cp -a "$emu/.git" "$R/tmp/emu.git"
chown -R 1000:1000 "$R/tmp/emu.git"
asu "git clone -q /tmp/emu.git ~/pistorm-atari-jit && cd ~/pistorm-atari-jit \
     && git checkout -q $PISTORM_REF && git remote set-url origin $PISTORM_REPO"
rm -rf "${R:?}/tmp/emu.git"
log "emulator: $PISTORM_REF = $(git -C "$emu" rev-parse "$PISTORM_REF^{commit}")"

say "Cloning apj-os"
cp -a "$here/.git" "$R/tmp/apj.git"
chown -R 1000:1000 "$R/tmp/apj.git"
asu "git clone -q /tmp/apj.git ~/apj-os && cd ~/apj-os \
     && git remote set-url origin https://github.com/gotaproblem/apj-os.git"
rm -rf "${R:?}/tmp/apj.git"
dirty=""
git -C "$here" diff --quiet HEAD || dirty=" (uncommitted changes in $here are NOT in the image)"
log "apj-os: $(git -C "$here" rev-parse HEAD)$dirty"

# --- 4. the installer, then the emulator build ------------------------------
# install-full.sh runs with BUILD=0 so that anything it trips over fails in
# minutes, not after the compile. The compile is done here instead, in
# parallel (the Makefile on its own is serial - that was the 2 hours), and
# its binary is cached in the output folder by commit: a re-run of the
# same PISTORM_REF reuses it and skips the compile altogether.
say "install-full.sh (WEB=$WEB SAMBA=$SAMBA, build afterwards)"
asu "cd ~/pistorm-atari-jit && BUILD=0 SERVICE=1 CADGUARD=1 MACFIX=1 \
     SAMBA=$SAMBA WEB=$WEB KILLGUI=0 APJOS_VERSION=$APJOS_VERSION \
     ./install-full.sh < /dev/null"

sha="$(git -C "$emu" rev-parse "$PISTORM_REF^{commit}")"
cache="$out/.emulator-$sha"
dest="$R$uhome/pistorm-atari-jit/emulator"
if [ -n "$prebuilt" ]; then
    install -m 755 -o 1000 -g 1000 "$prebuilt" "$dest"
    log "emulator binary: prebuilt $prebuilt  md5 $(md5sum < "$prebuilt" | cut -c1-32)"
elif [ -x "$cache" ]; then
    install -m 755 -o 1000 -g 1000 "$cache" "$dest"
    log "emulator binary: cached from an earlier run of ${sha:0:7}  md5 $(md5sum < "$cache" | cut -c1-32)"
else
    # -j2 is known good on a 2 GB Pi 4; MAKE_JOBS=n overrides. taskset puts
    # the jobs on all four cores - isolcpus=2,3 keeps the scheduler off the
    # emulator's cores, but the emulator is stopped for the whole build.
    jobs="${MAKE_JOBS:-2}"
    say "Building the emulator (make -j$jobs on cores 0-3, PI4)"
    t0=$(date +%s)
    asu "cd ~/pistorm-atari-jit && taskset -c 0-3 make -j$jobs PIMODEL=PI4"
    [ -x "$dest" ] || fail "make finished but there is no ./emulator"
    cp "$dest" "$cache"
    log "emulator binary: built -j$jobs in $(( ($(date +%s) - t0) / 60 )) min  md5 $(md5sum < "$dest" | cut -c1-32)"
fi

# psweb's MemoryHigh/MemoryMax were sized from THIS Pi's RAM; the card may
# go into a 2 GB Pi. psweb polices itself at 40% of the RAM it finds.
if [ -f "$R/etc/systemd/system/psweb.service" ]; then
    sed -i '/^Memory\(High\|Max\)=/d' "$R/etc/systemd/system/psweb.service"
fi

# --- 5. Atari boot disk -------------------------------------------------------------------
say "Boot disk -> ~/dkimages/$ATARI_DISK_NAME"
install -m 664 -o 1000 -g 1000 "$bootdisk" "$R$uhome/dkimages/$ATARI_DISK_NAME"
log "boot disk: $(basename "$bootdisk")  md5 $(md5sum < "$bootdisk" | cut -c1-32)"
log "APJOS.VER: $(cat "$R$uhome/atari-share/APJOS.VER" 2>/dev/null || echo MISSING)"
log "natfeats: $(cd "$R$uhome/atari-share/apj-os/natfeats" && echo *)"

# --- 6. scrub -----------------------------------------------------------------------------------
say "Scrubbing"
rm -f "${R:?}/etc/sudoers.d/zz-apj-build" "${R:?}/usr/sbin/policy-rc.d" "${R:?}/usr/local/sbin/systemctl"
ch apt-get clean
rm -rf "${R:?}"/var/lib/apt/lists/*
rm -f "${R:?}"/etc/ssh/ssh_host_*            # apj-sshkeys makes this card's own
rm -f "${R:?}/root/.bash_history" "${R:?}$uhome/.bash_history" "${R:?}$uhome/.wget-hsts"
rm -rf "${R:?}"/tmp/* "${R:?}"/var/tmp/* "${R:?}$uhome/.cache"
find "$R/var/log" -type f -exec truncate -s 0 {} +
umount "$R/etc/resolv.conf"
rm -f "${R:?}/etc/resolv.conf"
if [ -e "$R/etc/resolv.conf.apj" ] || [ -L "$R/etc/resolv.conf.apj" ]; then
    mv "$R/etc/resolv.conf.apj" "$R/etc/resolv.conf"
fi
log "root filesystem used: $(df -h --output=used "$R" | tail -1)"

for m in dev/pts dev proc sys boot/firmware ""; do umount "$R/$m"; done

# --- 7. shrink + compress --------------------------------------------------------------------------
say "Shrinking to contents + 1 GB"
rc=0; e2fsck -fy "${loop}p2" >/dev/null || rc=$?
[ "$rc" -le 1 ] || fail "e2fsck before shrink failed ($rc)"
resize2fs -M "${loop}p2" >/dev/null
bs=$(dumpe2fs -h "${loop}p2" 2>/dev/null | awk -F: '/^Block size/{print $2+0}')
bc=$(dumpe2fs -h "${loop}p2" 2>/dev/null | awk -F: '/^Block count/{print $2+0}')
newbytes=$(( bc * bs + 1024 * 1024 * 1024 ))
resize2fs "${loop}p2" "$(( newbytes / 1024 ))K" >/dev/null
p2start=$(cat "/sys/block/$(basename "$loop")/$(basename "$loop")p2/start")
losetup -d "$loop"
loop=""
newsec=$(( (newbytes + 4095) / 4096 * 8 ))
echo ", $newsec" | sfdisk -q -N 2 "$img"
truncate -s $(( (p2start + newsec) * 512 )) "$img"
log "image: $(( (p2start + newsec) / 2048 )) MiB uncompressed"

# -6, not -9: -9 wants ~675 MB per thread, which on a 2 GB Pi means one or
# two threads and swap. -6 is ~95 MB per thread; the file is a little
# bigger. Pinned to all four cores like the compile.
say "xz -6 on cores 0-3"
taskset -c 0-3 xz -6 -T4 -k -f "$img"
( cd "$out" && sha256sum "$name.img.xz" > "$name.img.xz.sha256" )
log "$(ls -l "$img.xz")"
[ "$(stat -c %s "$img.xz")" -lt 2147483648 ] || log "WARNING: over GitHub's 2 GiB release-asset limit"
[ "$keep" = 1 ] || rm -f "$img"
chown -R "$owner": "$out" 2>/dev/null || true
done_ok=1

say "Done: $img.xz"
echo "    login: $user / $pass (ssh on). Report: $report"
echo "    Flash it, boot it twice, check the taskbar shows APJ-OS v$APJOS_VERSION."
