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

    // ----------------------------
    // Pipeline control
    // ----------------------------
    logic stage1_ready, stage2_ready;
    logic stage1_valid, stage2_valid;
    assign busy = stage1_valid || stage2_valid || out_valid;

    assign in_ready     = stage1_ready;
    assign stage1_ready = !stage1_valid || stage2_ready;
    assign stage2_ready = !stage2_valid || out_ready;

    // ----------------------------
    // Stage 1: Edge/Bary Numerators
    // ----------------------------
    pixel_state_t stage1_pixel;
    logic signed [37:0] d20, d21;            // Q32.6
    logic signed [75:0] v_num, w_num, u_num; // Q64.12
    logic               stage1_inside;

    // Sample at pixel center (x+0.5, y+0.5) → +4 in Q16.3
    logic signed [18:0] e2x, e2y;
    assign e2x = {in_pixel.x, 3'b0} + 3'd4 - in_pixel.triangle.v0x;
    assign e2y = {in_pixel.y, 3'b0} + 3'd4 - in_pixel.triangle.v0y;

    // d20, d21 (Q32.6)
    assign d20 = e2x * in_pixel.triangle.e0x + e2y * in_pixel.triangle.e0y;
    assign d21 = e2x * in_pixel.triangle.e1x + e2y * in_pixel.triangle.e1y;

    always_comb begin
        // v = (d11*d20 - d01*d21) / denom
        // w = (d00*d21 - d01*d20) / denom
        v_num = in_pixel.triangle.d11 * d20 - in_pixel.triangle.d01 * d21; // Q64.12
        w_num = in_pixel.triangle.d00 * d21 - in_pixel.triangle.d01 * d20; // Q64.12
        u_num = (in_pixel.triangle.d00 * in_pixel.triangle.d11 -
                 in_pixel.triangle.d01 * in_pixel.triangle.d01)
                 - v_num - w_num; // Q64.12
    end

    // Inside test
    always_comb begin
        stage1_inside = (v_num >= 0 && w_num >= 0 && u_num >= 0);
    end

    // Stage 1 registers
    logic               stage1_inside_r;
    logic signed [75:0] stage1_v_num, stage1_w_num, stage1_u_num;
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            stage1_valid    <= 1'b0;
            stage1_pixel    <= '0;
            stage1_v_num    <= '0;
            stage1_w_num    <= '0;
            stage1_u_num    <= '0;
            stage1_inside_r <= 1'b0;
        end else if (stage1_ready) begin
            stage1_valid    <= in_valid;
            if (in_valid) begin
                stage1_pixel    <= in_pixel;
                stage1_v_num    <= v_num;
                stage1_w_num    <= w_num;
                stage1_u_num    <= u_num;
                stage1_inside_r <= stage1_inside;
            end
        end
    end

    // ----------------------------
    // Stage 2: Normalize + Interpolate
    // ----------------------------
    pixel_state_t       stage2_pixel;
    logic               stage2_inside;
    logic signed [75:0] stage2_v_num, stage2_w_num, stage2_u_num;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            stage2_valid  <= 1'b0;
            stage2_pixel  <= '0;
            stage2_v_num  <= '0;
            stage2_w_num  <= '0;
            stage2_u_num  <= '0;
            stage2_inside <= 1'b0;
            out_valid     <= 1'b0;
            out_x         <= '0;
            out_y         <= '0;
            out_color     <= '0;
            out_depth     <= '0;
        end else begin
            if (stage2_ready) begin
                stage2_valid  <= stage1_valid;
                if (stage1_valid) begin
                    stage2_pixel  <= stage1_pixel;
                    stage2_v_num  <= stage1_v_num;
                    stage2_w_num  <= stage1_w_num;
                    stage2_u_num  <= stage1_u_num;
                    stage2_inside <= stage1_inside_r;
                end
            end
        end
    end

    // ----------------------------
    // Barycentric weights (Q16.16)
    // ----------------------------
    q16_16_t u_w, v_w, w_w;
    logic signed [93:0] v_mul, w_mul, u_mul;
    always_comb begin
        v_mul = stage2_v_num * $signed({1'b0, stage2_pixel.triangle.denom_inv});
        w_mul = stage2_w_num * $signed({1'b0, stage2_pixel.triangle.denom_inv});
        u_mul = stage2_u_num * $signed({1'b0, stage2_pixel.triangle.denom_inv});

        // Correct scaling: shift right by 28 to land in Q16.16
        v_w = q16_16_t'((v_mul + 28'd134217728) >>> 28); // round-to-nearest
        w_w = q16_16_t'((w_mul + 28'd134217728) >>> 28);
        u_w = q16_16_t'(32'h0001_0000) - v_w - w_w;
    end

    // ----------------------------
    // Outputs
    // ----------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            out_valid <= 1'b0;
        end else begin
            if (stage2_valid && (!out_valid || out_ready)) begin
                out_valid <= stage2_inside;
                if (stage2_inside) begin
                    out_x <= stage2_pixel.x;
                    out_y <= stage2_pixel.y;

                    // Color interpolation per nibble
                    out_color[11:8] <= ( (u_w * $unsigned(stage2_pixel.triangle.v0_color[11:8])) +
                                         (v_w * $unsigned(stage2_pixel.triangle.v1_color[11:8])) +
                                         (w_w * $unsigned(stage2_pixel.triangle.v2_color[11:8])) + 32'h0000_8000 ) >>> 16;

                    out_color[7:4]  <= ( (u_w * $unsigned(stage2_pixel.triangle.v0_color[7:4])) +
                                         (v_w * $unsigned(stage2_pixel.triangle.v1_color[7:4])) +
                                         (w_w * $unsigned(stage2_pixel.triangle.v2_color[7:4])) + 32'h0000_8000 ) >>> 16;

                    out_color[3:0]  <= ( (u_w * $unsigned(stage2_pixel.triangle.v0_color[3:0])) +
                                         (v_w * $unsigned(stage2_pixel.triangle.v1_color[3:0])) +
                                         (w_w * $unsigned(stage2_pixel.triangle.v2_color[3:0])) + 32'h0000_8000 ) >>> 16;

                    // Depth interpolation
                    out_depth <= ( (u_w * stage2_pixel.triangle.v0_depth) +
                                   (v_w * stage2_pixel.triangle.v1_depth) +
                                   (w_w * stage2_pixel.triangle.v2_depth) + 32'h0000_8000 ) >>> 16;
                end else begin
                    out_x     <= stage2_pixel.x;
                    out_y     <= stage2_pixel.y;
                    out_color <= '0;
                    out_depth <= '0;
                end
            end else if (out_ready && out_valid) begin
                out_valid <= 1'b0;
            end
        end
    end

endmodule
