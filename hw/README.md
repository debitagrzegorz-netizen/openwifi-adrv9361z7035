# Hardware placeholder

The Vivado / HDL flow is not part of this tree yet.

`build.sh` consumes an XSA passed with `--xsa`. Put local XSA files in `hw/xsa/`
(gitignored). The only accepted XSA for this software line is the v1.0 XSA
whose SHA256 is `V1_0_XSA_SHA` in `config/versions.conf`.

The from-scratch FPGA track (16-QAM and 64-QAM transmit failure) is paused.
Do not point this build at that XSA.
