`default_nettype none
`timescale 1ns / 1ps

// Takes in signed 32-bit (Q16.16) vectors and outputs their dot product (Q32.32)
module dot2d (
    input  logic signed [31:0] p0x, input logic signed [31:0] p0y,
    input  logic signed [31:0] p1x, input logic signed [31:0] p1y,
    output logic signed [63:0] dot
);
    always_comb begin
        dot = p0x * p1x + p0y * p1y;
    end
endmodule
