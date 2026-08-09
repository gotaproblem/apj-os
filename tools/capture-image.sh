#!/bin/bash
# Capture a golden-master SD card into a distributable APJ-OS image.
#
# Workflow: get your Pi's SD card exactly how you want APJ-OS to ship
# (the "golden master"), power the Pi off, put the card in a USB reader on
# ANY Linux machine (another Pi booted from a different card works fine),
# then:
#
#     sudo ./capture-image.sh /dev/sdX apj-os-0.1.0
#
# Produces apj-os-0.1.0.img.xz, sanitized, shrunk, and set to auto-expand
# on first boot. Do NOT run against the disk of the running system.
#
# Steps:
#   1. dd the whole card to a working image
#   2. mount the image and SCRUB PERSONAL DATA:
#        - Wi-Fi credentials (NetworkManager + wpa_supplicant)
#        - ssh host keys (regenerate on first boot) and authorized_keys
#        - shell histories, git credentials/config, machine-id, logs
#   3. PiShrink: shrink the root filesystem, arm first-boot auto-expand,
#      compress with xz
#
# Review the scrub list before every release - it is YOUR data.

set -euo pipefail

[ "$(id -u)" = 0 ] || { echo "Run with sudo."; exit 1; }
dev="${1:?usage: capture-image.sh /dev/sdX <output-name>}"
name="${2:?usage: capture-image.sh /dev/sdX <output-name>}"
img="$name.img"

# The capture rig is expected to be a VANILLA Raspberry Pi OS Lite - make
# sure the few tools we and PiShrink need are present (parted/e2fsprogs
# for the shrink, xz for compression; everything else is base coreutils).
need=""
for t in parted resize2fs xz curl; do
    command -v "$t" >/dev/null || need="$need $t"
done
if [ -n "$need" ]; then
    echo "Installing missing tools:$need"
    apt-get update -qq
    apt-get install -y parted e2fsprogs xz-utils curl
fi

[ -b "$dev" ] || { echo "$dev is not a block device"; exit 1; }
mount | grep -q "^$dev" && { echo "$dev has mounted partitions - unmount first."; exit 1; }
findmnt -no SOURCE / | grep -q "${dev}" && { echo "That is the running system's disk. No."; exit 1; }

echo "== 1/3 Reading $dev -> $img (this takes a while)"
dd if="$dev" of="$img" bs=4M conv=fsync status=progress

echo "== 2/3 Sanitizing"
loop=$(losetup -fP --show "$img")
trap 'umount -q /mnt/apj-root /mnt/apj-boot 2>/dev/null; losetup -d "$loop"' EXIT
mkdir -p /mnt/apj-root /mnt/apj-boot
mount "${loop}p2" /mnt/apj-root
mount "${loop}p1" /mnt/apj-boot

r=/mnt/apj-root
# Wi-Fi / network secrets
rm -f "$r"/etc/NetworkManager/system-connections/* 2>/dev/null || true
rm -f "$r"/etc/wpa_supplicant/wpa_supplicant*.conf 2>/dev/null || true
# ssh: drop the golden master's host keys and user keys; arm Raspberry
# Pi OS's key-regeneration service by symlink (no container tools needed)
# so every flashed card generates its OWN host identity on first boot.
rm -f "$r"/etc/ssh/ssh_host_* 2>/dev/null || true
rm -rf "$r"/home/*/.ssh "$r"/root/.ssh 2>/dev/null || true
svc="$r/lib/systemd/system/regenerate_ssh_host_keys.service"
if [ -f "$svc" ]; then
    mkdir -p "$r"/etc/systemd/system/multi-user.target.wants
    ln -sf /lib/systemd/system/regenerate_ssh_host_keys.service \
        "$r"/etc/systemd/system/multi-user.target.wants/regenerate_ssh_host_keys.service
else
    echo "WARNING: regenerate_ssh_host_keys.service not found in image -"
    echo "         flashed cards will have NO ssh host keys until created manually."
fi
# histories, credentials, identity, logs
rm -f "$r"/home/*/.bash_history "$r"/root/.bash_history 2>/dev/null || true
rm -f "$r"/home/*/.git-credentials "$r"/home/*/.netrc 2>/dev/null || true
find "$r"/home -maxdepth 2 -name .gitconfig -exec sh -c \
  'grep -q "credential" "$1" && echo "WARNING: $1 mentions credentials - check it"' _ {} \; 2>/dev/null || true
truncate -s 0 "$r"/etc/machine-id 2>/dev/null || true
rm -rf "$r"/var/log/* "$r"/tmp/* "$r"/var/tmp/* 2>/dev/null || true
# anything personal in the media folders stays OUT of a release
for d in "$r"/home/*/Videos "$r"/home/*/movies "$r"/srv/media; do
    [ -d "$d" ] && echo "WARNING: media folder present in image: $d - remove before release?"
done

sync
umount /mnt/apj-root /mnt/apj-boot
losetup -d "$loop"
trap - EXIT

echo "== 3/3 PiShrink + xz"
if ! command -v pishrink.sh >/dev/null; then
    echo "Fetching pishrink..."
    curl -fL -o /usr/local/bin/pishrink.sh \
        https://raw.githubusercontent.com/Drewsif/PiShrink/master/pishrink.sh
    chmod +x /usr/local/bin/pishrink.sh
fi
pishrink.sh -zaX "$img"        # shrink, arm auto-expand, xz -9 multithreaded

echo "Done: $img.xz"
echo "Upload with: gh release upload v<version> $img.xz"
echo "GitHub release asset limit is 2 GiB per file - check the size."