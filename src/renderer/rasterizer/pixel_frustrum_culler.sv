`default_nettype none
`timescale 1ns / 1ps

import math_pkg::*;
import vertex_pkg::*;
import transformer_pkg::*;

module pixel_frustum_culler #(
    parameter int NEAR_PLANE = 1,
    parameter int FAR_PLANE  = 1000,
    localparam int N_BITS_FOR_DEPTH = 16 + $clog2(FAR_PLANE-NEAR_PLANE)
) (
    input  wire  logic             clk,
    input  wire  logic             rst,

    input  wire  color16_t         in_color,
    input  wire  q16_16_t          in_depth,
    input  wire  logic             in_valid,
    output       logic             in_ready,
    input  wire  logic [15:0]      in_x,
    input  wire  logic [15:0]      in_y,

    output       color16_t         out_color,
    output       logic [N_BITS_FOR_DEPTH-1:0] out_depth,
    output       logic             out_valid,
    input  wire  logic             out_ready,
    output       logic [15:0]      out_x,
    output       logic [15:0]      out_y,

    output       logic             busy
);


    localparam int NEAR_PLANE_Q16_16 = NEAR_PLANE << 16;
    localparam int FAR_PLANE_Q16_16  = FAR_PLANE  << 16;
    function automatic logic [N_BITS_FOR_DEPTH-1:0] normalize_depth_in_frustum(input q16_16_t depth);
        logic signed [31:0] depth_diff;

        begin
            depth_diff = depth - NEAR_PLANE_Q16_16;
            normalize_depth_in_frustum = depth_diff[N_BITS_FOR_DEPTH-1:0];
        end
    endfunction



    function automatic logic pixel_in_frustum(input q16_16_t depth);
        begin
            pixel_in_frustum =
                (depth >= NEAR_PLANE_Q16_16) &&
                (depth <= FAR_PLANE_Q16_16);
        end
    endfunction

    color16_t  color_reg;
    q16_16_t   depth_reg;
    logic       valid_reg;
    logic pix_in_frustum;
    logic [15:0] x_reg, y_reg;
    assign pix_in_frustum = pixel_in_frustum(depth_reg);

    assign in_ready  = !valid_reg || (pix_in_frustum ? out_ready : 1'b1);
    assign out_valid = valid_reg && pix_in_frustum;
    assign out_color    = color_reg;
    assign out_depth    = normalize_depth_in_frustum(depth_reg);
    assign out_x        = x_reg;
    assign out_y        = y_reg;
    assign busy         = valid_reg;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            valid_reg     <= 1'b0;
            color_reg  <= '0;
            depth_reg  <= '0;
            x_reg      <= '0;
            y_reg      <= '0;
        end else begin
            if (in_ready) begin
                valid_reg <= in_valid;
                if (in_valid) begin
                    color_reg <= in_color;
                    depth_reg <= in_depth;
                    x_reg     <= in_x;
                    y_reg     <= in_y;
                end
            end
        end
    end
    
endmodule
