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

    // From traversal stage
    input  wire pixel_state_t in_pixel,
    input  wire logic         in_valid,
    output wire logic         in_ready,

    // Output to framebuffer / z-buffer
    output logic [15:0] out_x,
    output logic [15:0] out_y,
    output color12_t    out_color,
    output q16_16_t     out_depth,
    output logic        out_valid,
    input  wire logic   out_ready,
    output logic        busy
);

    // ============================================================
    // 4-stage pipeline:
    //   S0: input reg
    //   S1: e2 + d20/d21
    //   S2: numerators u/v/w + inside
    //   S3: weights + color/depth interpolate + output reg
    // ============================================================

    // ----------------------------
    // Flow control
    // ----------------------------
    logic s0_valid, s1_valid, s2_valid, s3_valid;
    wire  s3_ready  = !s3_valid || out_ready;
    wire  s2_ready  = !s2_valid || s3_ready;
    wire  s1_ready  = !s1_valid || s2_ready;
    assign in_ready = !s0_valid || s1_ready;

    assign busy = s0_valid | s1_valid | s2_valid | s3_valid | out_valid;

    // ----------------------------
    // S0: input register
    // ----------------------------
    pixel_state_t s0_pixel;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            s0_valid <= 1'b0;
            s0_pixel <= '0;
        end else if (s1_ready) begin
            s0_valid <= in_valid;
            if (in_valid) s0_pixel <= in_pixel;
        end
    end

    // ----------------------------
    // S1: d20/d21
    // ----------------------------
    pixel_state_t s1_pixel;
    (* use_dsp = "yes" *) logic signed [37:0] s1_d20, s1_d21;
    logic signed [18:0] s1_e2x, s1_e2y;

    // pixel center (x+0.5,y+0.5) => +4 in Q16.3
    always_comb begin
        s1_e2x = {s0_pixel.x, 3'b000} + 19'sd4 - s0_pixel.triangle.v0x;
        s1_e2y = {s0_pixel.y, 3'b000} + 19'sd4 - s0_pixel.triangle.v0y;
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            s1_valid <= 1'b0;
            s1_pixel <= '0;
            s1_d20   <= '0;
            s1_d21   <= '0;
        end else if (s2_ready) begin
            s1_valid <= s0_valid;
            if (s0_valid) begin
                s1_pixel <= s0_pixel;
                s1_d20   <= s1_e2x * s0_pixel.triangle.e0x + s1_e2y * s0_pixel.triangle.e0y;
                s1_d21   <= s1_e2x * s0_pixel.triangle.e1x + s1_e2y * s0_pixel.triangle.e1y;
            end
        end
    end

    // ----------------------------
    // S2: numerators & inside
    // ----------------------------
    pixel_state_t s2_pixel;
    (* use_dsp = "yes" *) logic signed [75:0] s2_v_num, s2_w_num, s2_u_num; // Q64.12
    (* use_dsp = "yes" *) logic signed [75:0] s2_denom_q64_12;
    logic s2_inside;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            s2_valid <= 1'b0;
            s2_pixel <= '0;
            s2_v_num <= '0; s2_w_num <= '0; s2_u_num <= '0;
            s2_inside <= 1'b0;
            s2_denom_q64_12 <= '0;
        end else if (s3_ready) begin
            s2_valid <= s1_valid;
            if (s1_valid) begin
                s2_pixel <= s1_pixel;

                s2_v_num <= $signed(s1_pixel.triangle.d11) * $signed(s1_d20)
                         -  $signed(s1_pixel.triangle.d01) * $signed(s1_d21);

                s2_w_num <= $signed(s1_pixel.triangle.d00) * $signed(s1_d21)
                         -  $signed(s1_pixel.triangle.d01) * $signed(s1_d20);

                s2_denom_q64_12 <= $signed(s1_pixel.triangle.d00) * $signed(s1_pixel.triangle.d11)
                                 -  $signed(s1_pixel.triangle.d01) * $signed(s1_pixel.triangle.d01);

                s2_u_num <= s2_denom_q64_12 - s2_v_num - s2_w_num;

                if (s1_pixel.triangle.denom_neg)
                    s2_inside <= (s2_v_num <= 0) && (s2_w_num <= 0) && (s2_u_num <= 0);
                else
                    s2_inside <= (s2_v_num >= 0) && (s2_w_num >= 0) && (s2_u_num >= 0);
            end
        end
    end

    // ----------------------------
    // S3: weights + interpolation + output
    // ----------------------------
    (* use_dsp = "yes" *) logic signed [93:0] s3_v_mul, s3_w_mul, s3_u_mul; // 76x17
    q16_16_t v_w, w_w, u_w;
    pixel_state_t s3_pixel;
    logic s3_inside;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            s3_valid  <= 1'b0;
            s3_pixel  <= '0;
            s3_inside <= 1'b0;
            s3_v_mul <= '0; s3_w_mul <= '0; s3_u_mul <= '0;
            v_w <= '0; w_w <= '0; u_w <= '0;
            out_valid <= 1'b0;
            out_x <= '0; out_y <= '0; out_color <= '0; out_depth <= '0;
        end else begin
            // latch stage 3 when downstream is ready
            if (s3_ready) begin
                s3_valid  <= s2_valid;
                if (s2_valid) begin
                    s3_pixel  <= s2_pixel;
                    s3_inside <= s2_inside;

                    // Weights: (num * denom_inv) >> 28  (round)
                    s3_v_mul <= s2_v_num * $signed({1'b0, s2_pixel.triangle.denom_inv});
                    s3_w_mul <= s2_w_num * $signed({1'b0, s2_pixel.triangle.denom_inv});
                    s3_u_mul <= s2_u_num * $signed({1'b0, s2_pixel.triangle.denom_inv});

                    v_w <= q16_16_t'((s3_v_mul + 94'd134217728) >>> 28);
                    w_w <= q16_16_t'((s3_w_mul + 94'd134217728) >>> 28);
                    u_w <= q16_16_t'(32'h0001_0000) - v_w - w_w;
                end
            end

            // output stage
            if (out_ready || !out_valid) begin
                out_valid <= s3_valid & s3_inside;
                if (s3_valid) begin
                    out_x <= s3_pixel.x;
                    out_y <= s3_pixel.y;

                    if (s3_inside) begin
                        // Interpolate RGB444 by nibbles (round >>16)
                        out_color[11:8] <= ((u_w * $unsigned(s3_pixel.triangle.v0_color[11:8])) +
                                            (v_w * $unsigned(s3_pixel.triangle.v1_color[11:8])) +
                                            (w_w * $unsigned(s3_pixel.triangle.v2_color[11:8])) + 32'h0000_8000) >>> 16;

                        out_color[7:4]  <= ((u_w * $unsigned(s3_pixel.triangle.v0_color[7:4])) +
                                            (v_w * $unsigned(s3_pixel.triangle.v1_color[7:4])) +
                                            (w_w * $unsigned(s3_pixel.triangle.v2_color[7:4])) + 32'h0000_8000) >>> 16;

                        out_color[3:0]  <= ((u_w * $unsigned(s3_pixel.triangle.v0_color[3:0])) +
                                            (v_w * $unsigned(s3_pixel.triangle.v1_color[3:0])) +
                                            (w_w * $unsigned(s3_pixel.triangle.v2_color[3:0])) + 32'h0000_8000) >>> 16;

                        // Depth (round >>16)
                        out_depth <= ((u_w * s3_pixel.triangle.v0_depth) +
                                      (v_w * s3_pixel.triangle.v1_depth) +
                                      (w_w * s3_pixel.triangle.v2_depth) + 32'h0000_8000) >>> 16;
                    end else begin
                        out_color <= '0;
                        out_depth <= '0;
                    end
                end
            end
        end
    end

endmodule
