#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Compare critical nodes of a built DTB with the v1.0 reference DTS.

Critical mismatches exit 1. A full unified diff is written beside the report.
docs/SDT-NOTES.md must contain a ## Reviewed differences section that is not
still the placeholder, or the gate fails even when the nodes match.
"""
import re
import subprocess
import sys
from pathlib import Path


CRITICAL = {
    "sdr": "0 29 1 0 30 1 0 33 1 0 34 1",
    "dma@80400000": "0 35 4 0 36 4",
    "dma@80410000": "0 31 4 0 32 4",
    "i2c@41600000": "0 58 4",
}


def cells(text):
    nums = []
    for tok in re.findall(r"0x[0-9a-fA-F]+|\d+", text):
        nums.append(str(int(tok, 0)))
    return " ".join(nums)


def node_body(dts, name):
    # First node whose header is exactly this name. Children are included.
    pat = re.compile(r"(?m)^(?P<indent>\t*)%s(?:@[0-9a-fA-F]+)? \{" % re.escape(name.split("@")[0] if False else name))
    # Names already include @addr when that is the identity.
    pat = re.compile(r"(?m)^(?P<indent>\t*)%s \{" % re.escape(name))
    match = pat.search(dts)
    if not match:
        return ""
    i = match.end()
    depth = 1
    while i < len(dts) and depth:
        if dts[i] == "{":
            depth += 1
        elif dts[i] == "}":
            depth -= 1
        i += 1
    return dts[match.start() : i]


def prop(body, key):
    match = re.search(r"%s = <([^>]+)>" % re.escape(key), body)
    if not match:
        flag = re.search(r"(?m)^\s*%s;" % re.escape(key), body)
        return "true" if flag else ""
    return cells(match.group(1))


def fdt_interrupts(fdtget, dtb, suffix):
    listing = subprocess.check_output([fdtget, "-l", dtb, "/"], text=True, stderr=subprocess.DEVNULL)
    # Full walk is done by the shell helper; here ask fdtget for known paths via a walk.
    found = []

    def walk(node):
        try:
            kids = subprocess.check_output([fdtget, "-l", dtb, node], text=True, stderr=subprocess.DEVNULL)
        except subprocess.CalledProcessError:
            return
        for child in kids.splitlines():
            if not child:
                continue
            path = "/" + child if node == "/" else node + "/" + child
            if path.endswith("/" + suffix) or path == "/" + suffix:
                found.append(path)
            walk(path)

    walk("/")
    if not found:
        return "", ""
    path = found[0]
    try:
        raw = subprocess.check_output([fdtget, "-t", "u", dtb, path, "interrupts"], text=True, stderr=subprocess.DEVNULL)
    except subprocess.CalledProcessError:
        raw = ""
    return path, " ".join(raw.split())


def compatible_present(fdtget, dtb, needle):
    # fdtget cannot search. Walk is expensive but the tree is small.
    hits = []

    def walk(node):
        try:
            kids = subprocess.check_output([fdtget, "-l", dtb, node], text=True, stderr=subprocess.DEVNULL)
        except subprocess.CalledProcessError:
            return
        for child in kids.splitlines():
            if not child:
                continue
            path = "/" + child if node == "/" else node + "/" + child
            try:
                comp = subprocess.check_output([fdtget, dtb, path, "compatible"], text=True, stderr=subprocess.DEVNULL)
            except subprocess.CalledProcessError:
                comp = ""
            if needle in comp:
                hits.append(path)
            walk(path)

    walk("/")
    return hits


def main():
    if len(sys.argv) != 5:
        print("usage: check_dt_semantic.py REF.dts BUILT.dtb SDT-NOTES.md DIFF-OUT", file=sys.stderr)
        return 2
    ref_path, dtb, notes, diff_out = map(Path, sys.argv[1:])
    fdtget = "fdtget"
    ref = ref_path.read_text(errors="replace")
    built_dts = subprocess.check_output(["dtc", "-I", "dtb", "-O", "dts", str(dtb)], text=True, stderr=subprocess.DEVNULL)
    diff = subprocess.run(["diff", "-u", str(ref_path), "-"], input=built_dts, text=True, capture_output=True)
    diff_out.write_text(diff.stdout)
    print(f"WROTE {diff_out} ({len(diff.stdout.splitlines())} lines)")

    rc = 0
    for name, want in CRITICAL.items():
        body = node_body(ref, name)
        got_ref = prop(body, "interrupts") if body else ""
        path, got_dtb = fdt_interrupts(fdtget, str(dtb), name)
        if got_ref != want:
            print(f"FAIL: reference {name} interrupts '{got_ref}' != '{want}'")
            rc = 1
        if got_dtb != want:
            print(f"FAIL: built {path or name} interrupts '{got_dtb}' != '{want}'")
            rc = 1
        else:
            print(f"PASS: {path} interrupts = {got_dtb}")

    ad = node_body(ref, "ad9361-phy@0")
    for key in ("adi,rx-rf-port-input-select", "adi,tx-rf-port-input-select"):
        ref_v = prop(ad, key)
        if ref_v != "0":
            print(f"FAIL: reference {key} = '{ref_v}'")
            rc = 1
    phy_paths = compatible_present(fdtget, str(dtb), "adi,ad9361")
    if not phy_paths:
        print("FAIL: built DTB has no adi,ad9361 node")
        rc = 1
    else:
        for key in ("adi,rx-rf-port-input-select", "adi,tx-rf-port-input-select"):
            raw = subprocess.check_output([fdtget, "-t", "u", str(dtb), phy_paths[0], key], text=True, stderr=subprocess.DEVNULL)
            val = " ".join(raw.split())
            if val != "0":
                print(f"FAIL: built {phy_paths[0]} {key} = '{val}'")
                rc = 1
            else:
                print(f"PASS: {phy_paths[0]} {key} = 0")

    for needle, label in (
        ("adi,adm1166", "ADM1166"),
        ("cdns,gem", "Ethernet"),
        ("arasan,sdhci", "SD"),
        ("cdns,uart", "UART"),
        ("chipidea,usb2", "USB"),
    ):
        hits = compatible_present(fdtget, str(dtb), needle)
        # Ethernet on this SoC is often xlnx,zynq-gem as well as cdns,gem.
        if not hits and needle == "cdns,gem":
            hits = compatible_present(fdtget, str(dtb), "gem")
        if not hits and needle == "chipidea,usb2":
            hits = compatible_present(fdtget, str(dtb), "usb")
        if hits:
            print(f"PASS: {label} at {hits[0]}")
        else:
            print(f"FAIL: {label} ({needle}) missing")
            rc = 1

    text = notes.read_text(errors="replace") if notes.is_file() else ""
    marker = "## Reviewed differences"
    if marker not in text:
        print(f"FAIL: {notes} has no '{marker}' section")
        return 1
    section = text.split(marker, 1)[1]
    if "pending first image" in section:
        print("FAIL: Reviewed differences is still the placeholder")
        return 1
    if len(section.strip()) < 40:
        print("FAIL: Reviewed differences is empty")
        return 1
    print("PASS: Reviewed differences is filled in")
    return rc


if __name__ == "__main__":
    sys.exit(main())
