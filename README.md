# APJ-OS — Atari PiStorm JIT OS

A complete, ready-to-run operating environment for a **PiStorm-equipped Atari
ST/STe** with a **Raspberry Pi 4**: a JIT 68040 with FPU, FreeMiNT + XaAES +
fVDI at up to 1920×1080 in 32-bit colour over HDMI, a Fluent-style themed
desktop (the Bespoke Desktop, a TeraDesk fork) with a live PiStorm taskbar and
four independent virtual desktops, and a set of PiStorm GEM apps that hand the
heavy work to the Pi: video and MP3 playback, a PDF viewer, and a web
browser.

APJ-OS is a *distribution*: it pins tested versions of its source projects
and packages them with configuration that is known to work together.

| Component | Source | What it provides |
|---|---|---|
| Emulator | [pistorm-atari-jit](https://github.com/gotaproblem/pistorm-atari-jit) | JIT 68040, fVDI host rendering, the setup page, NatFeats (PSCTRL, MP3PLAY, VIDPLAY, PSPDF, PSWEB, STBOX, PSVIDEL, ...) |
| AES | [freemint](https://github.com/gotaproblem/freemint) (`apj-os-fluent`) | XaAES with the Fluent renderer, themed window chrome, anti-aliased text, virtual workspaces (`xaaes.km`) |
| Desktop | [teradesk](https://github.com/gotaproblem/teradesk) (`apj-os-fluent`) | Bespoke Desktop: taskbar, themes, wallpaper, 4 desktops (`desktop.prg`) |
| Terminal | [toswin2](https://github.com/gotaproblem/toswin2) (`apj-os-fluent`) | TosWin2 with themed AA text (`toswin2.app`) |
| GEM apps | [apj-os-tools](https://github.com/gotaproblem/apj-os-tools) | PSCTRL, PSMON, MP3GEM, VIDGEM, PDFGEM, WEBGEM, PSCLEAN, skins, icons, fonts |

The tags for this release are in [`VERSIONS`](VERSIONS).

---

## Install — three ways

### 1. Flash the SD-card image (easiest)

Download `apj-os-<version>.img.xz` from the [releases page](../../releases)
and flash it to a 16 GB+ SD card with Raspberry Pi Imager ("Use custom image";
skip Imager's OS customisation) or:

```bash
xzcat apj-os-<version>.img.xz | sudo dd of=/dev/sdX bs=4M conv=fsync status=progress
```

For Wi-Fi, open `wifi.txt` on the card's boot partition (any computer can
read it) and fill in your network before the first boot; it is applied and
renamed `wifi.txt.applied`. Insert the card into the PiStorm's Pi 4 and power
the Atari on. The first boot expands the filesystem; from then on
the machine boots straight into APJ-OS (see [Power-on](#power-on) below).

Linux login over ssh: **`pistorm` / `pistorm`** — change it with `passwd`.
Every card generates its own ssh host keys on first boot. (The Pi's console,
tty1, belongs to the emulator.)

### 2. Install script on stock Raspberry Pi OS

Start from **Raspberry Pi OS Lite (64-bit, trixie)** — Lite is mandatory: the
JIT needs the isolated cores and DRM master that a desktop environment steals.
The user should be `pistorm` (the shipped `psctrl.cfg` points its HOSTFS
drive at `/home/pistorm/atari-share`).

```bash
git clone https://github.com/gotaproblem/apj-os.git
cd apj-os
./install.sh
sudo reboot
```

The script clones the emulator at the pinned tag, runs its own
`install-full.sh` (dependencies, boot-firmware settings, build, the autostart
service, GEM apps onto the S: drive, the version file) and downloads the Atari
boot-disk image into place. The build and the autostart are on by default
(`BUILD=0` / `SERVICE=0 ./install.sh` to leave them out); it still asks about
the web browser engine and the Samba share. After the reboot the Pi boots
into APJ-OS exactly like the SD image.

### 3. Manual

Each component repo carries its own build documentation. `VERSIONS` tells you
which tags belong together; the [releases page](../../releases) carries the
Atari boot-disk image (`apj-os-boot-<version>.img.xz`).

---

## Power-on

APJ-OS is an appliance: switch the Atari on and it ends up at the desktop.

1. The Pi boots Raspberry Pi OS Lite (console only, no desktop).
2. `pistorm.service` starts the emulator on tty1, as root, with
   `~/configs/psctrl.cfg`.
3. The **PiStorm setup page** appears on the ST's monitor (mirrored to HDMI,
   or on HDMI alone when no ST monitor is connected). It lists the builds
   in `psctrl.cfg` and counts down 5 seconds on the one booted last — on a
   fresh install that is `apj-os`. Leave it and it boots; any key stops the
   countdown, `Enter` boots the build under the cursor, `E` edits it. Every
   key is in the emulator's `INSTALL-README.md`, "The setup page".
4. The `[apj-os]` build boots EmuTOS, FreeMiNT from `C:\AUTO`, XaAES and the
   Bespoke Desktop, at 1920×1080 in 32-bit colour on HDMI.

Changing that:

| To | Do |
|---|---|
| boot with no page at all | `countdown 0` in the `[psctrl]` block of `~/configs/psctrl.cfg` |
| boot a different build by default | boot it once from the page — the page boots whatever was booted last |
| stop the autostart | `sudo systemctl disable --now pistorm` (`enable` to put it back) |
| run the emulator by hand | `cd ~/pistorm-atari-jit && sudo ./emulator --config ../configs/psctrl.cfg` |
| see the emulator's output | `journalctl -u pistorm -f` |

Ctrl+Alt+Del is the ST's warm reset; the installer disables its Linux
console meaning (reboot the Pi), so the combo is safe to use.

## What goes where

**Drive C: — the Atari boot disk** (`~/dkimages/apj-os.img`): FreeMiNT
1-19 with the Fluent `xaaes.km`, fVDI (`aranym.sys`, 1920×1080×32 by
default in `FVDI.SYS`), TosWin2, the Bespoke Desktop `desktop.prg` with its
configuration, the APJ fonts (`GEMSYS\APJ*.FNT`), skins (`GEMSYS\SKINS`) and
icon sets, and the accessories `PSCTRL.ACC` and `PSMON.ACC`. `mint.cnf`
ships with the settings this hardware wants: `FS_CACHE_SIZE=4096`, a RAM
drive on `R:` and VFAT enabled.

**Drive S: — HOSTFS onto the Pi** (`~/atari-share`):

| Path on S: | Contents |
|---|---|
| `APJOS.VER` | the APJ-OS version (`1.0`); the taskbar shows it as "APJ-OS v1.0" |
| `apj-os\natfeats\` | PSCTRL, PSMON, MP3GEM, VIDGEM, PDFGEM, WEBGEM, PSCLEAN, FVDIMODE; and FVDICON, PSVIDEL, SETMCH for an AUTO folder |
| `apj-os\STBox\` | STBOX (an ST in a GEM window) and its game images |
| `apj-os\bg\` | wallpapers |
| `Downloads\` | WEBGEM downloads |

**TOS ROMs:** APJ-OS ships [EmuTOS](https://emutos.sourceforge.io/) (GPL,
freely redistributable). Real Atari TOS images are not included and not
required — except for STBOX, which needs a TOS 1.04/2.06 (or 192/256K
EmuTOS) image you supply as `~/roms/stbox-tos.rom`.

## Pi-side settings that matter

Applied by both install paths (see the emulator's `INSTALL-README.md` for the
full story):

- `gpu_mem=128` — **required**; the VPU H.264 decoder allocates its frame
  buffers here. At the Pi default the decoder opens but never delivers a frame.
- `cmdline.txt`: `isolcpus=2,3 nohz_full=2,3 rcu_nocbs=2,3 irqaffinity=0,1` —
  core 2 runs the JIT, core 3 the bus poller; cores 0-1 take Linux and IRQs.
- Ctrl+Alt+Del is the ST reset, so its Linux console reboot is masked.
- The web browser engine (`psweb`, WPE WebKit) is socket-activated: it only
  runs — and only uses memory — while WEBGEM is open.
- A heatsink or fan is strongly recommended — sustained video playback brushes
  the 80 °C soft throttle limit on a bare SoC.

## Building a release

`tools/make-release.sh` builds every asset on the Pi — the cleaned boot disk
and an SD image made from stock Raspberry Pi OS Lite. See
[`docs/RELEASING.md`](docs/RELEASING.md).

## Licences

All the source projects are free software; APJ-OS's own scripts are GPL-2.0.
See [`LICENSES.md`](LICENSES.md). The SD image contains Raspberry Pi OS
(redistributable) and EmuTOS (GPL). No Atari ROMs, no media files.
