`default_nettype none
`timescale 1ns / 1ps

package vertex_pkg;
    import math_pkg::point3d_t;
    import color_pkg::color12_t;

    typedef struct packed {
        point3d_t pos;
        color12_t color;
    } vertex_t;

endpackage
