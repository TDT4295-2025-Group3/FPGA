`default_nettype none
`timescale 1ns / 1ps

// Generate 25.2 MHz (VGA 640x480 @ 60 Hz) and ~40 MHz render clock
// from a 100 MHz input
module gfx_clocks_spi (
    input  wire logic clk_100m,     // input clock (100 MHz)
    input  wire logic rst,          // async reset
    output      logic sck,          // ~10 MHz serial clock
    output      logic clk_render,   // ~40.0 MHz render clock
    output      logic clk_locked    // PLL lock
);

    localparam real IN_PERIOD   = 10.0;   // ns (100 MHz)
    localparam real MULT_MASTER = 31.5;   // VCO multiplier
    localparam int  DIV_MASTER  = 5;      // VCO pre-divider

    // Derived VCO frequency: 100 MHz * 31.5 / 5 = 630 MHz

    // Output divides:
    // 630 / 63   = 10.0 MHz  (pixel clock)
    // 630 / 15.75 ≈ 40.0 MHz (render clock, using fractional)
    localparam real DIV_SCK    = 63.0;
    localparam real DIV_RENDER = 15.75;

    logic vco_fb;
    logic sck_unbuf, clk_render_unbuf;

    MMCME2_BASE #(
        .CLKIN1_PERIOD(IN_PERIOD),
        .CLKFBOUT_MULT_F(MULT_MASTER),
        .DIVCLK_DIVIDE(DIV_MASTER),

        .CLKOUT0_DIVIDE_F(DIV_SCK),       // fractional OK
        .CLKOUT1_DIVIDE(16),              // integer only → ~39.375 MHz
        .CLKOUT2_DIVIDE(1)                // unused
    ) mmcm_inst (
        .CLKIN1   (clk_100m),
        .RST      (rst),
        .CLKFBIN  (vco_fb),
        .CLKFBOUT (vco_fb),

        .CLKOUT0  (sck_unbuf),
        .CLKOUT1  (clk_render_unbuf),

        .LOCKED   (clk_locked),

        /* verilator lint_off PINCONNECTEMPTY */
        .CLKOUT0B (), .CLKOUT1B (),
        .CLKOUT2  (), .CLKOUT2B (),
        .CLKOUT3  (), .CLKOUT3B (),
        .CLKOUT4  (), .CLKOUT5  (), .CLKOUT6  (),
        .CLKFBOUTB(), .PWRDWN()
        /* verilator lint_on PINCONNECTEMPTY */
    );

    BUFG bufg_sck    (.I(sck_unbuf),        .O(sck));
    BUFG bufg_render (.I(clk_render_unbuf), .O(clk_render));

endmodule
