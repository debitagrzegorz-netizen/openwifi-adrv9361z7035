# Clone pinned sources into build/hw/src. The clones are never edited.

proc hw::git_porcelain {repo} {
  if {[catch {::exec git -C $repo status --porcelain --ignore-submodules=all 2>/dev/null} out]} {
    hw::fail "git status failed in $repo: $out"
  }
  return [string trim $out]
}

proc hw::clone_pin {name url rev dest} {
  if {$url eq ""} {
    hw::fail "config is missing the repository URL for $name"
  }
  if {![file exists [file join $dest .git]]} {
    file mkdir [file dirname $dest]
    puts "P24_FETCH_CLONE $name"
    if {[catch {hw::exec git clone --no-hardlinks $url $dest} err]} {
      hw::fail "git clone $name failed: $err"
    }
  }
  set head ""
  catch {set head [hw::exec git -C $dest rev-parse HEAD]}
  if {$head ne $rev} {
    puts "P24_FETCH_CHECKOUT $name"
    if {[catch {hw::exec git -C $dest checkout --detach $rev} err]} {
      hw::fail "checkout $name $rev failed: $err"
    }
  }
  set head [hw::exec git -C $dest rev-parse HEAD]
  if {$head ne $rev} {
    hw::fail "$name HEAD $head != $rev"
  }
  set dirty [hw::git_porcelain $dest]
  if {$dirty ne ""} {
    if {!$::hw::allow_dirty} {
      hw::fail "$name fetched tree is dirty"
    }
    puts "P24_FETCH_DIRTY_ALLOWED $name"
  }
  puts "P24_FETCH_OK $name $head"
}

proc hw::stage_fetch {} {
  set src [file join $::hw::build src]
  file mkdir $src
  hw::clone_pin openwifi-hw [hw::need OPENWIFI_HW_REPO] [hw::need OPENWIFI_HW_REV] \
    [file join $src openwifi-hw]
  hw::clone_pin hdl [hw::need ADI_HDL_REPO] [hw::need ADI_HDL_REV] \
    [file join $src hdl]
  hw::clone_pin openofdm_rx [hw::need OPENOFDM_RX_REPO] [hw::need OPENOFDM_RX_REV] \
    [file join $src openofdm_rx]
}

proc hw::fetch_outputs_ok {} {
  set src [file join $::hw::build src]
  foreach pair {
    {openwifi-hw OPENWIFI_HW_REV}
    {hdl ADI_HDL_REV}
    {openofdm_rx OPENOFDM_RX_REV}
  } {
    lassign $pair name key
    set dest [file join $src $name]
    if {![file exists [file join $dest .git]]} {
      return 0
    }
    if {[catch {hw::exec git -C $dest rev-parse HEAD} head]} {
      return 0
    }
    if {$head ne [hw::need $key]} {
      return 0
    }
    if {[hw::git_porcelain $dest] ne "" && !$::hw::allow_dirty} {
      return 0
    }
  }
  return 1
}
