# Non-project implementation: synth, opt, place, phys opt, route, hold fix.

proc hw::directive_map {name} {
  # place, route, post-place phys_opt. Synthesis stays on the tool default.
  if {$name eq "default"} {
    return {Default Default Default}
  } elseif {$name eq "explore"} {
    return {Explore Explore Explore}
  } elseif {$name eq "netdelay"} {
    return {ExtraNetDelay_high AggressiveExplore AggressiveExplore}
  } elseif {$name eq "spread"} {
    return {SpreadLogic_high Explore AggressiveExplore}
  } elseif {$name eq "altspread"} {
    return {AltSpreadLogic_medium Explore Explore}
  }
  hw::fail "unknown directive_set $name"
}

proc hw::ckpt {name} {
  set path [file join $::hw::build ckpt $::hw::directive ${name}.dcp]
  file mkdir [file dirname $path]
  write_checkpoint -force $path
  puts "P24_CKPT $path"
  return $path
}

proc hw::report_dir {} {
  set path [file join $::hw::build reports $::hw::directive]
  file mkdir $path
  return $path
}

proc hw::write_timing_numbers {} {
  set setup [get_timing_paths -delay_type max -max_paths 1 -nworst 1 -quiet]
  set hold [get_timing_paths -delay_type min -max_paths 1 -nworst 1 -quiet]
  if {$setup eq "" || $hold eq ""} {
    hw::fail "timing paths are missing after route"
  }
  set wns [get_property SLACK $setup]
  set whs [get_property SLACK $hold]
  set tns 0
  set ths 0
  if {$wns < 0} {
    set tns $wns
  }
  if {$whs < 0} {
    set ths $whs
  }
  set path [file join [hw::report_dir] timing_numbers.txt]
  set fh [open $path w]
  puts $fh "WNS $wns"
  puts $fh "WHS $whs"
  puts $fh "TNS $tns"
  puts $fh "THS $ths"
  close $fh
  puts "P24_TIMING WNS=$wns WHS=$whs TNS=$tns THS=$ths"
  report_timing_summary -file [file join [hw::report_dir] timing_summary.rpt]
  report_utilization -file [file join [hw::report_dir] utilization.rpt]
  report_drc -file [file join [hw::report_dir] drc.rpt]
  report_methodology -file [file join [hw::report_dir] methodology.rpt]
  if {[catch {report_cdc -file [file join [hw::report_dir] cdc.rpt]} err]} {
    puts "P24_CDC_WARN $err"
  }
  if {$wns < 0 || $whs < 0} {
    hw::fail "timing is not closed (WNS=$wns WHS=$whs)"
  }
}

proc hw::synth_dcp {} {
  return [file join $::hw::build ckpt post_synth.dcp]
}

proc hw::stage_synth {} {
  if {![file exists [hw::bd_project_path]]} {
    hw::fail "block-design project is missing"
  }
  open_project [hw::bd_project_path]
  hw::disable_ip_cache
  puts "P24_SYNTH_BEGIN"
  synth_design -top system_top -part [hw::need PART]
  file mkdir [file join $::hw::build ckpt]
  write_checkpoint -force [hw::synth_dcp]
  puts "P24_CKPT [hw::synth_dcp]"
  # Drop the in-memory netlist so the saved project stays the pre-synth BD.
  close_design
  close_project
  puts "P24_SYNTH_OK"
}

proc hw::stage_impl {} {
  set synth [hw::synth_dcp]
  if {![file exists $synth]} {
    hw::fail "synthesis checkpoint is missing"
  }
  lassign [hw::directive_map $::hw::directive] place route phys
  puts "P24_IMPL_BEGIN place=$place route=$route phys_opt=$phys"
  open_checkpoint $synth
  opt_design
  hw::ckpt post_opt
  place_design -directive $place
  hw::ckpt post_place
  phys_opt_design -directive $phys
  hw::ckpt post_phys_opt
  route_design -directive $route
  hw::ckpt post_route
  phys_opt_design -hold_fix
  hw::ckpt post_hold
  hw::write_timing_numbers
  # Leave the routed design open for the bitstream stage in this process.
  set ::hw::design_open 1
  puts "P24_IMPL_OK"
}

proc hw::synth_outputs_ok {} {
  return [file exists [hw::synth_dcp]]
}

proc hw::impl_outputs_ok {} {
  return [expr {
    [file exists [file join $::hw::build ckpt $::hw::directive post_hold.dcp]] &&
    [file exists [file join $::hw::build reports $::hw::directive timing_numbers.txt]]
  }]
}
