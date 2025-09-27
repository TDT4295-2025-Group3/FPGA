`timescale 1ns / 1ps
`default_nettype none
import rasterizer_pkg::*;
import vertex_pkg::vertex_t;

module triangle_setup #(
    parameter int WIDTH  = 320,
    parameter int HEIGHT = 240
) (
    input  wire logic clk,
    input  wire logic rst,

    input  wire vertex_t v0,
    input  wire vertex_t v1,
    input  wire vertex_t v2,

    input  wire logic    in_valid,
    output logic         in_ready,

    output triangle_state_t out_state,
    output logic            out_valid,
    input  wire logic       out_ready,
    output logic            busy
);

    // FSM states
    typedef enum logic [1:0] {S_IDLE, S_DIV_START, S_DIV_WAIT, S_OUTPUT} state_t;
    state_t state, next_state;

    // Registers for geometry
    triangle_state_t tri_reg;
    logic signed [75:0] denom_comb;   // Q64.12
    logic signed [63:0] denom_q64_0;  // Q64.0 (|denom|) for divider
    logic        denom_neg;

    // Divider interface signals
    logic        div_s_valid, div_s_ready;
    logic [63:0] div_divisor, div_dividend;
    logic        div_m_valid;
    logic [87:0] div_m_data;
    logic        div_m_ready;
    logic        div_dbz;

    // Instance of divider IP (stub in sim)
    div_rasterizer u_div (
        .aclk(clk),
        .aresetn(!rst),
        .s_axis_divisor_tdata (div_divisor),
        .s_axis_divisor_tvalid(div_s_valid),
        .s_axis_divisor_tready(div_s_ready),
        .s_axis_dividend_tdata (div_dividend),
        .s_axis_dividend_tvalid(div_s_valid),
        .s_axis_dividend_tready(/*unused*/),
        .m_axis_dout_tdata  (div_m_data),
        .m_axis_dout_tvalid (div_m_valid),
        .m_axis_dout_tuser  (div_dbz),
        .m_axis_dout_tready (div_m_ready)
    );

    // Handshake outputs
    assign busy      = (state != S_IDLE);
    assign in_ready  = (state == S_IDLE);
    assign out_valid = (state == S_OUTPUT);

    // Divider inputs
    assign div_divisor  = denom_q64_0; // integer |denom| in Q64.0 (see below)
    assign div_dividend = 64'd65536;   // 1.0 in Q0.16 (not used by stub, kept for API symmetry)

    // FSM
    always_ff @(posedge clk or posedge rst) begin
        if (rst) state <= S_IDLE;
        else     state <= next_state;
    end

    always_comb begin
        next_state = state;
        unique case (state)
            S_IDLE:      if (in_valid && in_ready)     next_state = S_DIV_START;
            S_DIV_START: if (div_s_ready)              next_state = S_DIV_WAIT;
            S_DIV_WAIT:  if (div_m_valid)              next_state = S_OUTPUT;
            S_OUTPUT:    if (out_valid && out_ready)   next_state = S_IDLE;
        endcase
    end

    // Drive div_s_valid in S_DIV_START
    assign div_s_valid = (state == S_DIV_START);
    assign div_m_ready = 1'b1; // Always ready to take divider result

    // Registered work
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            tri_reg      <= '0;
            denom_comb   <= '0;
            denom_q64_0  <= '0;
            denom_neg    <= 1'b0;
        end else begin
            if (state == S_IDLE && in_valid && in_ready) begin
                // --- Compute geometry from fresh vertex inputs ---
                // Convert positions to Q16.3
                logic signed [18:0] v0x_n = v0.pos.x[31:13];
                logic signed [18:0] v0y_n = v0.pos.y[31:13];
                logic signed [18:0] v1x_n = v1.pos.x[31:13];
                logic signed [18:0] v1y_n = v1.pos.y[31:13];
                logic signed [18:0] v2x_n = v2.pos.x[31:13];
                logic signed [18:0] v2y_n = v2.pos.y[31:13];

                // Edges in Q16.3
                logic signed [18:0] e0x_n = v1x_n - v0x_n;
                logic signed [18:0] e0y_n = v1y_n - v0y_n;
                logic signed [18:0] e1x_n = v2x_n - v0x_n;
                logic signed [18:0] e1y_n = v2y_n - v0y_n;

                // Dot products in Q32.6
                logic signed [37:0] d00_n = e0x_n*e0x_n + e0y_n*e0y_n;
                logic signed [37:0] d01_n = e0x_n*e1x_n + e0y_n*e1y_n;
                logic signed [37:0] d11_n = e1x_n*e1x_n + e1y_n*e1y_n;

                // denom = d00*d11 - d01*d01  (Q32.6 * Q32.6 = Q64.12)
                logic signed [75:0] denom_comb_n = d00_n*d11_n - d01_n*d01_n; // Q64.12

                // Preserve Q64.12 scaling; create integer |denom| in Q64.0 for the divider by >> 12
                logic signed [75:0] denom_abs_wide = denom_comb_n[75] ? (~denom_comb_n + 1) : denom_comb_n;
                logic signed [63:0] denom_q64_0_n  = denom_abs_wide[75:12]; // arithmetic >>12

                // Latch into triangle state
                tri_reg.v0x <= v0x_n;
                tri_reg.v0y <= v0y_n;
                tri_reg.e0x <= e0x_n;
                tri_reg.e0y <= e0y_n;
                tri_reg.e1x <= e1x_n;
                tri_reg.e1y <= e1y_n;

                tri_reg.d00 <= d00_n;
                tri_reg.d01 <= d01_n;
                tri_reg.d11 <= d11_n;

                denom_comb  <= denom_comb_n;
                denom_q64_0 <= denom_q64_0_n;
                denom_neg   <= denom_comb_n[75]; // sign of full Q64.12 (should be 0 for valid tri)

                // Fill bbox/colors/depths
                tri_reg.bbox_min_x <= clamp(min3(v0.pos.x, v1.pos.x, v2.pos.x) >>> 16, 0, WIDTH-1);
                tri_reg.bbox_max_x <= clamp((max3(v0.pos.x, v1.pos.x, v2.pos.x) + 32'hFFFF) >>> 16, 0, WIDTH-1);
                tri_reg.bbox_min_y <= clamp(min3(v0.pos.y, v1.pos.y, v2.pos.y) >>> 16, 0, HEIGHT-1);
                tri_reg.bbox_max_y <= clamp((max3(v0.pos.y, v1.pos.y, v2.pos.y) + 32'hFFFF) >>> 16, 0, HEIGHT-1);
                tri_reg.v0_color   <= v0.color;
                tri_reg.v1_color   <= v1.color;
                tri_reg.v2_color   <= v2.color;
                tri_reg.v0_depth   <= v0.pos.z;
                tri_reg.v1_depth   <= v1.pos.z;
                tri_reg.v2_depth   <= v2.pos.z;
            end

            if (state == S_DIV_WAIT && div_m_valid) begin
                // Grab reciprocal result: divider returns Q1.15 in div_m_data[15:0]
                // Convert to Q0.16 by appending a zero LSB.
                tri_reg.denom_inv <= div_m_data[16:0]; // Q0.16 (captured directly)
                tri_reg.denom_neg <= denom_neg;
                 $display("[%0t] denom=%0d raw_div=%0h (%0d) as real=%f (neg=%b dbz=%b)",
             $time,
             denom_comb,
             div_m_data,
             div_m_data,
             $itor($signed(div_m_data)) / (1<<16),  // interpret as Q1.16
             denom_neg,
             div_dbz);
            end
        end
    end

    // Output state register (combinational expose of tri_reg is fine)
    assign out_state = tri_reg;

endmodule
