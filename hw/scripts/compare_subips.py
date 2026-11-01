#!/usr/bin/env python3
"""Compare the sub-IP xci files packaged inside the OpenWiFi IPs with a
reference set (one directory of xci files, matched by file name).

Fails on any model-parameter difference and on any difference in a
component parameter that the reference marks as user-set. Ignored: power
estimates, Component_Name, COE file paths that differ only in directory,
and the derived xlslice DOUT_WIDTH when DIN_FROM/DIN_TO match.
usage: compare_subips.py REFERENCE_DIR IP_REPO_DIR REPORT
"""

import json
import sys
from pathlib import Path

IGNORE = {"Component_Name", "C_EST_POWER_SUMMARY"}


def load(path):
    inst = json.loads(Path(path).read_text())["ip_inst"]
    params = inst["parameters"]
    comp = {k: v[0] for k, v in params.get("component_parameters", {}).items()}
    model = {k: v[0].get("value") for k, v in params.get("model_parameters", {}).items()}
    return inst.get("component_reference", ""), comp, model


def main():
    if len(sys.argv) != 4:
        print(__doc__, file=sys.stderr)
        return 2
    ref_dir, repo, report = (Path(a) for a in sys.argv[1:])
    lines, fail = [], False
    new_files = {p.name: p for p in repo.rglob("*.xci")}
    for ref in sorted(ref_dir.glob("*.xci")):
        if ref.name not in new_files:
            lines.append(f"DIFF missing {ref.name}")
            fail = True
            continue
        rv, rc, rm = load(ref)
        nv, nc, nm = load(new_files[ref.name])
        if rv != nv:
            lines.append(f"DIFF vlnv {ref.name} {rv} -> {nv}")
            fail = True
        for k in sorted(set(rm) | set(nm)):
            if k in IGNORE or rm.get(k) == nm.get(k):
                continue
            lines.append(f"DIFF model {ref.name} {k} {rm.get(k)!r} -> {nm.get(k)!r}")
            fail = True
        for k, v in sorted(rc.items()):
            if k in IGNORE or v.get("value_src") != "user":
                continue
            a, b = v.get("value"), nc.get(k, {}).get("value")
            if a == b:
                continue
            # xlslice DOUT_WIDTH is derived; the v1.0 xci keeps a stale 1.
            if k == "DOUT_WIDTH" and "xlslice" in nv:
                width = int(nm.get("DIN_FROM", -1)) - int(nm.get("DIN_TO", 0)) + 1
                if str(width) == str(b) and rm.get("DIN_FROM") == nm.get("DIN_FROM") and rm.get("DIN_TO") == nm.get("DIN_TO"):
                    lines.append(f"ALLOW derived {ref.name} DOUT_WIDTH {a} -> {b} (DIN {nm.get('DIN_FROM')}:{nm.get('DIN_TO')})")
                    continue
            if k == "Coe_File" and Path(str(a)).name == Path(str(b)).name:
                lines.append(f"ALLOW coe-path {ref.name} {a} -> {b}")
                continue
            lines.append(f"DIFF user {ref.name} {k} {a!r} -> {b!r}")
            fail = True
        lines.append(f"CHECKED {ref.name} {nv}")
    Path(report).write_text("\n".join(lines) + "\n")
    print("\n".join(lines))
    if fail:
        print("P24_SUBIP_DIFF")
        return 1
    print("P24_SUBIP_OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
