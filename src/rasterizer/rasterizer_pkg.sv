`default_nettype none
`timescale 1ns / 1ps

package rasterizer_pkg;
    import math_pkg::*;
    import color_pkg::*;
    import vertex_pkg::vertex_t;

   typedef struct packed {
        logic signed [18:0] v0x, v0y; // Q16.3
        logic signed [18:0] e0x, e0y, e1x, e1y; // Q16.3
        logic signed [37:0] d00, d01, d11; // Q32.6

        logic [16:0]        denom_inv; // reciprocal in Q0.16
        logic               denom_neg; // true if denom < 0

        logic [15:0]  bbox_min_x, bbox_max_x;
        logic [15:0]  bbox_min_y, bbox_max_y;

        color12_t v0_color, v1_color, v2_color;
        q16_16_t v0_depth, v1_depth, v2_depth;
    } triangle_state_t;

    typedef struct packed {
        logic [15:0] x;
        logic [15:0] y;

        triangle_state_t triangle;
    } pixel_state_t;

endpackage
