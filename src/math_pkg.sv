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

    function automatic point2d_t point2d_sub(input point2d_t p1, p2);
        point2d_t result;
        result.x = p1.x - p2.x;
        result.y = p1.y - p2.y;
        return result;
    endfunction

    function automatic q32_32_t cross2d(input point2d_t p1, p2);
        return (p1.x * p2.y) - (p1.y * p2.x);
    endfunction

    function automatic q32_32_t dot2d(input point2d_t p1, p2);
        return (p1.x * p2.x) + (p1.y * p2.y);
    endfunction

    function automatic q16_16_t div_q32_32_to_q16_16(input q32_32_t num, input q32_32_t den);
    q64_64_t a = $signed(num);
    q64_64_t b = $signed(den);

    // abs values
    q64_64_t a_abs = (a < 0) ? -a : a;
    q64_64_t b_abs = (b < 0) ? -b : b;

    // round-to-nearest: (a<<16 + b/2) / b, done in abs-space
    q64_64_t res_abs = ((a_abs <<< 16) + (b_abs >>> 1)) / b_abs;

    // restore sign
    q64_64_t res = ((a ^ b) < 0) ? -res_abs : res_abs;

    // narrow to Q16.16
    return q16_16_t'(res[31:0]);
endfunction

endpackage
