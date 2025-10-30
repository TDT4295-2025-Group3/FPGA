`default_nettype none
`timescale 1ns / 1ps

import math_pkg::*;
import color_pkg::*;
import vertex_pkg::*;

module rasterizer #(
    parameter int WIDTH  = 320,
    parameter int HEIGHT = 240,
    parameter int SUBPIXEL_BITS = 4,
    parameter int DENOM_INV_BITS = 36,
    parameter int DENOM_INV_FBITS = 35,
    parameter bit BACKFACE_CULLING = 1'b1
) (
    input  wire logic clk,
    input  wire logic rst,

    input  vertex_t v0,
    input  vertex_t v1,
    input  vertex_t v2,
    
    input  wire logic in_valid,
    output      logic in_ready,

    output      logic [$clog2(WIDTH)-1:0]  out_pixel_x,
    output      logic [$clog2(HEIGHT)-1:0] out_pixel_y,
    output      q16_16_t                   out_depth,
    output      color12_t                  out_color,
    output      logic                      out_valid,
    input  wire logic                      out_ready,
    output      logic                      busy
);

    logic signed [16+SUBPIXEL_BITS-1:0] ts_v0x, ts_v0y;
    logic signed [16+SUBPIXEL_BITS-1:0] ts_e0x, ts_e0y;
    logic signed [16+SUBPIXEL_BITS-1:0] ts_e1x, ts_e1y;
    logic signed [DENOM_INV_BITS-1:0]  ts_denom_inv;
    logic [$clog2(WIDTH)-1:0]           ts_bbox_min_x, ts_bbox_max_x;
    logic [$clog2(HEIGHT)-1:0]          ts_bbox_min_y, ts_bbox_max_y;
    color12_t                           ts_v0_color, ts_v1_color, ts_v2_color;
    q16_16_t                            ts_v0_depth, ts_v1_depth, ts_v2_depth;

    logic ts_out_valid;
    logic ts_out_ready;
    logic ts_busy;

    triangle_setup #(
        .WIDTH(WIDTH),
        .HEIGHT(HEIGHT),
        .SUBPIXEL_BITS(SUBPIXEL_BITS),
        .DENOM_INV_BITS(DENOM_INV_BITS),
        .DENOM_INV_FBITS(DENOM_INV_FBITS),
        .BACKFACE_CULLING(BACKFACE_CULLING)
    ) ts_inst (
        .clk(clk),
        .rst(rst),

        .v0(v0),
        .v1(v1),
        .v2(v2),

        .in_valid(in_valid),
        .in_ready(in_ready),

        .out_v0x(ts_v0x), .out_v0y(ts_v0y),
        .out_e0x(ts_e0x), .out_e0y(ts_e0y),
        .out_e1x(ts_e1x), .out_e1y(ts_e1y),
        .out_denom_inv(ts_denom_inv),
        .out_bbox_min_x(ts_bbox_min_x), .out_bbox_max_x(ts_bbox_max_x),
        .out_bbox_min_y(ts_bbox_min_y), .out_bbox_max_y(ts_bbox_max_y),
        .out_v0_color(ts_v0_color), .out_v1_color(ts_v1_color), .out_v2_color(ts_v2_color),
        .out_v0_depth(ts_v0_depth), .out_v1_depth(ts_v1_depth), .out_v2_depth(ts_v2_depth),

        .out_valid(ts_out_valid),
        .out_ready(ts_out_ready),
        .busy(ts_busy)
    );

    logic [$clog2(WIDTH)-1:0]  pt_out_x;
    logic [$clog2(HEIGHT)-1:0] pt_out_y;

    logic signed [16+SUBPIXEL_BITS-1:0] pt_v0x, pt_v0y;
    logic signed [16+SUBPIXEL_BITS-1:0] pt_e0x, pt_e0y;
    logic signed [16+SUBPIXEL_BITS-1:0] pt_e1x, pt_e1y;
    logic signed [DENOM_INV_BITS-1:0]  pt_denom_inv;
    color12_t                           pt_v0_color, pt_v1_color, pt_v2_color;
    q16_16_t                            pt_v0_depth, pt_v1_depth, pt_v2_depth;

    logic pt_in_ready;
    logic pt_out_valid;
    logic pt_out_ready;
    logic pt_busy;

    pixel_traversal #(
        .WIDTH(WIDTH),
        .HEIGHT(HEIGHT),
        .SUBPIXEL_BITS(SUBPIXEL_BITS),
        .DENOM_INV_BITS(DENOM_INV_BITS),
        .DENOM_INV_FBITS(DENOM_INV_FBITS)
    ) pt_inst (
        .clk(clk),
        .rst(rst),

        .v0x(ts_v0x), .v0y(ts_v0y),
        .e0x(ts_e0x), .e0y(ts_e0y),
        .e1x(ts_e1x), .e1y(ts_e1y),
        .denom_inv(ts_denom_inv),
        .bbox_min_x(ts_bbox_min_x), .bbox_max_x(ts_bbox_max_x),
        .bbox_min_y(ts_bbox_min_y), .bbox_max_y(ts_bbox_max_y),
        .v0_color(ts_v0_color), .v1_color(ts_v1_color), .v2_color(ts_v2_color),
        .v0_depth(ts_v0_depth), .v1_depth(ts_v1_depth), .v2_depth(ts_v2_depth),

        .in_valid(ts_out_valid),
        .in_ready(ts_out_ready),

        .out_x(pt_out_x),
        .out_y(pt_out_y),
        .out_v0x(pt_v0x), .out_v0y(pt_v0y),
        .out_e0x(pt_e0x), .out_e0y(pt_e0y),
        .out_e1x(pt_e1x), .out_e1y(pt_e1y),
        .out_denom_inv(pt_denom_inv),
        .out_v0_color(pt_v0_color), .out_v1_color(pt_v1_color), .out_v2_color(pt_v2_color),
        .out_v0_depth(pt_v0_depth), .out_v1_depth(pt_v1_depth), .out_v2_depth(pt_v2_depth),

        .out_valid(pt_out_valid),
        .out_ready(pt_out_ready),
        .busy(pt_busy)
    );

    logic                      pe_in_ready;
    logic                      pe_out_valid;
    logic [$clog2(WIDTH)-1:0]  pe_out_x;
    logic [$clog2(HEIGHT)-1:0] pe_out_y;
    color12_t                  pe_out_color;
    q16_16_t                   pe_out_depth;
    logic                      pe_busy;

    pixel_eval #(
        .WIDTH(WIDTH),
        .HEIGHT(HEIGHT),
        .SUBPIXEL_BITS(SUBPIXEL_BITS),
        .DENOM_INV_BITS(DENOM_INV_BITS),
        .DENOM_INV_FBITS(DENOM_INV_FBITS)
    ) pe_inst (
        .clk(clk),
        .rst(rst),

        .pixel_x(pt_out_x),
        .pixel_y(pt_out_y),

        .v0x(pt_v0x), .v0y(pt_v0y),
        .e0x(pt_e0x), .e0y(pt_e0y),
        .e1x(pt_e1x), .e1y(pt_e1y),
        .denom_inv(pt_denom_inv),
        .v0_color(pt_v0_color), .v1_color(pt_v1_color), .v2_color(pt_v2_color),
        .v0_depth(pt_v0_depth), .v1_depth(pt_v1_depth), .v2_depth(pt_v2_depth),

        .in_valid(pt_out_valid),
        .in_ready(pt_out_ready),

        .out_x(pe_out_x),
        .out_y(pe_out_y),
        .out_color(pe_out_color),
        .out_depth(pe_out_depth),
        .out_valid(pe_out_valid),
        .out_ready(out_ready),
        .busy(pe_busy)
    );

    assign out_pixel_x = pe_out_x;
    assign out_pixel_y = pe_out_y;
    assign out_color   = pe_out_color;
    assign out_depth   = pe_out_depth;
    assign out_valid   = pe_out_valid;

    assign busy = ts_busy || pt_busy || pe_busy;

endmodule
