`default_nettype none
`timescale 1ns / 1ps

module triangle_feeder #(
    parameter int    N_TRIS    = 4,
    parameter string MEMFILE   = "tris.mem"
) (
    input  wire logic      clk,
    input  wire logic      rst,

    input  wire logic      begin_frame,
    input  wire logic      out_ready,
    input  wire q16_16_t   offset_x,
    input  wire q16_16_t   offset_y,

    output      logic      out_valid,
    output      triangle_t out_tri,
    output      logic      busy
);

    import vertex_pkg::*;

    logic [323:0] tri_mem [N_TRIS];
    initial begin
        if (N_TRIS > 0) $readmemh(MEMFILE, tri_mem);
    end

    localparam int IDX_W = (N_TRIS <= 1) ? 1 : $clog2(N_TRIS);

    logic [IDX_W-1:0] idx;  
    logic             sending;
    logic             have_data;

    triangle_t out_tri_reg;

    assign out_valid = have_data;
    assign out_tri   = out_tri_reg;

    assign busy = sending || have_data;

    function automatic triangle_t load_with_offset(input logic [IDX_W-1:0] i);
        triangle_t t;
        t = triangle_t'(tri_mem[i]);
        t.v0.pos.x = t.v0.pos.x + offset_x;
        t.v0.pos.y = t.v0.pos.y + offset_y;
        t.v1.pos.x = t.v1.pos.x + offset_x;
        t.v1.pos.y = t.v1.pos.y + offset_y;
        t.v2.pos.x = t.v2.pos.x + offset_x;
        t.v2.pos.y = t.v2.pos.y + offset_y;
        return t;
    endfunction

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            idx        <= '0;
            sending    <= 1'b0;
            have_data  <= 1'b0;
            out_tri_reg<= '0;
        end else begin
            if (begin_frame) begin
                if (N_TRIS > 0) begin
                    idx         <= '0;
                    out_tri_reg <= load_with_offset('0);
                    have_data   <= 1'b1;
                    sending     <= 1'b1;
                end else begin
                    idx        <= '0;
                    have_data  <= 1'b0;
                    sending    <= 1'b0;
                end
            end
            else if (sending && out_valid && out_ready) begin
                if (idx == N_TRIS-1) begin
                    have_data <= 1'b0;
                    sending   <= 1'b0;
                end else begin
                    idx         <= idx + 1'b1;
                    out_tri_reg <= load_with_offset(idx + 1'b1);
                    have_data   <= 1'b1;
                end
            end
        end
    end
endmodule
