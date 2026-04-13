## ============================================================
## nexys4.xdc — Constraints for synthesis_top on Nexys4 DDR
## Device: xc7a100tcsg324-1  (63,400 LUTs — fits cache arrays)
## ============================================================

## 80 MHz system clock (Fmax ~80.6 MHz after timing optimisations)
set_property PACKAGE_PIN E3  [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
create_clock -add -name sys_clk_pin -period 12.50 -waveform {0 6.25} [get_ports clk]

## Reset — BTNC (active HIGH; synthesis_top inverts to rst_n)
set_property PACKAGE_PIN N17 [get_ports btn_rst]
set_property IOSTANDARD LVCMOS33 [get_ports btn_rst]

## LEDs LD0-LD15
set_property PACKAGE_PIN H17 [get_ports {leds[0]}]
set_property PACKAGE_PIN K15 [get_ports {leds[1]}]
set_property PACKAGE_PIN J13 [get_ports {leds[2]}]
set_property PACKAGE_PIN N14 [get_ports {leds[3]}]
set_property PACKAGE_PIN R18 [get_ports {leds[4]}]
set_property PACKAGE_PIN V17 [get_ports {leds[5]}]
set_property PACKAGE_PIN U17 [get_ports {leds[6]}]
set_property PACKAGE_PIN U16 [get_ports {leds[7]}]
set_property PACKAGE_PIN V16 [get_ports {leds[8]}]
set_property PACKAGE_PIN T15 [get_ports {leds[9]}]
set_property PACKAGE_PIN U14 [get_ports {leds[10]}]
set_property PACKAGE_PIN T16 [get_ports {leds[11]}]
set_property PACKAGE_PIN V15 [get_ports {leds[12]}]
set_property PACKAGE_PIN V14 [get_ports {leds[13]}]
set_property PACKAGE_PIN V12 [get_ports {leds[14]}]
set_property PACKAGE_PIN V11 [get_ports {leds[15]}]
set_property IOSTANDARD LVCMOS33 [get_ports {leds[*]}]
