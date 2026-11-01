# Bitstream, XSA, and SDT. USR_ACCESS is the first 8 hex digits of the impl stamp.

proc hw::out_dir {} {
  set path [file join $::hw::build out $::hw::directive]
  file mkdir $path
  return $path
}

proc hw::read_stamp_hash {stage} {
  set path [hw::stamp_path $stage]
  if {![file exists $path]} {
    hw::fail "stamp $stage is missing"
  }
  set fh [open $path r]
  set hash [string trim [gets $fh]]
  close $fh
  if {![regexp {^[0-9a-f]{64}$} $hash]} {
    hw::fail "stamp $stage is not a sha256"
  }
  return $hash
}

proc hw::usr_access_value {} {
  set hash [hw::read_stamp_hash impl]
  return "0x[string range $hash 0 7]"
}

proc hw::ensure_routed_design {} {
  if {[info exists ::hw::design_open] && $::hw::design_open} {
    return
  }
  hw::open_bd_project
  set name [hw::impl_run]
  if {[get_runs -quiet $name] eq ""} {
    hw::fail "run $name is missing; run the impl stage"
  }
  hw::check_run $name write_bitstream
  open_run $name
  # write_hw_platform -include_bit writes the bitstream again from this
  # design, so it needs the same USR_ACCESS as the run's TCL.PRE hook.
  set ua [hw::usr_access_value]
  set_property BITSTREAM.CONFIG.USR_ACCESS $ua [current_design]
  set ::hw::usr_access $ua
  set ::hw::design_open 1
}

proc hw::stage_bit {} {
  set run_bit [file join [hw::run_dir [hw::impl_run]] system_top.bit]
  if {![file exists $run_bit]} {
    hw::fail "[hw::impl_run] wrote no bitstream"
  }
  set bit [file join [hw::out_dir] system_top.bit]
  file copy -force $run_bit $bit
  if {$::hw::directive eq "default"} {
    file copy -force $bit [file join $::hw::build out system_top.bit]
  }
  puts "P24_BIT_OK $bit USR_ACCESS=[hw::usr_access_value]"
}

proc hw::stage_xsa {} {
  set bit [file join [hw::out_dir] system_top.bit]
  if {![file exists $bit]} {
    hw::fail "bitstream is missing"
  }
  hw::ensure_routed_design
  set xsa [file join [hw::out_dir] system_top.xsa]
  puts "P24_XSA_BEGIN"
  write_hw_platform -fixed -include_bit -force -file $xsa
  hw::check_xsa_payload $bit $xsa
  hw::check_xsa_hwh $xsa
  if {$::hw::directive eq "default"} {
    file copy -force $xsa [file join $::hw::build out system_top.xsa]
  }
  puts "P24_XSA_OK $xsa"
}

proc hw::check_xsa_hwh {xsa} {
  set hwh [hw::extract_hwh $xsa [file join $::hw::build tmp xsa-check.hwh]]
  set fh [open $hwh r]
  set body [read $fh]
  close $fh
  foreach cell {
    /sys_ps7
    /openwifi_ip/openofdm_tx_0
    /openwifi_ip/openofdm_rx_0
    /openwifi_ip/xpu_0
    /openwifi_ip/tx_intf_0
    /openwifi_ip/rx_intf_0
    /openwifi_ip/side_ch_0
  } {
    if {[string first "FULLNAME=\"$cell\"" $body] < 0} {
      hw::fail "XSA hwh has no $cell"
    }
  }
  puts "P24_XSA_HWH_OK"
}

proc hw::check_xsa_payload {bit xsa} {
  set tmp [file join $::hw::build tmp xsa-unpack]
  file delete -force $tmp
  file mkdir $tmp
  if {[catch {hw::exec unzip -o $xsa -d $tmp} err]} {
    hw::fail "unzip XSA failed: $err"
  }
  set extracted ""
  foreach path [split [hw::exec find $tmp -type f -name *.bit] \n] {
    if {$path ne ""} {
      set extracted $path
      break
    }
  }
  if {$extracted eq ""} {
    hw::fail "XSA contains no bitstream"
  }
  set checker [file join $::hw::root scripts check_boot_bitstream.sh]
  if {[catch {hw::exec $checker $bit $extracted} err]} {
    hw::fail "XSA payload does not match the bitstream: $err"
  }
  puts "P24_XSA_PAYLOAD_OK"
}

proc hw::stage_sdt {} {
  set xsa [file join [hw::out_dir] system_top.xsa]
  if {![file exists $xsa]} {
    hw::fail "XSA is missing"
  }
  set out [file join $::hw::build sdt $::hw::directive]
  file delete -force $out
  file mkdir $out
  set tools [hw::need TOOLS_ROOT]
  set ::env(TOOLS_ROOT) $tools
  set sdtgen [file join $tools Vitis bin sdtgen]
  if {[file executable $sdtgen]} {
    set ::env(SDTGEN) $sdtgen
  }
  set script [file join $::hw::root sw sdt gen_sdt.sh]
  puts "P24_SDT_BEGIN"
  if {[catch {hw::exec $script --xsa $xsa --out $out} err]} {
    hw::fail "sdtgen failed: $err"
  }
  if {$::hw::directive eq "default"} {
    set current [file join $::hw::build sdt current]
    file delete -force $current
    file mkdir [file dirname $current]
    # A directory symlink keeps the software stage pointed at this SDT.
    file link -symbolic $current $out
  }
  puts "P24_SDT_OK $out"
}

proc hw::bit_outputs_ok {} {
  return [file exists [file join [hw::out_dir] system_top.bit]]
}

proc hw::xsa_outputs_ok {} {
  return [file exists [file join [hw::out_dir] system_top.xsa]]
}

proc hw::sdt_outputs_ok {} {
  return [expr {
    [file exists [file join $::hw::build sdt $::hw::directive system-top.dts]] &&
    [file exists [file join $::hw::build sdt $::hw::directive pl.dtsi]]
  }]
}
