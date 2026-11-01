# Synthesis as the project run synth_1. The block design is synthesized
# globally (synth_checkpoint_mode None), so there are no OOC runs.
# A project run keeps the block-design context that write_hw_platform needs;
# a design re-opened with open_checkpoint does not have it.

proc hw::synth_dcp {} {
  return [file join $::hw::build ckpt post_synth.dcp]
}

proc hw::open_bd_project {} {
  if {[llength [get_projects -quiet]]} {
    close_project
  }
  if {![file exists [hw::bd_project_path]]} {
    hw::fail "block-design project is missing; run the bd stage"
  }
  open_project [hw::bd_project_path]
  hw::disable_ip_cache
}

proc hw::run_dir {run} {
  return [file join $::hw::build proj p24_hw p24_hw.runs $run]
}

proc hw::check_run {run want} {
  set r [get_runs $run]
  set status [get_property STATUS $r]
  set progress [get_property PROGRESS $r]
  puts "P24_RUN $run STATUS=\"$status\" PROGRESS=$progress"
  if {[string first "ERROR" $status] >= 0 || ![string match "$want Complete!" $status]} {
    hw::fail "run $run ended with '$status'"
  }
}

proc hw::copy_run_log {run name} {
  set log [file join [hw::run_dir $run] runme.log]
  if {![file exists $log]} {
    hw::fail "run $run has no runme.log"
  }
  file copy -force $log [file join $::hw::build logs $name.log]
}

proc hw::stage_synth {} {
  hw::open_bd_project
  set run [get_runs synth_1]
  # The tool defaults, as synth_design with no options.
  set_property strategy {Vivado Synthesis Defaults} $run
  set ooc [get_runs -quiet -filter {IS_SYNTHESIS && NAME != synth_1}]
  if {[llength $ooc]} {
    hw::fail "unexpected OOC runs: $ooc"
  }
  puts "P24_SYNTH_BEGIN run=synth_1"
  reset_run synth_1
  launch_runs synth_1 -jobs $::hw::jobs
  wait_on_run synth_1
  hw::copy_run_log synth_1 synth_1
  hw::check_run synth_1 synth_design
  set dcp [file join [hw::run_dir synth_1] system_top.dcp]
  if {![file exists $dcp]} {
    hw::fail "synth_1 wrote no checkpoint"
  }
  file mkdir [file dirname [hw::synth_dcp]]
  file copy -force $dcp [hw::synth_dcp]
  puts "P24_CKPT [hw::synth_dcp]"
  close_project
  puts "P24_SYNTH_OK"
}

proc hw::synth_outputs_ok {} {
  return [expr {
    [file exists [hw::synth_dcp]] &&
    [file exists [file join [hw::run_dir synth_1] system_top.dcp]]
  }]
}
