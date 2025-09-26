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
    // Stage 1 registers
    // ----------------------------
    pixel_state_t stage1_pixel;
    logic signed [37:0] d20, d21;
    logic signed [75:0] v_num, w_num, u_num;
    logic stage1_inside;

    // Compute e2 (pixel relative to v0) in Q16.3
    logic signed [18:0] e2x, e2y;
    assign e2x = {in_pixel.x, 3'b0} - in_pixel.triangle.v0x;
    assign e2y = {in_pixel.y, 3'b0} - in_pixel.triangle.v0y;

    // d20, d21 (Q32.6)
    assign d20 = e2x * in_pixel.triangle.e0x + e2y * in_pixel.triangle.e0y;
    assign d21 = e2x * in_pixel.triangle.e1x + e2y * in_pixel.triangle.e1y;

    // Numerators (Q64.12)
    always_comb begin
        v_num = in_pixel.triangle.d11 * d20 - in_pixel.triangle.d01 * d21;
        w_num = in_pixel.triangle.d00 * d21 - in_pixel.triangle.d01 * d20;
        u_num = (in_pixel.triangle.d00 * in_pixel.triangle.d11 -
                 in_pixel.triangle.d01 * in_pixel.triangle.d01)
                 - v_num - w_num;
    end

    // Inside test using denom_neg
    always_comb begin
        if (!in_pixel.triangle.denom_neg)
            stage1_inside = (v_num >= 0 && w_num >= 0 && u_num >= 0);
        else
            stage1_inside = (v_num <= 0 && w_num <= 0 && u_num <= 0);
    end

    // Register stage 1
    logic signed [75:0] stage1_v_num, stage1_w_num, stage1_u_num;
    logic               stage1_inside_reg;
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            stage1_valid       <= 1'b0;
            stage1_pixel       <= '0;
            stage1_v_num       <= '0;
            stage1_w_num       <= '0;
            stage1_u_num       <= '0;
            stage1_inside_reg  <= 1'b0;
        end else if (stage1_ready) begin
            stage1_valid <= in_valid;
            if (in_valid) begin
                stage1_pixel      <= in_pixel;
                stage1_v_num      <= v_num;
                stage1_w_num      <= w_num;
                stage1_u_num      <= u_num;
                stage1_inside_reg <= stage1_inside;
            end
        end
    end

    // ----------------------------
    // Stage 2: Barycentric + Output
    // ----------------------------
    pixel_state_t stage2_pixel;
    logic signed [75:0] stage2_v_num, stage2_w_num, stage2_u_num;
    logic               stage2_inside;

    q16_16_t u_comb, v_comb, w_comb;

    always_comb begin
        if (stage2_inside) begin
            v_comb = (stage2_v_num * stage2_pixel.triangle.denom_inv) >>> 16;
            w_comb = (stage2_w_num * stage2_pixel.triangle.denom_inv) >>> 16;
            u_comb = 32'h00010000 - v_comb - w_comb; // 1.0 in Q16.16
        end else begin
            u_comb = '0;
            v_comb = '0;
            w_comb = '0;
        end
    end

    // Register stage 2 and drive outputs
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
        end else if (stage2_ready) begin
            stage2_valid  <= stage1_valid;
            if (stage1_valid) begin
                stage2_pixel  <= stage1_pixel;
                stage2_v_num  <= stage1_v_num;
                stage2_w_num  <= stage1_w_num;
                stage2_u_num  <= stage1_u_num;
                stage2_inside <= stage1_inside_reg;
            end

            out_valid <= stage2_valid && stage2_inside;
            if (stage2_valid && stage2_inside) begin
                out_x <= stage2_pixel.x;
                out_y <= stage2_pixel.y;

                // Color interpolation (per channel 4-bit)
                out_color[11:8] <= (u_comb * stage2_pixel.triangle.v0_color[11:8] +
                                    v_comb * stage2_pixel.triangle.v1_color[11:8] +
                                    w_comb * stage2_pixel.triangle.v2_color[11:8]) >>> 16;
                out_color[7:4]  <= (u_comb * stage2_pixel.triangle.v0_color[7:4] +
                                    v_comb * stage2_pixel.triangle.v1_color[7:4] +
                                    w_comb * stage2_pixel.triangle.v2_color[7:4]) >>> 16;
                out_color[3:0]  <= (u_comb * stage2_pixel.triangle.v0_color[3:0] +
                                    v_comb * stage2_pixel.triangle.v1_color[3:0] +
                                    w_comb * stage2_pixel.triangle.v2_color[3:0]) >>> 16;

                // Depth interpolation
                out_depth <= (u_comb * stage2_pixel.triangle.v0_depth +
                              v_comb * stage2_pixel.triangle.v1_depth +
                              w_comb * stage2_pixel.triangle.v2_depth) >>> 16;
            end else begin
                out_x     <= stage2_pixel.x;
                out_y     <= stage2_pixel.y;
                out_color <= 12'b0;
                out_depth <= 32'b0;
            end
        end else if (out_ready && out_valid) begin
            // Output was consumed, but no new data
            out_valid <= 1'b0;
        end
    end

endmodule
