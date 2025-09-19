`default_nettype none
`timescale 1ns / 1ps

import math_pkg::point2d_t;
import math_pkg::q32_32_t;

module dot2d (
    input  point2d_t p0,
    input  point2d_t p1,
    output q32_32_t dot
);
    always_comb begin
        dot = p0.x * p1.x + p0.y * p1.y;
    end
endmodule
