# APJ-OS — Atari PiStorm JIT OS

A complete, ready-to-run operating environment for a **PiStorm-equipped Atari
ST/STe** with a **Raspberry Pi 4**: a JIT 68040 with FPU, FreeMiNT + XaAES +
fVDI at up to 1920×1080 in 32-bit colour, the Bespoke Desktop (TeraDesk fork)
with live PiStorm taskbar and four truly independent virtual desktops,
hardware-accelerated video playback, MP3 player, and Pi-side integration
(temperature, throttle and JIT stats on the desktop, Pi-synced clock).

APJ-OS is a *distribution*: it pins tested versions of its three source
projects and packages them with configuration that is known to work together.

| Component | Source | What it provides |
|---|---|---|
| Emulator | [pistorm-atari-jit](https://github.com/gotaproblem/pistorm-atari-jit) (`psctrl` branch) | JIT 68040, fVDI host rendering, video/MP3 playback, PSCTRL/PSIMG NatFeats |
| Desktop | [teradesk](https://github.com/gotaproblem/teradesk) (`bespoke` branch) | Bespoke Desktop: taskbar, monitor, wallpaper, 4 desktops (`desktop.prg`) |
| AES | [freemint](https://github.com/gotaproblem/freemint) (`bespoke-ws` branch) | XaAES with per-window virtual workspaces (`xaaes.km`) |

Pinned versions for this release are in [`VERSIONS`](VERSIONS).

---

## Install — three ways

### 1. Flash the SD-card image (easiest)

Download `apj-os-<version>.img.xz` from the
[releases page](../../releases), flash it to a 16 GB+ SD card with Raspberry
Pi Imager ("Use custom image") or:

```bash
xzcat apj-os-<version>.img.xz | sudo dd of=/dev/sdX bs=4M conv=fsync status=progress
```

Insert into the PiStorm's Pi 4, power the Atari on. The filesystem expands
itself on first boot. Default login: see the release notes.

### 2. Install script on stock Raspberry Pi OS

Start from **Raspberry Pi OS Lite (64-bit, trixie)** — Lite is mandatory: the
JIT needs the isolated cores and DRM master that a desktop environment steals.

```bash
git clone https://github.com/gotaproblem/apj-os.git
cd apj-os
./install.sh
sudo reboot
```

The script clones the emulator at the pinned tag, runs its own
`install-full.sh` (dependencies, boot-firmware settings, optional autostart),
and downloads the Atari boot-disk image into place.

### 3. Manual

Each component repo carries its own build documentation. `VERSIONS` tells you
which tags/commits belong together; the [releases page](../../releases)
carries the prebuilt `desktop.prg`, `xaaes.km` and the Atari boot-disk image.

---

## What's on the Atari boot disk

FreeMiNT (1-19 snapshot) with the bespoke `xaaes.km`, fVDI (`aranym.sys`),
TOSWIN2, the Bespoke Desktop `desktop.prg` with its configuration, wallpapers,
and the PiStorm GEM apps (MP3GEM, VIDGEM, VIDPLAY). `mint.cnf` ships with the
settings this hardware wants: `FS_CACHE_SIZE=4096` (the 128 KB default is four
cache blocks — folder operations can exhaust it), a RAM drive on `R:`
(`sln u:\ram r:`), and VFAT enabled.

**TOS ROMs:** APJ-OS ships [EmuTOS](https://emutos.sourceforge.io/) (GPL,
freely redistributable). Real Atari TOS images are not included and not
required.

## Pi-side settings that matter

Applied by both install paths (see the emulator's `INSTALL-README.md` for the
full story):

- `gpu_mem=128` — **required**; the VPU H.264 decoder allocates its frame
  buffers here. At the Pi default the decoder opens but never delivers a frame.
- `cmdline.txt`: `isolcpus=2,3 nohz_full=2,3 rcu_nocbs=2,3 irqaffinity=0,1` —
  core 2 runs the JIT, core 3 the bus poller; cores 0-1 take Linux and IRQs.
- Kernel 6.18+ (stock trixie) with `gpu_mem=128`: both hardware decode engines
  (H.264 ≤1080p and HEVC) verified working.
- A heatsink or fan is strongly recommended — sustained video playback brushes
  the 80 °C soft throttle limit on a bare SoC.

## Licences

All three source projects are GPL; APJ-OS's own scripts are GPL-2.0. See
[`LICENSES.md`](LICENSES.md). The SD image contains Raspberry Pi OS
(redistributable) and EmuTOS (GPL). No Atari ROMs, no media files.
