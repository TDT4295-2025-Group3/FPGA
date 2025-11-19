`default_nettype none
`timescale 1ns / 1ps

module sincos_feeder #(
    parameter int    N_ANGLES    = 4,
    parameter string MEMFILE   = "sincos.mem"
) (
    input  wire logic      clk,
    input  wire logic      rst,

    input  wire logic[$clog2(N_ANGLES)-1:0] angle_idx,

    output      q16_16_t   out_sin,
    output      q16_16_t   out_cos
);

    import vertex_pkg::*;

    logic [63:0] sincos_mem [N_ANGLES];
    initial begin
        if (N_ANGLES > 0) $readmemh(MEMFILE, sincos_mem);
    end

    assign out_sin = sincos_mem[angle_idx][63:32];
    assign out_cos = sincos_mem[angle_idx][31:0];
endmodule
