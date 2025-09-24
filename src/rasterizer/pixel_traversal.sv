`default_nettype none
`timescale 1ns / 1ps

import rasterizer_pkg::*;
import math_pkg::*;

module pixel_traversal (
    input wire logic            clk,
    input wire logic            rst,

    // From triangle_setup
    input  wire triangle_state_t in_state,
    input  wire logic            in_valid,
    output logic            in_ready,

    // To pixel_eval
    output pixel_state_t    out_pixel,
    output logic            out_valid,
    input  wire logic            out_ready,

    // Visibility
    output logic            busy
);
    // ---- FSM ----
    typedef enum logic [0:0] { IDLE, RUN } state_t;
    state_t state, next_state;

    // ---- Triangle & scan registers ----
    triangle_state_t tri_reg;

    logic [15:0] current_x, current_y;
    logic [15:0] next_x,    next_y;

    // ---- 1-deep output buffer ----
    pixel_state_t pixel_reg;
    logic         pixel_valid;

    // Fire/can-emit helpers
    logic can_emit;     // allowed to produce a pixel this cycle
    logic fire_out;     // downstream handshake on buffered pixel

    assign can_emit = (!pixel_valid) || out_ready;     // buffer empty OR will be freed
    assign fire_out =  (pixel_valid)  && out_ready;    // buffered pixel consumed

    // Handshake up & status
    assign out_pixel = pixel_reg;
    assign out_valid = pixel_valid;
    assign in_ready  = (state == IDLE);
    assign busy      = (state != IDLE) || pixel_valid;

    // ---- Next-state / traversal combinational ----
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
                // Only advance when we actually emit a pixel
                if (can_emit) begin
                    if (current_x < tri_reg.bbox_max_x) begin
                        next_x = current_x + 16'd1;
                    end else begin
                        next_x = tri_reg.bbox_min_x;
                        if (current_y < tri_reg.bbox_max_y) begin
                            next_y = current_y + 16'd1;
                        end else begin
                            // Finished last pixel at (bbox_max_x, bbox_max_y)
                            next_state = IDLE;
                        end
                    end
                end
            end
        endcase
    end

    // ---- Sequential ----
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state       <= IDLE;
            tri_reg     <= '0;
            current_x   <= '0;
            current_y   <= '0;
            pixel_reg   <= '0;
            pixel_valid <= 1'b0;
        end else begin
            // FSM & counters
            state     <= next_state;
            current_x <= next_x;
            current_y <= next_y;

            // Latch new triangle when accepted
            if (in_valid && in_ready) begin
                tri_reg <= in_state;
            end

            // Output buffer behavior:
            // 1) If we are running and allowed to emit -> (re)fill the buffer
            // 2) Else, if downstream just consumed and we didn't refill -> clear valid
            if (state == RUN && can_emit) begin
                pixel_reg.x        <= current_x;
                pixel_reg.y        <= current_y;
                pixel_reg.v0       <= tri_reg.v0;
                pixel_reg.v1       <= tri_reg.v1;
                pixel_reg.v2       <= tri_reg.v2;
                pixel_reg.v0_color <= tri_reg.v0_color;
                pixel_reg.v1_color <= tri_reg.v1_color;
                pixel_reg.v2_color <= tri_reg.v2_color;
                pixel_reg.v0_depth <= tri_reg.v0_depth;
                pixel_reg.v1_depth <= tri_reg.v1_depth;
                pixel_reg.v2_depth <= tri_reg.v2_depth;
                pixel_valid        <= 1'b1;   // buffer is (re)filled
            end else if (fire_out) begin
                pixel_valid <= 1'b0;          // drained and not refilled this cycle
            end
        end
    end
endmodule
