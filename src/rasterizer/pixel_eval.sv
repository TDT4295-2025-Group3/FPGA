`default_nettype none
`timescale 1ns / 1ps

import rasterizer_pkg::*;
import math_pkg::*;
import color_pkg::*;

module pixel_eval #(
    parameter int WIDTH  = 320,
    parameter int HEIGHT = 240
) (
    input  wire logic clk,
    input  wire logic rst,

    input  wire pixel_state_t in_pixel,
    input  wire logic         in_valid,
    output wire logic         in_ready,

    output logic [15:0] out_x,
    output logic [15:0] out_y,
    output color12_t    out_color,
    output q16_16_t     out_depth,
    output logic        out_valid,
    input  wire logic   out_ready,
    output logic        busy
);

    // handshake
    logic s1_ready, s2_ready, s3_ready, s4_ready;
    pixel_eval_stage1_t s1_reg, s1_next;
    pixel_eval_stage2_t s2_reg, s2_next;
    pixel_eval_stage3_t s3_reg, s3_next;
    pixel_output_t      s4_reg, s4_next;

    assign s1_ready = !s1_reg.valid || s2_ready;
    assign s2_ready = !s2_reg.valid || s3_ready;
    assign s3_ready = !s3_reg.valid || s4_ready;
    assign s4_ready = !s4_reg.valid || out_ready;

    assign in_ready = s1_ready;
    assign busy     = s1_reg.valid || s2_reg.valid || s3_reg.valid || s4_reg.valid || out_valid;

    // Stage 1
    logic signed [18:0] e2x, e2y;                 // Q16.3
    logic signed [37:0] d20, d21;                 // Q32.6
    logic signed [75:0] v_num_c, w_num_c, denom_c;// Q64.12

    assign e2x = {in_pixel.x,3'b0} - in_pixel.triangle.v0x;
    assign e2y = {in_pixel.y,3'b0} - in_pixel.triangle.v0y;

    assign d20 = e2x * in_pixel.triangle.e0x + e2y * in_pixel.triangle.e0y;
    assign d21 = e2x * in_pixel.triangle.e1x + e2y * in_pixel.triangle.e1y;

    always_comb begin
        v_num_c  = in_pixel.triangle.d11 * d20 - in_pixel.triangle.d01 * d21; // Q64.12
        w_num_c  = in_pixel.triangle.d00 * d21 - in_pixel.triangle.d01 * d20; // Q64.12
        denom_c  = in_pixel.triangle.d00 * in_pixel.triangle.d11 - in_pixel.triangle.d01 * in_pixel.triangle.d01; // Q64.12

        s1_next.valid      = in_valid;
        s1_next.pixel      = in_pixel;
        s1_next.v_num      = v_num_c;
        s1_next.w_num      = w_num_c;
        s1_next.denom      = denom_c;
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            s1_reg <= '0;
        end else if (s1_ready) begin
            s1_reg <= s1_next;
        end
    end
    
    logic signed [75:0] u_num_c;                  // Q64.12
    always_comb begin
        u_num_c        = s1_reg.denom - s1_reg.v_num - s1_reg.w_num;

        s2_next.valid     = s1_reg.valid;
        s2_next.pixel     = s1_reg.pixel;
        s2_next.v_num     = s1_reg.v_num;
        s2_next.w_num     = s1_reg.w_num;
        s2_next.u_num     = u_num_c;
    end

    // Stage 2 reg
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            s2_reg <= '0;
        end else if (s2_ready) begin
            s2_reg <= s2_next;
        end
    end

    // Stage 3 comb: inside test (sign-aware)
    logic inside_c;
    always_comb begin
        if (s2_reg.pixel.triangle.denom_neg) begin
            inside_c = (s2_reg.v_num <= 0) && (s2_reg.w_num <= 0) && (s2_reg.u_num <= 0);
        end else begin
            inside_c = (s2_reg.v_num >= 0) && (s2_reg.w_num >= 0) && (s2_reg.u_num >= 0);
        end

        s3_next.valid     = s2_reg.valid;
        s3_next.pixel     = s2_reg.pixel;
        s3_next.v_num     = s2_reg.v_num;
        s3_next.w_num     = s2_reg.w_num;
        s3_next.u_num     = s2_reg.u_num;
        s3_next.is_inside = inside_c;
    end

    // Stage 3 reg
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            s3_reg <= '0;
        end else if (s3_ready) begin
            s3_reg <= s3_next;
        end
    end

    // Stage 4 comb: weights, interpolation
    // abs numerators since denom_inv = 1/abs(denom)
    logic signed [75:0] v_num_abs, w_num_abs, u_num_abs; // Q64.12
    logic signed [93:0] v_mul, w_mul, u_mul;             // Q64.12 * Q0.16 = Q64.28
    q16_16_t v_w, w_w, u_w;                              // Q16.16

    always_comb begin
        v_num_abs = s3_reg.pixel.triangle.denom_neg ? -s3_reg.v_num : s3_reg.v_num;
        w_num_abs = s3_reg.pixel.triangle.denom_neg ? -s3_reg.w_num : s3_reg.w_num;
        u_num_abs = s3_reg.pixel.triangle.denom_neg ? -s3_reg.u_num : s3_reg.u_num;

        v_mul = v_num_abs * $signed({1'b0, s3_reg.pixel.triangle.denom_inv}); // Q64.28
        w_mul = w_num_abs * $signed({1'b0, s3_reg.pixel.triangle.denom_inv}); // Q64.28
        u_mul = u_num_abs * $signed({1'b0, s3_reg.pixel.triangle.denom_inv}); // Q64.28

        v_w = q16_16_t'((v_mul + 28'd134217728) >>> 28); // round-to-nearest
        w_w = q16_16_t'((w_mul + 28'd134217728) >>> 28);
        u_w = q16_16_t'(32'h0001_0000) - v_w - w_w;

        s4_next.valid = s3_reg.valid & s3_reg.is_inside;
        s4_next.pixel = s3_reg.pixel;

        if (s3_reg.is_inside) begin
            s4_next.color[11:8] = ((u_w * $unsigned(s3_reg.pixel.triangle.v0_color[11:8])) +
                                 (v_w * $unsigned(s3_reg.pixel.triangle.v1_color[11:8])) +
                                 (w_w * $unsigned(s3_reg.pixel.triangle.v2_color[11:8])) + 32'h0000_8000) >>> 16;

            s4_next.color[7:4]  = ((u_w * $unsigned(s3_reg.pixel.triangle.v0_color[7:4])) +
                                 (v_w * $unsigned(s3_reg.pixel.triangle.v1_color[7:4])) +
                                 (w_w * $unsigned(s3_reg.pixel.triangle.v2_color[7:4])) + 32'h0000_8000) >>> 16;

            s4_next.color[3:0]  = ((u_w * $unsigned(s3_reg.pixel.triangle.v0_color[3:0])) +
                                 (v_w * $unsigned(s3_reg.pixel.triangle.v1_color[3:0])) +
                                 (w_w * $unsigned(s3_reg.pixel.triangle.v2_color[3:0])) + 32'h0000_8000) >>> 16;

            s4_next.depth       = ((u_w * s3_reg.pixel.triangle.v0_nextepth) +
                                (v_w * s3_reg.pixel.triangle.v1_nextepth) +
                                (w_w * s3_reg.pixel.triangle.v2_nextepth) + 32'h0000_8000) >>> 16;
        end else begin
            s4_next.color = '0;
            s4_next.depth = '0;
        end
    end

    // Stage 4 reg (output register)
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            s4_reg <= '0;
        end else if (s4_ready) begin
            s4_reg <= s4_next;
        end
    end

    // drive outputs
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            out_valid <= 1'b0;
            out_x     <= '0;
            out_y     <= '0;
            out_color <= '0;
            out_depth <= '0;
        end else if (!out_valid || out_ready) begin
            out_valid <= s4_reg.valid;
            out_x     <= s4_reg.pixel.x;
            out_y     <= s4_reg.pixel.y;
            out_color <= s4_reg.color;
            out_depth <= s4_reg.depth;
        end
    end

endmodule