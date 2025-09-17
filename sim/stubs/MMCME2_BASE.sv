`default_nettype none
`timescale 1ns/1ps

module MMCME2_BASE #(
    parameter real    CLKFBOUT_MULT_F   = 31.5, // VCO mult
    parameter real    CLKIN1_PERIOD     = 10.0, // ns (100 MHz)
    parameter real    CLKOUT0_DIVIDE_F  = 5.0,  // often 5x pixel (unused here)
    parameter integer CLKOUT1_DIVIDE    = 25,   // pixel: VCO/25 ≈ 25.2 MHz
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
    output wire CLKOUT0B, CLKOUT1B, CLKOUT2, CLKOUT2B, CLKOUT3, CLKOUT3B,
    output wire CLKOUT4, CLKOUT5, CLKOUT6, CLKFBOUTB, PWRDWN
);

    // -------------------- tie-offs --------------------
    assign {CLKOUT0B, CLKOUT1B, CLKOUT2, CLKOUT2B, CLKOUT3, CLKOUT3B,
            CLKOUT4, CLKOUT5, CLKOUT6, CLKFBOUTB, PWRDWN} = '0;
    assign CLKFBOUT = 1'b0;

    // -------------------- lock generation --------------------
    logic        locked_q = 1'b0;
    logic [31:0] lock_cnt = '0;
    assign LOCKED = locked_q;

    // -------------------- NCO for fractional division --------------------
    // We’ll generate CLKOUT1 accurately; CLKOUT0 is unused in your top, keep low.
    logic        clkout1_q = 1'b0;
    assign CLKOUT1 = clkout1_q;
    assign CLKOUT0 = 1'b0;  // not needed by your design

    // 32-bit phase accumulator
    logic [31:0] acc1 = 32'h0000_0000;
    logic [31:0] inc1 = 32'h0000_0000; // 2^32 * (fout/fin)

    // Compute increment from parameters at time 0
    // fin  = 1000 / CLKIN1_PERIOD (MHz)   (same units as in your original stub)
    // fout = fin * (CLKFBOUT_MULT_F / (DIVCLK_DIVIDE * CLKOUT1_DIVIDE))
    initial begin
        real fin_mhz  = 1000.0 / CLKIN1_PERIOD;
        real fout_mhz = fin_mhz * (CLKFBOUT_MULT_F / (DIVCLK_DIVIDE * CLKOUT1_DIVIDE));
        real ratio    = fout_mhz / fin_mhz;            // fout/fin
        real inc_real = ratio * 4294967296.0;          // 2^32 * ratio
        int unsigned inc_int = (inc_real < 0.0) ? 0 : (inc_real > 4294967295.0 ? 32'hFFFF_FFFF : int'(inc_real));
        inc1 = inc_int[31:0];
    end

    // Single clocked process: handle reset, lock, and NCO
    always_ff @(posedge CLKIN1 or posedge RST) begin
        if (RST) begin
            locked_q <= 1'b0;
            lock_cnt <= '0;
            acc1     <= '0;
            clkout1_q<= 1'b0;
        end else begin
            if (!locked_q) begin
                lock_cnt <= lock_cnt + 1;
                if (lock_cnt >= LOCK_DELAY_CYCLES) begin
                    locked_q <= 1'b1;
                end
                acc1      <= '0;
                clkout1_q <= 1'b0;
            end else begin
                // advance NCO and output MSB of next accumulator value
                logic [31:0] nxt1 = acc1 + inc1;
                acc1      <= nxt1;
                clkout1_q <= nxt1[31];
            end
        end
    end
endmodule
