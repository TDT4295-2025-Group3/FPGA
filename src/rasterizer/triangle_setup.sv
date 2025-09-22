`default_nettype none
`timescale 1ns / 1ps

import vertex_pkg::*;
import math_pkg::*;
import rasterizer_pkg::*;


module triangle_setup #(
    parameter int WIDTH  = 320,
    parameter int HEIGHT = 240
) (
    input  logic clk,
    input  logic rst,

    input  vertex_t v0,
    input  vertex_t v1,
    input  vertex_t v2,

    input  logic    in_valid,
    output logic    in_ready,

    output triangle_state_t out_state,
    output logic            out_valid
);
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            out_state <= '0;
            out_valid <= 1'b0;
            in_ready  <= 1'b1;
        end else begin
            if (in_valid && in_ready) begin
                // Store vertex positions
                out_state.v0 <= '{x: v0.pos.x, y: v0.pos.y};
                out_state.v1 <= '{x: v1.pos.x, y: v1.pos.y};
                out_state.v2 <= '{x: v2.pos.x, y: v2.pos.y};

                // Compute bounding box (round outwards to pixel edges)
                out_state.bbox_min_x <= clamp(min3(v0.pos.x, v1.pos.x, v2.pos.x) >>> 16, 0, WIDTH-1);
                out_state.bbox_max_x <= clamp((max3(v0.pos.x, v1.pos.x, v2.pos.x) + 32'hFFFF) >>> 16, 0, WIDTH-1);
                out_state.bbox_min_y <= clamp(min3(v0.pos.y, v1.pos.y, v2.pos.y) >>> 16, 0, HEIGHT-1);
                out_state.bbox_max_y <= clamp((max3(v0.pos.y, v1.pos.y, v2.pos.y) + 32'hFFFF) >>> 16, 0, HEIGHT-1);

                // Assign vertex colors and depths
                out_state.v0_color <= v0.color;
                out_state.v1_color <= v1.color;
                out_state.v2_color <= v2.color;
                out_state.v0_depth <= v0.pos.z;
                out_state.v1_depth <= v1.pos.z;
                out_state.v2_depth <= v2.pos.z;

                out_valid <= 1'b1;
                in_ready  <= 1'b0;
            end else if (out_valid && !in_valid) begin
                out_valid <= 1'b0;
                in_ready  <= 1'b1;
            end
        end
    end
endmodule