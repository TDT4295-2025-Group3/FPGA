`timescale 1ns / 1ps
`default_nettype wire
import opcode_defs::*;
import buffer_id_pkg::*;
import math_pkg::*;
import vertex_pkg::*;
import transformer_pkg::*;

module top_raster_system #(
    parameter MAX_VERT  = 8192,     // 2^13 bit = 8192, 
    parameter MAX_TRI   = 8192,     // 2^13 bit = 8192,
    parameter MAX_INST  = 256,      // maximum instences
    parameter SCK_FILTER    = 50,    // Min filter period for edge detection, we want n_max = T_raw/(2*T_ref)
    localparam MAX_VERT_BUF = 256,   // maximum distinct vertex buffers
    localparam MAX_TRI_BUF  = 256,   // maximum distinct triangle buffers
    localparam MAX_VERT_CNT = 4096,  // max vertices per buffer
    localparam MAX_TRI_CNT  = 4096,  // max triangles per buffer
    localparam VTX_W     = 108,
    localparam VIDX_W    = $clog2(MAX_VERT_CNT),
    localparam TIDX_W    = $clog2(MAX_TRI_CNT),
    localparam TRI_W     = 3*VIDX_W,
    localparam ID_W      = 8,
    localparam DATA_W    = 32,
    localparam TRANS_W   = DATA_W * 12
)(
    // === External signals ===
    input  logic clk_100m,       // raster clock
    input  logic sck,            // SPI clock
    input  logic rst_n,          // reset
    input  logic CS_n,           // chip select
    inout  logic [3:0] spi_io,   // SPI inputs
    
    // Pmod B-D
    output logic [7:0] red_1_2,   // JB pmod (send out color of vertex 1 and 2 of a triangle)
    output logic [3:0] red_3,
    output logic [7:0] inst_id_rd_out,
    
    output logic create_done_out,
    
    
    
    // LEDs
    output logic output_bit,
    output logic rst_test_LED
);
//    logic [3:0] red_1_2;
    assign rst_test_LED = rst_n;
    
    // ----------------------------------------------------------------
    // Clocks
    // ----------------------------------------------------------------
    logic sck_backup;
    logic sck_no_use;
    logic clk_render;
    logic clk_locked;

    gfx_clocks_spi clocks_inst (
        .clk_100m   (clk_100m),
        .rst        (!rst_n),
        .sck        (sck_no_use),
        .clk_render (clk_render),
        .clk_locked (clk_locked)
    );
    
    logic rst_raster;
    logic rst;
    logic soft_reset;
    logic reset_raster_sync_0;
    logic reset_raster_sync_1;
    logic [2:0] rst_ctr;
    logic rst_protect;
    logic reset_sck_sync;
    logic clk_locked_sync_raster;
    
    assign rst = !rst_n;
    // 2-stage synchronization
    always_ff @(posedge clk_render or posedge rst) begin
        if(rst) begin
            reset_raster_sync_0 <= 0;
            reset_raster_sync_1 <= 0;
        end else begin
            clk_locked_sync_raster <= clk_locked;
            reset_raster_sync_0 <= soft_reset;
            reset_raster_sync_1 <= reset_raster_sync_0;
        end
    end
    
    // Sck reset pulse with protection flag needed for state
    always_ff @(posedge sck or posedge rst) begin
        if(rst) begin
            rst_ctr <= 0;
            rst_protect    <= 0;
            reset_sck_sync <= 0;
        end else begin 
            if (rst_ctr == 3) begin           // protect signal an extra cycle
                rst_protect    <= 0;
                rst_ctr        <= 0;
            end else if(rst_ctr == 2) begin   // deasert the reset pulse
                reset_sck_sync <= 0;
                rst_ctr        <= rst_ctr +1;
            end else if(rst_ctr == 1) begin   // system spi_driver ready to be reset
                rst_protect    <= 1;
                reset_sck_sync <= 1;
                rst_ctr        <= rst_ctr +1;
            end else if(soft_reset) begin     // if soft reset, start counting
                reset_sck_sync <= 0;
                rst_ctr        <= rst_ctr +1;
            end
        end
    end
    
    logic rst_sck;
    assign rst_raster = !clk_locked_sync_raster || reset_raster_sync_1;
    assign rst_sck    = rst || reset_sck_sync;
    assign rst_wipe   = rst && !reset_sck_sync;
    
        // =========================================================
    // SPI clock synchronization and glitch filtering
    // =========================================================
    logic sck_sync_level;
    logic sck_rise_pulse;
    logic sck_fall_pulse;

    spi_sck_sync #(
        .MIN_PERIOD_CYCLES(SCK_FILTER)   // we want a min period of n_max = T_raw/(2*T_ref)
    ) u_spi_sck_sync (
        .clk_ref(clk_100m),     // reference clock (100 MHz domain)
        .rst_n(rst_n),
        .sck_raw(sck),          // raw external SCK input
        .sck_level(sck_sync_level), // stable version of SCK (optional use)
        .sck_rise_pulse(sck_rise_pulse),
        .sck_fall_pulse(sck_fall_pulse)
    );
    
    // =============================
    // Internal signals
    // =============================
    q16_16_t focal_length = -5;

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
    logic [ID_W-1:0] vert_id_out;
    logic [ID_W-1:0] tri_id_out;
    logic [ID_W-1:0] inst_id_out;
    logic [TRANS_W-1:0] transform_out_spi;
    logic [3:0] status;
    
    // spi frame ↔ driver
    logic [7:0] max_inst;
    logic [7:0] max_inst_sync;
    logic       create_done;
    logic       create_done_sync;
    
    // Raster memory ↔ frame driver
    logic [$clog2(MAX_INST)-1:0] inst_id_rd;
    logic [$clog2(MAX_VERT)-1:0] vert_addr_rd;
    logic [$clog2(MAX_TRI)-1:0] tri_addr_rd;

    logic [$clog2(MAX_VERT)-1:0] curr_vert_base_out;
    logic [VIDX_W-1:0] curr_vert_count_out;
    logic [$clog2(MAX_TRI)-1:0] curr_tri_base_out;
    logic [TIDX_W-1:0] curr_tri_count_out;
    logic [TRI_W-1:0] idx_tri_out;
    vertex_t vert_data_out;
    transform_t transform_out_mem;

    // Frame driver ↔ transform_setup
    logic transform_setup_ready;
    logic transform_setup_valid;
    transform_setup_t transform_setup;
    
    // Frame driver ↔ razter/system
    logic feed_done;
    logic draw_start;
    logic frame_driver_busy;
    
    
    // Transform_setup ↔ model_world
    model_world_t out_model_world;
    logic model_world_valid;
    logic model_world_ready; 
    logic transform_setup_busy;
    
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
        .ID_W(ID_W),
        .DATA_W(DATA_W),
        .TRANS_W(TRANS_W)
    ) u_spi_driver (
        .sck(clk_100m),
        .rst(rst_sck),
        .rst_protect(rst_protect),
        .spi_io(spi_io),
        .CS_n(CS_n),
        
        .soft_reset(soft_reset),
        .sck_rise_pulse(sck_rise_pulse),
        .sck_fall_pulse(sck_fall_pulse),

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
        .transform_out(transform_out_spi),
        .inst_id_out(inst_id_out),
        
        .max_inst(max_inst),
        .create_done(create_done)
    );
    
    // =============================
    // Raster memory
    // =============================

    raster_mem #(
        .MAX_VERT(MAX_VERT),
        .MAX_TRI(MAX_TRI),
        .MAX_INST(MAX_INST),
        .MAX_VERT_CNT(MAX_VERT_CNT),
        .MAX_TRI_CNT(MAX_TRI_CNT),
        .VTX_W(VTX_W),
        .VIDX_W(VIDX_W),
        .TIDX_W(TIDX_W),
        .TRI_W(TRI_W),
        .ID_W(ID_W),
        .DATA_W(DATA_W),
        .TRANS_W(TRANS_W)
    ) u_raster_mem (
        .clk(clk_render),
        .rst_sck(rst_sck),
        .rst_raster(rst_raster),
        .sck(clk_100m),
        .create_done(create_done),
        
        .sck_rise_pulse(sck_rise_pulse),
        .sck_fall_pulse(sck_fall_pulse),

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
        .transform_in(transform_out_spi),
        .inst_id_in(inst_id_out),

        .inst_id_rd(inst_id_rd),
        .vert_addr_rd(vert_addr_rd),
        .tri_addr_rd(tri_addr_rd),

        .curr_vert_base_out(curr_vert_base_out),
        .curr_vert_count_out(curr_vert_count_out),
        .curr_tri_base_out(curr_tri_base_out),
        .curr_tri_count_out(curr_tri_count_out),

        .idx_tri_out(idx_tri_out),
        .vert_out(vert_data_out),
        .transform_out(transform_out_mem)
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
        .TRI_W(TRI_W),
        .ID_W(ID_W)
    ) u_frame_driver (
        .clk(clk_render),
        .rst(rst_raster),
        .max_inst(max_inst),
        .create_done(create_done),

        // Frame driver → memory
        .vert_addr(vert_addr_rd),
        .tri_addr(tri_addr_rd),
        .inst_id_rd(inst_id_rd),

        // Memory → frame driver
        .vert_in(vert_data_out),
        .idx_tri(idx_tri_out),
        .transform_in(transform_out_mem),

        .curr_vert_base(curr_vert_base_out),
        .curr_tri_base(curr_tri_base_out),
        .curr_tri_count(curr_tri_count_out),

        // Frame driver → model world transform
        .out_ready(transform_setup_ready),
        .out_valid(transform_setup_valid),
        .transform_setup(transform_setup),
        
        // Frame driver ↔ razter/system
        .draw_done(feed_done),
        .busy(frame_driver_busy),
        .draw_start(1'b1), //draw_start
        
        
        .red_1_2(red_1_2),
        .red_3(red_3)
    );
    
    transform_setup 
        u_transform_setup(
        .clk(clk_render),
        .rst(rst_raster),
        
        .transform_setup(transform_setup),
        .in_valid(transform_setup_valid),
        .in_ready(transform_setup_ready),
        
        .out_model_world(out_model_world),
        .out_valid(model_world_valid),
        .out_ready(1'b1), //model_world_ready
        
        .busy(transform_setup_busy)
    );
    
    assign inst_id_rd_out = inst_id_rd[3:0];
    assign create_done_out = create_done;
    
    always @(posedge clk_render) begin
        if(|out_model_world)
            output_bit <= 1;
        else
            output_bit <= 0;
    end
endmodule

