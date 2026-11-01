# Hardware build

One Vivado 2025.1 batch script builds the ADRV9361-Z7035 design from pinned
sources. It does not modify those sources.

```
vivado -mode batch -notrace -source hw/build_hw.tcl -tclargs \
  [-config config/versions.conf] [-local config/local.conf] \
  [-stages fetch,ip,bd,synth,impl,bit,xsa,sdt,report | all] \
  [-from STAGE] [-to STAGE] \
  [-directive_set default|explore|netdelay|spread|altspread] \
  [-jobs N] [-clean] [-sim cdc] [-allow_dirty]
```

`./build.sh hw` calls that script. Outputs go to `build/hw/`. A stage whose
inputs are unchanged is skipped. `-clean` deletes `build/hw` only.

`config/local.conf` holds the repository URLs, `TOOLS_ROOT`, `HW_JOBS`, and
`EQUIV_HWH` (the reference `.hwh` used by the report stage). None of those
paths belong in this tree.

The block design is `hw/bd/system_bd.tcl`. OpenWiFi sub-IPs are recreated
from `hw/ip_xci_tcl/recreate_subips.tcl` with `create_ip`. `rot_lut` port B
is Always Enabled and has no primitive output register. The flow does not
call `upgrade_ip`.
