`default_nettype none
`timescale 1ns / 1ps

import math_pkg::*;
import color_pkg::*;
import vertex_pkg::*;
import rasterizer_pkg::*;


module rasterizer #(
    parameter int WIDTH  = 320,
    parameter int HEIGHT = 240
) (
    input  wire logic clk,
    input  wire logic rst,

    input  vertex_t v0,
    input  vertex_t v1,
    input  vertex_t v2,
    
    input wire logic in_valid,
    output logic in_ready,
    output logic busy,

    output logic [15:0]  out_pixel_x,
    output logic [15:0] out_pixel_y,
    output q16_16_t                   out_depth,
    output color12_t                  out_color,
    output logic                      out_valid,
    input wire logic                 out_ready
);

    always_comb begin
        if (in_valid && in_ready) begin
            $display("Rasterizer received triangle: v0=(%0d,%0d,%0d) c=%0h, v1=(%0d,%0d,%0d) c=%0h, v2=(%0d,%0d,%0d) c=%0h",
                v0.pos.x, v0.pos.y, v0.pos.z, v0.color,
                v1.pos.x, v1.pos.y, v1.pos.z, v1.color,
                v2.pos.x, v2.pos.y, v2.pos.z, v2.color);
        end
    end

    // Triangle setup stage
    logic                    ts_out_valid;
    triangle_state_t         ts_out_state;
    logic                    ts_busy;

    triangle_setup #(
        .WIDTH(WIDTH),
        .HEIGHT(HEIGHT)
    ) ts_inst (
        .clk(clk),
        .rst(rst),

        .v0(v0),
        .v1(v1),
        .v2(v2),

        .in_valid(in_valid),
        .in_ready(in_ready),
        .out_ready(pt_in_ready),

        .out_state(ts_out_state),
        .out_valid(ts_out_valid),
        .busy(ts_busy)
    );

    // Pixel traversal stage
    logic            pt_in_ready;
    logic            pt_out_valid;
    pixel_state_t    pt_out_pixel;
    logic            pt_busy;

    pixel_traversal pt_inst (
        .clk(clk),
        .rst(rst),

        .in_valid(ts_out_valid),
        .in_state(ts_out_state),
        .in_ready(pt_in_ready),

        .out_valid(pt_out_valid),
        .out_pixel(pt_out_pixel),
        .out_ready(pe_in_ready),
        .busy(pt_busy)
    );

    // Pixel evaluation stage
    logic                      pe_in_ready;
    logic                      pe_out_valid;
    logic [15:0]               pe_out_x;
    logic [15:0]               pe_out_y;
    color12_t                  pe_out_color;
    q16_16_t                   pe_out_depth;
    logic                      pe_busy;

    pixel_eval #(
        .WIDTH(WIDTH),
        .HEIGHT(HEIGHT)
    ) pe_inst (
        .clk(clk),
        .rst(rst),

        .in_pixel(pt_out_pixel),
        .in_valid(pt_out_valid),
        .in_ready(pe_in_ready),

        .out_x(pe_out_x),
        .out_y(pe_out_y),
        .out_color(pe_out_color),
        .out_depth(pe_out_depth),
        .out_valid(pe_out_valid),
        .out_ready(out_ready),
        .busy(pe_busy)
    );

    // Output assignments
    assign out_pixel_x = pe_out_x;
    assign out_pixel_y = pe_out_y;
    assign out_color   = pe_out_color;
    assign out_depth   = pe_out_depth;
    assign out_valid   = pe_out_valid;
    assign busy        = ts_busy || pt_busy || pe_busy;

endmodule
