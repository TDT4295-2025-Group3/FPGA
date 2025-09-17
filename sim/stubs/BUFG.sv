`default_nettype none
`timescale 1ns / 1ps

module BUFG (input  wire I, output wire O);
    assign O = I;
endmodule