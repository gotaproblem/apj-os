#!/usr/bin/env python3
"""
bootdisk.py - turn a copy of the curated APJ-OS boot partition into a
release partition. Called by make-bootdisk.sh; works on a BARE FAT
partition file (make-bootdisk.sh cuts it out of the disk image and puts
it back), using mtools for every directory operation.

    bootdisk.py PART.fat MANIFEST SRCROOT REPORT

  PART.fat  the partition, edited in place
  MANIFEST  tools/bootdisk.manifest: rm / put lines (see that file)
  SRCROOT   where `put` sources are found (the pinned emulator tree)
  REPORT    written: what was removed/added, md5 of the key binaries,
            and the full file list of the result

Run atariclean over the partition first - it takes out ._*, .DS_Store,
.Trashes and friends WITH their long names. This picks up what it can't
see: AppleDouble files whose long-name entries were lost, which survive
as 8.3 names like _CHAP-~1 (that is how the 0.1.0 disk shipped dozens of
4 KB "_XXX~1" files). Those are found by content - the AppleDouble magic
00 05 16 07 - never by name alone.

Finally every free cluster is zeroed, so nothing deleted (old XaAES
builds, personal files) survives in the release image, and the image
compresses to what is actually on it.
"""
import fnmatch
import hashlib
import os
import struct
import subprocess
import sys

os.environ["MTOOLS_SKIP_CHECK"] = "1"
os.environ.setdefault("MTOOLS_NO_VFAT", "0")

APPLEDOUBLE = b"\x00\x05\x16\x07"

# shown with md5 in the report: the components VERSIONS pins
KEY_FILES = [
    "/MINT/1-19-F8F/XAAES/XAAES.KM",
    "/MINT/1-19-F8F/XAAES/XAAES.CNF",
    "/MINT/1-19-F8F/MINT.CNF",
    "/MINT/1-19-F8F/MINTARA.PRG",
    "/AUTO/MINTARA.PRG",
    "/MINT/1-19-F8F/SYS-ROOT/OPT/GEM/TERADESK/DESKTOP.PRG",
    "/MINT/1-19-F8F/SYS-ROOT/OPT/GEM/TERADESK/TERADESK.INF",
    "/MINT/1-19-F8F/SYS-ROOT/OPT/GEM/TOSWIN2/TOSWIN2.APP",
    "/FVDI/FVDI.PRG",
    "/FVDI.SYS",
    "/GEMSYS/ARANYM.SYS",
]


def mt(*args, capture=True):
    r = subprocess.run(list(args), capture_output=capture, text=False)
    if r.returncode != 0:
        err = (r.stderr or b"").decode("latin-1", "replace").strip()
        raise RuntimeError("%s failed: %s" % (" ".join(args), err))
    return r.stdout


def listing(part):
    """{UPPER path: (real path, is_dir)} for everything on the partition"""
    out = mt("mdir", "-i", part, "-/", "-b", "-a", "::")
    m = {}
    for line in out.decode("latin-1").splitlines():
        line = line.strip()
        if not line.startswith("::/"):
            continue
        p = line[2:]
        d = p.endswith("/")
        p = p.rstrip("/")
        if p:
            m[p.upper()] = (p, d)
    return m


def read_head(part, path, n=4):
    return mt("mtype", "-i", part, "::" + path)[:n]


def remove(part, path, is_dir, log, why):
    if is_dir:
        mt("mdeltree", "-i", part, "::" + path)
    else:
        mt("mattrib", "-i", part, "-r", "-s", "-h", "::" + path)
        mt("mdel", "-i", part, "::" + path)
    log.append("removed  %-55s %s" % (path + ("/" if is_dir else ""), why))


def orphan_appledouble(part, log):
    n = 0
    for up, (p, d) in sorted(listing(part).items()):
        base = p.rsplit("/", 1)[-1]
        if d or not base.startswith("_") or "~" not in base:
            continue
        try:
            head = read_head(part, p)
        except RuntimeError:
            continue
        if head == APPLEDOUBLE:
            remove(part, p, False, log, "(AppleDouble, long name lost)")
            n += 1
    return n


def manifest(part, mf, srcroot, log):
    missing = 0
    for ln, raw in enumerate(open(mf, encoding="utf-8"), 1):
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        f = line.split()
        if f[0] == "rm" and len(f) == 2:
            pat = f[1].upper()
            hits = [(p, d) for up, (p, d) in listing(part).items()
                    if fnmatch.fnmatchcase(up, pat)]
            # a directory hit swallows its children
            hits.sort(key=lambda x: len(x[0]))
            done = []
            for p, d in hits:
                if any(p.upper().startswith(x.upper() + "/") for x in done):
                    continue
                remove(part, p, d, log, "(manifest line %d)" % ln)
                done.append(p)
            if not hits:
                log.append("absent   %-55s (manifest line %d)" % (f[1], ln))
        elif f[0] == "put" and len(f) == 3:
            src = os.path.join(srcroot, f[1])
            if not os.path.isfile(src):
                log.append("MISSING  %-55s source %s (manifest line %d)" % (f[2], f[1], ln))
                missing += 1
                continue
            parent = f[2].rsplit("/", 1)[0]
            if parent and parent.upper() not in listing(part):
                mt("mmd", "-i", part, "-D", "s", "::" + parent)
            mt("mcopy", "-i", part, "-o", "-m", src, "::" + f[2])
            log.append("put      %-55s %s  %s" % (f[2], md5file(src)[:12], f[1]))
        else:
            raise SystemExit("%s:%d: cannot parse: %s" % (mf, ln, raw.rstrip()))
    return missing


def md5file(path):
    h = hashlib.md5()
    with open(path, "rb") as fh:
        for b in iter(lambda: fh.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


def zero_free(part):
    """FAT12/16/32: overwrite every free cluster with zeros"""
    with open(part, "r+b") as fh:
        bs = fh.read(512)
        bps, spc, res, nf, rootent, ts16, _media, spf16 = struct.unpack("<HBHBHHBH", bs[11:24])
        ts32, = struct.unpack("<I", bs[32:36])
        spf32, = struct.unpack("<I", bs[36:40])
        total = ts16 or ts32
        spf = spf16 or spf32
        rootsec = (rootent * 32 + bps - 1) // bps
        first_data = res + nf * spf + rootsec
        nclus = (total - first_data) // spc
        if nclus < 4085:
            bits = 12
        elif nclus < 65525 or spf16:
            bits = 16
        else:
            bits = 32
        fh.seek(res * bps)
        fat = fh.read(spf * bps)
        zero = b"\0" * (spc * bps)
        freed = 0
        for c in range(2, nclus + 2):
            if bits == 16:
                v = struct.unpack_from("<H", fat, c * 2)[0]
            elif bits == 32:
                v = struct.unpack_from("<I", fat, c * 4)[0] & 0x0FFFFFFF
            else:
                o = c + c // 2
                v = struct.unpack_from("<H", fat, o)[0]
                v = (v >> 4) if (c & 1) else (v & 0xFFF)
            if v == 0:
                fh.seek((first_data + (c - 2) * spc) * bps)
                fh.write(zero)
                freed += 1
        return bits, freed, nclus


def main():
    if len(sys.argv) != 5:
        raise SystemExit(__doc__)
    part, mf, srcroot, report = sys.argv[1:]
    log = []
    n = orphan_appledouble(part, log)
    missing = manifest(part, mf, srcroot, log)
    bits, freed, nclus = zero_free(part)

    m = listing(part)
    keys = []
    for k in KEY_FILES:
        if k.upper() in m:
            p = m[k.upper()][0]
            data = mt("mtype", "-i", part, "::" + p)
            keys.append("%s  %8d  %s" % (hashlib.md5(data).hexdigest(), len(data), p))
        else:
            keys.append("%-32s  %8s  %s" % ("(not on disk)", "", k))

    with open(report, "w") as out:
        out.write("== changes\n" + "\n".join(log) + "\n\n")
        out.write("== key components (md5, bytes, path)\n" + "\n".join(keys) + "\n\n")
        out.write("== FAT%d, %d of %d clusters free (zeroed)\n\n" % (bits, freed, nclus))
        out.write("== files\n")
        for up in sorted(m):
            out.write(m[up][0] + ("/" if m[up][1] else "") + "\n")

    print("bootdisk: %d orphaned AppleDouble files removed, %d manifest actions, "
          "%d free clusters zeroed" % (n, len(log) - n, freed))
    for k in keys:
        print("   " + k)
    if missing:
        print("bootdisk: %d manifest source(s) MISSING - see %s" % (missing, report))
        sys.exit(1)


if __name__ == "__main__":
    main()
