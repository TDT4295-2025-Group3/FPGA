`default_nettype none
`timescale 1ns / 1ps

import math_pkg::*;
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

    logic [ADDR_WIDTH-1:0] addr, addr_reg;
    (* ram_style = "block" *) logic [31:0] depth_mem [0:FB_DEPTH-1];
    logic [31:0] depth_read;
    logic passed_depth_test;

    // pipeline registers to align in_* with depth_read
    logic        in_valid_s1,         in_valid_s2;
    logic        in_compare_depth_s1, in_compare_depth_s2;
    color12_t    in_color_s1,         in_color_s2;
    q16_16_t     in_depth_s1,         in_depth_s2;
    logic [15:0] in_x_s1,             in_x_s2;
    logic [15:0] in_y_s1,             in_y_s2;
    logic [ADDR_WIDTH-1:0] addr_reg_s2;

    // simple 1-entry write-forward buffer (for read-after-write hazard)
    logic                wr_bypass_vld;
    logic [ADDR_WIDTH-1:0] wr_bypass_addr;
    logic [31:0]         wr_bypass_data;

    // --- Pipeline stage 1: address computation ---
    always_ff @(posedge clk) begin
        // latch inputs for alignment
        in_valid_s1         <= in_valid;
        in_compare_depth_s1 <= in_compare_depth;
        in_color_s1         <= in_color;
        in_depth_s1         <= in_depth;
        in_x_s1             <= in_x;
        in_y_s1             <= in_y;

        addr_reg <= in_y * FB_WIDTH + in_x;
    end

    // --- Pipeline stage 2: synchronous BRAM read ---
    always_ff @(posedge clk) begin
        // advance pipeline
        in_valid_s2         <= in_valid_s1;
        in_compare_depth_s2 <= in_compare_depth_s1;
        in_color_s2         <= in_color_s1;
        in_depth_s2         <= in_depth_s1;
        in_x_s2             <= in_x_s1;
        in_y_s2             <= in_y_s1;
        addr_reg_s2         <= addr_reg;

        // default read from memory
        depth_read <= depth_mem[addr_reg];
        // RAW hazard bypass: if last cycle wrote same address, use that value instead
        if (wr_bypass_vld && (wr_bypass_addr == addr_reg)) begin
            depth_read <= wr_bypass_data;
        end
    end

    // Use strict '<' so the first winner on a tie keeps the pixel (prevents farther-from-equal overwrites)
    assign passed_depth_test = (in_compare_depth_s2 == 1'b0) || ($signed(in_depth_s2) <= $signed(depth_read));

    // --- Pipeline stage 3: comparison + writeback ---
    always_ff @(posedge clk) begin
        if (rst) begin
            out_valid       <= 1'b0;
            out_color       <= 12'b0;
            out_x           <= 16'b0;
            out_y           <= 16'b0;
            wr_bypass_vld   <= 1'b0;
            wr_bypass_addr  <= '0;
            wr_bypass_data  <= '0;
        end else begin
            if (in_valid_s2 && passed_depth_test) begin
                out_valid <= 1'b1;
                out_color <= in_color_s2;
                out_x     <= in_x_s2;
                out_y     <= in_y_s2;

                // write depth and update bypass register
                depth_mem[addr_reg_s2] <= in_depth_s2;
                wr_bypass_vld  <= 1'b1;
                wr_bypass_addr <= addr_reg_s2;
                wr_bypass_data <= in_depth_s2;
            end else begin
                out_valid <= 1'b0;
                out_color <= 12'b0;
                out_x     <= 16'b0;
                out_y     <= 16'b0;

                // if we didn’t write this cycle, clear bypass validity
                wr_bypass_vld <= 1'b0;
            end
        end
    end

endmodule
