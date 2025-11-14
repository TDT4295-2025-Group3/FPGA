`default_nettype none
`timescale 1ns / 1ps

import math_pkg::*;
import color_pkg::color16_t;

module depthbuffer #(
    parameter int FB_WIDTH  = 160,
    parameter int FB_HEIGHT = 120,
    parameter int DEPTH_BITS = 32
) (
    input wire logic        clk,
    input wire logic        rst,

    input wire logic in_valid,
    input wire logic in_compare_depth,
    input wire color16_t in_color,
    input wire logic [DEPTH_BITS-1:0] in_depth,
    input wire [15:0] in_x,
    input wire [15:0] in_y,

    output logic out_valid,
    output color16_t out_color,
    output logic [15:0] out_x,
    output logic [15:0] out_y
);
    localparam int FB_DEPTH    = FB_WIDTH * FB_HEIGHT;
    localparam int ADDR_WIDTH  = $clog2(FB_DEPTH);

    logic [ADDR_WIDTH-1:0] addr, addr_reg;
    logic [DEPTH_BITS-1:0] depth_mem [0:FB_DEPTH-1];
    logic [DEPTH_BITS-1:0] depth_read;
    logic passed_depth_test;

    // pipeline aligners for inputs (to match BRAM read latency)
    logic        in_valid_s1,         in_valid_s2;
    logic        in_compare_depth_s1, in_compare_depth_s2;
    color16_t    in_color_s1,         in_color_s2;
    logic [DEPTH_BITS-1:0] in_depth_s1,         in_depth_s2;
    logic [15:0] in_x_s1,             in_x_s2;
    logic [15:0] in_y_s1,             in_y_s2;

    // write address aligned to stage 3
    logic [ADDR_WIDTH-1:0] addr_wr_s2;

    // simple write-bypass (RAW hazard) state
    logic                  wr_bypass_vld;
    logic [ADDR_WIDTH-1:0] wr_bypass_addr;
    logic [DEPTH_BITS-1:0] wr_bypass_data;

    // --- Pipeline stage 1: address computation ---
    always_ff @(posedge clk) begin
        // latch inputs for alignment
        in_valid_s1         <= in_valid;
        in_compare_depth_s1 <= in_compare_depth;
        in_color_s1         <= in_color;
        in_depth_s1         <= in_depth;
        in_x_s1             <= in_x;
        in_y_s1             <= in_y;

        addr_reg <= in_y * FB_WIDTH + in_x;      // read address (stage 2)
    end

    // --- Pipeline stage 2: synchronous BRAM read ---
    logic [DEPTH_BITS-1:0] depth_read_bram;

    // BRAM read (registered output)
    always_ff @(posedge clk) begin
        depth_read_bram <= depth_mem[addr_reg];
    end

    // advance pipeline, compute write address corresponding to S2 payload
    always_ff @(posedge clk) begin
        in_valid_s2         <= in_valid_s1;
        in_compare_depth_s2 <= in_compare_depth_s1;
        in_color_s2         <= in_color_s1;
        in_depth_s2         <= in_depth_s1;
        in_x_s2             <= in_x_s1;
        in_y_s2             <= in_y_s1;

        addr_wr_s2          <= in_y_s1 * FB_WIDTH + in_x_s1;
    end

    // RAW bypass applied *outside* the RAM to keep BRAM inference clean
    always_comb begin
        depth_read = depth_read_bram;
        // FIX: use S2-aligned address for bypass (addr_wr_s2), not S1 addr_reg
        if (wr_bypass_vld && (wr_bypass_addr == addr_wr_s2)) begin
            depth_read = wr_bypass_data;
        end
    end

    assign passed_depth_test = (in_compare_depth_s2 == 1'b0) || (in_depth_s2 < depth_read);

    // --- Pipeline stage 3: comparison + writeback ---
    always_ff @(posedge clk) begin
        /* verilator lint_off SYNCASYNCNET */
        if (rst) begin
            /* verilator lint_off SYNCASYNCNET */
            out_valid      <= 1'b0;
            out_color      <= 12'b0;
            out_x          <= 16'b0;
            out_y          <= 16'b0;
            wr_bypass_vld  <= 1'b0;
            wr_bypass_addr <= '0;
            wr_bypass_data <= '0;
        end else begin
            if (in_valid_s2 && passed_depth_test) begin
                out_valid <= 1'b1;
                out_color <= in_color_s2;
                out_x     <= in_x_s2;
                out_y     <= in_y_s2;

                // BRAM write in a dedicated process style
                depth_mem[addr_wr_s2] <= in_depth_s2;

                // update bypass so the very next read of the same address sees new Z
                wr_bypass_vld  <= 1'b1;
                wr_bypass_addr <= addr_wr_s2;
                wr_bypass_data <= in_depth_s2;
            end else begin
                out_valid <= 1'b0;
                out_color <= 12'b0;
                out_x     <= 16'b0;
                out_y     <= 16'b0;

                wr_bypass_vld <= 1'b0;
            end
        end
    end

endmodule
