# Recreate openofdm_rx Xilinx sub-IPs with create_ip.
# User parameters come from the pinned zynq xci files. rot_lut port B
# is forced: Enable_B Always_Enabled and no primitive output register.
# Coe paths resolve from P24_OFDM_ROOT. There is no upgrade_ip.
#
# Source this from the openofdm_rx project after the original xci files
# have been added, in place of upgrade_ip.

proc p24_fail {msg} {
  puts "P24_SUBIP_FAIL $msg"
  error "P24_SUBIP_FAIL $msg"
}

proc p24_resolve_vlnv {vlnv} {
  if {[get_ipdefs -all $vlnv] ne ""} {
    return $vlnv
  }
  set name [lindex [split $vlnv :] 2]
  set defs [get_ipdefs -filter "NAME == $name"]
  if {$defs eq ""} {
    p24_fail "no catalog IP for $vlnv"
  }
  set best [lindex $defs end]
  puts "P24_SUBIP_VLNV_FALLBACK $vlnv -> $best"
  return $best
}

# One dict, so dependent parameters (COE file and Load_Init_File, divider
# remainder type and width) are validated together.
proc p24_set_dict {cell args} {
  set spec {}
  foreach {name value} $args {
    set prop CONFIG.$name
    if {[lsearch -exact [list_property $cell] $prop] < 0} {
      puts "P24_SUBIP_SKIP [get_property NAME $cell] $prop"
      continue
    }
    lappend spec $prop $value
  }
  if {[llength $spec] == 0} {
    p24_fail "no parameters applied to [get_property NAME $cell]"
  }
  if {[catch {set_property -dict $spec $cell} err]} {
    p24_fail "set_property dict on [get_property NAME $cell]: $err"
  }
}


proc p24_remove_ip {name} {
  set ip [get_ips -quiet $name]
  if {$ip eq ""} {
    return
  }
  # get_files -of_objects is empty for these locked xci files. IP_FILE is the xci.
  set xci ""
  catch {set xci [get_property IP_FILE $ip]}
  if {$xci eq ""} {
    p24_fail "$name has no IP_FILE"
  }
  set extras [get_files -all -quiet -of_objects $ip]
  set xci_files [get_files -all -quiet $xci]
  if {$xci_files eq ""} {
    p24_fail "$name xci is not a project file: $xci"
  }
  if {[catch {remove_files {*}$xci_files} err]} {
    p24_fail "remove_files $name: $err"
  }
  foreach extra $extras {
    set still [get_files -all -quiet $extra]
    if {$still ne ""} {
      catch {remove_files {*}$still}
    }
  }
  if {[get_ips -quiet $name] ne ""} {
    p24_fail "$name is still in the project after remove_files"
  }
}

if {![info exists ::env(P24_OFDM_ROOT)] || $::env(P24_OFDM_ROOT) eq ""} {
  p24_fail "P24_OFDM_ROOT is not set"
}
if {[catch {config_ip_cache -disable_cache} p24_cache_err]} {
  puts "P24_SUBIP_CACHE_WARN $p24_cache_err"
}

puts "P24_SUBIP_BEGIN atan_lut"
p24_remove_ip atan_lut
set p24_vlnv [p24_resolve_vlnv {xilinx.com:ip:blk_mem_gen:8.4}]
create_ip -vlnv $p24_vlnv -module_name atan_lut
set p24_cell [get_ips atan_lut]
set p24_coe [file join $::env(P24_OFDM_ROOT) ip_repo/atan_lut/atan_lut.coe]
if {![file exists $p24_coe]} {
  p24_fail "missing coefficient file $p24_coe"
}
p24_set_dict $p24_cell \
  Memory_Type {Single_Port_ROM} \
  Enable_A {Always_Enabled} \
  Load_Init_File {true} \
  Coe_File [file normalize $p24_coe] \
  Port_A_Write_Rate {0} \
  Read_Width_A {9} \
  Read_Width_B {9} \
  Register_PortA_Output_of_Memory_Primitives {false} \
  Write_Depth_A {512} \
  Write_Width_A {9} \
  Write_Width_B {9}
if {[catch {generate_target all $p24_cell} p24_gen_err]} {
  p24_fail "generate_target atan_lut: $p24_gen_err"
}
puts "P24_SUBIP_OK atan_lut $p24_vlnv"

puts "P24_SUBIP_BEGIN complex_multiplier"
p24_remove_ip complex_multiplier
set p24_vlnv [p24_resolve_vlnv {xilinx.com:ip:cmpy:6.0}]
create_ip -vlnv $p24_vlnv -module_name complex_multiplier
set p24_cell [get_ips complex_multiplier]
p24_set_dict $p24_cell \
  LatencyConfig {Manual} \
  MinimumLatency {3} \
  APortWidth {16} \
  BPortWidth {16} \
  OptimizeGoal {Performance} \
  OutputWidth {32}
if {[catch {generate_target all $p24_cell} p24_gen_err]} {
  p24_fail "generate_target complex_multiplier: $p24_gen_err"
}
puts "P24_SUBIP_OK complex_multiplier $p24_vlnv"

puts "P24_SUBIP_BEGIN deinter_lut"
p24_remove_ip deinter_lut
set p24_vlnv [p24_resolve_vlnv {xilinx.com:ip:blk_mem_gen:8.4}]
create_ip -vlnv $p24_vlnv -module_name deinter_lut
set p24_cell [get_ips deinter_lut]
set p24_coe [file join $::env(P24_OFDM_ROOT) ip_repo/deinter_lut/deinter_lut.coe]
if {![file exists $p24_coe]} {
  p24_fail "missing coefficient file $p24_coe"
}
p24_set_dict $p24_cell \
  Memory_Type {Single_Port_ROM} \
  Enable_A {Always_Enabled} \
  Load_Init_File {true} \
  Coe_File [file normalize $p24_coe] \
  Port_A_Write_Rate {0} \
  Read_Width_A {22} \
  Read_Width_B {22} \
  Register_PortA_Output_of_Memory_Primitives {false} \
  Write_Depth_A {4096} \
  Write_Width_A {22} \
  Write_Width_B {22}
if {[catch {generate_target all $p24_cell} p24_gen_err]} {
  p24_fail "generate_target deinter_lut: $p24_gen_err"
}
puts "P24_SUBIP_OK deinter_lut $p24_vlnv"

puts "P24_SUBIP_BEGIN div_for_rotafft"
p24_remove_ip div_for_rotafft
set p24_vlnv [p24_resolve_vlnv {xilinx.com:ip:div_gen:5.1}]
create_ip -vlnv $p24_vlnv -module_name div_for_rotafft
set p24_cell [get_ips div_for_rotafft]
p24_set_dict $p24_cell \
  remainder_type {Fractional} \
  latency_configuration {Manual} \
  fractional_width {28} \
  dividend_and_quotient_width {32} \
  divisor_width {40} \
  latency {36}
if {[catch {generate_target all $p24_cell} p24_gen_err]} {
  p24_fail "generate_target div_for_rotafft: $p24_gen_err"
}
puts "P24_SUBIP_OK div_for_rotafft $p24_vlnv"

puts "P24_SUBIP_BEGIN div_gen_csi_over_nova"
p24_remove_ip div_gen_csi_over_nova
set p24_vlnv [p24_resolve_vlnv {xilinx.com:ip:div_gen:5.1}]
create_ip -vlnv $p24_vlnv -module_name div_gen_csi_over_nova
set p24_cell [get_ips div_gen_csi_over_nova]
p24_set_dict $p24_cell \
  operand_sign {Unsigned} \
  remainder_type {Fractional} \
  fractional_width {2} \
  dividend_and_quotient_width {34} \
  divisor_width {25} \
  latency {38}
if {[catch {generate_target all $p24_cell} p24_gen_err]} {
  p24_fail "generate_target div_gen_csi_over_nova: $p24_gen_err"
}
puts "P24_SUBIP_OK div_gen_csi_over_nova $p24_vlnv"

puts "P24_SUBIP_BEGIN div_gen_div_gen_0_0"
p24_remove_ip div_gen_div_gen_0_0
set p24_vlnv [p24_resolve_vlnv {xilinx.com:ip:div_gen:5.1}]
create_ip -vlnv $p24_vlnv -module_name div_gen_div_gen_0_0
set p24_cell [get_ips div_gen_div_gen_0_0]
p24_set_dict $p24_cell \
  remainder_type {Fractional} \
  latency_configuration {Manual} \
  fractional_width {24} \
  dividend_and_quotient_width {32} \
  divisor_width {24} \
  latency {36}
if {[catch {generate_target all $p24_cell} p24_gen_err]} {
  p24_fail "generate_target div_gen_div_gen_0_0: $p24_gen_err"
}
puts "P24_SUBIP_OK div_gen_div_gen_0_0 $p24_vlnv"

puts "P24_SUBIP_BEGIN div_gen_xlslice_0_0"
p24_remove_ip div_gen_xlslice_0_0
set p24_vlnv [p24_resolve_vlnv {xilinx.com:ip:xlslice:1.0}]
create_ip -vlnv $p24_vlnv -module_name div_gen_xlslice_0_0
set p24_cell [get_ips div_gen_xlslice_0_0]
p24_set_dict $p24_cell \
  DIN_FROM {55} \
  DIN_TO {24} \
  DIN_WIDTH {56}
# DOUT_WIDTH in the xci is 1, which disagrees with DIN_FROM/DIN_TO (32 bits).
# Leave it for the catalog to compute from the slice bounds.
if {[catch {generate_target all $p24_cell} p24_gen_err]} {
  p24_fail "generate_target div_gen_xlslice_0_0: $p24_gen_err"
}
puts "P24_SUBIP_OK div_gen_xlslice_0_0 $p24_vlnv"

puts "P24_SUBIP_BEGIN rot_lut"
p24_remove_ip rot_lut
set p24_vlnv [p24_resolve_vlnv {xilinx.com:ip:blk_mem_gen:8.4}]
create_ip -vlnv $p24_vlnv -module_name rot_lut
set p24_cell [get_ips rot_lut]
set p24_coe [file join $::env(P24_OFDM_ROOT) ip_repo/rot_lut/rot_lut.coe]
if {![file exists $p24_coe]} {
  p24_fail "missing coefficient file $p24_coe"
}
p24_set_dict $p24_cell \
  Memory_Type {Dual_Port_ROM} \
  Assume_Synchronous_Clk {true} \
  Enable_A {Always_Enabled} \
  Enable_B {Always_Enabled} \
  Load_Init_File {true} \
  Coe_File [file normalize $p24_coe] \
  Port_A_Write_Rate {0} \
  Port_B_Clock {100} \
  Port_B_Enable_Rate {100} \
  Read_Width_A {32} \
  Read_Width_B {32} \
  Register_PortA_Output_of_Memory_Primitives {false} \
  Register_PortB_Output_of_Memory_Primitives {false} \
  Write_Depth_A {512} \
  Write_Width_A {32} \
  Write_Width_B {32}
set p24_enb [get_property CONFIG.Enable_B $p24_cell]
set p24_reg [get_property CONFIG.Register_PortB_Output_of_Memory_Primitives $p24_cell]
puts "P24_ROT_LUT Enable_B=$p24_enb Register_PortB=$p24_reg"
if {$p24_enb ne "Always_Enabled"} {
  p24_fail "Enable_B readback is $p24_enb"
}
if {$p24_reg ne "false" && $p24_reg ne "0"} {
  p24_fail "Register_PortB readback is $p24_reg"
}
if {[catch {generate_target all $p24_cell} p24_gen_err]} {
  p24_fail "generate_target rot_lut: $p24_gen_err"
}
puts "P24_SUBIP_OK rot_lut $p24_vlnv"

puts "P24_SUBIP_BEGIN viterbi_v7_0"
p24_remove_ip viterbi_v7_0
set p24_vlnv [p24_resolve_vlnv {xilinx.com:ip:viterbi:9.1}]
create_ip -vlnv $p24_vlnv -module_name viterbi_v7_0
set p24_cell [get_ips viterbi_v7_0]
p24_set_dict $p24_cell \
  ACLKEN {true} \
  BER_Symbol_Count {false} \
  Best_State {true} \
  Convolution0_Code0 {1011011} \
  Convolution0_Code1 {1111001} \
  Convolution_Code_0_Radix {Binary} \
  Puncturing {External} \
  Reduced_Latency {true} \
  TREADY {false} \
  Traceback_Length {84}
if {[catch {generate_target all $p24_cell} p24_gen_err]} {
  p24_fail "generate_target viterbi_v7_0: $p24_gen_err"
}
puts "P24_SUBIP_OK viterbi_v7_0 $p24_vlnv"

puts "P24_SUBIP_BEGIN xfft_v9"
p24_remove_ip xfft_v9
set p24_vlnv [p24_resolve_vlnv {xilinx.com:ip:xfft:9.1}]
create_ip -vlnv $p24_vlnv -module_name xfft_v9
set p24_cell [get_ips xfft_v9]
p24_set_dict $p24_cell \
  implementation_options {pipelined_streaming_io} \
  aresetn {true} \
  complex_mult_type {use_mults_resources} \
  number_of_stages_using_block_ram_for_data_and_phase_factors {0} \
  output_ordering {natural_order} \
  scaling_options {unscaled} \
  target_clock_frequency {200} \
  transform_length {64}
if {[catch {generate_target all $p24_cell} p24_gen_err]} {
  p24_fail "generate_target xfft_v9: $p24_gen_err"
}
puts "P24_SUBIP_OK xfft_v9 $p24_vlnv"

set p24_rot [get_ips rot_lut]
set p24_xci [get_property IP_FILE $p24_rot]
set p24_xci_dir [file dirname $p24_xci]
set p24_proj [get_property DIRECTORY [current_project]]
set p24_wrap {}
foreach p24_rel {sim/rot_lut.v sim/rot_lut.vhd synth/rot_lut.v synth/rot_lut.vhd} {
  set p24_p [file join $p24_xci_dir $p24_rel]
  if {[file exists $p24_p]} { lappend p24_wrap $p24_p }
}
foreach p24_p [glob -nocomplain \
    [file join $p24_proj openofdm_rx.gen sources_1 ip rot_lut sim rot_lut.v] \
    [file join $p24_proj openofdm_rx.gen sources_1 ip rot_lut sim rot_lut.vhd] \
    [file join $p24_proj openofdm_rx.gen sources_1 ip rot_lut synth rot_lut.v] \
    [file join $p24_proj openofdm_rx.gen sources_1 ip rot_lut synth rot_lut.vhd]] {
  lappend p24_wrap $p24_p
}
if {[llength $p24_wrap] == 0} {
  p24_fail "no rot_lut wrapper after generate_target"
}
set p24_checked 0
foreach p24_p $p24_wrap {
  set p24_fh [open $p24_p r]
  set p24_body [read $p24_fh]
  close $p24_fh
  set p24_enb_has [regexp {C_HAS_ENB\s*(\(|=>|=)\s*[01]} $p24_body]
  set p24_reg_has [regexp {C_HAS_MEM_OUTPUT_REGS_B\s*(\(|=>|=)\s*[01]} $p24_body]
  if {!$p24_enb_has || !$p24_reg_has} {
    puts "P24_ROT_LUT_SKIP_NO_GENERIC $p24_p"
    continue
  }
  if {[regexp {C_HAS_ENB\s*(\(|=>|=)\s*1} $p24_body] || [regexp {C_HAS_MEM_OUTPUT_REGS_B\s*(\(|=>|=)\s*1} $p24_body]} {
    p24_fail "wrapper $p24_p has C_HAS_ENB=1 or C_HAS_MEM_OUTPUT_REGS_B=1"
  }
  puts "P24_ROT_LUT_WRAPPER_OK $p24_p"
  incr p24_checked
}
if {$p24_checked == 0} {
  p24_fail "wrappers exist but none contain C_HAS_ENB"
}
puts "P24_ROT_LUT_OK checked=$p24_checked"

