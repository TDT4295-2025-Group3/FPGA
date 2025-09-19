`default_nettype none
`timescale 1ns / 1ps

package math_pkg;

    typedef logic signed [31:0] q16_16_t;
    typedef logic signed [63:0] q32_32_t;
    typedef logic signed [127:0] q64_64_t;

    typedef struct packed {
        q16_16_t x;
        q16_16_t y;
    } point2d_t;

    typedef struct packed {
        q16_16_t x;
        q16_16_t y;
        q16_16_t z;
    } point3d_t;

endpackage
