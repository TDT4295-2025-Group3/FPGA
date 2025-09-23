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
    output color12_t                  out_color,
    output q16_16_t                   out_depth,
    output logic                      out_valid
);

    assign in_ready = 1'b1; // Always ready

    q16_16_t v0x, v0y, v1x, v1y, v2x, v2y;

    assign v0x = in_pixel.v1.x - in_pixel.v0.x;
    assign v0y = in_pixel.v1.y - in_pixel.v0.y;
    assign v1x = in_pixel.v2.x - in_pixel.v0.x;
    assign v1y = in_pixel.v2.y - in_pixel.v0.y;
    assign v2x = to_q16_16(in_pixel.x) - in_pixel.v0.x;
    assign v2y = to_q16_16(in_pixel.y) - in_pixel.v0.y;

    
    q32_32_t d00, d01, d11, d20, d21;
    
    assign d00 = dot2d('{v0x, v0y}, '{v0x, v0y});
    assign d01 = dot2d('{v0x, v0y}, '{v1x, v1y});
    assign d11 = dot2d('{v1x, v1y}, '{v1x, v1y});
    assign d20 = dot2d('{v2x, v2y}, '{v0x, v0y});
    assign d21 = dot2d('{v2x, v2y}, '{v1x, v1y});


    q64_64_t denom, v_num, w_num, u_num;
    
    logic valid_reg;
    pixel_state_t pixel_reg;

    q16_16_t u, v, w;
    always_comb begin
        if (denom != 0) begin
            v = (v_num <<< 16) / denom;
            w = (w_num <<< 16) / denom;
            u = (u_num <<< 16) / denom;
        end
        else begin
            u = 0; v = 0; w = 0;
        end
    end

    logic is_inside;
    assign is_inside = (u >= 0) && (v >= 0) && (w >= 0);
    always_ff @(posedge clk or posedge rst) begin
            if (rst) begin
            out_valid <= 0;
            valid_reg <= 0;
            end
            else begin
                // Pipeline stage 1
                denom <= d00 * d11 - d01 * d01;
                v_num <= d11 * d20 - d01 * d21;
                w_num <= d00 * d21 - d01 * d20;
                u_num <= (d00 * d11 - d01 * d01) -  (d11 * d20 - d01 * d21) - (d00 * d21 - d01 * d20); // FIXME: denom - v_num - w_num;
                valid_reg <= in_valid;
                pixel_reg <= in_pixel;

                // Pipeline stage 2
                out_x <= pixel_reg.x;
                out_y <= pixel_reg.y;
                if (is_inside) begin
                    // Color channels are 4-bit, so u/v/w in Q16.16 -> shift down
                    out_color[11:8] <= (u * pixel_reg.v0_color[11:8] + v * pixel_reg.v1_color[11:8] + w * pixel_reg.v2_color[11:8]) >>> 16;
                    out_color[7:4]  <= (u * pixel_reg.v0_color[7:4]  + v * pixel_reg.v1_color[7:4]  + w * pixel_reg.v2_color[7:4])  >>> 16;
                    out_color[3:0]  <= (u * pixel_reg.v0_color[3:0]  + v * pixel_reg.v1_color[3:0]  + w * pixel_reg.v2_color[3:0])  >>> 16;
                    out_depth <= (u * pixel_reg.v0_depth + v * pixel_reg.v1_depth + w * pixel_reg.v2_depth) >>> 16;
                    out_valid <= valid_reg;
                end else begin
                    out_color <= 12'b0;
                    out_depth <= 32'b0;
                    out_valid <= 0;
                end
            end
    end
endmodule
