#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# SDT PetaLinux build for ADRV9361-Z7035. Stages are idempotent.
# all = fetch + sdt + plnx-create + sw + image. It does not flash and it does
# not run the on-board matrix.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")" && pwd)
cd "$ROOT"

STAGE="all"
XSA_ARG=""
DEVICE=""
YES=0
FORCE=0

usage() {
  echo "usage: $0 [fetch|sdt|plnx-create|sw|image|gates|flash|test|all] [--xsa FILE] [--device /dev/sdX] [--yes] [--force]" >&2
  exit 2
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    fetch|sdt|plnx-create|sw|image|gates|flash|test|all) STAGE=$1; shift ;;
    --xsa) XSA_ARG=${2:-}; shift 2 ;;
    --device) DEVICE=${2:-}; shift 2 ;;
    --yes) YES=1; shift ;;
    --force) FORCE=1; shift ;;
    -h|--help) usage ;;
    *) usage ;;
  esac
done

if [ ! -f "$ROOT/config/local.conf" ]; then
  echo "Copy config/local.conf.example to config/local.conf and fill it in." >&2
  exit 2
fi
# shellcheck disable=SC1091
source "$ROOT/config/versions.conf"
# shellcheck disable=SC1091
source "$ROOT/config/local.conf"

LOG=$ROOT/build/logs
STATUS=$LOG/status.txt
mkdir -p "$LOG" "$ROOT/build/src" "$ROOT/build/images"
: >>"$STATUS"

die() {
  printf 'P22_STAGE_FAIL %s\n' "$*" >>"$STATUS"
  printf 'P22_STAGE_FAIL %s\n' "$*" >&2
  exit 1
}

need() {
  local name=$1
  if [ -z "${!name:-}" ]; then
    die "config/local.conf is missing $name"
  fi
}

disk_ok() {
  local avail
  avail=$(df -BG --output=avail "$ROOT" | awk 'NR==2 {gsub(/[^0-9]/,"",$1); print $1}')
  if [ "${avail:-0}" -lt 30 ]; then
    die "free space ${avail}G is below 30G"
  fi
  echo "free_space_gb=$avail"
}

load_tools() {
  local settings=""
  if [ -n "${TOOLS_ROOT:-}" ] && [ -f "$TOOLS_ROOT/PetaLinux/tool/settings.sh" ]; then
    settings=$TOOLS_ROOT/PetaLinux/tool/settings.sh
  elif [ -n "${TOOLS_ROOT:-}" ] && [ -f "$TOOLS_ROOT/PetaLinux/settings.sh" ]; then
    settings=$TOOLS_ROOT/PetaLinux/settings.sh
  else
    die "PetaLinux settings.sh not found; set TOOLS_ROOT"
  fi
  # settings.sh treats a non-empty $# as an install prefix. Clear this function's args.
  set +u
  set --
  # shellcheck disable=SC1090
  source "$settings"
  set -u
  if [ -z "${XILINXD_LICENSE_FILE:-}" ] && [ -f "${HOME}/.Xilinx/xilinx_ise_vivado.lic" ]; then
    export XILINXD_LICENSE_FILE="${HOME}/.Xilinx/xilinx_ise_vivado.lic"
  fi
  export SDTGEN=${SDTGEN:-${TOOLS_ROOT}/Vitis/bin/sdtgen}
  if [ -n "${PETALINUX:-}" ] && [ -d "${PETALINUX}/sysroots/x86_64-petalinux-linux/usr/bin" ]; then
    export PATH="${PETALINUX}/sysroots/x86_64-petalinux-linux/usr/bin:${PATH}"
  fi
  if [ -d "${TOOLS_ROOT}/Vitis/bin" ]; then
    export PATH="${TOOLS_ROOT}/Vitis/bin:${PATH}"
  fi
}

xsa_path() {
  if [ -n "$XSA_ARG" ]; then
    printf '%s\n' "$XSA_ARG"
  elif [ -n "${XSA:-}" ]; then
    printf '%s\n' "$XSA"
  else
    die "pass --xsa or set XSA in config/local.conf"
  fi
}

run_stage() {
  local name=$1
  shift
  local log=$LOG/${name}.log
  local start
  start=$(date +%s)
  echo "P22_STAGE_BEGIN $name" >>"$STATUS"
  set +e
  (
    set -euo pipefail
    "$@"
  ) >"$log" 2>&1
  local rc=$?
  set -e
  local dur=$(( $(date +%s) - start ))
  printf '%s %s %s\n' "$name" "$dur" "$rc" >>"$LOG/times.txt"
  if [ "$rc" -ne 0 ]; then
    echo "P22_STAGE_FAIL $name rc=$rc ${dur}s" >>"$STATUS"
    exit "$rc"
  fi
  echo "P22_STAGE_OK $name ${dur}s" >>"$STATUS"
}

stage_fetch() {
  need OPENWIFI_REPO
  need OPENWIFI_BRANCH
  need META_ADI_DIR
  need DL_DIR
  need SSTATE_DIR
  git -C "$OPENWIFI_REPO" cat-file -e "${OPENWIFI_REV}^{commit}"
  local head
  head=$(git -C "$META_ADI_DIR" rev-parse HEAD)
  [ "$head" = "$META_ADI_REV" ] || die "meta-adi HEAD $head != $META_ADI_REV"
  [ -f "$META_ADI_DIR/meta-adi-xilinx/conf/layer.conf" ] || die "meta-adi-xilinx layer.conf missing"
  if [ -n "${OPENWIFI_HW_REPO:-}" ]; then
    head=$(git --git-dir="$OPENWIFI_HW_REPO/.git" rev-parse HEAD)
    [ "$head" = "$OPENWIFI_HW_REV" ] || die "openwifi-hw HEAD $head != $OPENWIFI_HW_REV"
  fi
  if [ -n "${ADI_HDL_REPO:-}" ]; then
    head=$(git -C "$ADI_HDL_REPO" rev-parse HEAD)
    [ "$head" = "$ADI_HDL_REV" ] || die "hdl HEAD $head != $ADI_HDL_REV"
  fi
  if [ -n "${OPENOFDM_RX_REPO:-}" ]; then
    head=$(git -C "$OPENOFDM_RX_REPO" rev-parse HEAD)
    [ "$head" = "$OPENOFDM_RX_REV" ] || die "openofdm_rx HEAD $head != $OPENOFDM_RX_REV"
  fi
  local dest=$ROOT/build/src/openwifi
  if [ ! -d "$dest/.git" ]; then
    git clone --local "$OPENWIFI_REPO" "$dest"
  fi
  git -C "$dest" checkout -B "$OPENWIFI_BRANCH" "$OPENWIFI_REV"
  git -C "$dest" rev-parse HEAD
  echo "fetch ok"
}

stage_sdt() {
  load_tools
  local xsa sha
  xsa=$(xsa_path)
  [ -f "$xsa" ] || die "XSA not found"
  sha=$(sha256sum "$xsa" | awk '{print $1}')
  [ "$sha" = "$V1_0_XSA_SHA" ] || die "XSA sha256 $sha does not match V1_0_XSA_SHA"
  if [ "$FORCE" != 1 ] && [ -f "$ROOT/build/sdt/system-top.dts" ] && [ -f "$ROOT/build/sdt/pl.dtsi" ] && [ "$(cat "$LOG/sdt.sha" 2>/dev/null || true)" = "$sha" ]; then
    echo "sdt outputs are current for $sha"
    return 0
  fi
  TOOLS_ROOT=${TOOLS_ROOT} "$ROOT/sw/sdt/gen_sdt.sh" --xsa "$xsa" --out "$ROOT/build/sdt"
  printf '%s\n' "$sha" >"$LOG/sdt.sha"
  local ndts
  ndts=$(find "$ROOT/build/sdt" -name '*.dts' | wc -l)
  echo "dts_count=$ndts"
  [ "$ndts" -ge 1 ] || die "sdtgen produced no dts"
}

hw_desc() {
  local ndts
  ndts=$(find "$ROOT/build/sdt" -name '*.dts' | wc -l)
  if [ "$ndts" -eq 1 ]; then
    printf '%s\n' "$ROOT/build/sdt"
  else
    printf '%s\n' "$ROOT/build/sdt/system-top.dts"
  fi
}

write_bsp() {
  local conf=$ROOT/build/plnx/project-spec/meta-user/conf/petalinuxbsp.conf
  mkdir -p "$(dirname "$conf")"
  [ -f "$conf" ] || printf '%s\n' "#User Configuration" >"$conf"
  local repo=$ROOT/build/src/openwifi
  python3 - "$conf" "$repo" <<PY
import re, sys
path, repo = sys.argv[1:]
text = open(path).read()
block = """# OPENWIFI-BEGIN
KERNEL_DTB = "zynq-adrv9361-z7035-bob"
DTB_PL_DELETE = "pl-delete-nodes-openwifi-adrv9361z7035-bob"
OPENWIFI_REPO = "%s"
OPENWIFI_REV = "$OPENWIFI_REV"
OPENWIFI_BRANCH = "$OPENWIFI_BRANCH"
OPENWIFI_HW_REV = "$OPENWIFI_HW_REV"
ADI_HDL_REV = "$ADI_HDL_REV"
OPENOFDM_RX_REV = "$OPENOFDM_RX_REV"
META_ADI_REV = "$META_ADI_REV"
OPENWIFI_XSA_SHA256 = "$V1_0_XSA_SHA"
OPENWIFI_TOOL_VERSION = "$TOOL_VERSION"
DL_DIR = "$DL_DIR"
SSTATE_DIR = "$SSTATE_DIR"
BB_NUMBER_THREADS = "${BB_NUMBER_THREADS:-8}"
PARALLEL_MAKE = "${PARALLEL_MAKE:--j 8}"
WKS_FILE = "openwifi-sd.wks"
# OPENWIFI-END
""" % repo
text = re.sub(r"# OPENWIFI-BEGIN\n.*?# OPENWIFI-END\n", "", text, flags=re.S)
text = text.rstrip() + "\n" + block
open(path, "w").write(text)
print("wrote", path)
PY
}

apply_kconfig() {
  local cfg=$ROOT/build/plnx/project-spec/configs/config
  [ -f "$cfg" ] || die "project config missing"
  python3 - "$cfg" "$META_ADI_DIR/meta-adi-xilinx" "$ROOT/sw/meta-openwifi" <<'PY'
import re, sys
path, adi, ow = sys.argv[1:]
text = open(path).read()
wanted = {
    "CONFIG_SUBSYSTEM_ARCH_ARM": "y",
    "CONFIG_SUBSYSTEM_ROOTFS_EXT4": "y",
    "CONFIG_SUBSYSTEM_BOOTARGS_AUTO": "y",
    "CONFIG_SUBSYSTEM_BOOTARGS_EARLYPRINTK": "y",
    "CONFIG_SUBSYSTEM_EXTRA_BOOTARGS": '"ignore_loglevel loglevel=8 net.ifnames=0"',
    "CONFIG_SUBSYSTEM_HOSTNAME": '"openwifi"',
    "CONFIG_USER_LAYER_0": '"%s"' % adi,
    "CONFIG_USER_LAYER_1": '"%s"' % ow,
}
for key, value in wanted.items():
    line = "%s=%s" % (key, value)
    pat = re.compile(r"(?m)^#?\s*%s\b.*$" % re.escape(key))
    if pat.search(text):
        text = pat.sub(line, text, count=1)
    else:
        text += "\n" + line + "\n"
open(path, "w").write(text)
open(path + ".intended", "w").write("\n".join("%s=%s" % kv for kv in wanted.items()) + "\n")
print("kconfig applied")
PY
}

verify_kconfig() {
  local cfg=$ROOT/build/plnx/project-spec/configs/config
  python3 - "$cfg" "$cfg.intended" <<'PY'
import sys
cfg, intended = sys.argv[1:]
text = open(cfg).read().splitlines()
missing = []
for line in open(intended):
    line = line.strip()
    if line not in text:
        missing.append(line)
if missing:
    print("MISSING")
    print("\n".join(missing))
    raise SystemExit(1)
print("kconfig verified")
for line in open(intended):
    print("OK", line.strip())
PY
}

write_bb_local() {
  local loc=$ROOT/build/plnx/build/conf/local.conf
  [ -f "$loc" ] || die "bitbake local.conf missing after petalinux-config"
  python3 - "$loc" <<PY
import re, sys
path = sys.argv[1]
text = open(path).read()
block = """# OPENWIFI-BEGIN
DL_DIR = "$DL_DIR"
SSTATE_DIR = "$SSTATE_DIR"
BB_NUMBER_THREADS = "${BB_NUMBER_THREADS:-8}"
PARALLEL_MAKE = "${PARALLEL_MAKE:--j 8}"
# OPENWIFI-END
"""
text = re.sub(r"# OPENWIFI-BEGIN\n.*?# OPENWIFI-END\n", "", text, flags=re.S)
open(path, "w").write(text.rstrip() + "\n" + block)
print("bitbake local.conf updated")
PY
}

stage_plnx() {
  load_tools
  disk_ok
  [ -f "$ROOT/build/sdt/system-top.dts" ] || die "run the sdt stage first"
  local proj=$ROOT/build/plnx
  if [ ! -d "$proj/.petalinux" ]; then
    (cd "$ROOT/build" && petalinux-create project -n plnx --template zynq)
  fi
  write_bsp
  local hw
  hw=$(hw_desc)
  echo "hw_description=$hw"
  (cd "$proj" && petalinux-config --get-hw-description "$hw" --silentconfig)
  apply_kconfig
  write_bsp
  (cd "$proj" && petalinux-config --silentconfig)
  if ! verify_kconfig; then
    echo "config lost user layers; applying again"
    apply_kconfig
    write_bsp
    (cd "$proj" && petalinux-config --silentconfig)
    verify_kconfig
  fi
  write_bb_local
  echo "plnx-create ok"
}

stage_sw() {
  load_tools
  disk_ok
  [ -d "$ROOT/build/plnx/.petalinux" ] || die "run plnx-create first"
  write_bb_local
  (cd "$ROOT/build/plnx" && petalinux-build)
}

extract_xsa_bit() {
  local xsa bit
  xsa=$(xsa_path)
  bit=$ROOT/build/xsa-system.bit
  python3 - "$xsa" "$bit" <<'PY'
import sys, zipfile
from pathlib import Path
xsa, dest = sys.argv[1:]
with zipfile.ZipFile(xsa) as zf:
    names = [n for n in zf.namelist() if n.lower().endswith(".bit")]
    if not names:
        raise SystemExit("XSA contains no .bit")
    names.sort(key=lambda n: zf.getinfo(n).file_size, reverse=True)
    Path(dest).write_bytes(zf.read(names[0]))
    print("extracted", names[0], "->", dest, file=sys.stderr)
PY
  printf '%s\n' "$bit"
}

copy_over() {
  local src=$1 dest=$2
  # petalinux-package already writes BOOT.BIN in images/linux. GNU cp
  # exits 1 when the source and the destination are the same file.
  if [ -e "$dest" ] && [ "$src" -ef "$dest" ]; then
    return 0
  fi
  cp -f "$src" "$dest"
}

install_boot_artifacts() {
  local bit=$1
  local boot=$ROOT/build/plnx/images/linux/BOOT.BIN
  local dest_bit=$ROOT/build/plnx/images/linux/system.bit
  [ -f "$boot" ] || die "BOOT.BIN was not packaged"
  [ -f "$bit" ] || die "extracted bitstream missing"
  copy_over "$bit" "$dest_bit"
  local deploy=$ROOT/build/plnx/build/tmp/deploy/images
  local dir
  if [ -d "$deploy" ]; then
    for dir in "$deploy"/*; do
      [ -d "$dir" ] || continue
      copy_over "$bit" "$dir/system.bit"
      copy_over "$boot" "$dir/BOOT.BIN"
      echo "installed boot files into $dir"
    done
  fi
}

stage_image() {
  load_tools
  disk_ok
  local proj=$ROOT/build/plnx
  local bit fsbl
  bit=$(extract_xsa_bit)
  fsbl=$proj/images/linux/zynq_fsbl.elf
  [ -f "$fsbl" ] || die "zynq_fsbl.elf missing; the sw stage did not build the multiconfig FSBL"
  cp -f "$bit" "$proj/images/linux/system.bit"
  rm -f "$proj/images/linux/BOOT.BIN"
  (cd "$proj" && petalinux-package --boot --fsbl "$fsbl" --fpga "$proj/images/linux/system.bit" --u-boot)
  install_boot_artifacts "$bit"
  (cd "$proj" && petalinux-build -c petalinux-image-minimal)
  # The image task reads BOOT.BIN during do_rootfs. Run it again if the first
  # parse of this build happened to hash the previous "missing" boot file.
  install_boot_artifacts "$bit"
  (cd "$proj" && petalinux-build -c petalinux-image-minimal)
  publish_sums
  stage_gates
}

stage_gates() {
  local bit
  bit=$(extract_xsa_bit)
  FDTGET_PATH="${PATH}" "$ROOT/scripts/check_image_gates.sh" \
    "$ROOT/build/plnx" "$bit" "$ROOT/docs/SDT-NOTES.md"
}

publish_sums() {
  local out=$ROOT/build/images
  mkdir -p "$out"
  local img=$ROOT/build/plnx/images/linux
  cp -f "$img/BOOT.BIN" "$img/system.bit" "$img/system.dtb" "$out/"
  local wic
  wic=$(find "$img" -name '*.wic' -type f -print -quit)
  cp -f "$wic" "$out/openwifi-adrv9361z7035.wic"
  (
    cd "$out"
    sha256sum BOOT.BIN system.bit system.dtb openwifi-adrv9361z7035.wic > SHA256SUMS
  )
  python3 - "$out/build-info.json" "$out/SHA256SUMS" <<PY
import json, sys
info = {
  "openwifi": "$OPENWIFI_REV",
  "openwifi_hw": "$OPENWIFI_HW_REV",
  "adi_hdl": "$ADI_HDL_REV",
  "openofdm_rx": "$OPENOFDM_RX_REV",
  "meta_adi": "$META_ADI_REV",
  "tool": "$TOOL_VERSION",
  "xsa_sha256": "$V1_0_XSA_SHA",
  "board": "$BOARD",
  "dt_strategy": "B",
}
sums = {}
for line in open(sys.argv[2]):
    sha, name = line.split()
    sums[name] = sha
info["images"] = sums
open(sys.argv[1], "w").write(json.dumps(info, indent=2) + "\n")
print("wrote", sys.argv[1])
PY
}

stage_flash() {
  if [ -z "$DEVICE" ] || [ "$YES" != 1 ]; then
    echo "Refusing to flash. After you confirm the target card, run:"
    echo "  ./build.sh flash --device /dev/sdX --yes"
    echo "Use a second microSD so the v1.0 card stays untouched."
    exit 2
  fi
  case "$DEVICE" in
    /dev/sd[a-z]|/dev/mmcblk[0-9]) ;;
    *) die "device must be /dev/sdX or /dev/mmcblkN" ;;
  esac
  local wic=$ROOT/build/images/openwifi-adrv9361z7035.wic
  [ -f "$wic" ] || die "image missing; run the image stage"
  lsblk -dn -o NAME,RM,TRAN,SIZE,TYPE "$DEVICE"
  python3 - "$DEVICE" <<'PY'
import json, subprocess, sys
dev = sys.argv[1].rsplit("/", 1)[-1]
data = json.loads(subprocess.check_output(["lsblk", "-J", "-o", "NAME,RM,TRAN,MOUNTPOINT", dev]))
# lsblk on a whole disk
raw = subprocess.check_output(["lsblk", "-J", "-o", "NAME,RM,TRAN,MOUNTPOINT", sys.argv[1]], text=True)
info = json.loads(raw)
nodes = info.get("blockdevices") or []
if not nodes:
    raise SystemExit("FAIL: lsblk returned nothing")
node = nodes[0]
if str(node.get("rm")) not in ("1", "True", "true"):
    raise SystemExit("FAIL: device is not removable")
def mounts(n):
    if n.get("mountpoint"):
        raise SystemExit("FAIL: device is mounted")
    for c in n.get("children") or []:
        mounts(c)
mounts(node)
print("flash target ok", node.get("name"), node.get("tran"))
PY
  dd if="$wic" of="$DEVICE" bs=4M conv=fsync status=progress
  sync
  echo "flashed $DEVICE"
  sha256sum "$wic"
}

stage_test() {
  "$ROOT/tests/run_regression.sh" --matrix --image "${IMAGE_NAME:-sdt}"
}

case "$STAGE" in
  fetch) run_stage fetch stage_fetch ;;
  sdt) run_stage sdt stage_sdt ;;
  plnx-create) run_stage plnx-create stage_plnx ;;
  sw) run_stage sw stage_sw ;;
  image) run_stage image stage_image ;;
  gates) run_stage gates stage_gates ;;
  flash) stage_flash ;;
  test) run_stage test stage_test ;;
  all)
    run_stage fetch stage_fetch
    run_stage sdt stage_sdt
    run_stage plnx-create stage_plnx
    run_stage sw stage_sw
    run_stage image stage_image
    ;;
esac
echo "P22_BUILD_DONE $STAGE"
