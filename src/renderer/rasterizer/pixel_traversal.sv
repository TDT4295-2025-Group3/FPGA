`default_nettype none
`timescale 1ns / 1ps

import rasterizer_pkg::*;
import math_pkg::*;

module pixel_traversal (
    input wire logic            clk,
    input wire logic            rst,

    input  wire triangle_state_t in_state,
    input  wire logic            in_valid,
    output logic            in_ready,

    output pixel_state_t    out_pixel,
    output logic            out_valid,
    input  wire logic       out_ready,
    output logic            busy
);

    // FSM
    typedef enum logic [0:0] {IDLE, RUN} state_t;
    state_t state, next_state;

    triangle_state_t tri_reg;

    logic [15:0] current_x, current_y;
    logic [15:0] next_x,    next_y;

    pixel_state_t pixel_reg;
    logic         pixel_valid_reg;
    
    logic can_emit; 
    logic fire_out;
    assign can_emit = (!pixel_valid_reg) || out_ready; 
    assign fire_out =  (pixel_valid_reg)  && out_ready;

    // Output / status signals
    assign out_pixel = pixel_reg;
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
                    next_x     = in_state.bbox_min_x;
                    next_y     = in_state.bbox_min_y;
                end
            end
            RUN: begin
                if (can_emit) begin
                    if (current_x + 16'd1 < tri_reg.bbox_max_x) begin
                        next_x = current_x + 16'd1;
                    end else begin
                        next_x = tri_reg.bbox_min_x;
                        if (current_y + 16'd1 < tri_reg.bbox_max_y) begin
                            next_y = current_y + 16'd1;
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
            state       <= IDLE;
            tri_reg     <= '0;
            current_x   <= '0;
            current_y   <= '0;
            pixel_reg   <= '0;
            pixel_valid_reg <= 1'b0;
        end else begin
            state     <= next_state;
            current_x <= next_x;
            current_y <= next_y;

            if (in_valid && in_ready) begin
                tri_reg <= in_state;
            end

            if (state == RUN && can_emit) begin
                pixel_reg.x        <= current_x;
                pixel_reg.y        <= current_y;
                pixel_reg.triangle <= tri_reg;
                pixel_valid_reg        <= 1'b1;
            end else if (fire_out) begin
                pixel_valid_reg <= 1'b0;
            end
        end
    end
endmodule
