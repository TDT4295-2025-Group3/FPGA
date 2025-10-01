## FPGA Configuration I/O Options
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]

## Board Clock: 100 MHz
set_property -dict {PACKAGE_PIN E3 IOSTANDARD LVCMOS33} [get_ports {clk_100m}]
create_clock -name clk_100m -period 10.00 [get_ports {clk_100m}]

## Pixel and Render clocks are asynchronous
## Use regex so this matches both _unbuf and buffered nets
set_clock_groups -name AsyncPixRender -asynchronous \
    -group [get_clocks -quiet -regexp {.*clk_pix.*}] \
    -group [get_clocks -quiet -regexp {.*clk_render.*}]

## Also mark false paths explicitly between domains
set_false_path -from [get_clocks -quiet -regexp {.*clk_pix.*}]    -to [get_clocks -quiet -regexp {.*clk_render.*}]
set_false_path -from [get_clocks -quiet -regexp {.*clk_render.*}] -to [get_clocks -quiet -regexp {.*clk_pix.*}]

## Mark synchronizer flip-flops to help timing and placement
set_property ASYNC_REG TRUE [get_cells -hier -regexp {.*frame_pix_sync1_reg.*}]
set_property ASYNC_REG TRUE [get_cells -hier -regexp {.*frame_pix_sync2_reg.*}]

## Buttons
set_property -dict {PACKAGE_PIN C2 IOSTANDARD LVCMOS33} [get_ports {btn_rst_n}]

## VGA Pmod on Header JB/JC
set_property -dict {PACKAGE_PIN U14 IOSTANDARD LVCMOS33} [get_ports {vga_hsync}]
set_property -dict {PACKAGE_PIN V14 IOSTANDARD LVCMOS33} [get_ports {vga_vsync}]
set_property -dict {PACKAGE_PIN E15 IOSTANDARD LVCMOS33} [get_ports {vga_r[0]}]
set_property -dict {PACKAGE_PIN E16 IOSTANDARD LVCMOS33} [get_ports {vga_r[1]}]
set_property -dict {PACKAGE_PIN D15 IOSTANDARD LVCMOS33} [get_ports {vga_r[2]}]
set_property -dict {PACKAGE_PIN C15 IOSTANDARD LVCMOS33} [get_ports {vga_r[3]}]
set_property -dict {PACKAGE_PIN U12 IOSTANDARD LVCMOS33} [get_ports {vga_g[0]}]
set_property -dict {PACKAGE_PIN V12 IOSTANDARD LVCMOS33} [get_ports {vga_g[1]}]
set_property -dict {PACKAGE_PIN V10 IOSTANDARD LVCMOS33} [get_ports {vga_g[2]}]
set_property -dict {PACKAGE_PIN V11 IOSTANDARD LVCMOS33} [get_ports {vga_g[3]}]
set_property -dict {PACKAGE_PIN J17 IOSTANDARD LVCMOS33} [get_ports {vga_b[0]}]
set_property -dict {PACKAGE_PIN J18 IOSTANDARD LVCMOS33} [get_ports {vga_b[1]}]
set_property -dict {PACKAGE_PIN K15 IOSTANDARD LVCMOS33} [get_ports {vga_b[2]}]
set_property -dict {PACKAGE_PIN J15 IOSTANDARD LVCMOS33} [get_ports {vga_b[3]}]
