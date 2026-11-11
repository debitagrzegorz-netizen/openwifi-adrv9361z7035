# One entry point for the ADRV9361-Z7035 hardware build.
#   vivado -mode batch -notrace -source hw/build_hw.tcl -tclargs \
#     [-config config/versions.conf] [-local config/local.conf] \
#     [-stages fetch,ip,bd,synth,impl,bit,xsa,sdt,report | all] \
#     [-from STAGE] [-to STAGE] \
#     [-directive_set default|explore|netdelay|spread|altspread] \
#     [-jobs N] [-clean] [-sim cdc] [-allow_dirty]

fconfigure stdout -buffering line
fconfigure stderr -buffering line

namespace eval hw {}

set ::hw::hwdir [file dirname [file normalize [info script]]]
set ::hw::root [file normalize [file join $::hw::hwdir ..]]
set ::hw::build [file join $::hw::root build hw]

foreach lib {config fetch adi_ip openwifi_ip bd synth impl export gates sim} {
  source [file join $::hw::hwdir tcl lib $lib.tcl]
}

proc hw::reject_host_paths {} {
  set files [concat \
    [glob -nocomplain [file join $::hw::hwdir *.tcl] [file join $::hw::hwdir *.txt]] \
    [glob -nocomplain [file join $::hw::hwdir tcl lib *.tcl]] \
    [glob -nocomplain [file join $::hw::hwdir bd *.tcl]] \
    [glob -nocomplain [file join $::hw::hwdir constraints *]] \
    [glob -nocomplain [file join $::hw::hwdir ip_xci_tcl *.tcl]] \
    [glob -nocomplain [file join $::hw::hwdir scripts *.py]]]
  foreach path $files {
    if {![file isfile $path]} {
      continue
    }
    set fh [open $path r]
    set body [read $fh]
    close $fh
    if {[hw::body_has_banned_path $body]} {
      hw::fail "host path in [file tail $path]"
    }
  }
  puts "P24_HOST_PATHS_OK"
}

proc hw::hw_files {subdir} {
  return [glob -nocomplain [file join $::hw::hwdir $subdir *] \
    [file join $::hw::hwdir $subdir * *]]
}

proc hw::hash_text {text} {
  set path [file join $::hw::build stamps hash-text.txt]
  file mkdir [file dirname $path]
  set fh [open $path w]
  puts -nonewline $fh $text
  close $fh
  return [lindex [hw::exec sha256sum $path] 0]
}

proc hw::files_hash {paths} {
  set lines {}
  foreach path [lsort $paths] {
    if {![file isfile $path]} {
      continue
    }
    set rel [fileutil_relative $::hw::hwdir $path]
    set sum [lindex [hw::exec sha256sum $path] 0]
    append lines "$sum  $rel\n"
  }
  return [hw::hash_text $lines]
}

proc fileutil_relative {root path} {
  set root [file normalize $root]
  set path [file normalize $path]
  if {[string first $root $path] == 0} {
    set rel [string range $path [string length $root] end]
    return [string trimleft $rel "/"]
  }
  return [file tail $path]
}

proc hw::fetch_identity {} {
  return [join [list \
    [hw::need OPENWIFI_HW_REV] \
    [hw::need ADI_HDL_REV] \
    [hw::need OPENOFDM_RX_REV] \
    [hw::need OPENWIFI_HW_REPO] \
    [hw::need ADI_HDL_REPO] \
    [hw::need OPENOFDM_RX_REPO]] \n]
}

proc hw::lib_file {name} {
  return [file join $::hw::hwdir tcl lib $name.tcl]
}

# Each stage hashes only the inputs it uses, plus the hash of the stage before
# it. build_hw.tcl is the driver only and is not a stage input.
proc hw::stage_hash {stage} {
  switch -- $stage {
    fetch {
      return [hw::hash_text [hw::fetch_identity]]
    }
    ip {
      set files [concat \
        [list [hw::lib_file config] [hw::lib_file fetch] \
              [hw::lib_file adi_ip] [hw::lib_file openwifi_ip]] \
        [hw::hw_files ip_xci_tcl]]
      return [hw::hash_text "[hw::stage_hash fetch]\n[hw::files_hash $files]\nADI_IGNORE_VERSION_CHECK=[hw::cfg_get ADI_IGNORE_VERSION_CHECK]"]
    }
    bd {
      set files [concat [list [hw::lib_file bd]] [hw::hw_files bd] [hw::hw_files constraints]]
      return [hw::hash_text "[hw::stage_hash ip]\n[hw::files_hash $files]\nPART=[hw::need PART]\nBOARD=[hw::need BOARD]"]
    }
    synth {
      return [hw::hash_text "[hw::stage_hash bd]\n[hw::files_hash [list [hw::lib_file synth]]]"]
    }
    impl {
      return [hw::hash_text "[hw::stage_hash synth]\n[hw::files_hash [list [hw::lib_file impl]]]\ndirective=$::hw::directive [hw::directive_map $::hw::directive]"]
    }
    bit -
    xsa {
      return [hw::hash_text "[hw::stage_hash impl]\n[hw::files_hash [list [hw::lib_file export]]]"]
    }
    sdt {
      return [hw::hash_text "[hw::stage_hash xsa]\n[hw::files_hash [list [file join $::hw::root sw sdt gen_sdt.sh]]]"]
    }
    report {
      set files [list \
        [hw::lib_file gates] \
        [file join $::hw::hwdir known_critical_warnings.txt] \
        [file join $::hw::hwdir scripts compare_hwh.py] \
        [file join $::hw::hwdir scripts compare_subips.py]]
      set ref [hw::cfg_get EQUIV_HWH]
      set ref_sum none
      if {$ref ne "" && [file isfile $ref]} {
        set ref_sum [lindex [hw::exec sha256sum $ref] 0]
      }
      set sdt_sum none
      set sdt_ref [hw::cfg_get EQUIV_SDT]
      if {$sdt_ref ne "" && [file isfile [file join $sdt_ref pl.dtsi]]} {
        set sdt_sum [lindex [hw::exec sha256sum [file join $sdt_ref pl.dtsi]] 0]
      }
      return [hw::hash_text "[hw::stage_hash sdt]\n[hw::files_hash $files]\nEQUIV_HWH=$ref_sum\nEQUIV_SDT=$sdt_sum"]
    }
    default {
      hw::fail "no hash for stage $stage"
    }
  }
}

proc hw::stamp_path {stage} {
  if {[lsearch -exact {impl bit xsa sdt report} $stage] >= 0} {
    return [file join $::hw::build stamps $::hw::directive $stage.ok]
  }
  return [file join $::hw::build stamps $stage.ok]
}

proc hw::stage_outputs_ok {stage} {
  switch -- $stage {
    fetch  { return [hw::fetch_outputs_ok] }
    ip     { return [expr {[hw::adi_products_ok] && [hw::openwifi_products_ok]}] }
    bd     { return [hw::bd_outputs_ok] }
    synth  { return [hw::synth_outputs_ok] }
    impl   { return [hw::impl_outputs_ok] }
    bit    { return [hw::bit_outputs_ok] }
    xsa    { return [hw::xsa_outputs_ok] }
    sdt    { return [hw::sdt_outputs_ok] }
    report { return [hw::report_outputs_ok] }
    default { hw::fail "no outputs for $stage" }
  }
}

proc hw::can_skip {stage} {
  set path [hw::stamp_path $stage]
  if {![file exists $path]} {
    return 0
  }
  set fh [open $path r]
  set got [string trim [gets $fh]]
  close $fh
  if {$got ne [hw::stage_hash $stage]} {
    return 0
  }
  return [hw::stage_outputs_ok $stage]
}

proc hw::write_stamp {stage} {
  set path [hw::stamp_path $stage]
  file mkdir [file dirname $path]
  set fh [open $path w]
  puts $fh [hw::stage_hash $stage]
  close $fh
  puts "P24_STAMP $stage"
}

proc hw::run_stage {stage} {
  if {[hw::can_skip $stage]} {
    puts "P24_STAGE_SKIP $stage"
    return
  }
  if {[lsearch -exact {bd synth impl} $stage] >= 0} {
    hw::disk_ok
  }
  set started [clock seconds]
  puts "P24_STAGE_BEGIN $stage"
  switch -- $stage {
    fetch  { hw::stage_fetch }
    ip     { hw::stage_ip }
    bd     { hw::stage_bd }
    synth  { hw::stage_synth }
    impl   { hw::stage_impl }
    bit    { hw::stage_bit }
    xsa    { hw::stage_xsa }
    sdt    { hw::stage_sdt }
    report { hw::stage_report }
    default { hw::fail "unknown stage $stage" }
  }
  hw::write_stamp $stage
  set dur [expr {[clock seconds] - $started}]
  puts "P24_STAGE_OK $stage ${dur}s"
}

proc hw::parse_args {} {
  set ::hw::config_file ""
  set ::hw::local_file ""
  set ::hw::jobs ""
  set ::hw::directive default
  set ::hw::clean 0
  set ::hw::allow_dirty 0
  set ::hw::from ""
  set ::hw::to ""
  set ::hw::stages {}
  set ::hw::sim ""
  set ::hw::design_open 0
  for {set i 0} {$i < $::argc} {incr i} {
    set arg [lindex $::argv $i]
    switch -- $arg {
      -config { incr i; set ::hw::config_file [lindex $::argv $i] }
      -local { incr i; set ::hw::local_file [lindex $::argv $i] }
      -jobs { incr i; set ::hw::jobs [lindex $::argv $i] }
      -directive_set { incr i; set ::hw::directive [lindex $::argv $i] }
      -from { incr i; set ::hw::from [lindex $::argv $i] }
      -to { incr i; set ::hw::to [lindex $::argv $i] }
      -stages {
        incr i
        set ::hw::stages [split [lindex $::argv $i] ","]
      }
      -clean { set ::hw::clean 1 }
      -allow_dirty { set ::hw::allow_dirty 1 }
      -sim { incr i; set ::hw::sim [lindex $::argv $i] }
      default { hw::fail "unknown argument $arg" }
    }
  }
  hw::directive_map $::hw::directive
}

proc hw::main {} {
  hw::parse_args
  if {$::hw::clean} {
    puts "P24_CLEAN build/hw"
    file delete -force $::hw::build
  }
  file mkdir $::hw::build $::hw::build/logs $::hw::build/stamps $::hw::build/out
  # The host-path guard reads HOST_PATH_GUARD from config/local.conf.
  hw::load_config
  hw::reject_host_paths
  if {$::hw::sim ne ""} {
    hw::stage_sim $::hw::sim
    return
  }
  hw::check_viterbi
  set order {fetch ip bd synth impl bit xsa sdt report}
  set plan $order
  if {[llength $::hw::stages]} {
    if {$::hw::stages ne "all" && $::hw::stages ne [list all]} {
      set plan {}
      foreach stage $::hw::stages {
        if {[lsearch -exact $order $stage] < 0} {
          hw::fail "unknown stage $stage"
        }
        lappend plan $stage
      }
    }
  } else {
    set from $::hw::from
    set to $::hw::to
    if {$from eq ""} { set from fetch }
    if {$to eq ""} { set to report }
    set plan {}
    set active 0
    foreach stage $order {
      if {$stage eq $from} { set active 1 }
      if {$active} { lappend plan $stage }
      if {$stage eq $to} { break }
    }
    if {![llength $plan]} {
      hw::fail "empty stage range $from..$to"
    }
  }
  foreach stage $order {
    if {[lsearch -exact $plan $stage] >= 0} {
      break
    }
    if {![hw::can_skip $stage]} {
      hw::run_stage $stage
    }
  }
  foreach stage $plan {
    hw::run_stage $stage
  }
  puts "P24_HW_OK"
}

if {[catch {hw::main} ::hw::fatal]} {
  puts $::hw::fatal
  exit 1
}
exit 0
