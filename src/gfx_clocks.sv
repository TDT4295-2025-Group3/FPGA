// `default_nettype none
// `timescale 1ns / 1ps

// // Generate 40 MHz and 100 MHz from 25.175 MHz input
// module gfx_clocks (
//     input  wire logic clk_pix,  // 25.175 MHz input clock
//     input  wire logic rst,            // async reset (active-high)
//     output      logic clk_render,     // ~40.0 MHz render clock
//     output      logic clk_100m,       // ~100.0 MHz system clock
//     output      logic clk_locked,     // PLL lock
//     output      logic rst_render,     // sync reset to clk_render
//     output      logic rst_100m        // sync reset to clk_100m
// );

//     // Input clock period (ns)
//     localparam real IN_PERIOD = 39.73; // 1 / 25.175 MHz ≈ 39.73 ns

//     // MMCM configuration
//     localparam real MULT_MASTER = 79.5;  // VCO multiplier
//     localparam int  DIV_MASTER  = 2;     // input divider
//     // Derived VCO: 25.175 * 79.5 / 2 = 999.20625 MHz

//     localparam real DIV_RENDER = 24.98;  // 999.2 / 24.98 ≈ 40.0 MHz
//     localparam real DIV_SYS    = 10.0;   // 999.2 / 10.0 ≈ 100.0 MHz

//     logic vco_fb;
//     logic clk_render_unbuf, clk_100m_unbuf;

//     MMCME2_BASE #(
//         .CLKIN1_PERIOD(IN_PERIOD),
//         .CLKFBOUT_MULT_F(MULT_MASTER),
//         .DIVCLK_DIVIDE(DIV_MASTER),

//         .CLKOUT0_DIVIDE_F(DIV_RENDER),
//         .CLKOUT1_DIVIDE(DIV_SYS)
//     ) mmcm_inst (
//         .CLKIN1   (clk_pix),
//         .RST      (rst),
//         .CLKFBIN  (vco_fb),
//         .CLKFBOUT (vco_fb),

//         .CLKOUT0  (clk_render_unbuf),
//         .CLKOUT1  (clk_100m_unbuf),

//         .LOCKED   (clk_locked),

//         /* verilator lint_off PINCONNECTEMPTY */
//         .CLKOUT0B (), .CLKOUT1B (),
//         .CLKOUT2  (), .CLKOUT2B (),
//         .CLKOUT3  (), .CLKOUT3B (),
//         .CLKOUT4  (), .CLKOUT5  (), .CLKOUT6  (),
//         .CLKFBOUTB(), .PWRDWN()
//         /* verilator lint_on PINCONNECTEMPTY */
//     );

//     BUFG bufg_render (.I(clk_render_unbuf), .O(clk_render));
//     BUFG bufg_sys    (.I(clk_100m_unbuf),    .O(clk_100m));

//     // Per-domain synchronous resets
//     wire arst_n_common = clk_locked & ~rst;

//     (* ASYNC_REG = "TRUE" *) logic ren_ff1, ren_ff2;
//     always_ff @(posedge clk_render or negedge arst_n_common) begin
//         if (!arst_n_common) begin
//             ren_ff1 <= 0; ren_ff2 <= 0;
//         end else begin
//             ren_ff1 <= 1; ren_ff2 <= ren_ff1;
//         end
//     end
//     assign rst_render = ~ren_ff2;

//     (* ASYNC_REG = "TRUE" *) logic sys_ff1, sys_ff2;
//     always_ff @(posedge clk_100m or negedge arst_n_common) begin
//         if (!arst_n_common) begin
//             sys_ff1 <= 0; sys_ff2 <= 0;
//         end else begin
//             sys_ff1 <= 1; sys_ff2 <= sys_ff1;
//         end
//     end
//     assign rst_100m = ~sys_ff2;

// endmodule

`default_nettype none
`timescale 1ns / 1ps

// Generate ~40 MHz and ~100 MHz from 25.175 MHz input
module gfx_clocks (
    input  wire logic clk_pix,   // 25.175 MHz input clock
    input  wire logic rst,       // async reset (active-high)

    output      logic clk_render, // ~40.0 MHz render clock
    output      logic clk_100m,   // ~100.0 MHz system clock
    output      logic clk_locked, // MMCM lock indicator

    output      logic rst_render, // sync reset to clk_render
    output      logic rst_100m    // sync reset to clk_100m
);

    // Input clock period (ns) for 25.175 MHz
    // 1e3 / 25.175 ≈ 39.72 ns
    localparam real IN_PERIOD   = 39.72;

    // MMCM configuration
    // VCO = Fin * M / D = 25.175 * 35.75 / 1 ≈ 900.00625 MHz
    localparam real MULT_MASTER = 35.75; // CLKFBOUT_MULT_F (0.125-step)
    localparam int  DIV_MASTER  = 1;     // DIVCLK_DIVIDE

    // Output clocks:
    // clk_render ≈ 900.00625 / 22.5 ≈ 40.0003 MHz
    // clk_100m   ≈ 900.00625 / 9   ≈ 100.0007 MHz
    localparam real DIV_RENDER  = 22.5; // CLKOUT0_DIVIDE_F (0.125-step)
    localparam int  DIV_SYS     = 9;    // CLKOUT1_DIVIDE (integer)

    logic vco_fb;
    logic clk_render_unbuf;
    logic clk_100m_unbuf;

    MMCME2_BASE #(
        .BANDWIDTH("OPTIMIZED"),
        .CLKIN1_PERIOD     (IN_PERIOD),
        .CLKFBOUT_MULT_F   (MULT_MASTER),
        .DIVCLK_DIVIDE     (DIV_MASTER),

        .CLKOUT0_DIVIDE_F  (DIV_RENDER),
        .CLKOUT0_PHASE     (0.0),

        .CLKOUT1_DIVIDE    (DIV_SYS),
        .CLKOUT1_PHASE     (0.0),

        // Leave other outputs unused with default divides
        .CLKOUT2_DIVIDE    (1),
        .CLKOUT2_PHASE     (0.0),
        .CLKOUT3_DIVIDE    (1),
        .CLKOUT3_PHASE     (0.0),
        .CLKOUT4_DIVIDE    (1),
        .CLKOUT4_PHASE     (0.0),
        .CLKOUT5_DIVIDE    (1),
        .CLKOUT5_PHASE     (0.0),
        .CLKOUT6_DIVIDE    (1),
        .CLKOUT6_PHASE     (0.0)
    ) mmcm_inst (
        .CLKIN1   (clk_pix),
        .RST      (rst),

        .CLKFBIN  (vco_fb),
        .CLKFBOUT (vco_fb),

        .CLKOUT0  (clk_render_unbuf),
        .CLKOUT1  (clk_100m_unbuf),

        .LOCKED   (clk_locked),

        // Unused ports
        .CLKOUT0B (),
        .CLKOUT1B (),
        .CLKOUT2  (), .CLKOUT2B (),
        .CLKOUT3  (), .CLKOUT3B (),
        .CLKOUT4  (), .CLKOUT5  (), .CLKOUT6  (),
        .CLKFBOUTB(),
        .PWRDWN   ()
    );

    // Global buffers for generated clocks
    BUFG bufg_render (.I(clk_render_unbuf), .O(clk_render));
    BUFG bufg_sys    (.I(clk_100m_unbuf),   .O(clk_100m));

    // Common async reset (active-low) released when MMCM is locked
    wire arst_n_common = clk_locked & ~rst;

    // Per-domain synchronous reset: clk_render
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

    // Per-domain synchronous reset: clk_100m
    (* ASYNC_REG = "TRUE" *) logic sys_ff1, sys_ff2;
    always_ff @(posedge clk_100m or negedge arst_n_common) begin
        if (!arst_n_common) begin
            sys_ff1 <= 1'b0;
            sys_ff2 <= 1'b0;
        end else begin
            sys_ff1 <= 1'b1;
            sys_ff2 <= sys_ff1;
        end
    end
    assign rst_100m = ~sys_ff2;

endmodule
