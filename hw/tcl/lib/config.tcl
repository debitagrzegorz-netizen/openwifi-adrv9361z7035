# Parse the shared key=value configs. No host path is written back.

namespace eval hw {}

proc hw::fail {msg} {
  puts "P24_HW_FAIL $msg"
  error "P24_HW_FAIL $msg"
}

# Needles are assembled at runtime so this tree does not store a host path.
proc hw::banned_needles {} {
  return [list [file join / dysk] [file join / home grzegorz]]
}

proc hw::body_has_banned_path {body} {
  foreach needle [hw::banned_needles] {
    if {[string first $needle $body] >= 0} {
      return 1
    }
  }
  return 0
}

# Child tools often write progress to stderr and still exit 0. Tcl hw::exec treats
# that as a failure unless stderr is merged.
proc hw::exec {args} {
  if {[catch {::exec {*}$args 2>@1} out]} {
    return -code error $out
  }
  return $out
}

proc hw::cfg_get {key {default ""}} {
  if {[info exists ::hw::cfg($key)]} {
    return $::hw::cfg($key)
  }
  return $default
}

proc hw::need {key} {
  set value [hw::cfg_get $key]
  if {$value eq ""} {
    hw::fail "config is missing $key"
  }
  return $value
}

proc hw::parse_conf {path} {
  if {![file exists $path]} {
    hw::fail "config file not found: $path"
  }
  set fh [open $path r]
  while {[gets $fh line] >= 0} {
    set line [string trim $line]
    if {$line eq "" || [string match "#*" $line]} {
      continue
    }
    if {[string match "export *" $line]} {
      set line [string trim [string range $line 7 end]]
    }
    set eq [string first "=" $line]
    if {$eq < 1} {
      continue
    }
    set key [string trim [string range $line 0 [expr {$eq - 1}]]]
    set value [string trim [string range $line [expr {$eq + 1}] end]]
    if {[string length $value] >= 2} {
      set q [string index $value 0]
      set z [string index $value end]
      if {($q eq "\"" && $z eq "\"") || ($q eq "'" && $z eq "'")} {
        set value [string range $value 1 end-1]
      }
    }
    set ::hw::cfg($key) $value
  }
  close $fh
}

proc hw::disk_gb {} {
  set out [hw::exec df -BG --output=avail $::hw::root]
  set line [string trim [lindex [split $out \n] 1]]
  regsub -all {[^0-9]} $line "" line
  if {$line eq ""} {
    hw::fail "df returned no free-space figure"
  }
  return $line
}

proc hw::disk_ok {} {
  set gb [hw::disk_gb]
  puts "P24_DISK_GB $gb"
  if {$gb < 30} {
    hw::fail "free space ${gb}G is below 30G"
  }
}

proc hw::load_config {} {
  array unset ::hw::cfg
  if {$::hw::config_file eq ""} {
    set ::hw::config_file [file join $::hw::root config versions.conf]
  }
  if {$::hw::local_file eq ""} {
    set ::hw::local_file [file join $::hw::root config local.conf]
  }
  hw::parse_conf $::hw::config_file
  hw::parse_conf $::hw::local_file
  set tool [hw::cfg_get TOOL_VERSION]
  set vivado [hw::cfg_get VIVADO_VERSION $tool]
  if {$vivado ne "2025.1" || $tool ne "2025.1"} {
    hw::fail "TOOL_VERSION/VIVADO_VERSION must be 2025.1"
  }
  if {[version -short] ne "2025.1"} {
    hw::fail "Vivado is [version -short], want 2025.1"
  }
  hw::need BOARD
  hw::need PART
  hw::need OPENWIFI_HW_REV
  hw::need ADI_HDL_REV
  hw::need OPENOFDM_RX_REV
  if {$::hw::jobs eq ""} {
    set ::hw::jobs [hw::cfg_get HW_JOBS 8]
  }
  if {![string is integer -strict $::hw::jobs] || $::hw::jobs < 1} {
    hw::fail "jobs must be a positive integer"
  }
  if {[catch {set_param general.maxThreads $::hw::jobs} err]} {
    puts "P24_THREADS_WARN $err"
  }
  puts "P24_CONFIG board=[hw::need BOARD] part=[hw::need PART] jobs=$::hw::jobs directive=$::hw::directive"
}
