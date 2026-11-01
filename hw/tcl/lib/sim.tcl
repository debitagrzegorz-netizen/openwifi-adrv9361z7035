# Simulation entry. The CDC bench is added when the post-hold delays exist.

proc hw::stage_sim {which} {
  if {$which ne "cdc"} {
    hw::fail "unknown simulation '$which'"
  }
  hw::fail "P24_SIM_CDC is not in this run yet. Phase B adds the bench under logs/p24-s1 after the post-hold checkpoints exist."
}
