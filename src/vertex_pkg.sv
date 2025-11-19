`default_nettype none
`timescale 1ns / 1ps

package vertex_pkg;
    import math_pkg::point3d_t;
    import color_pkg::color12_t;

    typedef struct packed {
        point3d_t pos;
        color12_t color;
    } vertex_t;

    typedef struct packed {
        vertex_t v0;
        vertex_t v1;
        vertex_t v2;
    } triangle_t;

    typedef struct packed {
        point3d_t pos;
        point3d_t rot_sin;
        point3d_t rot_cos;
        point3d_t scale;
    } transform_t;

endpackage
