`default_nettype none
`timescale 1ns / 1ps

package rasterizer_pkg;
    import math_pkg::*;
    import color_pkg::*;
    import vertex_pkg::vertex_t;

   typedef struct packed {
        point2d_t v0, v1, v2;

        logic [15:0]  bbox_min_x, bbox_max_x;
        logic [15:0]  bbox_min_y, bbox_max_y;

        color12_t v0_color, v1_color, v2_color;
        q16_16_t v0_depth, v1_depth, v2_depth;
    } triangle_state_t;

    typedef struct packed {
        logic [15:0] x;
        logic [15:0] y;

        point2d_t v0, v1, v2;
        color12_t v0_color, v1_color, v2_color;
        q16_16_t v0_depth, v1_depth, v2_depth;
    } pixel_state_t;

endpackage
