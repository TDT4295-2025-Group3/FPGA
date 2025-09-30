`default_nettype none
`timescale 1ns / 1ps

package rasterizer_pkg;
    import math_pkg::*;
    import color_pkg::*;
    import vertex_pkg::vertex_t;

    typedef struct packed {
        logic        valid;
        vertex_t     v0, v1, v2;
        logic [15:0] bbox_min_x, bbox_max_x;
        logic [15:0] bbox_min_y, bbox_max_y;
    } triangle_setup_stage1_t;

    typedef struct packed {
        logic valid;
        logic signed [18:0] v0x, v0y;
        logic signed [18:0] v1x, v1y;
        logic signed [18:0] v2x, v2y;
        logic signed [18:0] e0x, e0y;
        logic signed [18:0] e1x, e1y;
        logic [15:0]  bbox_min_x, bbox_max_x;
        logic [15:0]  bbox_min_y, bbox_max_y;
        color12_t     v0_color, v1_color, v2_color;
        q16_16_t      v0_depth, v1_depth, v2_depth;
    } triangle_setup_stage2_t;

    typedef struct packed {
        logic valid;
        logic signed [18:0] v0x, v0y;
        logic signed [18:0] e0x, e0y;
        logic signed [18:0] e1x, e1y;
        logic signed [37:0] d00, d01, d11;
        logic [15:0]  bbox_min_x, bbox_max_x;
        logic [15:0]  bbox_min_y, bbox_max_y;
        color12_t     v0_color, v1_color, v2_color;
        q16_16_t      v0_depth, v1_depth, v2_depth;
    } triangle_setup_stage3_t;

    typedef struct packed {
        logic valid;
        logic signed [18:0] v0x, v0y;
        logic signed [18:0] e0x, e0y;
        logic signed [18:0] e1x, e1y;
        logic signed [37:0] d00, d01, d11;
        logic signed [75:0] denom;                // Q64.12
        logic [15:0]  bbox_min_x, bbox_max_x;
        logic [15:0]  bbox_min_y, bbox_max_y;
        color12_t     v0_color, v1_color, v2_color;
        q16_16_t      v0_depth, v1_depth, v2_depth;
    } triangle_setup_stage4_t;

    typedef struct packed {
        logic valid;
        logic signed [18:0] v0x, v0y;
        logic signed [18:0] e0x, e0y;
        logic signed [18:0] e1x, e1y;
        logic signed [37:0] d00, d01, d11;
        logic [63:0]        div_divisor;         // Q64.0
        logic               denom_neg;
        logic [15:0]  bbox_min_x, bbox_max_x;
        logic [15:0]  bbox_min_y, bbox_max_y;
        color12_t     v0_color, v1_color, v2_color;
        q16_16_t      v0_depth, v1_depth, v2_depth;
    } triangle_setup_stage5_t;

    typedef struct packed {
        logic signed [18:0] v0x, v0y;                 // Q16.3
        logic signed [18:0] e0x, e0y, e1x, e1y;       // Q16.3
        logic signed [37:0] d00, d01, d11;            // Q32.6

        logic [15:0] denom_inv;                // Q0.16
        logic        denom_neg;                // true if denom < 0

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

 typedef struct packed {
    logic        valid;
    pixel_state_t pixel;
} pixel_eval_stage1_t;

typedef struct packed {
    logic        valid;
    pixel_state_t pixel;
    logic signed [37:0] d20, d21;          // Q32.6
} pixel_eval_stage2_t;

typedef struct packed {
    logic        valid;
    pixel_state_t pixel;
    logic signed [75:0] v_num, w_num, denom; // Q64.12
} pixel_eval_stage3_t;

typedef struct packed {
    logic        valid;
    pixel_state_t pixel;
    logic signed [75:0] v_num, w_num, u_num;  // Q64.12
    logic        is_inside;
} pixel_eval_stage4_t;

typedef struct packed {
    logic        valid;
    pixel_state_t pixel;
    color12_t    color;
    q16_16_t     depth;
} pixel_output_t;

 
endpackage
