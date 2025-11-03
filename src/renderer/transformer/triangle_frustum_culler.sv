`default_nettype none
`timescale 1ns / 1ps

import math_pkg::*;
import vertex_pkg::*;
import transformer_pkg::*;

module triangle_frustum_culler #(
    parameter int WIDTH  = 320,
    parameter int HEIGHT = 240,
    parameter int NEAR_PLANE = 1,
    parameter int FAR_PLANE  = 1000
) (
    input  wire  logic             clk,
    input  wire  logic             rst,

    input  wire  triangle_t        triangle,
    input  wire  logic             in_valid,
    output       logic             in_ready,

    output       triangle_t        out_triangle,
    output       logic             out_valid,
    input  wire  logic             out_ready,

    output       logic             busy
);


    localparam int NEAR_PLANE_Q16_16 = NEAR_PLANE << 16;
    localparam int FAR_PLANE_Q16_16  = FAR_PLANE  << 16;
    localparam int WIDTH_Q16_16      = WIDTH      << 16;
    localparam int HEIGHT_Q16_16     = HEIGHT     << 16;

    function automatic logic vertex_in_frustum(input vertex_t v);
        begin
            vertex_in_frustum =
                (v.pos.z >= NEAR_PLANE_Q16_16) &&
                (v.pos.z <= FAR_PLANE_Q16_16)  &&
                (v.pos.x >= 0) && (v.pos.x <= WIDTH_Q16_16) &&
                (v.pos.y >= 0) && (v.pos.y <= HEIGHT_Q16_16);
        end
    endfunction

    function automatic logic triangle_in_frustum(input triangle_t t);
        begin
            triangle_in_frustum =
                vertex_in_frustum(t.v0) ||
                vertex_in_frustum(t.v1) ||
                vertex_in_frustum(t.v2);
        end
    endfunction

    triangle_t triangle_reg;
    logic       valid_reg;
    logic tri_in_frustum;
    assign tri_in_frustum = triangle_in_frustum(triangle_reg);

    assign in_ready     = !valid_reg || out_ready;
    assign out_valid    = valid_reg && tri_in_frustum;
    assign out_triangle = triangle_reg;
    assign busy         = valid_reg;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            valid_reg     <= 1'b0;
            triangle_reg  <= '0;
        end else begin
            if (in_ready) begin
                valid_reg <= in_valid;
                if (in_valid) begin
                    triangle_reg <= triangle;
                end
            end
        end
    end
    
endmodule
