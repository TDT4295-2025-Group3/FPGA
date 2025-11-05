## ===================================================================
## SPI Driver Constraints - Arty A7-100T (XC7A100T-CSG324)
## ===================================================================

## Clock internal: 100 MHz
set_property PACKAGE_PIN E3 [get_ports clk_100m] ; # IO_L12P_T1_MRCC_35 
set_property IOSTANDARD LVCMOS33 [get_ports clk_100m]
create_clock -period 10.0 [get_ports clk_100m] ; # 100 MHz

## Clock external (sclk)
set_property PACKAGE_PIN F4 [get_ports sck] ; # L16  IO_L3N_T0_DQS_EMCCLK_14
set_property IOSTANDARD LVCMOS33 [get_ports sck]
create_clock -period 100.0 [get_ports sck] ; # 10 MHz

# Ignore timing for specific async CDC paths from SPI driver to frame/raster logic
set_false_path -from [get_pins u_spi_driver/max_inst_reg[0]/C] -to [get_pins u_frame_driver/max_inst_sync_0_reg[0]/D]
set_false_path -from [get_pins u_spi_driver/max_inst_reg[1]/C] -to [get_pins u_frame_driver/max_inst_sync_0_reg[1]/D]
set_false_path -from [get_pins u_spi_driver/max_inst_reg[2]/C] -to [get_pins u_frame_driver/max_inst_sync_0_reg[2]/D]
set_false_path -from [get_pins u_spi_driver/max_inst_reg[3]/C] -to [get_pins u_frame_driver/max_inst_sync_0_reg[3]/D]
set_false_path -from [get_pins u_spi_driver/max_inst_reg[4]/C] -to [get_pins u_frame_driver/max_inst_sync_0_reg[4]/D]
set_false_path -from [get_pins u_spi_driver/max_inst_reg[5]/C] -to [get_pins u_frame_driver/max_inst_sync_0_reg[5]/D]
set_false_path -from [get_pins u_spi_driver/max_inst_reg[6]/C] -to [get_pins u_frame_driver/max_inst_sync_0_reg[6]/D]
set_false_path -from [get_pins u_spi_driver/max_inst_reg[7]/C] -to [get_pins u_frame_driver/max_inst_sync_0_reg[7]/D]

set_false_path -from [get_pins u_spi_driver/create_done_reg/C] -to [get_pins u_frame_driver/create_done_sync_0_reg/D]
set_false_path -from [get_pins u_spi_driver/create_done_reg/C] -to [get_pins u_raster_mem/done_sync_0_reg/D]



## Reset Button
## Connected to pushbutton BTN0 on pin C2
set_property -dict { PACKAGE_PIN C2 IOSTANDARD LVCMOS33 } [get_ports rst_n]

## Chip Select 
## Connected to pin JD4 (for testing btn0: D9)
set_property -dict { PACKAGE_PIN F3 IOSTANDARD LVCMOS33 } [get_ports CS_n] ; # JA8

## SPI MOSI lines - PMOD JA header
## JA1=G13, JA2=B11, JA3=A11, JA4=D12
set_property -dict { PACKAGE_PIN G13 IOSTANDARD LVCMOS33 } [get_ports spi_io[0]] ; # JA1
set_property -dict { PACKAGE_PIN B11 IOSTANDARD LVCMOS33 } [get_ports spi_io[1]] ; # JA2
set_property -dict { PACKAGE_PIN A11 IOSTANDARD LVCMOS33 } [get_ports spi_io[2]] ; # JA3
set_property -dict { PACKAGE_PIN D12 IOSTANDARD LVCMOS33 } [get_ports spi_io[3]] ; # JA4


# Pmod Header JB
set_property -dict { PACKAGE_PIN E15   IOSTANDARD LVCMOS33 } [get_ports { tri_id_out[0] }]; #IO_L11P_T1_SRCC_15 Sch=jb_p[1]
set_property -dict { PACKAGE_PIN E16   IOSTANDARD LVCMOS33 } [get_ports { tri_id_out[1] }]; #IO_L11N_T1_SRCC_15 Sch=jb_n[1]
set_property -dict { PACKAGE_PIN D15   IOSTANDARD LVCMOS33 } [get_ports { tri_id_out[2] }]; #IO_L12P_T1_MRCC_15 Sch=jb_p[2]
set_property -dict { PACKAGE_PIN C15   IOSTANDARD LVCMOS33 } [get_ports { tri_id_out[3] }]; #IO_L12N_T1_MRCC_15 Sch=jb_n[2]
set_property -dict { PACKAGE_PIN J17   IOSTANDARD LVCMOS33 } [get_ports { tri_id_out[4] }]; #IO_L23P_T3_FOE_B_15 Sch=jb_p[3]
set_property -dict { PACKAGE_PIN J18   IOSTANDARD LVCMOS33 } [get_ports { tri_id_out[5] }]; #IO_L23N_T3_FWE_B_15 Sch=jb_n[3]
set_property -dict { PACKAGE_PIN K15   IOSTANDARD LVCMOS33 } [get_ports { tri_id_out[6] }]; #IO_L24P_T3_RS1_15 Sch=jb_p[4]
set_property -dict { PACKAGE_PIN J15   IOSTANDARD LVCMOS33 } [get_ports { tri_id_out[7] }]; #IO_L24N_T3_RS0_15 Sch=jb_n[4]



## Pmod Header JB
#set_property -dict { PACKAGE_PIN E15   IOSTANDARD LVCMOS33 } [get_ports { red_1_2[0] }]; #IO_L11P_T1_SRCC_15 Sch=jb_p[1]
#set_property -dict { PACKAGE_PIN E16   IOSTANDARD LVCMOS33 } [get_ports { red_1_2[1] }]; #IO_L11N_T1_SRCC_15 Sch=jb_n[1]
#set_property -dict { PACKAGE_PIN D15   IOSTANDARD LVCMOS33 } [get_ports { red_1_2[2] }]; #IO_L12P_T1_MRCC_15 Sch=jb_p[2]
#set_property -dict { PACKAGE_PIN C15   IOSTANDARD LVCMOS33 } [get_ports { red_1_2[3] }]; #IO_L12N_T1_MRCC_15 Sch=jb_n[2]
#set_property -dict { PACKAGE_PIN J17   IOSTANDARD LVCMOS33 } [get_ports { wait_ctr_out[0] }]; #IO_L23P_T3_FOE_B_15 Sch=jb_p[3]
#set_property -dict { PACKAGE_PIN J18   IOSTANDARD LVCMOS33 } [get_ports { wait_ctr_out[1] }]; #IO_L23N_T3_FWE_B_15 Sch=jb_n[3]
#set_property -dict { PACKAGE_PIN K15   IOSTANDARD LVCMOS33 } [get_ports { wait_ctr_out[2] }]; #IO_L24P_T3_RS1_15 Sch=jb_p[4]
#set_property -dict { PACKAGE_PIN J15   IOSTANDARD LVCMOS33 } [get_ports { wait_ctr_out[3] }]; #IO_L24N_T3_RS0_15 Sch=jb_n[4]

# Pmod Header JC
set_property -dict { PACKAGE_PIN U12   IOSTANDARD LVCMOS33 } [get_ports { spi_status_test[0] }]; #IO_L20P_T3_A08_D24_14 Sch=jc_p[1]
set_property -dict { PACKAGE_PIN V12   IOSTANDARD LVCMOS33 } [get_ports { spi_status_test[1] }]; #IO_L20N_T3_A07_D23_14 Sch=jc_n[1]
set_property -dict { PACKAGE_PIN V10   IOSTANDARD LVCMOS33 } [get_ports { spi_status_test[2] }]; #IO_L21P_T3_DQS_14 Sch=jc_p[2]
set_property -dict { PACKAGE_PIN V11   IOSTANDARD LVCMOS33 } [get_ports { spi_status_test[3] }]; #IO_L21N_T3_DQS_A06_D22_14 Sch=jc_n[2]
set_property -dict { PACKAGE_PIN U14   IOSTANDARD LVCMOS33 } [get_ports { error_status_test[0] }]; #IO_L22P_T3_A05_D21_14 Sch=jc_p[3]
set_property -dict { PACKAGE_PIN V14   IOSTANDARD LVCMOS33 } [get_ports { error_status_test[1] }]; #IO_L22N_T3_A04_D20_14 Sch=jc_n[3]
set_property -dict { PACKAGE_PIN T13   IOSTANDARD LVCMOS33 } [get_ports { error_status_test[2] }]; #IO_L23P_T3_A03_D19_14 Sch=jc_p[4]
set_property -dict { PACKAGE_PIN U13   IOSTANDARD LVCMOS33 } [get_ports { error_status_test[3] }]; #IO_L23N_T3_A02_D18_14 Sch=jc_n[4]

# Pmod Header JD
set_property -dict { PACKAGE_PIN D4    IOSTANDARD LVCMOS33 } [get_ports { CS_ready_out }]; #IO_L11N_T1_SRCC_35 Sch=jd[1]
#set_property -dict { PACKAGE_PIN D3    IOSTANDARD LVCMOS33 } [get_ports { clk_locked_out }]; #IO_L12N_T1_MRCC_35 Sch=jd[2]
#set_property -dict { PACKAGE_PIN     IOSTANDARD LVCMOS33 } [get_ports { sck_out }]; #IO_L13P_T2_MRCC_35 Sch=jd[3]
#set_property -dict { PACKAGE_PIN F3    IOSTANDARD LVCMOS33 } [get_ports { jd[3] }]; #IO_L13N_T2_MRCC_35 Sch=jd[4]
set_property -dict { PACKAGE_PIN E2    IOSTANDARD LVCMOS33 } [get_ports { ready_ctr_out[0] }]; #IO_L14P_T2_SRCC_35 Sch=jd[7]
set_property -dict { PACKAGE_PIN D2    IOSTANDARD LVCMOS33 } [get_ports { ready_ctr_out[1] }]; #IO_L14N_T2_SRCC_35 Sch=jd[8]
set_property -dict { PACKAGE_PIN H2    IOSTANDARD LVCMOS33 } [get_ports { ready_ctr_out[2] }]; #IO_L15P_T2_DQS_35 Sch=jd[9]
set_property -dict { PACKAGE_PIN G2    IOSTANDARD LVCMOS33 } [get_ports { ready_ctr_out[3] }]; #IO_L15N_T2_DQS_35 Sch=jd[10]

# Debug LEDs (optional, onboard LEDs)
# LED0 = H17, LED1 = K15, LED2 = J15, LED3 = G14
set_property -dict { PACKAGE_PIN H5  IOSTANDARD LVCMOS33 } [get_ports output_bit] ; # LED0
set_property -dict { PACKAGE_PIN J5  IOSTANDARD LVCMOS33 } [get_ports rst_test_LED] ; # LED1
#set_property -dict { PACKAGE_PIN T9  IOSTANDARD LVCMOS33 } [get_ports sck_out]  ; # LED2
# set_property -dict { PACKAGE_PIN T10 IOSTANDARD LVCMOS33 } [get_ports inst_valid]   ; # LED3






