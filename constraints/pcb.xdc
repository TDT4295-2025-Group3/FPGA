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

## SRAM Left
set_property -dict { PACKAGE_PIN T14 IOSTANDARD LVCMOS33 } [get_ports { sram_l_addr[0] }]
set_property -dict { PACKAGE_PIN P13 IOSTANDARD LVCMOS33 } [get_ports { sram_l_addr[1] }]
set_property -dict { PACKAGE_PIN R13 IOSTANDARD LVCMOS33 } [get_ports { sram_l_addr[2] }]
set_property -dict { PACKAGE_PIN T13 IOSTANDARD LVCMOS33 } [get_ports { sram_l_addr[3] }]
set_property -dict { PACKAGE_PIN N12 IOSTANDARD LVCMOS33 } [get_ports { sram_l_addr[4] }]
set_property -dict { PACKAGE_PIN R12 IOSTANDARD LVCMOS33 } [get_ports { sram_l_addr[5] }]
set_property -dict { PACKAGE_PIN T12 IOSTANDARD LVCMOS33 } [get_ports { sram_l_addr[6] }]
set_property -dict { PACKAGE_PIN P11 IOSTANDARD LVCMOS33 } [get_ports { sram_l_addr[7] }]
set_property -dict { PACKAGE_PIN R11 IOSTANDARD LVCMOS33 } [get_ports { sram_l_addr[8] }]
set_property -dict { PACKAGE_PIN M6 IOSTANDARD LVCMOS33 } [get_ports { sram_l_addr[9] }]
set_property -dict { PACKAGE_PIN R6 IOSTANDARD LVCMOS33 } [get_ports { sram_l_addr[10] }]
set_property -dict { PACKAGE_PIN P6 IOSTANDARD LVCMOS33 } [get_ports { sram_l_addr[11] }]
set_property -dict { PACKAGE_PIN T5 IOSTANDARD LVCMOS33 } [get_ports { sram_l_addr[12] }]
set_property -dict { PACKAGE_PIN R5 IOSTANDARD LVCMOS33 } [get_ports { sram_l_addr[13] }]
set_property -dict { PACKAGE_PIN N6 IOSTANDARD LVCMOS33 } [get_ports { sram_l_addr[14] }]
set_property -dict { PACKAGE_PIN K12 IOSTANDARD LVCMOS33 } [get_ports { sram_l_addr[15] }]
set_property -dict { PACKAGE_PIN L14 IOSTANDARD LVCMOS33 } [get_ports { sram_l_addr[16] }]
set_property -dict { PACKAGE_PIN M16 IOSTANDARD LVCMOS33 } [get_ports { sram_l_addr[17] }]
set_property -dict { PACKAGE_PIN L13 IOSTANDARD LVCMOS33 } [get_ports { sram_l_addr[18] }]
set_property -dict { PACKAGE_PIN M14 IOSTANDARD LVCMOS33 } [get_ports { sram_l_addr[19] }]
set_property -dict { PACKAGE_PIN R7 IOSTANDARD LVCMOS33 } [get_ports { sram_l_addr[20] }]

set_property -dict { PACKAGE_PIN N13 IOSTANDARD LVCMOS33 } [get_ports { sram_l_dq[0] }]
set_property -dict { PACKAGE_PIN R15 IOSTANDARD LVCMOS33 } [get_ports { sram_l_dq[1] }]
set_property -dict { PACKAGE_PIN R16 IOSTANDARD LVCMOS33 } [get_ports { sram_l_dq[2] }]
set_property -dict { PACKAGE_PIN P14 IOSTANDARD LVCMOS33 } [get_ports { sram_l_dq[3] }]
set_property -dict { PACKAGE_PIN P15 IOSTANDARD LVCMOS33 } [get_ports { sram_l_dq[4] }]
set_property -dict { PACKAGE_PIN P16 IOSTANDARD LVCMOS33 } [get_ports { sram_l_dq[5] }]
set_property -dict { PACKAGE_PIN N14 IOSTANDARD LVCMOS33 } [get_ports { sram_l_dq[6] }]
set_property -dict { PACKAGE_PIN M12 IOSTANDARD LVCMOS33 } [get_ports { sram_l_dq[7] }]
set_property -dict { PACKAGE_PIN T7 IOSTANDARD LVCMOS33 } [get_ports { sram_l_dq[8] }]
set_property -dict { PACKAGE_PIN P8 IOSTANDARD LVCMOS33 } [get_ports { sram_l_dq[9] }]
set_property -dict { PACKAGE_PIN R8 IOSTANDARD LVCMOS33 } [get_ports { sram_l_dq[10] }]
set_property -dict { PACKAGE_PIN T8 IOSTANDARD LVCMOS33 } [get_ports { sram_l_dq[11] }]
set_property -dict { PACKAGE_PIN N9 IOSTANDARD LVCMOS33 } [get_ports { sram_l_dq[12] }]
set_property -dict { PACKAGE_PIN P9 IOSTANDARD LVCMOS33 } [get_ports { sram_l_dq[13] }]
set_property -dict { PACKAGE_PIN T9 IOSTANDARD LVCMOS33 } [get_ports { sram_l_dq[14] }]
set_property -dict { PACKAGE_PIN P10 IOSTANDARD LVCMOS33 } [get_ports { sram_l_dq[15] }]

set_property -dict { PACKAGE_PIN N16 IOSTANDARD LVCMOS33 } [get_ports { sram_l_we_n }]
set_property -dict { PACKAGE_PIN T15 IOSTANDARD LVCMOS33 } [get_ports { sram_l_cs_n }]
set_property -dict { PACKAGE_PIN N11 IOSTANDARD LVCMOS33 } [get_ports { sram_l_oe_n }]
set_property -dict { PACKAGE_PIN T10 IOSTANDARD LVCMOS33 } [get_ports { sram_l_ub_n }]
set_property -dict { PACKAGE_PIN R10 IOSTANDARD LVCMOS33 } [get_ports { sram_l_lb_n }]

## SRAM Right
set_property -dict { PACKAGE_PIN A13 IOSTANDARD LVCMOS33 } [get_ports { sram_r_addr[0] }]
set_property -dict { PACKAGE_PIN E12 IOSTANDARD LVCMOS33 } [get_ports { sram_r_addr[1] }]
set_property -dict { PACKAGE_PIN C14 IOSTANDARD LVCMOS33 } [get_ports { sram_r_addr[2] }]
set_property -dict { PACKAGE_PIN A14 IOSTANDARD LVCMOS33 } [get_ports { sram_r_addr[3] }]
set_property -dict { PACKAGE_PIN B14 IOSTANDARD LVCMOS33 } [get_ports { sram_r_addr[4] }]
set_property -dict { PACKAGE_PIN D14 IOSTANDARD LVCMOS33 } [get_ports { sram_r_addr[5] }]
set_property -dict { PACKAGE_PIN A15 IOSTANDARD LVCMOS33 } [get_ports { sram_r_addr[6] }]
set_property -dict { PACKAGE_PIN B15 IOSTANDARD LVCMOS33 } [get_ports { sram_r_addr[7] }]
set_property -dict { PACKAGE_PIN E13 IOSTANDARD LVCMOS33 } [get_ports { sram_r_addr[8] }]
set_property -dict { PACKAGE_PIN H12 IOSTANDARD LVCMOS33 } [get_ports { sram_r_addr[9] }]
set_property -dict { PACKAGE_PIN H16 IOSTANDARD LVCMOS33 } [get_ports { sram_r_addr[10] }]
set_property -dict { PACKAGE_PIN H14 IOSTANDARD LVCMOS33 } [get_ports { sram_r_addr[11] }]
set_property -dict { PACKAGE_PIN H13 IOSTANDARD LVCMOS33 } [get_ports { sram_r_addr[12] }]
set_property -dict { PACKAGE_PIN J16 IOSTANDARD LVCMOS33 } [get_ports { sram_r_addr[13] }]
set_property -dict { PACKAGE_PIN J15 IOSTANDARD LVCMOS33 } [get_ports { sram_r_addr[14] }]
set_property -dict { PACKAGE_PIN C8 IOSTANDARD LVCMOS33 } [get_ports { sram_r_addr[15] }]
set_property -dict { PACKAGE_PIN A8 IOSTANDARD LVCMOS33 } [get_ports { sram_r_addr[16] }]
set_property -dict { PACKAGE_PIN D8 IOSTANDARD LVCMOS33 } [get_ports { sram_r_addr[17] }]
set_property -dict { PACKAGE_PIN D9 IOSTANDARD LVCMOS33 } [get_ports { sram_r_addr[18] }]
set_property -dict { PACKAGE_PIN A9 IOSTANDARD LVCMOS33 } [get_ports { sram_r_addr[19] }]
set_property -dict { PACKAGE_PIN G12 IOSTANDARD LVCMOS33 } [get_ports { sram_r_addr[20] }]

set_property -dict { PACKAGE_PIN B12 IOSTANDARD LVCMOS33 } [get_ports { sram_r_dq[0] }]
set_property -dict { PACKAGE_PIN A12 IOSTANDARD LVCMOS33 } [get_ports { sram_r_dq[1] }]
set_property -dict { PACKAGE_PIN C11 IOSTANDARD LVCMOS33 } [get_ports { sram_r_dq[2] }]
set_property -dict { PACKAGE_PIN B11 IOSTANDARD LVCMOS33 } [get_ports { sram_r_dq[3] }]
set_property -dict { PACKAGE_PIN E11 IOSTANDARD LVCMOS33 } [get_ports { sram_r_dq[4] }]
set_property -dict { PACKAGE_PIN B10 IOSTANDARD LVCMOS33 } [get_ports { sram_r_dq[5] }]
set_property -dict { PACKAGE_PIN A10 IOSTANDARD LVCMOS33 } [get_ports { sram_r_dq[6] }]
set_property -dict { PACKAGE_PIN C9 IOSTANDARD LVCMOS33 } [get_ports { sram_r_dq[7] }]
set_property -dict { PACKAGE_PIN G16 IOSTANDARD LVCMOS33 } [get_ports { sram_r_dq[8] }]
set_property -dict { PACKAGE_PIN G14 IOSTANDARD LVCMOS33 } [get_ports { sram_r_dq[9] }]
set_property -dict { PACKAGE_PIN F14 IOSTANDARD LVCMOS33 } [get_ports { sram_r_dq[10] }]
set_property -dict { PACKAGE_PIN F15 IOSTANDARD LVCMOS33 } [get_ports { sram_r_dq[11] }]
set_property -dict { PACKAGE_PIN F13 IOSTANDARD LVCMOS33 } [get_ports { sram_r_dq[12] }]
set_property -dict { PACKAGE_PIN E16 IOSTANDARD LVCMOS33 } [get_ports { sram_r_dq[13] }]
set_property -dict { PACKAGE_PIN F12 IOSTANDARD LVCMOS33 } [get_ports { sram_r_dq[14] }]
set_property -dict { PACKAGE_PIN D16 IOSTANDARD LVCMOS33 } [get_ports { sram_r_dq[15] }]

set_property -dict { PACKAGE_PIN B9 IOSTANDARD LVCMOS33 } [get_ports { sram_r_we_n }]
set_property -dict { PACKAGE_PIN D11 IOSTANDARD LVCMOS33 } [get_ports { sram_r_cs_n }]
set_property -dict { PACKAGE_PIN B16 IOSTANDARD LVCMOS33 } [get_ports { sram_r_oe_n }]
set_property -dict { PACKAGE_PIN C16 IOSTANDARD LVCMOS33 } [get_ports { sram_r_ub_n }]
set_property -dict { PACKAGE_PIN D15 IOSTANDARD LVCMOS33 } [get_ports { sram_r_lb_n }]
