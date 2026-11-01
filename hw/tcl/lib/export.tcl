# Bitstream, XSA, and SDT. USR_ACCESS is the first 8 hex digits of the impl stamp.

proc hw::out_dir {} {
  set path [file join $::hw::build out $::hw::directive]
  file mkdir $path
  return $path
}

proc hw::read_stamp_hash {stage} {
  set path [hw::stamp_path $stage]
  if {![file exists $path]} {
    hw::fail "stamp $stage is missing"
  }
  set fh [open $path r]
  set hash [string trim [gets $fh]]
  close $fh
  if {![regexp {^[0-9a-f]{64}$} $hash]} {
    hw::fail "stamp $stage is not a sha256"
  }
  return $hash
}

proc hw::usr_access_value {} {
  set hash [hw::read_stamp_hash impl]
  return "0x[string range $hash 0 7]"
}

proc hw::ensure_routed_design {} {
  if {[info exists ::hw::design_open] && $::hw::design_open} {
    return
  }
  set dcp [file join $::hw::build ckpt $::hw::directive post_hold.dcp]
  if {![file exists $dcp]} {
    hw::fail "post-hold checkpoint is missing"
  }
  open_checkpoint $dcp
  set ::hw::design_open 1
}

proc hw::stage_bit {} {
  hw::ensure_routed_design
  set ua [hw::usr_access_value]
  set_property BITSTREAM.CONFIG.USR_ACCESS $ua [current_design]
  set bit [file join [hw::out_dir] system_top.bit]
  puts "P24_BIT_BEGIN USR_ACCESS=$ua"
  write_bitstream -force $bit
  if {$::hw::directive eq "default"} {
    file copy -force $bit [file join $::hw::build out system_top.bit]
  }
  set ::hw::usr_access $ua
  puts "P24_BIT_OK $bit"
}

proc hw::read_text {path} {
  set fh [open $path r]
  set body [read $fh]
  close $fh
  return $body
}

proc hw::write_text {path body} {
  set fh [open $path w]
  puts -nonewline $fh $body
  close $fh
}

proc hw::xsa_add_bitstream {xsa bit} {
  # write_hw_platform on the flat routed netlist aborts in the MMI step.
  # The block-design archive has the processor handoff and no bitstream.
  set tmp [file join $::hw::build tmp xsa-pack]
  file delete -force $tmp
  file mkdir $tmp
  if {[catch {hw::exec unzip -o $xsa -d $tmp} err]} {
    hw::fail "unzip XSA failed: $err"
  }
  file copy -force $bit [file join $tmp system_top.bit]
  set xml_path [file join $tmp xsa.xml]
  set xml [hw::read_text $xml_path]
  if {[string first "FULL_BIT" $xml] < 0} {
    if {[string first "<Files/>" $xml] < 0} {
      hw::fail "xsa.xml has no Files element"
    }
    set xml [string map {<Files/> {<Files>
      <File Type="FULL_BIT" Name="system_top.bit"/>
    </Files>}} $xml]
    hw::write_text $xml_path $xml
  }
  set bit_xml "\t<File Type=\"BIT\" Name=\"system_top.bit\" src_db=\"temp.hdf\">\n\t</File>\n"
  foreach handoff {hwdef.xml sysdef.xml} {
    set path [file join $tmp $handoff]
    if {![file exists $path]} {
      continue
    }
    set body [hw::read_text $path]
    if {[string first "Type=\"BIT\"" $body] < 0} {
      if {[string first "<USEDRESOURCES/>" $body] < 0} {
        hw::fail "$handoff has no USEDRESOURCES element"
      }
      set body [string map [list <USEDRESOURCES/> "$bit_xml\t<USEDRESOURCES/>"] $body]
      hw::write_text $path $body
    }
  }
  if {![file exists [file join $tmp sysdef.xml]] && [file exists [file join $tmp hwdef.xml]]} {
    file copy -force [file join $tmp hwdef.xml] [file join $tmp sysdef.xml]
  }
  set json_path [file join $tmp xsa.json]
  set json [hw::read_text $json_path]
  if {[string first "system_top.bit" $json] < 0} {
    set idx [string last "\}" $json]
    if {$idx < 0} {
      hw::fail "xsa.json has no closing brace"
    }
    set snippet {,
    "files": [
        {
            "name": "system_top.bit",
            "type": "FULL_BIT"
        }
    ]
}
}
    set json "[string range $json 0 [expr {$idx - 1}]]$snippet"
    hw::write_text $json_path $json
  }
  file delete -force $xsa
  set here [pwd]
  cd $tmp
  if {[catch {hw::exec zip -X -r $xsa .} err]} {
    cd $here
    hw::fail "zip XSA failed: $err"
  }
  cd $here
}

proc hw::stage_xsa {} {
  set bit [file join [hw::out_dir] system_top.bit]
  if {![file exists $bit]} {
    hw::fail "bitstream is missing"
  }
  if {[info exists ::hw::design_open] && $::hw::design_open} {
    close_design
    set ::hw::design_open 0
  }
  if {[llength [get_projects -quiet]]} {
    close_project
  }
  set xpr [file join $::hw::build proj p24_hw p24_hw.xpr]
  if {![file exists $xpr]} {
    hw::fail "block design project is missing"
  }
  set xsa [file join [hw::out_dir] system_top.xsa]
  puts "P24_XSA_BEGIN"
  open_project $xpr
  write_hw_platform -fixed -force -file $xsa
  close_project
  hw::xsa_add_bitstream $xsa $bit
  if {$::hw::directive eq "default"} {
    file copy -force $xsa [file join $::hw::build out system_top.xsa]
  }
  hw::check_xsa_payload $bit $xsa
  puts "P24_XSA_OK $xsa"
}

proc hw::check_xsa_payload {bit xsa} {
  set tmp [file join $::hw::build tmp xsa-unpack]
  file delete -force $tmp
  file mkdir $tmp
  if {[catch {hw::exec unzip -o $xsa -d $tmp} err]} {
    hw::fail "unzip XSA failed: $err"
  }
  set extracted ""
  foreach path [split [hw::exec find $tmp -type f -name *.bit] \n] {
    if {$path ne ""} {
      set extracted $path
      break
    }
  }
  if {$extracted eq ""} {
    hw::fail "XSA contains no bitstream"
  }
  set checker [file join $::hw::root scripts check_boot_bitstream.sh]
  if {[catch {hw::exec $checker $bit $extracted} err]} {
    hw::fail "XSA payload does not match the bitstream: $err"
  }
  puts "P24_XSA_PAYLOAD_OK"
}

proc hw::stage_sdt {} {
  set xsa [file join [hw::out_dir] system_top.xsa]
  if {![file exists $xsa]} {
    hw::fail "XSA is missing"
  }
  set out [file join $::hw::build sdt $::hw::directive]
  file delete -force $out
  file mkdir $out
  set tools [hw::need TOOLS_ROOT]
  set ::env(TOOLS_ROOT) $tools
  set sdtgen [file join $tools Vitis bin sdtgen]
  if {[file executable $sdtgen]} {
    set ::env(SDTGEN) $sdtgen
  }
  set script [file join $::hw::root sw sdt gen_sdt.sh]
  puts "P24_SDT_BEGIN"
  if {[catch {hw::exec $script --xsa $xsa --out $out} err]} {
    hw::fail "sdtgen failed: $err"
  }
  if {$::hw::directive eq "default"} {
    set current [file join $::hw::build sdt current]
    file delete -force $current
    file mkdir [file dirname $current]
    # A directory symlink keeps the software stage pointed at this SDT.
    file link -symbolic $current $out
  }
  puts "P24_SDT_OK $out"
}

proc hw::bit_outputs_ok {} {
  return [file exists [file join [hw::out_dir] system_top.bit]]
}

proc hw::xsa_outputs_ok {} {
  return [file exists [file join [hw::out_dir] system_top.xsa]]
}

proc hw::sdt_outputs_ok {} {
  return [expr {
    [file exists [file join $::hw::build sdt $::hw::directive system-top.dts]] &&
    [file exists [file join $::hw::build sdt $::hw::directive pl.dtsi]]
  }]
}
