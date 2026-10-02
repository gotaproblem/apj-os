# Cutting an APJ-OS release

A release is a *set of tags plus three assets*: the component repos are
tagged at the commits the shipped binaries were built from, and
`tools/make-release.sh` builds the assets on the Pi from those tags.

Everything below runs on the **Pi** (the release scripts need the arm64
chroot, mtools and the dkimages folder), except where it says Mac.

## 0. Before you start

- The curated boot disk — `~/dkimages/apj-os-dev.img` — boots and is what you
  want to ship: current `xaaes.km`, `desktop.prg`, `toswin2.app`, cnf files,
  skins, fonts. You do **not** need to tidy it: the release copy is cleaned
  automatically (Mac litter, backups and logs, personal files, deleted data —
  see `tools/bootdisk.manifest`). Your dev disk is only ever read.
- `pistorm-atari-jit/configs/gem-binaries/` holds the current GEM apps. The
  list it must contain is `GEM_APPS` in `install-full.sh`; make-release.sh
  warns about any that are missing (for 1.0: `SETMCH.PRG` until it is built).
- Shut APJ-OS down: `sudo systemctl stop pistorm`. The scripts refuse to run
  beside the emulator — it writes the dev disk, and the SD build needs the
  cores.

## 1. Tag the components

Annotated tags, on the commits the shipped binaries came from:

```bash
# Pi: the emulator - its release branch holds the installer/README update
cd ~/pistorm-atari-jit
git tag -a apj-1.0 -m "APJ-OS 1.0" apj-os-1.0 && git push origin apj-1.0

# Mac: the Atari-side repos (the builds that are on apj-os-dev.img)
git -C ~/Workspace/ATARI/cdev/freemint   tag -a apj-1.0 -m "APJ-OS 1.0" && git -C ~/Workspace/ATARI/cdev/freemint push origin apj-1.0
git -C ~/teradesk/teradesk               tag -a apj-1.0 -m "APJ-OS 1.0" && git -C ~/teradesk/teradesk push origin apj-1.0
git -C ~/Workspace/ATARI/cdev/toswin2    tag -a apj-1.0 -m "APJ-OS 1.0" && git -C ~/Workspace/ATARI/cdev/toswin2 push mine apj-1.0
git -C ~/Workspace/ATARI/cdev/apj-os-tools tag -a apj-1.0 -m "APJ-OS 1.0" && git -C ~/Workspace/ATARI/cdev/apj-os-tools push origin apj-1.0
```

`VERSIONS` here already names these tags and the asset URLs for 1.0. For the
next release: bump `APJOS_VERSION`, the `*_REF` tags and the
`ATARI_DISK_*` lines, and commit.

## 2. Build the assets

```bash
cd ~/apj-os
tools/make-release.sh                     # everything. The first run compiles the
                                          # emulator in parallel and caches it in
                                          # ~/apj-os-release/<v>/; re-runs reuse it
tools/make-release.sh -m ~/pistorm-atari-jit/emulator
                                          # reuse a binary built from apj-1.0
tools/make-release.sh --disk-only         # just the boot disk, ~1 min
```

Output in `~/apj-os-release/1.0/`:

| File | What |
|---|---|
| `apj-os-boot-1.0.img.xz` | Atari drive C: (install.sh downloads it) |
| `apj-os-boot-1.0.txt` | every change made to it, md5 of XaAES/TeraDesk/TosWin2/FreeMiNT/fVDI, file list |
| `apj-os-1.0.img.xz` | the SD-card image |
| `apj-os-1.0.txt` | base Raspberry Pi OS image + sha256, commits, APJOS.VER, apps |
| `release-notes-1.0.md` | draft notes with the component table filled in |
| `SHA256SUMS`, `*.sha256` | checksums |

The steps can also be run on their own: `tools/make-bootdisk.sh` and
`sudo tools/build-sd-image.sh -b <boot disk>` (see each script's header).

### What the SD image is

Stock **Raspberry Pi OS Lite arm64** (downloaded, sha256-checked, its name
recorded), with — inside a chroot, natively on the Pi:

- user `pistorm` / `pistorm`, ssh on, host keys made per card on first boot
- `~/pistorm-atari-jit` at `apj-1.0` and `~/apj-os`, origins on GitHub
- `install-full.sh` unattended: build, `pistorm.service`, Ctrl+Alt+Del mask,
  atariclean + Samba (Mac-friendly), psweb, `wifi.txt` onboarding,
  `APJOS.VER` = `1.0` on S:
- `~/dkimages/apj-os.img` = the release boot disk

then scrubbed and shrunk. Nothing of your own Pi's card ends up in it.

## 3. Test

1. Flash `apj-os-1.0.img.xz` to a **spare** card, fill in `wifi.txt`, boot.
2. First boot expands the card; the setup page then boots `[apj-os]`.
3. Check: the taskbar shows **APJ-OS v1.0**; PSCTRL and PSMON are in the
   accessory menu; S: has `apj-os\natfeats` with the apps; MP3GEM, VIDGEM,
   PDFGEM and WEBGEM start; `ssh pistorm@<pi>` works.
4. Read the "changes" section of `apj-os-boot-1.0.txt` once.

## 4. Publish

Edit `release-notes-1.0.md` (what's new, upgrade notes, known issues), then:

```bash
cd ~/apj-os
git tag -a v1.0 -m "APJ-OS 1.0" && git push origin v1.0
gh release create v1.0 ~/apj-os-release/1.0/apj-os-1.0.img.xz \
    ~/apj-os-release/1.0/apj-os-boot-1.0.img.xz ~/apj-os-release/1.0/SHA256SUMS \
    --title "APJ-OS 1.0" --notes-file ~/apj-os-release/1.0/release-notes-1.0.md
```

GitHub's limit is 2 GiB per asset; `build-sd-image.sh` warns if the SD
image is over it.

## Legacy

`tools/capture-image.sh` (dd a hand-made golden-master card, scrub, PiShrink)
was the 0.1.0 method. It is kept for reference; the from-stock build
replaces it.
