# ============================================================
# create_axi_project.tcl — Synthesise and implement axi_top
#
# Usage (from rv32i-core root):
#   vivado -mode batch -source vivado/create_axi_project.tcl
# Or: Vivado GUI -> Tools -> Run Tcl Script
#
# Top module : axi_top  (rtl/axi_top.v)
# Device     : xc7a100tcsg324-1  (Nexys A7 / Nexys4 DDR)
# Clock      : 80 MHz (12.5 ns) on port clk
#
# I/O note: axi_top exposes AXI4-Lite buses and debug ports.
# Only clk and rst_n are assigned to physical pins; all other
# ports are left unconstrained (DRC errors downgraded to
# warnings) so that implementation completes and gives accurate
# post-route timing and area numbers.
# ============================================================

set PROJ_NAME  rv32i_axi
set PROJ_DIR   [file normalize [file dirname [info script]]/$PROJ_NAME]
set RTL_DIR    [file normalize [file dirname [info script]]/../rtl]
set PART       xc7a100tcsg324-1

puts "=== Creating AXI project at $PROJ_DIR ==="
create_project $PROJ_NAME $PROJ_DIR -part $PART -force

# -- RTL sources (all of rtl/) ------------------------------------------------
add_files -norecurse [glob $RTL_DIR/*.v]
set_property top axi_top [current_fileset]
update_compile_order -fileset sources_1

# -- Constraints: clock + reset only ------------------------------------------
# AXI ports are left unplaced; unconstrained-IO DRC errors are
# downgraded to warnings so implementation can complete.
set xdc_path $PROJ_DIR/axi_clk.xdc
set fp [open $xdc_path w]
puts $fp {## Clock — 80 MHz on Nexys4 DDR (E3)}
puts $fp {set_property PACKAGE_PIN E3 [get_ports clk]}
puts $fp {set_property IOSTANDARD LVCMOS33 [get_ports clk]}
puts $fp {create_clock -add -name sys_clk_pin -period 12.50 -waveform {0 6.25} [get_ports clk]}
puts $fp {}
puts $fp {## Reset — BTNC on Nexys4 DDR (N17)}
puts $fp {set_property PACKAGE_PIN N17 [get_ports rst_n]}
puts $fp {set_property IOSTANDARD LVCMOS33 [get_ports rst_n]}
puts $fp {}
puts $fp {## Suppress unconstrained-IO DRC errors for AXI/debug ports}
puts $fp {set_property SEVERITY {Warning} [get_drc_checks NSTD-1]}
puts $fp {set_property SEVERITY {Warning} [get_drc_checks UCIO-1]}
close $fp

add_files -fileset constrs_1 -norecurse $xdc_path
puts "  -> constraints written to $xdc_path"

# -- Synthesis ----------------------------------------------------------------
puts "=== Running synthesis ==="
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    error "Synthesis failed!"
}
open_run synth_1
report_utilization -file $PROJ_DIR/post_synth_utilization.rpt
puts "  -> post_synth_utilization.rpt written"

# -- Implementation -----------------------------------------------------------
puts "=== Running implementation (Performance_ExplorePostRoutePhysOpt) ==="
set_property strategy Performance_ExplorePostRoutePhysOpt [get_runs impl_1]
set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED                true               [get_runs impl_1]
set_property STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE            AggressiveExplore  [get_runs impl_1]
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED     true               [get_runs impl_1]
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.ARGS.DIRECTIVE AggressiveExplore  [get_runs impl_1]

launch_runs impl_1 -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    error "Implementation failed!"
}
open_run impl_1

# -- Reports ------------------------------------------------------------------
puts "=== Writing reports ==="
report_timing_summary  -file $PROJ_DIR/timing_summary.rpt     -warn_on_violation
report_utilization     -file $PROJ_DIR/utilization.rpt
report_power           -file $PROJ_DIR/power.rpt

puts ""
puts "============================================================"
puts " DONE.  Reports in $PROJ_DIR:"
puts "   timing_summary.rpt        <- WNS / achieved frequency"
puts "   utilization.rpt           <- LUT / FF / BRAM counts"
puts "   post_synth_utilization.rpt"
puts "   power.rpt"
puts "============================================================"
