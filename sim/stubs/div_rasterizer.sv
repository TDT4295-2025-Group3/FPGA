`timescale 1ns/1ps
`default_nettype none

module div_rasterizer (
    input  logic         aclk,
    input  logic         aresetn,

    // Divisor stream
    input  logic [63:0]  s_axis_divisor_tdata,
    input  logic         s_axis_divisor_tvalid,
    output logic         s_axis_divisor_tready,

    // Dividend stream
    input  logic [63:0]  s_axis_dividend_tdata,
    input  logic         s_axis_dividend_tvalid,
    output logic         s_axis_dividend_tready,

    // Result stream
    output logic [87:0]  m_axis_dout_tdata,   // {rem[43:0], quot[43:0]}
    output logic         m_axis_dout_tvalid,
    output logic         m_axis_dout_tuser,   // dbz flag
    input  logic         m_axis_dout_tready
);

    typedef enum logic [1:0] {IDLE, BUSY, OUT} state_t;
    state_t state, nxt;

    logic [63:0] divisor_reg, dividend_reg;
    logic [63:0] quot, rem;
    logic        dbz;

    // Ready when we can accept both streams
    assign s_axis_divisor_tready  = (state == IDLE);
    assign s_axis_dividend_tready = (state == IDLE);

    // Simple 1-cycle compute and 1-cycle output
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            state <= IDLE;
        end else begin
            state <= nxt;
        end
    end

    always_comb begin
        nxt = state;
        unique case (state)
            IDLE: if (s_axis_divisor_tvalid && s_axis_dividend_tvalid) nxt = BUSY;
            BUSY: nxt = OUT;
            OUT:  if (m_axis_dout_tready) nxt = IDLE;
            default: nxt = IDLE;
        endcase

    end

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            divisor_reg <= '0;
            dividend_reg <= '0;
        end else if (state == IDLE && s_axis_divisor_tvalid && s_axis_dividend_tvalid) begin
            divisor_reg  <= s_axis_divisor_tdata;
            dividend_reg <= s_axis_dividend_tdata;
        end
    end

    always_comb begin
        if (divisor_reg == 64'd0) begin
            dbz = 1'b1;
            quot = 64'd0;
            rem  = dividend_reg;
        end else begin
            dbz = 1'b0;
            quot = dividend_reg / divisor_reg;
            rem  = dividend_reg % divisor_reg;
        end
    end

    // Output: {remainder[43:0], quotient[43:0]} — your setup reads quotient[16:0]
    assign m_axis_dout_tdata  = {rem[43:0], quot[43:0]};
    assign m_axis_dout_tvalid = (state == OUT);
    assign m_axis_dout_tuser  = dbz;

endmodule
