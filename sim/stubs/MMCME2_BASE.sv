`timescale 1ns/1ps

module MMCME2_BASE #(
    parameter real    CLKFBOUT_MULT_F   = 31.5,
    parameter real    CLKIN1_PERIOD     = 10.0,
    parameter real    CLKOUT0_DIVIDE_F  = 25.0,
    parameter integer CLKOUT1_DIVIDE    = 40,
    parameter integer CLKOUT2_DIVIDE    = 1,
    parameter integer DIVCLK_DIVIDE     = 5,
    parameter integer LOCK_DELAY_CYCLES = 64
) (
    input  wire CLKIN1,
    input  wire RST,
    output wire CLKOUT0,
    output wire CLKOUT1,
    output wire LOCKED,
    output wire CLKFBOUT,
    input  wire CLKFBIN,
    output wire CLKOUT0B, CLKOUT1B, CLKOUT2, CLKOUT2B,
    output wire CLKOUT3, CLKOUT3B, CLKOUT4, CLKOUT5, CLKOUT6,
    output wire CLKFBOUTB, PWRDWN
);

    // ---------------- tie-offs ----------------
    assign {CLKOUT0B, CLKOUT1B, CLKOUT2, CLKOUT2B,
            CLKOUT3, CLKOUT3B, CLKOUT4, CLKOUT5, CLKOUT6,
            CLKFBOUTB, PWRDWN} = '0;
    assign CLKFBOUT = 1'b0;

    // ---------------- lock generation ----------------
    logic        locked_q = 1'b0;
    logic [31:0] lock_cnt = '0;
    assign LOCKED = locked_q;

    // ---------------- simple clock divider ----------------
    logic        clkout0_q = 1'b0;
    logic        clkout1_q = 1'b0;
    assign CLKOUT0 = clkout0_q;
    assign CLKOUT1 = clkout1_q;

    // crude NCO-ish divider: just approximate frequency scaling
    always_ff @(posedge CLKIN1 or posedge RST) begin
        if (RST) begin
            locked_q  <= 1'b0;
            lock_cnt  <= '0;
            clkout0_q <= 1'b0;
            clkout1_q <= 1'b0;
        end else begin
            if (!locked_q) begin
                lock_cnt <= lock_cnt + 1;
                if (lock_cnt >= LOCK_DELAY_CYCLES) locked_q <= 1'b1;
            end else begin
                clkout0_q <= ~clkout0_q;   // toy model
                clkout1_q <= ~clkout1_q;   // not frequency-accurate
            end
        end
    end
endmodule
