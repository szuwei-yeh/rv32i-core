## ============================================================
## basys3.xdc — Constraints for synthesis_top on Basys3
## Device: xc7a35tcpg236-1
## ============================================================

## 100 MHz system clock
set_property PACKAGE_PIN W5  [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports clk]

## Reset — BTNC (active HIGH; synthesis_top inverts to rst_n)
set_property PACKAGE_PIN T18 [get_ports btn_rst]
set_property IOSTANDARD LVCMOS33 [get_ports btn_rst]

## LEDs LD0-LD15
set_property PACKAGE_PIN U16 [get_ports {leds[0]}]
set_property PACKAGE_PIN E19 [get_ports {leds[1]}]
set_property PACKAGE_PIN U19 [get_ports {leds[2]}]
set_property PACKAGE_PIN V19 [get_ports {leds[3]}]
set_property PACKAGE_PIN W18 [get_ports {leds[4]}]
set_property PACKAGE_PIN U15 [get_ports {leds[5]}]
set_property PACKAGE_PIN U14 [get_ports {leds[6]}]
set_property PACKAGE_PIN V14 [get_ports {leds[7]}]
set_property PACKAGE_PIN V13 [get_ports {leds[8]}]
set_property PACKAGE_PIN V3  [get_ports {leds[9]}]
set_property PACKAGE_PIN W3  [get_ports {leds[10]}]
set_property PACKAGE_PIN U3  [get_ports {leds[11]}]
set_property PACKAGE_PIN P3  [get_ports {leds[12]}]
set_property PACKAGE_PIN N3  [get_ports {leds[13]}]
set_property PACKAGE_PIN P1  [get_ports {leds[14]}]
set_property PACKAGE_PIN L1  [get_ports {leds[15]}]
set_property IOSTANDARD LVCMOS33 [get_ports {leds[*]}]
