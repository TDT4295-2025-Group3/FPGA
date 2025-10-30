`default_nettype none
`timescale 1ns / 1ps

import math_pkg::*;
import color_pkg::*;

module pixel_traversal #(
    parameter int WIDTH  = 320,
    parameter int HEIGHT = 240,
    parameter int SUBPIXEL_BITS = 4,
    parameter int DENOM_INV_BITS = 36,
    parameter int DENOM_INV_FBITS = 35
)(  
    input  wire logic            clk,
    input  wire logic            rst,

    input  wire logic signed [16+SUBPIXEL_BITS-1:0] v0x, v0y,
    input  wire logic signed [16+SUBPIXEL_BITS-1:0] e0x, e0y,
    input  wire logic signed [16+SUBPIXEL_BITS-1:0] e1x, e1y,
    input  wire logic signed [DENOM_INV_BITS-1:0]  denom_inv,
    input  wire logic [$clog2(WIDTH)-1:0]           bbox_min_x, bbox_max_x,
    input  wire logic [$clog2(HEIGHT)-1:0]          bbox_min_y, bbox_max_y,
    input  wire color12_t                           v0_color, v1_color, v2_color,
    input  wire q16_16_t                            v0_depth, v1_depth, v2_depth,
    input  wire logic                               in_valid,
    output      logic                               in_ready,

    output      logic [$clog2(WIDTH)-1:0]           out_x,
    output      logic [$clog2(HEIGHT)-1:0]          out_y,
    output      logic signed [16+SUBPIXEL_BITS-1:0] out_v0x, out_v0y,
    output      logic signed [16+SUBPIXEL_BITS-1:0] out_e0x, out_e0y,
    output      logic signed [16+SUBPIXEL_BITS-1:0] out_e1x, out_e1y,
    output      logic signed [DENOM_INV_BITS-1:0]   out_denom_inv,
    output      color12_t                           out_v0_color, out_v1_color, out_v2_color,
    output      q16_16_t                            out_v0_depth, out_v1_depth, out_v2_depth,
    output      logic                               out_valid,
    input  wire logic                               out_ready,
    output      logic                               busy
);

    // FSM
    typedef enum logic [0:0] {IDLE, RUN} state_t;
    state_t state, next_state;

    logic signed [16+SUBPIXEL_BITS-1:0] tri_v0x, tri_v0y;
    logic signed [16+SUBPIXEL_BITS-1:0] tri_e0x, tri_e0y;
    logic signed [16+SUBPIXEL_BITS-1:0] tri_e1x, tri_e1y;
    logic signed [DENOM_INV_BITS-1:0]  tri_denom_inv;
    logic [$clog2(WIDTH)-1:0]           tri_bbox_min_x, tri_bbox_max_x;
    logic [$clog2(HEIGHT)-1:0]          tri_bbox_min_y, tri_bbox_max_y;
    color12_t                           tri_v0_color, tri_v1_color, tri_v2_color;
    q16_16_t                            tri_v0_depth, tri_v1_depth, tri_v2_depth;

    logic [$clog2(WIDTH)-1:0]  current_x, next_x;
    logic [$clog2(HEIGHT)-1:0] current_y, next_y;

    logic [$clog2(WIDTH)-1:0]  out_x_reg;
    logic [$clog2(HEIGHT)-1:0] out_y_reg;

    logic pixel_valid_reg;
    
    logic can_emit; 
    logic fire_out;
    assign can_emit = (!pixel_valid_reg) || out_ready; 
    assign fire_out =  (pixel_valid_reg)  && out_ready;

    // Output / status signals
    assign out_x          = out_x_reg;
    assign out_y          = out_y_reg;
    assign out_v0x        = tri_v0x;
    assign out_v0y        = tri_v0y;
    assign out_e0x        = tri_e0x;
    assign out_e0y        = tri_e0y;
    assign out_e1x        = tri_e1x;
    assign out_e1y        = tri_e1y;
    assign out_denom_inv  = tri_denom_inv;
    assign out_v0_color   = tri_v0_color;
    assign out_v1_color   = tri_v1_color;
    assign out_v2_color   = tri_v2_color;
    assign out_v0_depth   = tri_v0_depth;
    assign out_v1_depth   = tri_v1_depth;
    assign out_v2_depth   = tri_v2_depth;

    assign out_valid = pixel_valid_reg;
    assign in_ready  = (state == IDLE);
    assign busy      = (state != IDLE) || pixel_valid_reg;

    always_comb begin
        next_state = state;
        next_x     = current_x;
        next_y     = current_y;

        unique case (state)
            IDLE: begin
                if (in_valid && in_ready) begin
                    next_state = RUN;
                    next_x     = bbox_min_x;
                    next_y     = bbox_min_y;
                end
            end
            RUN: begin
                if (can_emit) begin
                    if (current_x < tri_bbox_max_x) begin
                        next_x = current_x + 'd1;
                    end else begin
                        next_x = tri_bbox_min_x;
                        if (current_y < tri_bbox_max_y) begin
                            next_y = current_y + 'd1;
                        end else begin
                            next_state = IDLE;
                        end
                    end
                end
            end
        endcase
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state            <= IDLE;
            current_x        <= '0;
            current_y        <= '0;
            out_x_reg        <= '0;
            out_y_reg        <= '0;
            pixel_valid_reg  <= 1'b0;

            tri_v0x          <= '0; tri_v0y <= '0;
            tri_e0x          <= '0; tri_e0y <= '0;
            tri_e1x          <= '0; tri_e1y <= '0;
            tri_denom_inv    <= '0;
            tri_bbox_min_x   <= '0; tri_bbox_max_x <= '0;
            tri_bbox_min_y   <= '0; tri_bbox_max_y <= '0;
            tri_v0_color     <= '0; tri_v1_color  <= '0; tri_v2_color <= '0;
            tri_v0_depth     <= '0; tri_v1_depth  <= '0; tri_v2_depth <= '0;

        end else begin
            state     <= next_state;
            current_x <= next_x;
            current_y <= next_y;

            // Latch new triangle when accepted
            if (in_valid && in_ready) begin
                tri_v0x         <= v0x;
                tri_v0y         <= v0y;
                tri_e0x         <= e0x;
                tri_e0y         <= e0y;
                tri_e1x         <= e1x;
                tri_e1y         <= e1y;
                tri_denom_inv   <= denom_inv;
                tri_bbox_min_x  <= bbox_min_x;
                tri_bbox_max_x  <= bbox_max_x;
                tri_bbox_min_y  <= bbox_min_y;
                tri_bbox_max_y  <= bbox_max_y;
                tri_v0_color    <= v0_color;
                tri_v1_color    <= v1_color;
                tri_v2_color    <= v2_color;
                tri_v0_depth    <= v0_depth;
                tri_v1_depth    <= v1_depth;
                tri_v2_depth    <= v2_depth;
            end

            // Emit pixel when RUN and consumer is ready (or skid empty)
            if (state == RUN && can_emit) begin
                out_x_reg        <= current_x;
                out_y_reg        <= current_y;
                pixel_valid_reg  <= 1'b1;
            end else if (fire_out) begin
                pixel_valid_reg  <= 1'b0;
            end
        end
    end
endmodule
