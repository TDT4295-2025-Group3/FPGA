`default_nettype none
`timescale 1ns / 1ps

import math_pkg::*;
import vertex_pkg::*;
import transformer_pkg::*;

module screen_normalizer #(
    parameter int WIDTH   = 320,
    parameter int HEIGHT  = 240
) (
    input  wire  logic       clk,
    input  wire  logic       rst,

    input  wire  triangle_t  triangle,
    input  wire  logic       in_valid,
    output       logic       in_ready,

    output       triangle_t  out_triangle,
    output       logic       out_valid,
    input  wire  logic       out_ready,

    output       logic       busy
);

    localparam int SCALE = 200;
    localparam int HALF_WIDTH = WIDTH  / 2;
    localparam int HALF_HEIGHT = HEIGHT / 2;
    localparam int SCALE_FACTOR_Q16_16 = q16_16_t'((HALF_HEIGHT<<16)/SCALE);

    function automatic vertex_t norm_vertex(input vertex_t vin);
        vertex_t vout;
        q32_32_t tmp;
        begin
            vout = vin;

            tmp   = q32_32_t'(-vin.pos.x) * q32_32_t'(SCALE_FACTOR_Q16_16);
            vout.pos.x = q16_16_t'(((tmp + q32_32_t'(1<<15)) >>> 16)) + q16_16_t'(HALF_WIDTH  << 16);

            tmp   = q32_32_t'(vin.pos.y) * q32_32_t'(SCALE_FACTOR_Q16_16);
            vout.pos.y = q16_16_t'(((tmp + q32_32_t'(1<<15)) >>> 16)) + q16_16_t'(HALF_HEIGHT << 16);

            vout.pos.z = -vin.pos.z;
            return vout;
        end
    endfunction


    function automatic triangle_t norm_triangle(input triangle_t tin);
        triangle_t tout;
        begin
            tout       = tin;
            tout.v0    = norm_vertex(tin.v0);
            tout.v1    = norm_vertex(tin.v1);
            tout.v2    = norm_vertex(tin.v2);
            return tout;
        end
    endfunction

    triangle_t out_triangle_r;
    logic      out_valid_r;

    assign in_ready     = !out_valid_r || out_ready;
    assign out_valid    = out_valid_r;
    assign out_triangle = out_triangle_r;
    assign busy         = out_valid_r;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            out_valid_r     <= 1'b0;
            out_triangle_r  <= '0;
        end else begin
            if (in_ready) begin
                out_valid_r <= in_valid;
                if (in_valid) begin
                    out_triangle_r <= norm_triangle(triangle);
                end
            end
        end
    end

endmodule
