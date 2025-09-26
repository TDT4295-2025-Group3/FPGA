`default_nettype none
`timescale 1ns / 1ps

package math_pkg;

    typedef logic signed [31:0] q16_16_t;
    typedef logic signed [63:0] q32_32_t;
    typedef logic signed [127:0] q64_64_t;

    function automatic q16_16_t to_q16_16(input int val);
        return val <<< 16;
    endfunction

    function automatic int from_q16_16(input logic signed [31:0] val);
        return val >>> 16;
    endfunction


    typedef struct packed {
        q16_16_t x;
        q16_16_t y;
    } point2d_t;

    typedef struct packed {
        q16_16_t x;
        q16_16_t y;
        q16_16_t z;
    } point3d_t;

    function automatic int clamp (input int value, input int lo, input int hi);
        if (value < lo) return lo;
        else if (value > hi) return hi;
        else return value;
    endfunction

    function automatic q16_16_t min3 (input q16_16_t a, b, c);
        q16_16_t m;
        m = (a < b) ? a : b;
        return (m < c) ? m : c;
    endfunction

    function automatic q16_16_t max3 (input q16_16_t a, b, c);
        q16_16_t m;
        m = (a > b) ? a : b;
        return (m > c) ? m : c;
    endfunction

    function automatic q32_32_t dot2d(input point2d_t p1, p2);
        return (p1.x * p2.x) + (p1.y * p2.y);
    endfunction

endpackage
