`default_nettype none
module divu #(
    parameter int WIDTH = 8,   // total result width (integer+fraction)
    parameter int FBITS = 4    // fractional bits in the result
) (
    input  wire logic                clk,    // clock
    input  wire logic                rst,    // reset (sync)
    input  wire logic                start,  // start calculation (pulse when idle)
    output      logic                busy,   // calculation in progress
    output      logic                done,   // 1-cycle pulse when complete
    output      logic                valid,  // result is valid (latched on done)
    output      logic                dbz,    // divide by zero flag (1-cycle on start if b==0)
    output      logic                ovf,    // overflow flag (never fires in this minimal impl)
    input  wire logic [WIDTH-1:0]    a,      // dividend (numerator), treated as unsigned
    input  wire logic [WIDTH-1:0]    b,      // divisor  (denominator), unsigned
    output      logic [WIDTH-1:0]    val     // quotient in Q( WIDTH-FBITS . FBITS )
);

    // Number of shift/sub iterations: integer part (WIDTH bits from 'a') + FBITS fractional zeros.
    localparam int ITER   = WIDTH + FBITS;
    localparam int IWIDTH = (ITER > 0) ? $clog2(ITER) : 1;

    // State
    logic [WIDTH-1:0]   a_latched;          // latch 'a' on start so it can change upstream
    logic [WIDTH-1:0]   b1;                 // latched divisor
    logic [WIDTH:0]     acc;                // accumulator (remainder), WIDTH+1
    logic [WIDTH-1:0]   quo;                // running quotient
    logic [IWIDTH-1:0]  i;                  // iteration counter

    // Synchronous FSM
    always_ff @(posedge clk or posedge rst) begin
        // default strobes
        done  <= 1'b0;

        if (rst) begin
            busy      <= 1'b0;
            valid     <= 1'b0;
            dbz       <= 1'b0;
            ovf       <= 1'b0;
            val       <= '0;
            a_latched <= '0;
            b1        <= '0;
            acc       <= '0;
            quo       <= '0;
            i         <= '0;

        end else begin
            if (start && !busy) begin
                // kick off a new division
                valid     <= 1'b0;
                done      <= 1'b0;
                ovf       <= 1'b0;          // minimal implementation: never asserts
                dbz       <= 1'b0;

                if (b == '0) begin
                    // divide-by-zero -> finish immediately with zero result
                    busy      <= 1'b0;
                    done      <= 1'b1;
                    dbz       <= 1'b1;
                    val       <= '0;
                    // leave other regs don't-care
                end else begin
                    busy      <= 1'b1;
                    a_latched <= a;
                    b1        <= b;
                    acc       <= '0;
                    quo       <= '0;
                    i         <= '0;
                end

            end else if (busy) begin
                // ----- One restoring-division iteration -----
                // Shift in next dividend bit (MSB-first), then compare/subtract.
                logic next_bit;
                logic [WIDTH:0]   acc_sh;
                logic [WIDTH-1:0] quo_sh;
                logic             ge;
                logic [WIDTH:0]   acc_sub;
                logic [WIDTH-1:0] quo_new;

                // Feed MSB of 'a' for the first WIDTH iterations, then zeros for FBITS frac bits
                if (i < WIDTH)           next_bit = a_latched[WIDTH-1 - i];
                else if (i < ITER)       next_bit = 1'b0;
                else                     next_bit = 1'b0;

                // Fixed shifts (wire re-indexing), no barrel shifters
                acc_sh = {acc[WIDTH-1:0], next_bit};
                quo_sh = {quo[WIDTH-2:0], 1'b0};

                // Single compare and (conditional) subtract
                ge      = (acc_sh >= {1'b0, b1});
                acc_sub = acc_sh - {1'b0, b1};
                acc     <= ge ? acc_sub : acc_sh;
                quo_new = ge ? {quo_sh[WIDTH-2:0], 1'b1}
                             : {quo_sh[WIDTH-2:0], 1'b0};
                quo     <= quo_new;

                // Advance / finish
                if (i == ITER-1) begin
                    busy  <= 1'b0;
                    done  <= 1'b1;
                    valid <= 1'b1;
                    val   <= quo_new;    // final quotient (Q with FBITS fractional bits)
                end
                i <= i + 1'b1;
            end
        end
    end

endmodule
