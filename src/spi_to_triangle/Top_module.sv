`timescale 1ns / 1ps
`default_nettype wire
import opcode_defs::*;
import buffer_id_pkg::*;
import vertex_pkg::*;
import transform_pkg::*;

module top_raster_system #(
    parameter MAX_VERT  = 8192, // 2^13 = 8192
    parameter MAX_TRI   = 8192,
    parameter MAX_INST  = 256,
    parameter MAX_VERT_BUF = 256,
    parameter MAX_TRI_BUF  = 256,
    parameter MAX_VERT_CNT = 256,
    parameter MAX_TRI_CNT = 256,
    parameter VTX_W     = 108,
    parameter VIDX_W    = $clog2(MAX_VERT_CNT),
    parameter TIDX_W    = $clog2(MAX_TRI_CNT),
    parameter TRI_W     = 3*VIDX_W,
    parameter DATA_W    = 32,
    parameter TRANS_W   = DATA_W * 9
)(
    // === External signals ===
    input  logic clk,       // raster clock
    input  logic sck,       // SPI clock
    input  logic rst,       // reset
    input  logic CS_n,      // chip select
    input  logic [3:0] mosi,    // SPI inputs
    output logic miso,          // SPI output

    // === Frame driver outputs (for observation / next stage) ===
    input  logic draw_ready,
    output logic draw_done,
    output logic draw_valid
//    output triangle_t tri_out,
//    output transform_t transform_out
);

    // =============================
    // Temporary signals
    // =============================
    
    triangle_t tri_out;  
    transform_t transform_out;
    
    // =============================
    // Internal signals
    // =============================

    // SPI ↔ Raster memory
    logic        opcode_valid;
    logic [3:0]  opcode;

    logic        vert_hdr_valid;
    logic        vert_valid;
    logic [VTX_W-1:0] vert_out;
    logic [$clog2(MAX_VERT)-1:0] vert_base;
    logic [VIDX_W-1:0] vert_count;

    logic        tri_hdr_valid;
    logic        tri_valid;
    logic [TRI_W-1:0] tri_out_mem;
    logic [$clog2(MAX_TRI)-1:0] tri_base;
    logic [TIDX_W-1:0] tri_count;

    logic        inst_valid, inst_id_valid;
    logic [VIDX_W-1:0] vert_id_out;
    logic [TIDX_W-1:0] tri_id_out;
    logic [TRANS_W-1:0] transform_out_mem;
    logic [7:0] inst_id_out;

    logic [3:0] status;

    // Raster memory frame interface
    logic [$clog2(MAX_INST)-1:0] inst_id_rd;
    logic [$clog2(MAX_VERT)-1:0] vert_addr_rd;
    logic [$clog2(MAX_TRI)-1:0] tri_addr_rd;

    logic [$clog2(MAX_VERT)-1:0] curr_vert_base_out;
    logic [VIDX_W-1:0] curr_vert_count_out;
    logic [$clog2(MAX_TRI)-1:0] curr_tri_base_out;
    logic [TIDX_W-1:0] curr_tri_count_out;
    logic [TRI_W-1:0] idx_tri_out;
    vertex_t vert_data_out;
    transform_t transform_data_out;

    // =============================
    // SPI front-end
    // =============================

    spi_driver #(
        .MAX_VERT(MAX_VERT),
        .MAX_TRI(MAX_TRI),
        .MAX_INST(MAX_INST),
        .MAX_VERT_BUF(MAX_VERT_BUF),
        .MAX_TRI_BUF(MAX_TRI_BUF),
        .MAX_VERT_CNT(MAX_VERT_CNT),
        .MAX_TRI_CNT(MAX_TRI_CNT),
        .VTX_W(VTX_W),
        .VIDX_W(VIDX_W),
        .TIDX_W(TIDX_W),
        .TRI_W(TRI_W),
        .DATA_W(DATA_W),
        .TRANS_W(TRANS_W)
    ) u_spi_driver (
        .sck(sck),
        .rst(rst),
        .mosi(mosi),
        .miso(miso),
        .CS_n(CS_n),

        .opcode_valid(opcode_valid),
        .opcode(opcode),

        .vert_hdr_valid(vert_hdr_valid),
        .vert_valid(vert_valid),
        .vert_out(vert_out),
        .vert_base(vert_base),
        .vert_count(vert_count),

        .tri_hdr_valid(tri_hdr_valid),
        .tri_valid(tri_valid),
        .tri_out(tri_out_mem),
        .tri_base(tri_base),
        .tri_count(tri_count),

        .inst_valid(inst_valid),
        .inst_id_valid(inst_id_valid),
        .vert_id_out(vert_id_out),
        .tri_id_out(tri_id_out),
        .transform_out(transform_out_mem),
        .inst_id_out(inst_id_out),

        .status(status)
    );

    // =============================
    // Raster memory
    // =============================

    raster_mem #(
        .MAX_VERT(MAX_VERT),
        .MAX_TRI(MAX_TRI),
        .MAX_INST(MAX_INST),
        .MAX_VERT_BUF(MAX_VERT_BUF),
        .MAX_TRI_BUF(MAX_TRI_BUF),
        .MAX_VERT_CNT(MAX_VERT_CNT),
        .MAX_TRI_CNT(MAX_TRI_CNT),
        .VTX_W(VTX_W),
        .VIDX_W(VIDX_W),
        .TIDX_W(TIDX_W),
        .TRI_W(TRI_W),
        .DATA_W(DATA_W),
        .TRANS_W(TRANS_W)
    ) u_raster_mem (
        .clk(clk),
        .rst(rst),
        .sck(sck),

        .opcode_valid(opcode_valid),
        .opcode(opcode),

        .vert_hdr_valid(vert_hdr_valid),
        .vert_valid(vert_valid),
        .vert_in(vert_out),
        .vert_id_in(vert_id_out),
        .vert_base(vert_base),
        .vert_count(vert_count),

        .tri_hdr_valid(tri_hdr_valid),
        .tri_valid(tri_valid),
        .tri_in(tri_out_mem),
        .tri_id_in(tri_id_out),
        .tri_base(tri_base),
        .tri_count(tri_count),

        .inst_valid(inst_valid),
        .transform_in(transform_out_mem),
        .inst_id_in(inst_id_out),

        .status(status),

        .inst_id_rd(inst_id_rd),
        .vert_addr_rd(vert_addr_rd),
        .tri_addr_rd(tri_addr_rd),

        .curr_vert_base_out(curr_vert_base_out),
        .curr_vert_count_out(curr_vert_count_out),
        .curr_tri_base_out(curr_tri_base_out),
        .curr_tri_count_out(curr_tri_count_out),

        .idx_tri_out(idx_tri_out),
        .vert_out(vert_data_out),
        .transform_out(transform_out)
    );

    // =============================
    // Frame driver
    // =============================

    frame_driver #(
        .MAX_VERT(MAX_VERT),
        .MAX_TRI(MAX_TRI),
        .MAX_VERT_CNT(MAX_VERT_CNT),
        .MAX_TRI_CNT(MAX_TRI_CNT),
        .VTX_W(VTX_W),
        .VIDX_W(VIDX_W),
        .TIDX_W(TIDX_W),
        .TRI_W(TRI_W)
    ) u_frame_driver (
        .clk(clk),
        .rst(rst),

        // Frame driver → memory
        .vert_addr(vert_addr_rd),
        .tri_addr(tri_addr_rd),
        .rd_inst_id(inst_id_rd),

        // Memory → frame driver
        .vert_in(vert_data_out),
        .idx_tri(idx_tri_out),

        .curr_vert_base(curr_vert_base_out),
        .curr_tri_base(curr_tri_base_out),
        .curr_tri_count(curr_tri_count_out),

        // Frame driver → next stage
        .draw_ready(draw_ready),
        .draw_done(draw_done),
        .draw_valid(draw_valid),
        .tri_out(tri_out)
    );
    
    triangle_t end_node_tri;
    transform_t end_node_trans;
    
    assign end_node_tri = tri_out;
    assign end_node_trans = transform_out;

endmodule

