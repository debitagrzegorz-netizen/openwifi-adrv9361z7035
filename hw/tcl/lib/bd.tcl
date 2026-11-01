# Create the block design in a project under build/hw and generate products.

proc hw::bd_project_path {} {
  return [file join $::hw::build proj p24_hw p24_hw.xpr]
}

proc hw::disable_ip_cache {} {
  set cache [file join $::hw::build ip-cache]
  file mkdir $cache
  if {[catch {config_ip_cache -use_cache_location $cache} err]} {
    hw::fail "config_ip_cache -use_cache_location failed: $err"
  }
  if {[catch {config_ip_cache -disable_cache} err]} {
    hw::fail "config_ip_cache -disable_cache failed: $err"
  }
  set perm [string trim [get_property ip_cache_permissions [current_project]]]
  puts "P24_IP_CACHE $perm"
  if {![string match -nocase {disable*} $perm]} {
    hw::fail "ip_cache_permissions is '$perm'"
  }
}

proc hw::stage_bd {} {
  if {![hw::adi_products_ok] || ![hw::openwifi_products_ok]} {
    hw::fail "IP packages are missing; run the ip stage"
  }
  set proj_dir [file join $::hw::build proj p24_hw]
  if {[llength [get_projects -quiet]]} {
    close_project
  }
  file delete -force $proj_dir
  file mkdir $proj_dir
  create_project p24_hw $proj_dir -part [hw::need PART]
  set_property target_language Verilog [current_project]
  set_property xpm_libraries {XPM_CDC XPM_FIFO XPM_MEMORY} [current_project]
  hw::disable_ip_cache
  set repos [list \
    [file join $::hw::build work hdl library] \
    [file join $::hw::build ip_repo openwifi]]
  set_property ip_repo_paths $repos [current_project]
  update_ip_catalog -rebuild
  set rc [source [file join $::hw::hwdir bd system_bd.tcl]]
  if {$rc eq "1"} {
    hw::fail "system_bd.tcl returned 1"
  }
  foreach cell {axi_ad9361 sys_ps7 openofdm_rx_0 openofdm_tx_0 xpu_0 tx_intf_0 rx_intf_0 side_ch_0} {
    if {[get_bd_cells -quiet -hierarchical $cell] eq ""} {
      hw::fail "block design is missing cell $cell"
    }
  }
  puts "P24_BD_CELLS [llength [get_bd_cells]]"
  set bds [get_files -quiet *.bd]
  if {$bds eq ""} {
    hw::fail "block design was not created"
  }
  set_property synth_checkpoint_mode None $bds
  puts "P24_BD_GENERATE"
  generate_target all $bds
  set top_v [file join $::hw::build work openwifi-hw boards [hw::need BOARD] src system_top.v]
  set iobuf [file join $::hw::build work hdl library common ad_iobuf.v]
  if {![file exists $top_v] || ![file exists $iobuf]} {
    hw::fail "system_top.v or ad_iobuf.v is missing from the work tree"
  }
  add_files -norecurse [list $top_v $iobuf]
  set xdcs {}
  foreach name {
    adrv9361z7035_constr.xdc
    adrv9361z7035_constr_lvds.xdc
    ccbob_constr.xdc
    system.xdc
  } {
    lappend xdcs [file join $::hw::hwdir constraints $name]
  }
  add_files -fileset constrs_1 -norecurse $xdcs
  # generate_target writes the wrapper under .gen. get_files does not list it
  # until it is a project source, and system_top instantiates it.
  set wrap_path [file join $proj_dir p24_hw.gen sources_1 bd system hdl system_wrapper.v]
  if {![file exists $wrap_path]} {
    hw::fail "generate_target did not produce system_wrapper.v"
  }
  set wrap [get_files -all -quiet $wrap_path]
  if {$wrap eq ""} {
    add_files -norecurse $wrap_path
    puts "P24_BD_WRAPPER_ADDED $wrap_path"
  } else {
    puts "P24_BD_WRAPPER $wrap"
  }
  set_property top system_top [current_fileset]
  update_compile_order -fileset sources_1
  # Keep this project pre-synthesis. Implementation opens the checkpoint.
  close_project
  puts "P24_BD_OK"
}

proc hw::bd_outputs_ok {} {
  return [file exists [hw::bd_project_path]]
}
