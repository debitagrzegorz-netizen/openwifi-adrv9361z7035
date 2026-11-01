# Package the ADI library IPs the block design uses, in a work copy.

proc hw::adi_ip_list {} {
  return {
    util_cdc
    axi_ad9361
    util_tdd_sync
    xilinx/util_clkdiv
    util_wfifo
    util_pack/util_cpack2
    util_rfifo
    util_pack/util_upack2
    xilinx/axi_xcvrlb
    axi_gpreg
  }
}

proc hw::rsync_tree {src dest} {
  file mkdir $dest
  if {[catch {hw::exec rsync -a --delete $src/ $dest/} err]} {
    hw::fail "rsync $src failed: $err"
  }
}

proc hw::stage_adi_ip {} {
  set src [file join $::hw::build src hdl]
  set work [file join $::hw::build work hdl]
  if {![file exists [file join $src .git]]} {
    hw::fail "hdl fetch is missing"
  }
  puts "P24_ADI_RSYNC"
  hw::rsync_tree $src $work
  set ::env(ADI_HDL_DIR) $work
  set ignore [hw::cfg_get ADI_IGNORE_VERSION_CHECK]
  if {$ignore ne ""} {
    set ::env(ADI_IGNORE_VERSION_CHECK) $ignore
  }
  set exe [file dirname [info nameofexecutable]]
  set ::env(PATH) "$exe:$::env(PATH)"
  foreach ip [hw::adi_ip_list] {
    set xml [file join $work library $ip component.xml]
    if {[file exists $xml]} {
      puts "P24_ADI_IP_SKIP $ip"
      continue
    }
    puts "P24_ADI_IP_MAKE $ip"
    set dir [file join $work library $ip]
    if {[catch {hw::exec make -C $dir xilinx} err]} {
      hw::fail "ADI make xilinx $ip failed: $err"
    }
    if {![file exists $xml]} {
      hw::fail "ADI IP $ip produced no component.xml"
    }
    puts "P24_ADI_IP_OK $ip"
  }
}

proc hw::adi_products_ok {} {
  set work [file join $::hw::build work hdl]
  foreach ip [hw::adi_ip_list] {
    if {![file exists [file join $work library $ip component.xml]]} {
      return 0
    }
  }
  return 1
}
