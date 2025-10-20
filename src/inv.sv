`default_nettype none
`timescale 1ns / 1ps

module inv #(
    parameter IN_BITS   = 64,  // total input width
    parameter IN_FBITS  = 0,   // fractional bits in input (0 = integer input)
    parameter OUT_FBITS = 32   // fractional bits in output (Q0.OUT_FBITS)
)(
    input  wire logic clk,
    input  wire logic rst,
    input  wire logic start,
    input  wire logic signed [IN_BITS-1:0] x,  // signed fixed-point input
    output      logic busy,
    output      logic done,
    output      logic valid,
    output      logic dbz,
    output      logic ovf,
    output      logic signed [OUT_FBITS-1:0] y   // signed fixed-point output (1/x) in Q0.OUT_FBITS
);

    localparam WIDTH = IN_BITS; // divider width = input width

    // Numerator scaled by 2^(IN_FBITS)
    logic signed [WIDTH-1:0] dividend;
    assign dividend = 1 <<< IN_FBITS;

    logic signed [WIDTH-1:0] quotient;

    div #(
        .WIDTH(WIDTH),
        .FBITS(OUT_FBITS)
    ) u_div (
        .clk   (clk),
        .rst   (rst),
        .start (start),
        .busy  (busy),
        .done  (done),
        .valid (valid),
        .dbz   (dbz),
        .ovf   (ovf),
        .a     (dividend),
        .b     (x),
        .val   (quotient)
    );

    logic signed [WIDTH-1:0] shifted;
    assign shifted = quotient >>> (WIDTH - OUT_FBITS);
    assign y = shifted[OUT_FBITS-1:0];

endmodule
