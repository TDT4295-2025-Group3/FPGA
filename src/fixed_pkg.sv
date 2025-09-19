`default_nettype none
`timescale 1ns / 1ps

package fixed_pkg;

    // Convert 32-bit int to Q16.16 fixed point
    function automatic logic signed [31:0] to_q16_16(input int val);
        return val <<< 16;
    endfunction

    // Convert Q16.16 back to int (truncate fractional part)
    function automatic int from_q16_16(input logic signed [31:0] val);
        return val >>> 16;
    endfunction

endpackage : fixed_pkg
