# Implementation as one project run per directive set (impl_<set>), child of
# synth_1: opt, place, phys opt, route, post-route phys opt with -hold_fix.
# Every step and directive is set here. The run ends with write_bitstream;
# a TCL.PRE hook sets USR_ACCESS to the first 8 hex digits of the impl hash.

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

proc hw::impl_run {} {
  return "impl_$::hw::directive"
}

# Run checkpoint name -> diagnostic checkpoint name under ckpt/<set>.
proc hw::impl_ckpts {} {
  return {
    system_top_opt.dcp post_opt
    system_top_placed.dcp post_place
    system_top_physopt.dcp post_phys_opt
    system_top_routed.dcp post_route
    system_top_postroute_physopt.dcp post_hold
  }
}

proc hw::stage_impl {} {
  hw::open_bd_project
  hw::check_run synth_1 synth_design
  lassign [hw::directive_map $::hw::directive] place route phys
  set name [hw::impl_run]
  if {[get_runs -quiet $name] eq ""} {
    # Same flow as the impl_1 run that create_project made.
    create_run $name -parent_run synth_1 -flow [get_property FLOW [get_runs impl_1]]
  }
  set run [get_runs $name]
  set_property strategy {Vivado Implementation Defaults} $run
  set_property STEPS.OPT_DESIGN.IS_ENABLED true $run
  set_property STEPS.OPT_DESIGN.ARGS.DIRECTIVE Default $run
  set_property STEPS.POWER_OPT_DESIGN.IS_ENABLED false $run
  set_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE $place $run
  set_property STEPS.POST_PLACE_POWER_OPT_DESIGN.IS_ENABLED false $run
  set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED true $run
  set_property STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE $phys $run
  set_property STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE $route $run
  set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED true $run
  set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.ARGS.DIRECTIVE Default $run
  set_property -name {STEPS.POST_ROUTE_PHYS_OPT_DESIGN.ARGS.MORE OPTIONS} -value {-hold_fix} -objects $run
  set ua "0x[string range [hw::stage_hash impl] 0 7]"
  set hook [file join $::hw::build tmp usr_access_$::hw::directive.tcl]
  file mkdir [file dirname $hook]
  set fh [open $hook w]
  puts $fh "set_property BITSTREAM.CONFIG.USR_ACCESS $ua \[current_design\]"
  close $fh
  set_property STEPS.WRITE_BITSTREAM.TCL.PRE $hook $run
  puts "P24_IMPL_BEGIN run=$name place=$place route=$route phys_opt=$phys USR_ACCESS=$ua"
  reset_run $name
  launch_runs $name -to_step write_bitstream -jobs $::hw::jobs
  wait_on_run $name
  hw::copy_run_log $name $name
  hw::check_run $name write_bitstream
  set dir [file join $::hw::build ckpt $::hw::directive]
  file mkdir $dir
  foreach {src dst} [hw::impl_ckpts] {
    set path [file join [hw::run_dir $name] $src]
    if {![file exists $path]} {
      hw::fail "$name has no $src"
    }
    file copy -force $path [file join $dir $dst.dcp]
    puts "P24_CKPT [file join $dir $dst.dcp]"
  }
  open_run $name
  hw::write_timing_numbers
  close_design
  close_project
  puts "P24_IMPL_OK"
}

proc hw::impl_outputs_ok {} {
  return [expr {
    [file exists [file join $::hw::build ckpt $::hw::directive post_hold.dcp]] &&
    [file exists [file join [hw::run_dir [hw::impl_run]] system_top_postroute_physopt.dcp]] &&
    [file exists [file join [hw::run_dir [hw::impl_run]] system_top.bit]] &&
    [file exists [file join $::hw::build reports $::hw::directive timing_numbers.txt]]
  }]
}
