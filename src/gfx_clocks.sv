`default_nettype none
`timescale 1ns / 1ps

// Generate 25.2 MHz (VGA 640x480 @ 60 Hz) and ~40 MHz render clock
// from a 100 MHz input
module gfx_clocks (
    input  wire logic clk_100m,     // input clock (100 MHz)
    input  wire logic rst,          // async reset (active-high)
    output      logic clk_pix,      // ~25.2 MHz VGA pixel clock
    output      logic clk_render,   // ~40.0 MHz render clock
    output      logic clk_locked,   // PLL lock
    output      logic rst_pix,      // synchronous reset to clk_pix (active-high)
    output      logic rst_render    // synchronous reset to clk_render (active-high)
);

    localparam real IN_PERIOD   = 10.0;   // ns (100 MHz)
    localparam real MULT_MASTER = 31.5;   // VCO multiplier
    localparam int  DIV_MASTER  = 5;      // VCO pre-divider

    // Derived VCO frequency: 100 MHz * 31.5 / 5 = 630 MHz

    // Output divides:
    // 630 / 25   = 25.2 MHz  (pixel clock)
    // 630 / 16   = 39.375 MHz (render clock, integer divide)
    localparam real DIV_PIX    = 25.0;
    localparam int  DIV_RENDER_INT = 16;

    logic vco_fb;
    logic clk_pix_unbuf, clk_render_unbuf;

    MMCME2_BASE #(
        .CLKIN1_PERIOD(IN_PERIOD),
        .CLKFBOUT_MULT_F(MULT_MASTER),
        .DIVCLK_DIVIDE(DIV_MASTER),

        .CLKOUT0_DIVIDE_F(DIV_PIX),
        .CLKOUT1_DIVIDE(DIV_RENDER_INT),
        .CLKOUT2_DIVIDE(1)
    ) mmcm_inst (
        .CLKIN1   (clk_100m),
        .RST      (rst),
        .CLKFBIN  (vco_fb),
        .CLKFBOUT (vco_fb),

        .CLKOUT0  (clk_pix_unbuf),
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

    BUFG bufg_pix    (.I(clk_pix_unbuf),    .O(clk_pix));
    BUFG bufg_render (.I(clk_render_unbuf), .O(clk_render));

    // Per-domain synchronous resets (async assert, sync release)
    // Assert when external rst is high OR MMCM not locked.
    wire arst_n_common = clk_locked & ~rst;  // active-low for synchronizers

    (* ASYNC_REG = "TRUE" *) logic pix_ff1, pix_ff2;
    always_ff @(posedge clk_pix or negedge arst_n_common) begin
        if (!arst_n_common) begin
            pix_ff1 <= 1'b0;
            pix_ff2 <= 1'b0;
        end else begin
            pix_ff1 <= 1'b1;
            pix_ff2 <= pix_ff1;
        end
    end
    assign rst_pix = ~pix_ff2;

    (* ASYNC_REG = "TRUE" *) logic ren_ff1, ren_ff2;
    always_ff @(posedge clk_render or negedge arst_n_common) begin
        if (!arst_n_common) begin
            ren_ff1 <= 1'b0;
            ren_ff2 <= 1'b0;
        end else begin
            ren_ff1 <= 1'b1;
            ren_ff2 <= ren_ff1;
        end
    end
    assign rst_render = ~ren_ff2;

endmodule
