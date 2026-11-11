#!/bin/bash
# Read-only build-host check. Needs no sudo and changes nothing.
# It prints what is missing and the command that would fix it.
#   tools/check_host.sh [--dir <build dir>] [--bench]
# --bench also checks the tools the on-air test harness needs.
# Exit status: 0 if the build prerequisites are met, 1 otherwise.
set -u
export LC_ALL=C

DIR=.
BENCH=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dir) DIR=$2; shift 2 ;;
    --bench) BENCH=1; shift ;;
    -h|--help) sed -n '2,6p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

fail=0
ok()   { printf 'OK    %s\n' "$*"; }
warn() { printf 'WARN  %s\n' "$*"; }
miss() { printf 'MISS  %s\n' "$*"; fail=1; }

# OS
if [ -r /etc/os-release ]; then
  . /etc/os-release
  case "${ID:-}-${VERSION_ID:-}" in
    ubuntu-22.04) ok "OS ${PRETTY_NAME} (PetaLinux 2025.1 supported host)" ;;
    ubuntu-24.04) ok "OS ${PRETTY_NAME} (see docs/BUILD.md for its status; PetaLinux 2025.1 prints 'not a supported OS')" ;;
    *) warn "OS ${PRETTY_NAME:-unknown} is not a validated host (Ubuntu 22.04 or 24.04)" ;;
  esac
else
  warn "no /etc/os-release"
fi

# /bin/sh must be bash for PetaLinux
sh_target=$(readlink -f /bin/sh)
case "$sh_target" in
  */bash) ok "/bin/sh -> $sh_target" ;;
  *) miss "/bin/sh -> $sh_target; fix: echo 'dash dash/sh boolean false' | sudo debconf-set-selections && sudo DEBIAN_FRONTEND=noninteractive dpkg-reconfigure dash" ;;
esac

# Unprivileged user namespaces (bitbake). Ubuntu 23.10+ restricts them through AppArmor.
uns=$(sysctl -n kernel.apparmor_restrict_unprivileged_userns 2>/dev/null || echo absent)
case "$uns" in
  0|absent) ok "kernel.apparmor_restrict_unprivileged_userns=$uns" ;;
  *) miss "kernel.apparmor_restrict_unprivileged_userns=$uns; fix: echo 'kernel.apparmor_restrict_unprivileged_userns = 0' | sudo tee /etc/sysctl.d/60-petalinux-userns.conf && sudo sysctl --system" ;;
esac

# Locale
if locale -a 2>/dev/null | grep -qiE '^en_US\.utf-?8$'; then
  ok "locale en_US.UTF-8 available"
else
  miss "locale en_US.UTF-8; fix: sudo locale-gen en_US.UTF-8"
fi

# Packages (Debian/Ubuntu). Names are the 24.04 ones; they also exist on 22.04
# except libsdl1.2-compat-dev (22.04: libsdl1.2-dev).
BUILD_PKGS="iproute2 gawk python3 python3-pip build-essential gcc git make net-tools libncurses-dev
zlib1g-dev libssl-dev flex bison libselinux1 gnupg wget diffstat chrpath socat xterm autoconf libtool
tar unzip texinfo gcc-multilib automake screen pax gzip cpio python3-pexpect xz-utils debianutils
iputils-ping python3-git python3-jinja2 python3-subunit lz4 zstd file locales libacl1 bc rsync less
lsb-release xxd"
BENCH_PKGS="iw hostapd sshpass dnsmasq-base tcpdump network-manager libpcap-dev bmap-tools device-tree-compiler u-boot-tools"
check_pkgs() { # label list
  local missing="" p
  for p in $2; do
    dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q '^install ok installed' || missing="$missing $p"
  done
  if [ -z "$missing" ]; then ok "$1 packages present"; else miss "$1 packages:$missing; fix: sudo apt-get install$missing"; fi
}
if command -v dpkg-query >/dev/null 2>&1; then
  check_pkgs build "$BUILD_PKGS"
  [ "$BENCH" = 1 ] && check_pkgs bench "$BENCH_PKGS"
else
  warn "dpkg-query not found; package check skipped"
fi

# Release tooling
if command -v gitleaks >/dev/null 2>&1; then ok "gitleaks $(gitleaks version 2>/dev/null)"; else warn "gitleaks not found (needed before a release tag)"; fi

# Xilinx tools on PATH (after sourcing the Vivado/Vitis/PetaLinux settings scripts)
for t in vivado sdtgen petalinux-build; do
  if command -v "$t" >/dev/null 2>&1; then ok "$t on PATH"; else warn "$t not on PATH (source the 2025.1 settings scripts first)"; fi
done

# Free space where the build runs
avail=$(df -BG --output=avail "$DIR" 2>/dev/null | awk 'NR==2 {gsub(/[^0-9]/,"",$1); print $1}')
if [ -z "$avail" ]; then
  warn "cannot read free space for $DIR"
elif [ "$avail" -lt 30 ]; then
  miss "free space ${avail}G in $DIR (build.sh stops below 30G)"
elif [ "$avail" -lt 120 ]; then
  warn "free space ${avail}G in $DIR (a clean-room build with cold native sstate wants about 120G)"
else
  ok "free space ${avail}G in $DIR"
fi

[ "$fail" = 0 ] && echo "RESULT: build prerequisites met" || echo "RESULT: something is missing (see MISS lines)"
exit "$fail"
