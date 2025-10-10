`default_nettype none
`timescale 1ns / 1ps

import color_pkg::color12_t;

module depthbuffer #(
    parameter int FB_WIDTH  = 160,
    parameter int FB_HEIGHT = 120
) (
    input wire logic        clk,
    input wire logic        rst,

    input wire logic in_valid,
    input wire logic in_compare_depth,
    input wire color12_t in_color,
    input wire q16_16_t in_depth,
    input wire [15:0] in_x,
    input wire [15:0] in_y,

    output logic out_valid,
    output color12_t out_color,
    output logic [15:0] out_x,
    output logic [15:0] out_y
);
    localparam int FB_DEPTH    = FB_WIDTH * FB_HEIGHT;
    localparam int ADDR_WIDTH  = $clog2(FB_DEPTH);

    logic [ADDR_WIDTH-1:0] addr;
    assign addr = in_y * FB_WIDTH + in_x;

    logic [31:0] depth_mem [0:FB_DEPTH-1];
    logic [31:0] depth_read;

    logic passed_depth_test;

    always_ff @(posedge clk) begin
        depth_read <= depth_mem[addr];
    end

    assign passed_depth_test = (in_compare_depth == 1'b0) || (in_depth < depth_read);

    always_ff @(posedge clk) begin
        if (rst) begin
            out_valid <= 1'b0;
            out_color <= 12'b0;
            out_x     <= 16'b0;
            out_y     <= 16'b0;
        end else begin
            if (in_valid && passed_depth_test) begin
                out_valid <= 1'b1;
                out_color <= in_color;
                out_x     <= in_x;
                out_y     <= in_y;
                depth_mem[addr] <= in_depth;
            end else begin
                out_valid <= 1'b0;
                out_color <= 12'b0;
                out_x     <= 16'b0;
                out_y     <= 16'b0;
            end
        end
    end

endmodule
