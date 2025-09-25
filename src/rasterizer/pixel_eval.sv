`default_nettype none
`timescale 1ns / 1ps

import rasterizer_pkg::*;
import math_pkg::*;
import color_pkg::*;

module pixel_eval #(
    parameter int WIDTH  = 320,
    parameter int HEIGHT = 240
) (
    input wire logic clk,
    input wire logic rst,

    // From traversal stage
    input  wire pixel_state_t in_pixel,
    input  wire logic    in_valid,
    output wire logic    in_ready,

    // Output to framebuffer / z-buffer
    output logic [15:0]      out_x,
    output logic [15:0]      out_y,
    output color12_t         out_color,
    output q16_16_t          out_depth,
    output logic             out_valid,
    input  wire logic        out_ready,
    output logic             busy
);

    // Pipeline control signals
    logic stage1_ready, stage2_ready;
    logic stage1_valid, stage2_valid;
    assign busy = stage1_valid || stage2_valid || out_valid;

    // Ready logic: can accept new data if stage1 is ready
    assign in_ready     = stage1_ready;
    assign stage1_ready = !stage1_valid || stage2_ready;
    assign stage2_ready = !stage2_valid || out_ready;

    // Stage 1 registers
    pixel_state_t stage1_pixel;
    logic signed [75:0] stage1_denom, stage1_v_num, stage1_w_num, stage1_u_num;
    logic signed [63:0] stage1_denom_trunc, stage1_v_num_trunc, stage1_w_num_trunc;

    // Stage 2 registers
    pixel_state_t stage2_pixel;
    logic signed [75:0] stage2_denom, stage2_v_num, stage2_w_num, stage2_u_num;
    logic signed [63:0] stage2_denom_trunc, stage2_v_num_trunc, stage2_w_num_trunc;
    logic stage2_inside;

    // Clamped coords
    logic signed [18:0] clamped_x, clamped_y; // Q16.3
    logic signed [18:0] clamped_v0x, clamped_v0y;
    logic signed [18:0] clamped_v1x, clamped_v1y;
    logic signed [18:0] clamped_v2x, clamped_v2y;

    //Take top 16 bits of vertex coordinates (Q16.16 -> Q16.3)
    assign clamped_x   = {in_pixel.x, 3'b0};
    assign clamped_y   = {in_pixel.y, 3'b0};
    assign clamped_v0x = in_pixel.v0.x[31:13];
    assign clamped_v0y = in_pixel.v0.y[31:13];
    assign clamped_v1x = in_pixel.v1.x[31:13];
    assign clamped_v1y = in_pixel.v1.y[31:13];
    assign clamped_v2x = in_pixel.v2.x[31:13];
    assign clamped_v2y = in_pixel.v2.y[31:13];

    logic signed [18:0] v0x, v0y, v1x, v1y, v2x, v2y; // Q16.3

    assign v0x = clamped_v1x - clamped_v0x;
    assign v0y = clamped_v1y - clamped_v0y;
    assign v1x = clamped_v2x - clamped_v0x;
    assign v1y = clamped_v2y - clamped_v0y;
    assign v2x = clamped_x   - clamped_v0x;
    assign v2y = clamped_y   - clamped_v0y;

    logic signed [37:0] d00, d01, d11, d20, d21; // Q32.6

    assign d00 = v0x * v0x + v0y * v0y;
    assign d01 = v0x * v1x + v0y * v1y;
    assign d11 = v1x * v1x + v1y * v1y;
    assign d20 = v2x * v0x + v2y * v0y;
    assign d21 = v2x * v1x + v2y * v1y;

    logic signed [75:0] denom_comb, v_num_comb, w_num_comb, u_num_comb; // Q64.12
    always_comb begin
        denom_comb = d00 * d11 - d01 * d01;
        v_num_comb = d11 * d20 - d01 * d21;
        w_num_comb = d00 * d21 - d01 * d20;
        u_num_comb = denom_comb - v_num_comb - w_num_comb;
    end

    logic signed [63:0] denom_trunc_comb, v_num_trunc_comb, w_num_trunc_comb;
    assign denom_trunc_comb = denom_comb[75 -: 64]; // bits 75..12
    assign v_num_trunc_comb = v_num_comb[75 -: 64];
    assign w_num_trunc_comb = w_num_comb[75 -: 64];

    // Inside test logic
    logic inside_comb;
    always_comb begin
        if (stage1_denom != 0) begin
            inside_comb = ((stage1_denom > 0 && stage1_v_num >= 0 && stage1_w_num >= 0 && stage1_u_num >= 0) ||
                           (stage1_denom < 0 && stage1_v_num <= 0 && stage1_w_num <= 0 && stage1_u_num <= 0));
        end else begin
            inside_comb = 1'b0;
        end
    end

    // Pipeline stage 1: Register inputs and intermediate calculations
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            stage1_valid       <= 1'b0;
            stage1_denom       <= 0;
            stage1_v_num       <= 0;
            stage1_w_num       <= 0;
            stage1_u_num       <= 0;
            stage1_pixel       <= '0;
            stage1_denom_trunc <= '0;
            stage1_v_num_trunc <= '0;
            stage1_w_num_trunc <= '0;
        end else begin
            if (stage1_ready) begin
                stage1_valid <= in_valid;
                if (in_valid) begin
                    stage1_denom       <= denom_comb;
                    stage1_v_num       <= v_num_comb;
                    stage1_w_num       <= w_num_comb;
                    stage1_u_num       <= u_num_comb;
                    stage1_pixel       <= in_pixel;
                    stage1_denom_trunc <= denom_trunc_comb;
                    stage1_v_num_trunc <= v_num_trunc_comb;
                    stage1_w_num_trunc <= w_num_trunc_comb;
                end
            end
        end
    end

    // Barycentric coordinate calculation (use stage2-aligned truncated values)
    q16_16_t u_comb, v_comb, w_comb;
    always_comb begin
        if (stage2_denom_trunc != 0) begin
            v_comb = (stage2_v_num_trunc <<< 16) / stage2_denom_trunc;
            w_comb = (stage2_w_num_trunc <<< 16) / stage2_denom_trunc;
            u_comb = 32'h00010000 - v_comb - w_comb; // 1.0 in Q16.16
        end else begin
            u_comb = 0;
            v_comb = 0;
            w_comb = 0;
        end
    end

    // Pipeline stage 2: Final calculation and output
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            stage2_valid        <= 1'b0;
            out_valid           <= 1'b0;
            out_x               <= 0;
            out_y               <= 0;
            out_color           <= '0;
            out_depth           <= '0;
            stage2_pixel        <= '0;
            stage2_denom        <= 0;
            stage2_v_num        <= 0;
            stage2_w_num        <= 0;
            stage2_u_num        <= 0;
            stage2_inside       <= 1'b0;
            stage2_denom_trunc  <= '0;
            stage2_v_num_trunc  <= '0;
            stage2_w_num_trunc  <= '0;
        end else begin
            if (stage2_ready) begin
                // Move data from stage 1 to stage 2
                stage2_valid       <= stage1_valid;
                if (stage1_valid) begin
                    stage2_pixel       <= stage1_pixel;
                    stage2_denom       <= stage1_denom;
                    stage2_v_num       <= stage1_v_num;
                    stage2_w_num       <= stage1_w_num;
                    stage2_u_num       <= stage1_u_num;
                    stage2_inside      <= inside_comb;
                    stage2_denom_trunc <= stage1_denom_trunc;
                    stage2_v_num_trunc <= stage1_v_num_trunc;
                    stage2_w_num_trunc <= stage1_w_num_trunc;
                end

                // Stage 2 output
                out_valid <= stage2_valid && stage2_inside;
                if (stage2_valid && stage2_inside) begin
                    out_x <= stage2_pixel.x;
                    out_y <= stage2_pixel.y;

                    // Color interpolation (each channel is 4 bits)
                    out_color[11:8] <= (u_comb * stage2_pixel.v0_color[11:8] +
                                        v_comb * stage2_pixel.v1_color[11:8] +
                                        w_comb * stage2_pixel.v2_color[11:8]) >>> 16;
                    out_color[7:4]  <= (u_comb * stage2_pixel.v0_color[7:4] +
                                        v_comb * stage2_pixel.v1_color[7:4] +
                                        w_comb * stage2_pixel.v2_color[7:4]) >>> 16;
                    out_color[3:0]  <= (u_comb * stage2_pixel.v0_color[3:0] +
                                        v_comb * stage2_pixel.v1_color[3:0] +
                                        w_comb * stage2_pixel.v2_color[3:0]) >>> 16;

                    // Depth interpolation
                    out_depth <= (u_comb * stage2_pixel.v0_depth +
                                  v_comb * stage2_pixel.v1_depth +
                                  w_comb * stage2_pixel.v2_depth) >>> 16;
                end else begin
                    out_x      <= stage2_pixel.x;
                    out_y      <= stage2_pixel.y;
                    out_color  <= 12'b0;
                    out_depth  <= 32'b0;
                end
            end else if (out_ready && out_valid) begin
                // Output was consumed, but no new data to replace it
                out_valid <= 1'b0;
            end
        end
    end
endmodule
