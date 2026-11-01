#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Image gates. Every check is fatal. No skipped essential step.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
if [ "$#" -ne 3 ]; then
  echo "usage: $0 PLNX_DIR XSA_BIT NOTES.md" >&2
  exit 2
fi
PLNX=$1
XSA_BIT=$2
NOTES=$3
IMG=$PLNX/images/linux
OUT=${GATE_OUT:-$ROOT/build/logs}
mkdir -p "$OUT"

find_one() {
  local hits
  hits=$(find "$1" -name "$2" -type f -print -quit)
  if [ -z "$hits" ]; then
    echo "FAIL: no $2 under $1" >&2
    exit 1
  fi
  printf '%s\n' "$hits"
}

BOOT=$(find_one "$IMG" 'BOOT.BIN')
BIT=$(find_one "$IMG" 'system.bit')
DTB=$(find_one "$IMG" 'system.dtb')
WIC=$(find "$IMG" -name '*.wic' -type f -print -quit)
if [ -z "$WIC" ]; then
  echo "FAIL: no uncompressed WIC under $IMG" >&2
  exit 1
fi
ROOTFS=$(find "$IMG" -name 'rootfs.tar.gz' -type f -print -quit)
if [ -z "$ROOTFS" ]; then
  echo "FAIL: no rootfs.tar.gz under $IMG" >&2
  exit 1
fi

echo "BOOT=$BOOT"
echo "BIT=$BIT"
echo "DTB=$DTB"
echo "WIC=$WIC"
echo "ROOTFS=$ROOTFS"

python3 - "$WIC" "$OUT/fat-system.bit" <<'PY'
import struct, sys
wic, dest = sys.argv[1:]
with open(wic, "rb") as f:
    mbr = f.read(512)
start = None
for i in range(4):
    ent = mbr[446 + 16 * i : 446 + 16 * (i + 1)]
    if ent[4] in (0x01, 0x04, 0x06, 0x0B, 0x0C, 0x0E):
        start = int.from_bytes(ent[8:12], "little") * 512
        break
if start is None:
    raise SystemExit("FAIL: WIC has no FAT partition in the MBR")
print(f"FAT_OFFSET {start}")
# Copy system.bit out with mtools via a small offset image is done by the shell.
open(dest + ".offset", "w").write(str(start))
PY
OFF=$(cat "$OUT/fat-system.bit.offset")
mcopy -i "${WIC}@@${OFF}" ::/system.bit "$OUT/fat-system.bit"
mcopy -i "${WIC}@@${OFF}" ::/BOOT.BIN "$OUT/fat-BOOT.BIN"
"$ROOT/scripts/check_boot_bitstream.sh" "$XSA_BIT" "$BOOT" "$BIT" "$OUT/fat-system.bit" "$OUT/fat-BOOT.BIN"
echo "PASS: bitstream payload"

export PATH="${FDTGET_PATH:-$PATH}"
if ! command -v fdtget >/dev/null 2>&1; then
  echo "FAIL: fdtget not on PATH" >&2
  exit 1
fi
"$ROOT/scripts/check_dtb_irqs.sh" "$DTB"
python3 "$ROOT/scripts/check_dt_semantic.py" \
  "$ROOT/sw/reference/v1.0-system.dts" "$DTB" "$NOTES" "$OUT/dt-semantic.diff"

MANIFEST=$(find "$IMG" -name '*.manifest' -type f -print -quit)
if [ -z "$MANIFEST" ]; then
  echo "FAIL: no rootfs manifest" >&2
  exit 1
fi
python3 - "$ROOTFS" "$MANIFEST" <<'PY'
import sys, tarfile
rootfs, manifest = sys.argv[1:]
need_files = [
    "etc/openwifi-build-info",
    "home/analog/openwifi/wgd.sh",
    "home/analog/openwifi/rf_init_11n.sh",
    "home/analog/openwifi/agc_settings.sh",
    "home/analog/openwifi/monitor_ch.sh",
    "home/analog/openwifi/sdrctl",
    "home/analog/openwifi/inject_80211",
    "home/analog/openwifi/side_ch_ctl",
    "home/analog/openwifi/sdr.ko",
    "home/analog/openwifi/side_ch.ko",
    "home/analog/openwifi/tx_intf.ko",
    "home/analog/openwifi/rx_intf.ko",
    "home/analog/openwifi/openofdm_tx.ko",
    "home/analog/openwifi/openofdm_rx.ko",
    "home/analog/openwifi/xpu.ko",
    "home/analog/openwifi/hostapd-openwifi-2g.conf",
    "home/analog/openwifi/dnsmasq-sdr0.conf",
    "home/analog/openwifi/sdr-ad-hoc-up.sh",
    "home/analog/openwifi/sdr-ad-hoc-join.sh",
    "home/analog/openwifi/cw_max_min_cfg.sh",
    "home/analog/openwifi/slice_cfg.sh",
    "home/analog/openwifi/stat_enable.sh",
    "etc/modprobe.d/openwifi.conf",
    "usr/sbin/hostapd",
    "usr/sbin/iw",
    "usr/sbin/tcpdump",
    "usr/sbin/dnsmasq",
    "usr/sbin/wpa_supplicant",
    "usr/bin/iperf3",
]
need_pkgs = [
    "openwifi-userspace", "openwifi-driver", "openwifi-tools", "hostapd",
    "iw", "wireless-regdb-static", "tcpdump", "dnsmasq", "iperf3",
    "avahi-daemon", "kernel-module-xilinx-dma", "openwifi-net", "libnl",
    "wpa-supplicant",
]
# tcpdump and dnsmasq install under /usr/bin on this release.
file_alts = {
    "usr/sbin/tcpdump": ("usr/sbin/tcpdump", "usr/bin/tcpdump"),
    "usr/sbin/dnsmasq": ("usr/sbin/dnsmasq", "usr/bin/dnsmasq"),
}

def has_file(names, path):
    for cand in file_alts.get(path, (path,)):
        if cand in names or ("./" + cand) in names:
            return True
    return False

def has_pkg(lines, pkg):
    if pkg in lines:
        return True
    # The split module package is versioned. libnl ships as libnl-3-200.
    if pkg == "kernel-module-xilinx-dma":
        return any(item == pkg or item.startswith(pkg + "-") for item in lines)
    if pkg == "libnl":
        return any(item == pkg or item.startswith("libnl-") for item in lines)
    return False

names = set()
with tarfile.open(rootfs, "r:gz") as tar:
    for member in tar.getnames():
        names.add(member.lstrip("./"))
missing = [n for n in need_files if not has_file(names, n)]
text = open(manifest, errors="replace").read()
# Manifest lines are "pkg arch version". Match the package token.
lines = [ln.split()[0] for ln in text.splitlines() if ln.strip()]
missing_pkg = [p for p in need_pkgs if not has_pkg(lines, p)]
if missing or missing_pkg:
    print("FAIL files", missing)
    print("FAIL packages", missing_pkg)
    raise SystemExit(1)
info = None
with tarfile.open(rootfs, "r:gz") as tar:
    for member in tar.getmembers():
        if member.name.lstrip("./") == "etc/openwifi-build-info":
            info = tar.extractfile(member).read().decode()
            break
print(info)
for key in ("openwifi_srcrev=", "xsa_sha256=", "bitstream_sha256=", "tool_version="):
    if key not in (info or ""):
        print("FAIL: build-info missing", key)
        raise SystemExit(1)
print("PASS: rootfs manifest")
PY

python3 - "$ROOTFS" <<'PY'
import sys, tarfile, re
rootfs = sys.argv[1]
ko = None
kver = None
with tarfile.open(rootfs, "r:gz") as tar:
    for member in tar.getmembers():
        name = member.name.lstrip("./")
        if name.endswith("/extra/sdr.ko") or name.endswith("extra/sdr.ko"):
            ko = tar.extractfile(member).read()
            parts = name.split("/")
            # lib/modules/<ver>/extra/sdr.ko
            if "modules" in parts:
                kver = parts[parts.index("modules") + 1]
if ko is None or not kver:
    raise SystemExit("FAIL: sdr.ko not in rootfs")
text = ko.decode("latin1", errors="ignore")
m = re.search(r"vermagic=([^\s]+)", text)
if not m:
    # The string is stored without a key in some builds: "<ver> SMP preempt ..."
    m = re.search(re.escape(kver), text)
    if not m:
        raise SystemExit("FAIL: vermagic string not found")
    print("PASS: vermagic contains", kver)
else:
    if not m.group(1).startswith(kver):
        raise SystemExit(f"FAIL: vermagic {m.group(1)} != kernel {kver}")
    print("PASS: vermagic", m.group(1))
PY

echo "PASS: image gates"
