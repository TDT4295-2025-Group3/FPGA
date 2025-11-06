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
    
    // JB pmod
    output logic [7:0] red_1_2,   // JB pmod (send out color of vertex 1 and 2 of a triangle)
//    output logic [ID_W-1:0] tri_id_out,
//    output logic [3:0] wait_ctr_out,
    
    output logic [3:0] spi_status_test,   // JC pmod 1-4
    output logic [3:0] error_status_test, // JC pmod 7-10
    output logic [3:0] ready_ctr_out,
    output logic       CS_ready_out,
    output logic       sck_toggle,
    
    // LEDs
    output logic output_bit,
    output logic rst_test_LED
);
    assign rst_test_LED = rst_n;
    
    // ----------------------------------------------------------------
    // Clocks
    // ----------------------------------------------------------------
    logic sck_backup;
//    logic sck;
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
    logic soft_reset;
    logic soft_reset_sync_0;
    logic soft_reset_sync_1;
    logic clk_locked_sync_raster;
    
    // 2-stage synchronization
    always_ff @(posedge clk_render) begin
        clk_locked_sync_raster <= clk_locked;
        soft_reset_sync_0 <= soft_reset;
        soft_reset_sync_1 <= soft_reset_sync_0;
    end
    
    logic rst_sck;
    assign rst_raster = !clk_locked_sync_raster || soft_reset_sync_1;
    assign rst_sck    = !rst_n || soft_reset;
    
        // =========================================================
    // SPI clock synchronization and glitch filtering
    // =========================================================
    logic sck_sync_level;
    logic sck_rise_pulse;
    logic sck_fall_pulse;

    spi_sck_sync #(
        .MIN_PERIOD_CYCLES(23)   // // we want a min period of n_max = T_raw/(2*T_ref)
    ) u_spi_sck_sync (
        .clk_ref(clk_100m),     // reference clock (100 MHz domain)
        .rst_n(rst_n),
        .sck_raw(sck),          // raw external SCK input
        .sck_level(sck_sync_level), // stable version of SCK (optional use)
        .sck_rise_pulse(sck_rise_pulse),
        .sck_fall_pulse(sck_fall_pulse)
    );

    
    // test section
    always_ff @(posedge clk_100m or posedge rst_sck) begin 
        if(rst_sck) begin 
            sck_toggle <= 0;
        end else if(sck_rise_pulse || sck_fall_pulse) begin
            sck_toggle <= !sck_toggle;
        end
    end
        
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
    
    
//    // model/world ↔ world/camera
//    triangle_t  world_triangle;
//    logic world_valid;
//    logic camera_ready;
//    logic world_busy;
    
//    // world/camera ↔ triangle project
//    triangle_t camera_triangle;
//    logic camera_valid;
//    logic project_ready;
//    logic camera_busy;
    
//    // triangle project ↔ rasterdizer stuff
//    triangle_t project_triangle;
//    logic project_valid;
//    logic resterdizer_ready = 1;
//    logic project_busy;

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
        .create_done(create_done),
        
        .spi_status_test(spi_status_test),
        .error_status_test(error_status_test),
        .ready_ctr_out(ready_ctr_out),
        .CS_ready_out(CS_ready_out)
    );
    
//    logic fifo_rst;
//    logic fifo_emty;
//    assign fifo_rst = rst_sck | rst_raster;

//    xpm_fifo_async #(
//        .FIFO_MEMORY_TYPE   ("auto"),
//        .FIFO_WRITE_DEPTH   (16),
//        .WRITE_DATA_WIDTH   (9),
//        .READ_DATA_WIDTH    (9),
//        .READ_MODE          ("fwft"),
//        .CDC_SYNC_STAGES    (2)
//    ) cdc_fifo_inst (
//        // write domain
//        .wr_clk   (sck),
//        .wr_en    (create_done),
//        .din      ({create_done, max_inst}),
//        .full     (),               // not used
    
//        // read domain
//        .rd_clk   (clk_raster),
//        .rd_en    (1'b0),
//        .dout     ({create_done_sync, max_inst_sync}),
//        .empty    (fifo_emty),
    
//        // status/reset
//        .rst      (fifo_rst),
    
//        // optional outputs (left unconnected)
//        .wr_data_count (),
//        .rd_data_count (),
//        .prog_full     (),
//        .prog_empty    (),
//        .overflow      (),
//        .underflow     (),
//        .almost_full   (),
//        .almost_empty  (),
//        .data_valid    (),
//        .sleep         (1'b0)
//    );


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
        .draw_start(1'b1) //draw_start
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
        
        .busy(transform_setup_busy),
        
        .red_1_2(red_1_2)
    );
    
    
//    model_world_transformer
//        u_model_world_transformer (
//        .clk(clk_render),
//        .rst(rst),
//        .camera_transform_valid(camera_transform_valid),
        
//        // communication with frame driver
//        .transform(transform_out),
//        .triangle(world_tri_out),
//        .in_valid(frame_driver_valid),
//        .in_ready(world_ready),
        
//        // communication with world to camera
//        .out_triangle(world_triangle),
//        .out_valid(world_valid),
//        .out_ready(camera_ready),
//        .busy(world_busy)
//    );

//    world_camera_transformer 
//        u_world_camera_transformer (
//        .clk_render(clk_render),
//        .rst(rst),
        
//        .triangle(world_triangle),
//        .in_valid(world_valid),
//        .in_ready(camera_ready),
        
//        .out_triangle(camera_triangle),
//        .out_valid(camera_valid),
//        .out_ready(project_ready),
//        .busy(camera_busy)
//    );  
        
//    triangle_projector 
//        u_trangle_projector (
//        .clk_render(clk_render),
//        .rst(rst),
        
//        .triangle(camera_triangle),
//        .in_valid(camera_valid),
//        .in_ready(project_ready),
        
//        .focal_length(focal_length),
        
//        .out_triangle(project_triangle),
//        .out_valid(project_valid),
//        .out_ready(1'b1),
//        .busy(project_busy)
//    );
    
//    assign tri_id  = tri_id_out[7:0];
//    assign vert_id = vert_id_out[7:0];
    always @(posedge clk_render) begin
        if(|out_model_world)
            output_bit <= 1;
        else
            output_bit <= 0;
    end
endmodule

