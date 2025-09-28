`timescale 1ns/1ps
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

    typedef enum logic [2:0] {S_IDLE, S_DOT, S_DENOM, S_DIV_START, S_DIV_WAIT, S_OUTPUT} state_t;
    state_t state, next_state;

    // Pipeline registers
    triangle_state_t tri_reg;

    // Q16.3 vertex coords and edges
    logic signed [18:0] v0x_r, v0y_r, v1x_r, v1y_r, v2x_r, v2y_r;
    logic signed [18:0] e0x_r, e0y_r, e1x_r, e1y_r;

    // Q32.6 dot products
    logic signed [37:0] d00_r, d01_r, d11_r;

    // Denominator pipeline
    logic signed [75:0] denom_q64_12_r;
    logic               denom_neg_r;
    logic        [63:0] denom_q64_0_r;

    // Vertex input temporaries
    wire signed [31:0] v0x_tmp, v1x_tmp, v2x_tmp;
    wire signed [31:0] v0y_tmp, v1y_tmp, v2y_tmp;

    assign v0x_tmp = v0.pos.x;
    assign v1x_tmp = v1.pos.x;
    assign v2x_tmp = v2.pos.x;
    assign v0y_tmp = v0.pos.y;
    assign v1y_tmp = v1.pos.y;
    assign v2y_tmp = v2.pos.y;

    // Denominator temps
    logic signed [75:0] denom_tmp;
    logic signed [75:0] denom_abs;

    // BBox temporaries
    logic [15:0] minx, maxx, miny, maxy;

    // Divider interface
    logic        div_s_valid;
    logic [63:0] div_divisor, div_dividend;
    logic        div_divisor_tready, div_dividend_tready;
    logic [87:0] div_m_data;
    logic        div_m_valid, div_m_ready;

    assign div_divisor  = denom_q64_0_r;
    assign div_dividend = 64'd65536; // 1 << 16
    assign div_m_ready  = 1'b1;

    div_rasterizer u_div (
        .aclk                   (clk),
        .aresetn                (!rst),
        .s_axis_divisor_tdata   (div_divisor),
        .s_axis_divisor_tvalid  (div_s_valid),
        .s_axis_divisor_tready  (div_divisor_tready),
        .s_axis_dividend_tdata  (div_dividend),
        .s_axis_dividend_tvalid (div_s_valid),
        .s_axis_dividend_tready (div_dividend_tready),
        .m_axis_dout_tdata      (div_m_data),
        .m_axis_dout_tvalid     (div_m_valid),
        .m_axis_dout_tready     (div_m_ready),
        .m_axis_dout_tuser      () // unused
    );

    // Control signals
    assign busy      = (state != S_IDLE);
    assign in_ready  = (state == S_IDLE);
    assign out_valid = (state == S_OUTPUT);

    always_ff @(posedge clk or posedge rst) begin
        if (rst) state <= S_IDLE;
        else     state <= next_state;
    end

    always_comb begin
        next_state  = state;
        div_s_valid = 1'b0;
        unique case (state)
            S_IDLE:       if (in_valid && in_ready) next_state = S_DOT;
            S_DOT:        next_state = S_DENOM;
            S_DENOM:      next_state = S_DIV_START;
            S_DIV_START: begin
                div_s_valid = 1'b1;
                if (div_divisor_tready && div_dividend_tready)
                    next_state = S_DIV_WAIT;
            end
            S_DIV_WAIT:   if (div_m_valid) next_state = S_OUTPUT;
            S_OUTPUT:     if (out_ready)   next_state = S_IDLE;
            default:      next_state = S_IDLE;
        endcase
    end

    assign denom_tmp = (d00_r*d11_r) - (d01_r*d01_r);

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            tri_reg <= '0;
            v0x_r <= '0; v0y_r <= '0; v1x_r <= '0; v1y_r <= '0; v2x_r <= '0; v2y_r <= '0;
            e0x_r <= '0; e0y_r <= '0; e1x_r <= '0; e1y_r <= '0;
            d00_r <= '0; d01_r <= '0; d11_r <= '0;
            denom_q64_12_r <= '0;
            denom_q64_0_r  <= '0;
            denom_neg_r    <= 1'b0;
            minx <= '0; maxx <= '0; miny <= '0; maxy <= '0;
        end else begin
            case (state)
                S_IDLE: if (in_valid && in_ready) begin
                    v0x_r <= v0x_tmp[31:13]; v0y_r <= v0y_tmp[31:13];
                    v1x_r <= v1x_tmp[31:13]; v1y_r <= v1y_tmp[31:13];
                    v2x_r <= v2x_tmp[31:13]; v2y_r <= v2y_tmp[31:13];

                    // Colors / depths
                    tri_reg.v0_color <= v0.color;
                    tri_reg.v1_color <= v1.color;
                    tri_reg.v2_color <= v2.color;
                    tri_reg.v0_depth <= v0.pos.z;
                    tri_reg.v1_depth <= v1.pos.z;
                    tri_reg.v2_depth <= v2.pos.z;

                    // Bounding box
                    minx <= (v0x_tmp < v1x_tmp) ? ((v0x_tmp < v2x_tmp) ? v0x_tmp[31:16] : v2x_tmp[31:16])
                                                : ((v1x_tmp < v2x_tmp) ? v1x_tmp[31:16] : v2x_tmp[31:16]);
                    maxx <= (v0x_tmp > v1x_tmp) ? ((v0x_tmp > v2x_tmp) ? v0x_tmp[31:16] : v2x_tmp[31:16])
                                                : ((v1x_tmp > v2x_tmp) ? v1x_tmp[31:16] : v2x_tmp[31:16]);
                    miny <= (v0y_tmp < v1y_tmp) ? ((v0y_tmp < v2y_tmp) ? v0y_tmp[31:16] : v2y_tmp[31:16])
                                                : ((v1y_tmp < v2y_tmp) ? v1y_tmp[31:16] : v2y_tmp[31:16]);
                    maxy <= (v0y_tmp > v1y_tmp) ? ((v0y_tmp > v2y_tmp) ? v0y_tmp[31:16] : v2y_tmp[31:16])
                                                : ((v1y_tmp > v2y_tmp) ? v1y_tmp[31:16] : v2y_tmp[31:16]);

                    tri_reg.bbox_min_x <= (minx > (WIDTH-1))  ? WIDTH-1  : minx;
                    tri_reg.bbox_max_x <= (maxx > (WIDTH-1))  ? WIDTH-1  : maxx;
                    tri_reg.bbox_min_y <= (miny > (HEIGHT-1)) ? HEIGHT-1 : miny;
                    tri_reg.bbox_max_y <= (maxy > (HEIGHT-1)) ? HEIGHT-1 : maxy;

                    e0x_r <= v1x_r - v0x_r;  e0y_r <= v1y_r - v0y_r;
                    e1x_r <= v2x_r - v0x_r;  e1y_r <= v2y_r - v0y_r;

                    tri_reg.v0x <= v0x_r;
                    tri_reg.v0y <= v0y_r;
                end

                S_DOT: begin
                    d00_r <= e0x_r*e0x_r + e0y_r*e0y_r;
                    d01_r <= e0x_r*e1x_r + e0y_r*e1y_r;
                    d11_r <= e1x_r*e1x_r + e1y_r*e1y_r;

                    tri_reg.e0x <= e0x_r; tri_reg.e0y <= e0y_r;
                    tri_reg.e1x <= e1x_r; tri_reg.e1y <= e1y_r;
                end

                S_DENOM: begin
                    denom_q64_12_r <= denom_tmp;
                    denom_neg_r    <= denom_tmp[75];
                    denom_abs      <= denom_tmp[75] ? (~denom_tmp + 1'b1) : denom_tmp;
                    denom_q64_0_r  <= denom_abs[75:12];

                    tri_reg.d00 <= d00_r;
                    tri_reg.d01 <= d01_r;
                    tri_reg.d11 <= d11_r;
                end

                S_DIV_WAIT: if (div_m_valid) begin
                    tri_reg.denom_inv <= div_m_data[16:1]; // Q0.16
                    tri_reg.denom_neg <= denom_neg_r;
                end

                default: ;
            endcase
        end
    end

    assign out_state = tri_reg;

endmodule

`default_nettype wire
