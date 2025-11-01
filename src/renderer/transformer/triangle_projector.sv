`timescale 1ns / 1ps
`default_nettype wire
import vertex_pkg::*;
import math_pkg::*;

module triangle_projector#(
    parameter int FOCAL_LENGTH = 256
) (
    input  logic clk,
    input  logic rst,

    input  triangle_t triangle,
    input  logic      in_valid,
    output logic      in_ready,

    output triangle_t out_triangle,
    output logic      out_valid,
    input  logic      out_ready,
    output logic      busy
);

    logic v0_busy;
    logic v1_busy;
    logic v2_busy;
    
    logic v0_ready;
    logic v1_ready;
    logic v2_ready;
    
    logic v0_valid;
    logic v1_valid;
    logic v2_valid;

    // Handshake helper signals (local to this module)
    wire all_valid   = v0_valid && v1_valid && v2_valid;
    wire tp_out_ready = out_ready && all_valid;
    
    vertex_projector #(
        .FOCAL_LENGTH(FOCAL_LENGTH)
    ) project_v0 (
        .clk(clk),
        .rst(rst),
        
        .vertex(triangle.v0),
        .in_valid(in_valid),
        .in_ready(v0_ready),
        
        .out_vertex(out_triangle.v0),
        .out_valid(v0_valid),
        .out_ready(tp_out_ready),
        .busy(v0_busy)
    );

    vertex_projector #(
        .FOCAL_LENGTH(FOCAL_LENGTH)
    ) project_v1 (
        .clk(clk),
        .rst(rst),
        
        .vertex(triangle.v1),
        .in_valid(in_valid),
        .in_ready(v1_ready),
        
        .out_vertex(out_triangle.v1),
        .out_valid(v1_valid),
        .out_ready(tp_out_ready),
        .busy(v1_busy)
    );
    
    vertex_projector #(
        .FOCAL_LENGTH(FOCAL_LENGTH)
    )
        project_v2 (
        .clk(clk),
        .rst(rst),
        
        .vertex(triangle.v2),
        .in_valid(in_valid),
        .in_ready(v2_ready),
        
        .out_vertex(out_triangle.v2),
        .out_valid(v2_valid),
        .out_ready(tp_out_ready),
        .busy(v2_busy)
    );
    
    assign busy     = v0_busy || v1_busy || v2_busy;
    assign in_ready = v0_ready && v1_ready && v2_ready;
    assign out_valid = all_valid;
endmodule
