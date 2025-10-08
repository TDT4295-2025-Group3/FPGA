`default_nettype none
`timescale 1ns / 1ps

module triangle_feeder #(
    parameter int N_TRIS   = 4,
    parameter string MEMFILE = "tris.mem"
)(
    input  wire logic        clk,
    input  wire logic        rst,
    input  wire logic        begin_frame,
    input  wire logic        out_ready,
    output      logic        out_valid,
    output      logic        busy,
    output      triangle_t   out_tri
);


    import vertex_pkg::*;

    // Flattened storage (one entry = 324 bits)
    logic [323:0] tri_mem [N_TRIS];

    // Load at elaboration
    initial begin
        $readmemh(MEMFILE, tri_mem);
    end

    // Feed state
    logic [$clog2(N_TRIS)-1:0] idx;
    logic sending;

    assign busy    = sending;
    assign out_tri = triangle_t'(tri_mem[idx]); // cast bits into struct

    always_ff @(posedge clk) begin
        if (rst) begin
            idx       <= '0;
            out_valid <= 1'b0;
            sending   <= 1'b0;
        end else if (begin_frame) begin
            idx       <= '0;
            out_valid <= 1'b1;
            sending   <= 1'b1;
        end else if (sending) begin
            if (out_valid && out_ready) begin
                if (idx == N_TRIS-1) begin
                    out_valid <= 1'b0;
                    sending   <= 1'b0;
                end else begin
                    idx       <= idx + 1;
                    out_valid <= 1'b1;
                end
            end
        end
    end

endmodule
