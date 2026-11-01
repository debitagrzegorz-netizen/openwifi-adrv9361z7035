#!/usr/bin/env python3
"""Compare two Vivado .hwh handoffs.

Path-valued parameter differences are reported and allowed. Every other
difference in cells, VLNVs, parameters, address blocks, memory ranges, and
ports fails the process.
"""

import sys
import xml.etree.ElementTree as ET
from pathlib import Path


SKIP_PARAMS = {"Component_Name"}


def load(path):
    text = Path(path).read_text(encoding="utf-8-sig")
    return ET.fromstring(text)


def modules(root):
    out = {}
    for mod in root.iter("MODULE"):
        full = mod.attrib.get("FULLNAME", "")
        params = {}
        for param in mod.findall("PARAMETER"):
            name = param.attrib.get("NAME", "")
            if name in SKIP_PARAMS:
                continue
            params[name] = param.attrib.get("VALUE", "")
        blocks = []
        for block in mod.findall("./ADDRESSBLOCKS/ADDRESSBLOCK"):
            blocks.append(
                (
                    block.attrib.get("INTERFACE", ""),
                    block.attrib.get("NAME", ""),
                    block.attrib.get("RANGE", ""),
                    block.attrib.get("ACCESS", ""),
                )
            )
        out[full] = {
            "instance": mod.attrib.get("INSTANCE", ""),
            "vlnv": mod.attrib.get("VLNV", ""),
            "params": params,
            "blocks": sorted(blocks),
        }
    return out


def memranges(root):
    rows = []
    for node in root.iter("MEMRANGE"):
        rows.append(
            (
                node.attrib.get("INSTANCE", ""),
                node.attrib.get("SLAVEBUSINTERFACE", ""),
                node.attrib.get("MASTERBUSINTERFACE", ""),
                node.attrib.get("ADDRESSBLOCK", ""),
                node.attrib.get("BASEVALUE", ""),
                node.attrib.get("HIGHVALUE", ""),
            )
        )
    return sorted(rows)


def ports(root):
    rows = []
    for port in root.iter("PORT"):
        conns = []
        for conn in port.findall("./CONNECTIONS/CONNECTION"):
            conns.append((conn.attrib.get("INSTANCE", ""), conn.attrib.get("PORT", "")))
        rows.append(
            (
                port.attrib.get("NAME", ""),
                port.attrib.get("SIGNAME", ""),
                port.attrib.get("DIR", ""),
                tuple(sorted(conns)),
            )
        )
    return sorted(rows)


def is_path(value):
    return "/" in value


def same_path_tail(a, b):
    return Path(a).name == Path(b).name and Path(a).name != ""


def main():
    if len(sys.argv) != 4:
        print("usage: compare_hwh.py REFERENCE NEW REPORT", file=sys.stderr)
        return 2
    ref_path, new_path, report_path = sys.argv[1:]
    ref = modules(load(ref_path))
    new = modules(load(new_path))
    lines = []
    fail = False

    def add(kind, detail, allowed=False):
        nonlocal fail
        flag = "ALLOW" if allowed else "DIFF"
        lines.append(f"{flag}\t{kind}\t{detail}")
        if not allowed:
            fail = True

    for key in sorted(set(ref) - set(new)):
        add("module-missing", key)
    for key in sorted(set(new) - set(ref)):
        add("module-extra", key)
    for key in sorted(set(ref) & set(new)):
        if ref[key]["vlnv"] != new[key]["vlnv"]:
            add("vlnv", f"{key} {ref[key]['vlnv']} -> {new[key]['vlnv']}")
        if ref[key]["blocks"] != new[key]["blocks"]:
            add("addressblock", f"{key} {ref[key]['blocks']} -> {new[key]['blocks']}")
        names = set(ref[key]["params"]) | set(new[key]["params"])
        for name in sorted(names):
            a = ref[key]["params"].get(name, "<absent>")
            b = new[key]["params"].get(name, "<absent>")
            if a == b:
                continue
            if is_path(a) and is_path(b) and same_path_tail(a, b):
                add("param-path", f"{key} {name}", allowed=True)
                continue
            add("param", f"{key} {name} {a!r} -> {b!r}")

    ref_mem = memranges(load(ref_path))
    new_mem = memranges(load(new_path))
    if ref_mem != new_mem:
        only_ref = sorted(set(ref_mem) - set(new_mem))
        only_new = sorted(set(new_mem) - set(ref_mem))
        for row in only_ref[:40]:
            add("memrange-missing", " ".join(row))
        for row in only_new[:40]:
            add("memrange-extra", " ".join(row))
        if len(only_ref) > 40 or len(only_new) > 40:
            add("memrange-count", f"missing {len(only_ref)} extra {len(only_new)}")

    ref_ports = ports(load(ref_path))
    new_ports = ports(load(new_path))
    if ref_ports != new_ports:
        only_ref = sorted(set(ref_ports) - set(new_ports))
        only_new = sorted(set(new_ports) - set(ref_ports))
        for row in only_ref[:40]:
            add("port-missing", str(row))
        for row in only_new[:40]:
            add("port-extra", str(row))
        if len(only_ref) > 40 or len(only_new) > 40:
            add("port-count", f"missing {len(only_ref)} extra {len(only_new)}")

    vlnvs = sorted({item["vlnv"] for item in new.values()})
    lines.insert(0, "VLNVS " + " ".join(vlnvs))
    lines.insert(0, f"modules {len(new)} memranges {len(new_mem)} ports {len(new_ports)}")
    text = "\n".join(lines) + "\n"
    Path(report_path).write_text(text)
    print(text)
    if fail:
        print("P24_HWH_DIFF")
        return 1
    print("P24_HWH_OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
