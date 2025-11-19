`timescale 1ns/1ps
`default_nettype none

module div_rasterizer #(
    parameter int FRACTIONAL_WIDTH = 16
)(
    input  logic         aclk,
    input  logic         aresetn,

    // Divisor stream (signed 64-bit)
    input  logic         s_axis_divisor_tvalid,
    output logic         s_axis_divisor_tready,
    input  logic [63:0]  s_axis_divisor_tdata,

    // Dividend stream (signed 64-bit)
    input  logic         s_axis_dividend_tvalid,
    output logic         s_axis_dividend_tready,
    input  logic [63:0]  s_axis_dividend_tdata,

    // Result stream
    output logic         m_axis_dout_tvalid,
    input  logic         m_axis_dout_tready,
    output logic [0:0]   m_axis_dout_tuser,    // [0] = divide-by-zero
    output logic [87:0]  m_axis_dout_tdata
);

    // -------------------------
    // Independent input latches
    // -------------------------
    logic signed [63:0] lat_dividend;
    logic               lat_dividend_v;

    logic signed [63:0] lat_divisor;
    logic               lat_divisor_v;

    // Accept whenever the channel's latch is free
    assign s_axis_dividend_tready = !lat_dividend_v;
    assign s_axis_divisor_tready  = !lat_divisor_v;

    // -------------------------
    // Single-result output regs
    // -------------------------
    logic               out_valid;
    logic               out_dbz;
    logic signed [80:0] out_result;  // 81-bit signed (integer + fraction)

    // Pack to 88 bits with sign extension (Vivado layout)
    assign m_axis_dout_tvalid = out_valid;
    assign m_axis_dout_tuser  = out_dbz;
    assign m_axis_dout_tdata  = { {7{out_result[80]}}, out_result };

    // -------------------------
    // Combinational 128-bit math
    // -------------------------
    logic               calc_dbz;
    logic signed [127:0] calc_num, calc_den, calc_q, calc_q_emit;
    logic signed [80:0]  calc_out81;

    always_comb begin
        // Defaults
        calc_dbz    = 1'b0;
        calc_num    = '0;
        calc_den    = '0;
        calc_q      = '0;
        calc_q_emit = '0;
        calc_out81  = '0;

        if (lat_dividend_v && lat_divisor_v) begin
            if (lat_divisor == 0) begin
                calc_dbz = 1'b1;
            end else begin
                // Q64.17 internally: floor((dividend << FRACTIONAL_WIDTH)/divisor)
                calc_num = {{64{lat_dividend[63]}}, lat_dividend};
                calc_num = calc_num <<< FRACTIONAL_WIDTH;
                calc_den = {{64{lat_divisor[63]}},  lat_divisor};
                calc_q   = calc_num / calc_den; // trunc toward 0 per SV
            end
        end

        // Result to emit is just the computed quotient
        calc_q_emit = calc_q;

        // Truncate to 81-bit signed like the IP packing
        calc_out81 = calc_q_emit[80:0];
    end

    // -------------------------
    // Sequencing (nonblocking <=)
    // -------------------------
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            lat_dividend_v <= 1'b0;
            lat_divisor_v  <= 1'b0;
            lat_dividend   <= '0;
            lat_divisor    <= '0;

            out_valid      <= 1'b0;
            out_dbz        <= 1'b0;
            out_result     <= '0;
        end else begin
            // Latch inputs independently
            if (s_axis_dividend_tvalid && s_axis_dividend_tready) begin
                lat_dividend   <= $signed(s_axis_dividend_tdata);
                lat_dividend_v <= 1'b1;
            end
            if (s_axis_divisor_tvalid && s_axis_divisor_tready) begin
                lat_divisor   <= $signed(s_axis_divisor_tdata);
                lat_divisor_v <= 1'b1;
            end

            // Output handshake
            if (out_valid) begin
                if (m_axis_dout_tready) begin
                    out_valid <= 1'b0;  // consumed
                end
            end else begin
                // No result pending → if both operands ready, compute and present
                if (lat_dividend_v && lat_divisor_v) begin
                    out_dbz    <= calc_dbz;
                    out_result <= calc_out81;
                    out_valid  <= 1'b1;

                    // consume the latched operands
                    lat_dividend_v <= 1'b0;
                    lat_divisor_v  <= 1'b0;
                end
            end
        end
    end

endmodule

`default_nettype wire
