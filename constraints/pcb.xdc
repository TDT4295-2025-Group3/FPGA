## FPGA Configuration I/O Options
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]

## Clocks
set_property -dict {PACKAGE_PIN D4 IOSTANDARD LVCMOS33} [get_ports {clk_pix}]
create_clock -name clk_pix -period 39.72 [get_ports {clk_pix}]


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

## Reset (active low)
# set_property -dict {PACKAGE_PIN L9 IOSTANDARD LVCMOS33} [get_ports {rst_n}] 

## VGA
set_property -dict { PACKAGE_PIN L2 IOSTANDARD LVCMOS33 } [get_ports { vga_r[0] }]
set_property -dict { PACKAGE_PIN K3 IOSTANDARD LVCMOS33 } [get_ports { vga_r[1] }]
set_property -dict { PACKAGE_PIN K2 IOSTANDARD LVCMOS33 } [get_ports { vga_r[2] }]
set_property -dict { PACKAGE_PIN K1 IOSTANDARD LVCMOS33 } [get_ports { vga_r[3] }]
set_property -dict { PACKAGE_PIN J3 IOSTANDARD LVCMOS33 } [get_ports { vga_r[4] }]

set_property -dict { PACKAGE_PIN J5 IOSTANDARD LVCMOS33 } [get_ports { vga_g[0] }]
set_property -dict { PACKAGE_PIN J1 IOSTANDARD LVCMOS33 } [get_ports { vga_g[1] }]
set_property -dict { PACKAGE_PIN H3 IOSTANDARD LVCMOS33 } [get_ports { vga_g[2] }]
set_property -dict { PACKAGE_PIN H2 IOSTANDARD LVCMOS33 } [get_ports { vga_g[3] }]
set_property -dict { PACKAGE_PIN H1 IOSTANDARD LVCMOS33 } [get_ports { vga_g[4] }]
set_property -dict { PACKAGE_PIN H5 IOSTANDARD LVCMOS33 } [get_ports { vga_g[5] }]

set_property -dict { PACKAGE_PIN E1 IOSTANDARD LVCMOS33 } [get_ports { vga_b[0] }]
set_property -dict { PACKAGE_PIN F3 IOSTANDARD LVCMOS33 } [get_ports { vga_b[1] }]
set_property -dict { PACKAGE_PIN F2 IOSTANDARD LVCMOS33 } [get_ports { vga_b[2] }]
set_property -dict { PACKAGE_PIN G1 IOSTANDARD LVCMOS33 } [get_ports { vga_b[3] }]
set_property -dict { PACKAGE_PIN G5 IOSTANDARD LVCMOS33 } [get_ports { vga_b[4] }]

set_property -dict { PACKAGE_PIN L3 IOSTANDARD LVCMOS33 } [get_ports { vga_hsync }]
set_property -dict { PACKAGE_PIN K5 IOSTANDARD LVCMOS33 } [get_ports { vga_vsync }]

## SPI
set_property -dict { PACKAGE_PIN A2 IOSTANDARD LVCMOS33 } [get_ports { spi_io[0] }]
set_property -dict { PACKAGE_PIN A3 IOSTANDARD LVCMOS33 } [get_ports { spi_io[1] }]
set_property -dict { PACKAGE_PIN A4 IOSTANDARD LVCMOS33 } [get_ports { spi_io[2] }]
set_property -dict { PACKAGE_PIN A5 IOSTANDARD LVCMOS33 } [get_ports { spi_io[3] }]
# set_property -dict { PACKAGE_PIN E2 IOSTANDARD LVCMOS33 } [get_ports { spi_io[4] }]
# set_property -dict { PACKAGE_PIN D1 IOSTANDARD LVCMOS33 } [get_ports { spi_io[5] }]
# set_property -dict { PACKAGE_PIN C2 IOSTANDARD LVCMOS33 } [get_ports { spi_io[6] }]
# set_property -dict { PACKAGE_PIN C1 IOSTANDARD LVCMOS33 } [get_ports { spi_io[7] }]
set_property -dict { PACKAGE_PIN F5 IOSTANDARD LVCMOS33 } [get_ports { spi_clk } ]
set_property -dict { PACKAGE_PIN B2 IOSTANDARD LVCMOS33 } [get_ports { spi_cs_n } ]

## General Purpose I/O
set_property -dict { PACKAGE_PIN A7 IOSTANDARD LVCMOS33 } [get_ports { gp_io[0] }]
set_property -dict { PACKAGE_PIN B7 IOSTANDARD LVCMOS33 } [get_ports { gp_io[1] }]
set_property -dict { PACKAGE_PIN B6 IOSTANDARD LVCMOS33 } [get_ports { gp_io[2] }]
set_property -dict { PACKAGE_PIN B5 IOSTANDARD LVCMOS33 } [get_ports { gp_io[3] }]
set_property -dict { PACKAGE_PIN C7 IOSTANDARD LVCMOS33 } [get_ports { gp_io[4] }]
set_property -dict { PACKAGE_PIN C6 IOSTANDARD LVCMOS33 } [get_ports { gp_io[5] }]


# Testing
# set_property -dict { PACKAGE_PIN A8 IOSTANDARD LVCMOS33 } [get_ports { output_bit }]