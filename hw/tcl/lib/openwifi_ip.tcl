# Package the six OpenWiFi IPs in a work copy. Generated headers stay there.

proc hw::replace_once {path old new} {
  set fh [open $path r]
  set body [read $fh]
  close $fh
  set count 0
  set idx 0
  while {[set found [string first $old $body $idx]] >= 0} {
    incr count
    set idx [expr {$found + 1}]
  }
  if {$count != 1} {
    hw::fail "expected one occurrence in [file tail $path], found $count"
  }
  set fh [open $path w]
  puts -nonewline $fh [string map [list $old $new] $body]
  close $fh
}

proc hw::write_text {path body} {
  file mkdir [file dirname $path]
  set fh [open $path w]
  puts -nonewline $fh $body
  close $fh
}

proc hw::git_header {} {
  set repo [file join $::hw::build src openwifi-hw]
  set full [hw::exec git -C $repo rev-parse HEAD]
  set short [hw::exec git -C $repo log -1 --pretty=%h]
  if {![regexp {^[0-9a-fA-F]+$} $short]} {
    hw::fail "openwifi-hw short hash is not hex: $short"
  }
  set dirty [hw::git_porcelain $repo]
  set flag 0
  if {$dirty ne ""} {
    set flag 1
  }
  set body "// OPENWIFI_HW_GIT_SHA $full\n// OPENWIFI_HW_GIT_DIRTY $flag\n`define OPENWIFI_HW_GIT_REV (32'h$short)\n"
  set ::hw::git_full $full
  set ::hw::git_short $short
  set ::hw::git_dirty $flag
  return $body
}

proc hw::stage_openwifi_ip {} {
  set src_hw [file join $::hw::build src openwifi-hw]
  set src_ofdm [file join $::hw::build src openofdm_rx]
  set work [file join $::hw::build work openwifi-hw]
  if {![file exists [file join $src_hw .git]] || ![file exists [file join $src_ofdm .git]]} {
    hw::fail "openwifi fetches are missing"
  }
  puts "P24_OW_RSYNC"
  hw::rsync_tree $src_hw $work
  file delete -force [file join $work ip openofdm_rx]
  hw::rsync_tree $src_ofdm [file join $work ip openofdm_rx]
  set ofdm_tcl [file join $work ip openofdm_rx openofdm_rx.tcl]
  set upgrade {upgrade_ip [get_ips  {atan_lut complex_multiplier deinter_lut div_gen_div_gen_0_0 div_gen_xlslice_0_0 rot_lut viterbi_v7_0 xfft_v9 div_for_rotafft div_gen_csi_over_nova}] -log ip_upgrade.log}
  set replacement "source \$::env(P24_SUBIP_TCL)"
  hw::replace_once $ofdm_tcl $upgrade $replacement
  set fh [open $ofdm_tcl r]
  set patched [read $fh]
  close $fh
  if {[string first "upgrade_ip" $patched] >= 0} {
    hw::fail "openofdm_rx.tcl still calls upgrade_ip"
  }
  if {[hw::body_has_banned_path $patched]} {
    hw::fail "openofdm_rx work copy contains a host path"
  }
  set cache_old {set_property -name "ip_cache_permissions" -value "read write" -objects $obj}
  set cache_new {set_property -name "ip_cache_permissions" -value "disable" -objects $obj}
  foreach ip {openofdm_rx openofdm_tx rx_intf tx_intf xpu side_ch} {
    hw::replace_once [file join $work ip $ip $ip.tcl] $cache_old $cache_new
  }

  set board [hw::need BOARD]
  set gen [file join $::hw::build gen headers]
  file mkdir $gen
  set git_body [hw::git_header]
  hw::write_text [file join $gen openwifi_hw_git_rev.v] $git_body
  set clock "`define NUM_CLK_PER_US 100\n"
  hw::write_text [file join $gen clock_speed.v] $clock
  set scale "// fpga_size_flag is 1 for this part; SIDE_CH_LESS_BRAM stays unset.\n"
  hw::write_text [file join $gen fpga_scale.v] $scale
  set side "`define HAS_SIDE_CH 1\n"
  hw::write_text [file join $gen has_side_ch_flag.v] $side
  set spi "`define SPI_HIGH 24'h088A01\n`define SPI_LOW 24'h008A01\n"
  hw::write_text [file join $gen spi_command.v] $spi
  set pre "// Naming pre_def.v differently for all IPs.\n`define adrv9361z7035\n"
  set ip_config [file join $work boards $board ip_config]
  file mkdir $ip_config
  set ::env(P24_SUBIP_TCL) [file join $::hw::hwdir ip_xci_tcl recreate_subips.tcl]
  set ::env(P24_OFDM_ROOT) [file join $work ip openofdm_rx]
  foreach ip {openofdm_rx openofdm_tx rx_intf tx_intf xpu side_ch} {
    hw::write_text [file join $ip_config ${ip}_pre_def.v] $pre
    hw::write_text [file join $gen ${ip}_pre_def.v] $pre
    if {$ip eq "openofdm_rx"} {
      continue
    }
    set dest [file join $work ip $ip src]
    file mkdir $dest
    file copy -force [file join $gen openwifi_hw_git_rev.v] $dest
    file copy -force [file join $work ip board_def.v] $dest
    file copy -force [file join $gen clock_speed.v] $dest
    file copy -force [file join $gen spi_command.v] $dest
    file copy -force [file join $gen fpga_scale.v] $dest
    file copy -force [file join $gen has_side_ch_flag.v] $dest
    file copy -force [file join $ip_config ${ip}_pre_def.v] [file join $dest ${ip}_pre_def.v]
  }

  set saved_argc $::argc
  set saved_argv $::argv
  set here [pwd]
  foreach ip {openofdm_rx openofdm_tx rx_intf tx_intf xpu side_ch} {
    puts "P24_OW_PACKAGE $ip"
    set src_dir [file join $work ip $ip]
    set ip_dir [file join $::hw::build ip_repo openwifi $ip]
    file delete -force $ip_dir
    file mkdir [file dirname $ip_dir]
    cd $src_dir
    set ::argc 1
    set ::argv [list $board]
    if {[catch {set rc [uplevel #0 [list source [file join $src_dir $ip.tcl]]]} err]} {
      set ::argc $saved_argc
      set ::argv $saved_argv
      cd $here
      hw::fail "sourcing $ip.tcl failed: $err"
    }
    if {$rc eq "1"} {
      set ::argc $saved_argc
      set ::argv $saved_argv
      cd $here
      hw::fail "$ip.tcl returned 1"
    }
    hw::package_ip_dir $ip_dir
    if {$ip eq "openofdm_rx"} {
      set packaged_pre [file join $ip_dir src openofdm_rx_pre_def.v]
      if {![file exists $packaged_pre]} {
        hw::fail "packaged openofdm_rx_pre_def.v is missing"
      }
      set in [open [file join $ip_config openofdm_rx_pre_def.v] r]
      set extra [read $in]
      close $in
      set out [open $packaged_pre a]
      puts -nonewline $out $extra
      close $out
      hw::check_packaged_rot_lut $ip_dir
    }
    file delete -force [file join $ip_dir xgui]
    if {![file exists [file join $ip_dir component.xml]]} {
      hw::fail "$ip package has no component.xml"
    }
    puts "P24_OW_PACKAGE_OK $ip"
  }
  set ::argc $saved_argc
  set ::argv $saved_argv
  cd $here
}

proc hw::package_ip_dir {ip_dir} {
  update_compile_order -fileset sources_1
  update_compile_order -fileset sources_1
  ipx::package_project -root_dir $ip_dir -vendor user.org -library user \
    -taxonomy /UserIP -import_files -set_current false
  ipx::unload_core [file join $ip_dir component.xml]
  ipx::edit_ip_in_project -upgrade true -name tmp_edit_project \
    -directory $ip_dir [file join $ip_dir component.xml]
  update_compile_order -fileset sources_1
  set_property core_revision 2 [ipx::current_core]
  ipx::update_source_project_archive -component [ipx::current_core]
  ipx::create_xgui_files [ipx::current_core]
  ipx::update_checksums [ipx::current_core]
  ipx::save_core [ipx::current_core]
  ipx::move_temp_component_back -component [ipx::current_core]
  catch {close_project -delete}
  catch {close_project -delete}
}

proc hw::xci_enb_bad {body} {
  if {[regexp {"C_HAS_ENB": \[ \{ "value": "1"} $body]} {
    return 1
  }
  if {[regexp {"C_HAS_MEM_OUTPUT_REGS_B": \[ \{ "value": "1"} $body]} {
    return 1
  }
  if {[regexp {C_HAS_ENB\s*(\(|=>|=)\s*1\M} $body]} {
    return 1
  }
  if {[regexp {C_HAS_MEM_OUTPUT_REGS_B\s*(\(|=>|=)\s*1\M} $body]} {
    return 1
  }
  return 0
}

proc hw::xci_enb_good {body} {
  if {![regexp {Enable_B.{0,120}Always_Enabled} $body]} {
    return 0
  }
  if {![regexp {Register_PortB_Output_of_Memory_Primitives.{0,120}false} $body]} {
    return 0
  }
  if {[regexp {"C_HAS_ENB": \[ \{ "value": "0"} $body]} {
    return 1
  }
  if {[regexp {C_HAS_ENB\s*(\(|=>|=)\s*0\M} $body]} {
    return 1
  }
  return 0
}

proc hw::check_packaged_rot_lut {ip_dir} {
  # package_project keeps the xci. Generated HDL wrappers stay in the
  # project .gen directory and are not imported into the IP.
  set xcis [hw::find_files $ip_dir {rot_lut.xci}]
  if {[llength $xcis] == 0} {
    hw::fail "packaged openofdm_rx has no rot_lut.xci"
  }
  set xci_ok 0
  foreach path $xcis {
    set fh [open $path r]
    set body [read $fh]
    close $fh
    if {[hw::xci_enb_bad $body] || ![hw::xci_enb_good $body]} {
      hw::fail "packaged rot_lut xci enables port B: $path"
    }
    incr xci_ok
  }
  set checked 0
  foreach path [hw::find_files $ip_dir {rot_lut.v rot_lut.vhd}] {
    set fh [open $path r]
    set body [read $fh]
    close $fh
    if {![regexp {C_HAS_ENB\s*(\(|=>|=)\s*[01]} $body]} {
      continue
    }
    if {[hw::xci_enb_bad $body]} {
      hw::fail "packaged rot_lut wrapper enables port B: $path"
    }
    incr checked
  }
  puts "P24_ROT_LUT_PACKAGED_OK xci=$xci_ok wrappers=$checked"
}

proc hw::find_files {dir names} {
  set out {}
  foreach name $names {
    foreach path [glob -nocomplain [file join $dir $name] [file join $dir * $name] \
        [file join $dir * * $name] [file join $dir * * * $name] \
        [file join $dir * * * * $name]] {
      lappend out $path
    }
  }
  return $out
}

proc hw::openwifi_products_ok {} {
  foreach ip {openofdm_rx openofdm_tx rx_intf tx_intf xpu side_ch} {
    if {![file exists [file join $::hw::build ip_repo openwifi $ip component.xml]]} {
      return 0
    }
  }
  return 1
}

proc hw::stage_ip {} {
  hw::disk_ok
  hw::stage_adi_ip
  hw::stage_openwifi_ip
}
