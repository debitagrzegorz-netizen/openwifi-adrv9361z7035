#!/bin/bash
# Fail unless every given BOOT.BIN / system.bit carries the same bitstream
# payload as EXPECTED.bit (Xilinx field 'e'). Zynq bootgen stores that
# payload with 32-bit words byte-swapped; a plain .bit file stores it as-is.
set -euo pipefail
if [ "$#" -lt 2 ]; then
  echo "usage: $0 EXPECTED.bit FILE [FILE...]" >&2
  exit 2
fi
exec python3 - "$@" << 'PY'
import hashlib
import struct
import sys
from pathlib import Path


def bit_payload(data: bytes) -> bytes:
    if len(data) < 16:
        raise ValueError("short file")
    i = 0
    hdr_len = struct.unpack(">H", data[i : i + 2])[0]
    i += 2 + hdr_len + 2
    while i < len(data):
        key = data[i]
        i += 1
        if key == ord("e"):
            blen = struct.unpack(">I", data[i : i + 4])[0]
            i += 4
            if blen <= 0 or i + blen > len(data):
                raise ValueError(f"bad bitstream length {blen}")
            return data[i : i + blen]
        if i + 2 > len(data):
            break
        ln = struct.unpack(">H", data[i : i + 2])[0]
        i += 2 + ln
    raise ValueError("Xilinx field e not found")


def swap32(blob: bytes) -> bytes:
    n = len(blob) - (len(blob) % 4)
    out = bytearray(n)
    for off in range(0, n, 4):
        out[off : off + 4] = blob[off : off + 4][::-1]
    return bytes(out)


def payload_of(path: Path, expected: bytes) -> bytes | None:
    data = path.read_bytes()
    if len(data) >= 2 and data[0:1] == b"\x00" and data[1:2] == b"\x09":
        try:
            return bit_payload(data)
        except ValueError:
            pass
    sync = bytes.fromhex("aa995566")
    sync_sw = bytes.fromhex("665599aa")
    soff = expected.find(sync)
    if soff < 0:
        raise SystemExit("expected bitstream has no AA995566 sync word")
    blen = len(expected)
    first = None
    for swapped, needle in ((True, sync_sw), (False, sync)):
        start = 0
        while True:
            pos = data.find(needle, start)
            if pos < 0:
                break
            base = pos - soff
            if base >= 0 and base + blen <= len(data):
                chunk = data[base : base + blen]
                if swapped:
                    chunk = swap32(chunk)
                if first is None:
                    first = chunk
                if chunk == expected:
                    return chunk
            start = pos + 1
    return first


expected_path = Path(sys.argv[1])
expected = bit_payload(expected_path.read_bytes())
exp_sha = hashlib.sha256(expected).hexdigest()
print(f"expected {expected_path} payload {exp_sha} len {len(expected)}")
rc = 0
for arg in sys.argv[2:]:
    path = Path(arg)
    if not path.is_file():
        print(f"FAIL {path} missing")
        rc = 1
        continue
    got = payload_of(path, expected)
    got_sha = hashlib.sha256(got).hexdigest() if got is not None else "not-found"
    if got == expected:
        print(f"PASS {path} payload {got_sha}")
    else:
        print(f"FAIL {path} payload {got_sha} != {exp_sha}")
        rc = 1
sys.exit(rc)
PY
