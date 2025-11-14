`timescale 1ns / 1ps
`default_nettype none

import math_pkg::*;
import color_pkg::*;

module screen_filler #(
    parameter int WIDTH  = 320,
    parameter int HEIGHT = 240
) (
    input  wire logic clk,
    input  wire logic rst,

    input  wire color12_t fill_color,

    input  wire logic    in_valid,
    output logic         in_ready,

    output logic [15:0] out_pixel_x,
    output logic [15:0] out_pixel_y,
    output color16_t    out_color,
    output logic            out_valid,
    input  wire logic       out_ready,
    output logic            busy
);
    // FSM
    typedef enum logic [0:0] {IDLE, RUN} state_t;
    state_t state, next_state;

    color16_t color_reg;

    logic [15:0] current_x, current_y;
    logic [15:0] next_x,    next_y;

    logic [15:0] x_reg, y_reg;
    logic         valid_reg;
    
    logic can_emit; 
    logic fire_out;
    assign can_emit = (!valid_reg) || out_ready; 
    assign fire_out =  (valid_reg)  && out_ready;

    // Output / status signals
    assign out_pixel_x = x_reg;
    assign out_pixel_y = y_reg;
    assign out_color = color_reg;

    assign out_valid = valid_reg;
    assign in_ready  = (state == IDLE);
    assign busy      = (state != IDLE) || valid_reg;

    always_comb begin
        next_state = state;
        next_x     = current_x;
        next_y     = current_y;

        unique case (state)
            IDLE: begin
                if (in_valid && in_ready) begin
                    next_state = RUN;
                    next_x     = 0;
                    next_y     = 0;
                end
            end
            RUN: begin
                if (can_emit) begin
                    if (current_x < WIDTH-1) begin
                        next_x = current_x + 16'd1;
                    end else begin
                        next_x = 0;
                        if (current_y < HEIGHT-1) begin
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
            x_reg     <= '0;
            y_reg     <= '0;
            current_x   <= '0;
            current_y   <= '0;
            valid_reg <= 1'b0;
        end else begin
            state     <= next_state;
            current_x <= next_x;
            current_y <= next_y;

            if (in_valid && in_ready) begin
                color_reg <= { // convert to 16-bit color
                    {fill_color[11:8], fill_color[11]},  
                    {fill_color[7:4],  fill_color[7:6]},   
                    {fill_color[3:0],  fill_color[3]}      
                };
            end

            if (state == RUN && can_emit) begin
                x_reg        <= current_x;
                y_reg        <= current_y;
                valid_reg        <= 1'b1;
            end else if (fire_out) begin
                valid_reg <= 1'b0;
            end
        end
    end

endmodule
