# ============================================================
# create_project.tcl
# Usage (from rv32i-core root):
#   vivado -mode batch -source vivado/create_project.tcl
# Or open Vivado GUI → Tools → Run Tcl Script → select this file
# ============================================================

set PROJ_NAME  rv32i_core
set PROJ_DIR   [file normalize [file dirname [info script]]/$PROJ_NAME]
set RTL_DIR    [file normalize [file dirname [info script]]/../rtl]
set FPGA_DIR   [file normalize [file dirname [info script]]/../fpga]
set PART       xc7a35tcpg236-1

puts "=== Creating Vivado project at $PROJ_DIR ==="
create_project $PROJ_NAME $PROJ_DIR -part $PART -force

# ── Add all RTL sources ──────────────────────────────────────
add_files -norecurse [glob $RTL_DIR/*.v]
set_property top synthesis_top [current_fileset]
update_compile_order -fileset sources_1

# ── Add constraints ──────────────────────────────────────────
add_files -fileset constrs_1 -norecurse $FPGA_DIR/basys3.xdc

# ── Synthesis ────────────────────────────────────────────────
puts "=== Running synthesis ==="
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    error "Synthesis failed!"
}
open_run synth_1
report_utilization -file $PROJ_DIR/post_synth_utilization.rpt
puts "  → post_synth_utilization.rpt written"

# ── Implementation ───────────────────────────────────────────
puts "=== Running implementation ==="
launch_runs impl_1 -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    error "Implementation failed!"
}
open_run impl_1

# ── Reports ──────────────────────────────────────────────────
puts "=== Writing reports ==="
report_timing_summary  -file $PROJ_DIR/timing_summary.rpt       -warn_on_violation
report_utilization     -file $PROJ_DIR/utilization.rpt
report_power           -file $PROJ_DIR/power.rpt

puts ""
puts "============================================================"
puts " DONE.  Check these files in $PROJ_DIR:"
puts "   timing_summary.rpt   ← WNS / achieved frequency"
puts "   utilization.rpt      ← LUT / FF / BRAM counts"
puts "   power.rpt            ← estimated power"
puts "============================================================"
