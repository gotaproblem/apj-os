# Cutting an APJ-OS release

The distribution is a *set of pins plus assets*. A release means: the three
component repos are at states that work together in the field, and the assets
built from them are attached to a tag here.

## 1. Pin the components

In each component repo, tag the tested state (annotated tags):

```bash
# on the Pi / Mac clone of each repo
git -C pistorm-atari-jit tag -a apj-0.1.0 -m "APJ-OS 0.1.0" && git push origin apj-0.1.0
git -C teradesk          tag -a apj-0.1.0 -m "APJ-OS 0.1.0" && git push origin apj-0.1.0
git -C freemint          tag -a apj-0.1.0 -m "APJ-OS 0.1.0" && git push origin apj-0.1.0
```

Update `VERSIONS` in this repo: set `APJOS_VERSION`, point the three `_REF`s
at the tags, and set the disk-asset URL for the new version. Commit.

Note: teradesk's CI publishes `desktop.prg` as a release asset on tags
matching its release pattern; the freemint `bespoke-ws` workflow can be
re-run from the Actions tab if the 30-day artifact with `xaaes*.km` has
expired. Both binaries also live *inside* the Atari boot disk, which is the
copy users actually run — the loose assets are for manual installs.

## 2. Build the Atari boot-disk asset

The master `dk0.img` is curated by hand (it IS drive C:). Before packaging:

- current `desktop.prg`, `xaaes.km`, cnf files, wallpapers on it
- no personal files in `C:\` (documents, downloaded media)
- `mint.cnf`: `FS_CACHE_SIZE=4096`, `sln u:\ram r:`, VFAT lines present

```bash
xz -9 -k -T0 dk0.img && mv dk0.img.xz apj-boot-0.1.0.img.xz
```

## 3. Build the SD-card image

Golden master card → `tools/capture-image.sh` (see its header; it scrubs
Wi-Fi/ssh/history secrets, arms first-boot expansion, shrinks and compresses).
Boot-test the *flashed result* on a spare card before releasing: first boot
expands the filesystem, second boot must reach the Atari desktop.

## 4. Publish

```bash
git tag -a v0.1.0 -m "APJ-OS 0.1.0" && git push origin v0.1.0
gh release create v0.1.0 \
    apj-os-0.1.0.img.xz \
    apj-boot-0.1.0.img.xz \
    --title "APJ-OS 0.1.0" \
    --notes-file docs/release-notes-0.1.0.md
```

Release notes should carry: default login of the SD image, the component tag
table, upgrade notes (can an existing card just `git pull` + rebuild, or is a
reflash needed), and known issues.

## Asset checklist

| Asset | Source | Limit |
|---|---|---|
| `apj-os-<v>.img.xz` | capture-image.sh from golden master | < 2 GiB (GitHub hard limit) |
| `apj-boot-<v>.img.xz` | curated dk0.img | should be well under |
| `desktop.prg` | teradesk CI release | tiny |
| `xaaes040.km` / `xaaes020.km` | freemint bespoke-ws CI | tiny |
