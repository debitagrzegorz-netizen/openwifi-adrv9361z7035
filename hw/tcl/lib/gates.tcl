# Tool, licence, timing, utilization, handoff, warning, and cleanliness gates.

proc hw::check_viterbi {} {
  set part [hw::need PART]
  set dir [file join $::hw::build tmp viterbi-lic]
  file delete -force $dir
  file mkdir $dir
  create_project p24_viterbi_lic $dir/p24_viterbi_lic -part $part -force
  set defs [get_ipdefs -filter {NAME == viterbi}]
  if {$defs eq ""} {
    hw::fail "no viterbi IP definition in this Vivado"
  }
  set def [lindex $defs end]
  if {[catch {create_ip -vlnv $def -module_name p24_viterbi} err]} {
    hw::fail "viterbi create_ip failed: $err"
  }
  set ip [get_ips p24_viterbi]
  if {[catch {generate_target all $ip} err]} {
    hw::fail "viterbi generate_target failed: $err"
  }
  set locked [get_property IS_LOCKED $ip]
  if {[catch {set keys [get_property USED_LICENSE_KEYS $ip]} err]} {
    hw::fail "viterbi has no USED_LICENSE_KEYS: $err"
  }
  puts "P24_VITERBI IS_LOCKED=$locked"
  if {$locked ne "0" && $locked ne "false"} {
    hw::fail "viterbi core is locked"
  }
  set keys_l [string tolower $keys]
  if {![string match *bought* $keys_l]} {
    hw::fail "viterbi license is not a bought key"
  }
  if {[string match *hardware_evaluation* $keys_l] || [string match *evaluation* $keys_l]} {
    hw::fail "viterbi license is an evaluation key"
  }
  close_project -delete
  puts "P24_VITERBI_OK"
}

proc hw::allow_warnings {} {
  set path [file join $::hw::hwdir known_critical_warnings.txt]
  set ids {}
  set fh [open $path r]
  while {[gets $fh line] >= 0} {
    set line [string trim $line]
    if {$line eq "" || [string match "#*" $line]} {
      continue
    }
    lappend ids $line
  }
  close $fh
  return $ids
}

proc hw::scan_critical {logs} {
  set found {}
  foreach log $logs {
    if {![file exists $log]} {
      continue
    }
    set fh [open $log r]
    while {[gets $fh line] >= 0} {
      if {![string match "*CRITICAL WARNING*" $line]} {
        continue
      }
      if {[regexp {\[([^\]]+)\]} $line -> id]} {
        dict set found $id 1
      }
    }
    close $fh
  }
  set allow [hw::allow_warnings]
  set unknown {}
  foreach id [dict keys $found] {
    if {[lsearch -exact $allow $id] < 0} {
      lappend unknown $id
    }
  }
  set out [file join [hw::report_dir] critical.txt]
  file mkdir [file dirname $out]
  set fh [open $out w]
  puts $fh "seen [join [lsort [dict keys $found]] {, }]"
  if {[llength $unknown]} {
    puts $fh "unknown [join [lsort $unknown] {, }]"
  }
  close $fh
  if {[llength $unknown]} {
    hw::fail "new critical warnings: [join [lsort $unknown] {, }]"
  }
  puts "P24_CRITICAL_OK [llength [dict keys $found]]"
}

proc hw::log_files {} {
  set logs {}
  foreach path [glob -nocomplain \
      [file join $::hw::build logs *.log] \
      [file join $::hw::build work hdl library * *_ip.log] \
      [file join $::hw::build work hdl library * * *_ip.log]] {
    lappend logs $path
  }
  return $logs
}

proc hw::parse_timing_rpt {} {
  set path [file join $::hw::build reports $::hw::directive timing_summary.rpt]
  if {![file exists $path]} {
    hw::fail "timing summary is missing"
  }
  set fh [open $path r]
  set text [read $fh]
  close $fh
  if {![regexp {WNS\(ns\).*\n[^\n]*\n\s*(-?[0-9.]+)\s+(-?[0-9.]+)\s+[0-9]+\s+[0-9]+\s+(-?[0-9.]+)\s+(-?[0-9.]+)} $text -> wns tns whs ths]} {
    hw::fail "could not parse timing summary"
  }
  puts "P24_TIMING_RPT WNS=$wns TNS=$tns WHS=$whs THS=$ths"
  if {$wns < 0 || $whs < 0 || $tns < 0 || $ths < 0} {
    hw::fail "timing report is not closed"
  }
  set ::hw::timing [list $wns $tns $whs $ths]
}

proc hw::parse_util_rpt {} {
  set path [file join $::hw::build reports $::hw::directive utilization.rpt]
  set fh [open $path r]
  set text [read $fh]
  close $fh
  if {![regexp {\|\s*Slice LUTs\s*\|\s*([0-9]+)} $text -> luts]} {
    hw::fail "utilization report has no Slice LUTs"
  }
  if {![regexp {\|\s*Slice Registers\s*\|\s*([0-9]+)} $text -> ffs]} {
    hw::fail "utilization report has no Slice Registers"
  }
  # P19 post-route baseline: 41608 LUT, 56663 FF. Gate is plus or minus 2%.
  set lut_lo 40776
  set lut_hi 42440
  set ff_lo 55530
  set ff_hi 57796
  puts "P24_UTIL LUT=$luts FF=$ffs"
  if {$luts < $lut_lo || $luts > $lut_hi || $ffs < $ff_lo || $ffs > $ff_hi} {
    hw::fail "utilization LUT=$luts FF=$ffs is outside the P19 band"
  }
  set ::hw::util [list $luts $ffs]
}

proc hw::extract_hwh {xsa dest} {
  set tmp [file join $::hw::build tmp hwh]
  file delete -force $tmp
  file mkdir $tmp
  if {[catch {hw::exec unzip -o $xsa -d $tmp} err]} {
    hw::fail "unzip XSA for hwh failed: $err"
  }
  set found ""
  foreach path [split [hw::exec find $tmp -type f -name *.hwh] \n] {
    if {$path ne ""} {
      set found $path
      break
    }
  }
  if {$found eq ""} {
    hw::fail "XSA contains no hwh"
  }
  file copy -force $found $dest
  return $dest
}

proc hw::compile_sdt_dtb {} {
  set sdt [file join $::hw::build sdt $::hw::directive]
  set dtb [file join $sdt system.dtb]
  set dts [file join $sdt system-top.dts]
  set bindir [file join [hw::need TOOLS_ROOT] PetaLinux sysroots x86_64-petalinux-linux usr bin]
  if {[file executable [file join $bindir dtc]]} {
    set ::env(PATH) "$bindir:$::env(PATH)"
  }
  # The SDT top file uses #include, so it goes through cpp first, as in the
  # kernel DT build.
  set pp [file join $sdt system-top.pp.dts]
  if {[catch {hw::exec cpp -nostdinc -undef -D__DTS__ -x assembler-with-cpp \
      -I $sdt -I [file join $sdt include] -o $pp $dts} err]} {
    hw::fail "cpp on the SDT failed: $err"
  }
  if {[catch {hw::exec dtc -q -I dts -O dtb -o $dtb -i $sdt $pp} err]} {
    hw::fail "dtc failed: $err"
  }
  puts "P24_SDT_DTB_OK"
}

# The raw SDT has no /axi/sdr node and the image deletes its PL nodes
# (DTB_PL_DELETE), so check_dtb_irqs.sh runs on the image DTB in
# build.sh gates. Here the SDT must equal the reference SDT (generated from
# the v1.0 XSA) except for the bitstream file name.
proc hw::compare_sdt {} {
  set ref [hw::cfg_get EQUIV_SDT]
  if {$ref eq "" || ![file isdirectory $ref]} {
    hw::fail "set EQUIV_SDT in local.conf to the reference SDT directory"
  }
  set sdt [file join $::hw::build sdt $::hw::directive]
  set out [file join [hw::report_dir] sdt-diff.txt]
  set fh [open $out w]
  set bad 0
  foreach name {system-top.dts pl.dtsi pcw.dtsi zynq-7000.dtsi} {
    set a [split [hw::read_file [file join $ref $name]] \n]
    set b [split [hw::read_file [file join $sdt $name]] \n]
    if {[llength $a] != [llength $b]} {
      puts $fh "DIFF $name line count [llength $a] -> [llength $b]"
      set bad 1
      continue
    }
    for {set i 0} {$i < [llength $a]} {incr i} {
      set la [lindex $a $i]
      set lb [lindex $b $i]
      if {$la eq $lb} {
        continue
      }
      if {[regexp {^\s*firmware-name = } $la] && [regexp {^\s*firmware-name = } $lb]} {
        puts $fh "ALLOW $name:[expr {$i + 1}] [string trim $la] -> [string trim $lb]"
        continue
      }
      puts $fh "DIFF $name:[expr {$i + 1}] [string trim $la] -> [string trim $lb]"
      set bad 1
    }
  }
  close $fh
  if {$bad} {
    hw::fail "SDT differs from EQUIV_SDT (see sdt-diff.txt)"
  }
  puts "P24_SDT_EQUIV_OK"
}

proc hw::read_file {path} {
  set fh [open $path r]
  set body [read $fh]
  close $fh
  return $body
}

proc hw::check_sources_clean {} {
  foreach name {openwifi-hw hdl openofdm_rx} {
    set repo [file join $::hw::build src $name]
    set dirty [hw::git_porcelain $repo]
    if {$dirty ne ""} {
      hw::fail "fetched $name is dirty after the build"
    }
  }
  puts "P24_SOURCES_CLEAN"
}

proc hw::sha256_file {path} {
  return [lindex [hw::exec sha256sum $path] 0]
}

proc hw::write_build_info {} {
  lassign $::hw::timing wns tns whs ths
  lassign $::hw::util luts ffs
  set out [hw::out_dir]
  set bit [file join $out system_top.bit]
  set xsa [file join $out system_top.xsa]
  set info [file join $out build-info.json]
  set sdt [file join $::hw::build sdt $::hw::directive system-top.dts]
  set host [hw::exec hostname]
  set fh [open $info w]
  puts $fh "\{"
  puts $fh "  \"openwifi_hw\": \"[hw::need OPENWIFI_HW_REV]\","
  puts $fh "  \"adi_hdl\": \"[hw::need ADI_HDL_REV]\","
  puts $fh "  \"openofdm_rx\": \"[hw::need OPENOFDM_RX_REV]\","
  puts $fh "  \"openwifi_hw_short\": \"$::hw::git_short\","
  puts $fh "  \"openwifi_hw_dirty\": $::hw::git_dirty,"
  puts $fh "  \"tool\": \"2025.1\","
  puts $fh "  \"part\": \"[hw::need PART]\","
  puts $fh "  \"board\": \"[hw::need BOARD]\","
  puts $fh "  \"directive\": \"$::hw::directive\","
  puts $fh "  \"jobs\": $::hw::jobs,"
  puts $fh "  \"host\": \"$host\","
  puts $fh "  \"usr_access\": \"[hw::usr_access_value]\","
  puts $fh "  \"wns\": $wns,"
  puts $fh "  \"tns\": $tns,"
  puts $fh "  \"whs\": $whs,"
  puts $fh "  \"ths\": $ths,"
  puts $fh "  \"slice_luts\": $luts,"
  puts $fh "  \"slice_ffs\": $ffs,"
  puts $fh "  \"bit_sha256\": \"[hw::sha256_file $bit]\","
  puts $fh "  \"xsa_sha256\": \"[hw::sha256_file $xsa]\","
  puts $fh "  \"sdt_dts_sha256\": \"[hw::sha256_file $sdt]\""
  puts $fh "\}"
  close $fh
  if {$::hw::directive eq "default"} {
    file copy -force $info [file join $::hw::build out build-info.json]
  }
  puts "P24_BUILD_INFO $info"
}

proc hw::stage_report {} {
  hw::parse_timing_rpt
  hw::parse_util_rpt
  hw::scan_critical [hw::log_files]
  set xsa [file join [hw::out_dir] system_top.xsa]
  set hwh [file join [hw::report_dir] system.hwh]
  hw::extract_hwh $xsa $hwh
  set ref [hw::cfg_get EQUIV_HWH]
  if {$ref eq ""} {
    hw::fail "set EQUIV_HWH in local.conf to the reference system.hwh"
  }
  if {![file exists $ref]} {
    hw::fail "EQUIV_HWH does not exist"
  }
  set diff [file join [hw::report_dir] hwh-diff.txt]
  set script [file join $::hw::hwdir scripts compare_hwh.py]
  if {[catch {hw::exec python3 $script $ref $hwh $diff} err]} {
    hw::fail "hwh equivalence failed: $err"
  }
  hw::compile_sdt_dtb
  hw::compare_sdt
  hw::check_sources_clean
  if {![info exists ::hw::git_short]} {
    hw::git_header
  }
  hw::write_build_info
  set fh [open [file join [hw::report_dir] gate.txt] w]
  puts $fh "P24_GATE_OK"
  close $fh
  puts "P24_GATE_OK"
}

proc hw::report_outputs_ok {} {
  return [file exists [file join $::hw::build reports $::hw::directive gate.txt]]
}
