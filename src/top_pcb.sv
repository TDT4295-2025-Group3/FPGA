`default_nettype none
`timescale 1ns / 1ps

module top_pcb #(
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
    input wire logic clk_pix,       // raster clock

    // VGA
    output      logic [4:0] vga_r,
    output      logic [5:0] vga_g,
    output      logic [4:0] vga_b,
    output      logic vga_hsync,
    output      logic vga_vsync,

    // SPI
    inout wire logic [3:0] spi_io,
    input wire logic spi_clk,
    input wire logic spi_cs_n,

//    input wire logic rst_n,

    // General Purpose I/O
    inout wire logic [5:0] gp_io
);

    import math_pkg::*;
    import color_pkg::*;
    import vertex_pkg::*;
    import transformer_pkg::*;
    import opcode_defs::*;
    import buffer_id_pkg::*;
    logic rst_n = 1'b1; // active low reset 

    // ----------------------------------------------------------------
    // Clocks
    // ----------------------------------------------------------------
    logic clk_100m;
    logic clk_render;
    logic clk_locked;

    // new per-domain synchronous resets
    logic rst;
    logic rst_100m_locked;
    logic rst_render_locked;

    gfx_clocks clocks_inst (
        .clk_pix    (clk_pix),
        .rst        (!rst_n),
        .clk_100m   (clk_100m),
        .clk_render (clk_render),
        .clk_locked (clk_locked),
        .rst_100m   (rst_100m_locked),
        .rst_render (rst_render_locked)
    );

    
    // =========================================================
    // SPI clock synchronization and glitch filtering
    // =========================================================
    logic sck_sync_level;
    logic sck_rise_pulse;
    logic sck_fall_pulse;

    spi_sck_sync #(
        .MIN_PERIOD_CYCLES(SCK_FILTER)   // we want a min period of n_max = T_raw/(2*T_ref)
    ) spi_sck_sync_inst (
        .clk_ref(clk_100m),     // reference clock (100 MHz domain)
        .rst_n(rst_n),
        .sck_raw(spi_clk),      // raw external SCK input
        .sck_level(sck_sync_level),
        .sck_rise_pulse(sck_rise_pulse),
        .sck_fall_pulse(sck_fall_pulse)
    );

    
    logic soft_reset;
    logic rst_protect;
    logic rst_100m;
    logic rst_render;
    logic rst_pix;

    reset_controller 
        reset_ctrl_inst (
    .rst_n              (rst_n),
    // Clocks
    .spi_clk            (spi_clk),
    .sck_rise_pulse     (sck_rise_pulse),
    .clk_render         (clk_render),
    .clk_pix            (clk_pix),
    // Reset inputs
    .soft_reset         (soft_reset),
    .clk_locked         (clk_locked),
    .rst_100m_locked    (rst_100m_locked),
    .rst_render_locked  (rst_render_locked),
    // Reset outputs
    .rst_100m           (rst_100m),
    .rst_render         (rst_render),
    .rst_pix            (rst_pix),
    .rst_protect        (rst_protect)
);


    // Internal signals
    // These signals are used as ports between modules

    // SPI ↔ Raster memory
    logic              opcode_valid;
    logic [3:0]        opcode;

    logic              vert_hdr_valid;
    logic              vert_valid;
    logic [VTX_W-1:0]  vert_out;
    logic [$clog2(MAX_VERT)-1:0] vert_base;
    logic [VIDX_W-1:0] vert_count;

    logic              tri_hdr_valid;
    logic              tri_valid;
    logic [TRI_W-1:0]  tri_out_mem;
    logic [$clog2(MAX_TRI)-1:0] tri_base;
    logic [TIDX_W-1:0] tri_count;

    logic              inst_valid, inst_id_valid;
    logic [ID_W-1:0]   vert_id_out;
    logic [ID_W-1:0]   tri_id_out;
    logic [ID_W-1:0]   inst_id_out;
    logic [TRANS_W-1:0] transform_out_spi;
    logic [3:0]        status;

    // spi frame ↔ driver
    logic [7:0]        max_inst;
    logic [7:0]        max_inst_sync;
    logic              create_done;
    logic              create_done_sync;

    // Raster memory ↔ frame driver
    logic [$clog2(MAX_INST)-1:0] inst_id_rd;
    logic [$clog2(MAX_VERT)-1:0] vert_addr_rd;
    logic [$clog2(MAX_TRI)-1:0]  tri_addr_rd;

    logic [$clog2(MAX_VERT)-1:0] curr_vert_base_out;
    logic [VIDX_W-1:0]           curr_vert_count_out;
    logic [$clog2(MAX_TRI)-1:0]  curr_tri_base_out;
    logic [TIDX_W-1:0]           curr_tri_count_out;
    logic [TRI_W-1:0]            idx_tri_out;
    logic [ID_W*2-1:0]           id_data; // IDs for an inst
    vertex_t                     vert_data_out;
    transform_t                  transform_out_mem;

    // Frame driver ↔ transform_setup
    transform_setup_t  transform_setup;
    logic              transform_setup_ready;
    logic              transform_setup_valid;

    // Frame driver ↔ raster/system
    logic         feed_done;
    logic         frame_driver_busy;
    color12_t     background_color;

    // Transform_setup ↔ model_world
    model_world_t out_model_world;
    logic         model_world_valid;
    logic         model_world_ready;
    logic         transform_setup_busy;

    
    // SPI MCU interface
    // This module takes in quad spi, an spi clock, interprets the data, and
    // pack in into usable registers acording to the spi protocol
    spi_driver #(
        .MAX_VERT       (MAX_VERT),
        .MAX_TRI        (MAX_TRI),
        .MAX_INST       (MAX_INST),
        .MAX_VERT_BUF   (MAX_VERT_BUF),
        .MAX_TRI_BUF    (MAX_TRI_BUF),
        .MAX_VERT_CNT   (MAX_VERT_CNT),
        .MAX_TRI_CNT    (MAX_TRI_CNT),
        .VTX_W          (VTX_W),
        .VIDX_W         (VIDX_W),
        .TIDX_W         (TIDX_W),
        .TRI_W          (TRI_W),
        .ID_W           (ID_W),
        .DATA_W         (DATA_W),
        .TRANS_W        (TRANS_W)
    ) spi_driver_inst (
        .sck            (clk_100m),
        .rst            (rst_100m),
        .rst_protect    (rst_protect),
        .spi_io         (spi_io),
        .CS_n           (spi_cs_n),
        
        .soft_reset     (soft_reset),
        .sck_rise_pulse (sck_rise_pulse),
        .sck_fall_pulse (sck_fall_pulse),

        .opcode_valid   (opcode_valid),
        .opcode         (opcode),

        .vert_hdr_valid (vert_hdr_valid),
        .vert_valid     (vert_valid),
        .vert_out       (vert_out),
        .vert_base      (vert_base),
        .vert_count     (vert_count),

        .tri_hdr_valid  (tri_hdr_valid),
        .tri_valid      (tri_valid),
        .tri_out        (tri_out_mem),
        .tri_base       (tri_base),
        .tri_count      (tri_count),

        .inst_valid     (inst_valid),
        .inst_id_valid  (inst_id_valid),
        .vert_id_out    (vert_id_out),
        .tri_id_out     (tri_id_out),
        .transform_out  (transform_out_spi),
        .inst_id_out    (inst_id_out),
        
        .max_inst       (max_inst),
        .create_done    (create_done)
    );
    
    // Raster memory
    // This module uses falgs and packed data from spi driver to 
    // store and update game models 
    raster_mem #(
        .MAX_VERT       (MAX_VERT),
        .MAX_TRI        (MAX_TRI),
        .MAX_INST       (MAX_INST),
        .MAX_VERT_CNT   (MAX_VERT_CNT),
        .MAX_TRI_CNT    (MAX_TRI_CNT),
        .VTX_W          (VTX_W),
        .VIDX_W         (VIDX_W),
        .TIDX_W         (TIDX_W),
        .TRI_W          (TRI_W),
        .ID_W           (ID_W),
        .DATA_W         (DATA_W),
        .TRANS_W(TRANS_W)
    ) raster_mem_inst (
        .clk            (clk_render),
        .sck            (clk_100m),
        .rst_render     (rst_render),
        .rst_sck        (rst_100m),
        .create_done    (create_done),
        
        .sck_rise_pulse (sck_rise_pulse),
        .sck_fall_pulse (sck_fall_pulse),

        .opcode_valid   (opcode_valid),
        .opcode         (opcode),

        .vert_hdr_valid (vert_hdr_valid),
        .vert_valid     (vert_valid),
        .vert_in        (vert_out),
        .vert_id_in     (vert_id_out),
        .vert_base      (vert_base),
        .vert_count     (vert_count),

        .tri_hdr_valid  (tri_hdr_valid),
        .tri_valid      (tri_valid),
        .tri_in         (tri_out_mem),
        .tri_id_in      (tri_id_out),
        .tri_base       (tri_base),
        .tri_count      (tri_count),

        .inst_valid     (inst_valid),
        .transform_in   (transform_out_spi),
        .inst_id_in     (inst_id_out),

        .inst_id_rd     (inst_id_rd),
        .vert_addr_rd   (vert_addr_rd),
        .tri_addr_rd    (tri_addr_rd),

        .curr_vert_base_out  (curr_vert_base_out),
        .curr_vert_count_out (curr_vert_count_out),
        .curr_tri_base_out   (curr_tri_base_out),
        .curr_tri_count_out  (curr_tri_count_out),

        .idx_tri_out    (idx_tri_out),
        .vert_out       (vert_data_out),
        .id_data        (id_data),
        .transform_out  (transform_out_mem)
    );

    // Frame driver
    // This module look up buffer ids and fetch triangle/vertex data from memory
    frame_driver #(
        .MAX_VERT       (MAX_VERT),
        .MAX_TRI        (MAX_TRI),
        .MAX_VERT_CNT   (MAX_VERT_CNT),
        .MAX_TRI_CNT    (MAX_TRI_CNT),
        .VTX_W          (VTX_W),
        .VIDX_W         (VIDX_W),
        .TIDX_W         (TIDX_W),
        .TRI_W          (TRI_W),
        .ID_W           (ID_W)
    ) frame_driver_inst (
        .clk            (clk_render),
        .rst            (rst_render),
        .max_inst       (max_inst),
        .create_done    (create_done),

        // Frame driver → memory
        .vert_addr      (vert_addr_rd),
        .tri_addr       (tri_addr_rd),
        .inst_id_rd     (inst_id_rd),

        // Memory → frame driver
        .vert_in        (vert_data_out),
        .idx_tri        (idx_tri_out),
        .id_data        (id_data),
        .transform_in   (transform_out_mem),

        .curr_vert_base (curr_vert_base_out),
        .curr_tri_base  (curr_tri_base_out),
        .curr_tri_count (curr_tri_count_out),

        // Frame driver → model world transform
        .out_ready      (renderer_ready),
        .out_valid      (transform_setup_valid),
        .transform_setup(transform_setup),
        
        // Frame driver ↔ razter/system
        .frame_feed_done    (feed_done),    // Do i need to do anything with this ??
        .frame_start_render (frame_start_render),  // begin_frame
        .background_color   (background_color),
        .busy               (frame_driver_busy)
    );
    


    // ----------------------------------------------------------------
    // VGA timing
    // ----------------------------------------------------------------
    localparam CORDW = 10;
    logic [CORDW-1:0] sx, sy;
    logic hsync, vsync, de, frame;

    display_480p display_inst (
        .clk_pix (clk_pix),
        .rst_pix (rst_pix),
        .hsync   (hsync),
        .vsync   (vsync),
        .de      (de),
        .frame   (frame),
        .line    (),
        .sx      (sx),
        .sy      (sy)
    );

    // Sync frame pulse into render domain
    logic frame_pix_sync1, frame_pix_sync2, frame_pix_sync2_d;
    always_ff @(posedge clk_render) begin
        frame_pix_sync1   <= frame;
        frame_pix_sync2   <= frame_pix_sync1;
        frame_pix_sync2_d <= frame_pix_sync2;
    end
    wire frame_start_render = frame_pix_sync2 & ~frame_pix_sync2_d;

    // ----------------------------------------------------------------
    // Framebuffer
    // ----------------------------------------------------------------
    localparam FB_WIDTH  = 160;
    localparam FB_HEIGHT = 120;

    logic [7:0]  fb_read_x;
    logic [6:0]  fb_read_y;

    logic [11:0] fb_read_data;

    assign fb_read_x = sx[9:2];
    assign fb_read_y = sy[8:2];
    
    // ----------------------------------------------------------------
    // Renderer outputs (render_manager -> depthbuffer)
    // ----------------------------------------------------------------
    logic [15:0] rm_x16, rm_y16;
    q16_16_t     rm_depth;
    logic [11:0] rm_color;
    logic        rm_use_depth;
    logic        rm_out_valid;
    logic        renderer_busy;
    logic        renderer_ready;

    logic begin_frame;
    always_ff @(posedge clk_render or posedge rst_render) begin
        if (rst_render)
            begin_frame <= 1'b0;
        else
            begin_frame <= frame_start_render && !renderer_busy && !frame_driver_busy;
    end

    // ----------------------------------------------------------------
    // Render manager (clear + triangles)
    // ----------------------------------------------------------------
    
    localparam color12_t CLEAR_COLOR = 12'h223;
    localparam int       FOCAL_LENGTH  = 256;

    render_manager #(
        .WIDTH (FB_WIDTH),
        .HEIGHT(FB_HEIGHT),
        .FOCAL_LENGTH       (FOCAL_LENGTH),
        .SUBPIXEL_BITS       (3),
        .DENOM_INV_BITS      (36),
        .DENOM_INV_FBITS     (32),
        .BACKFACE_CULLING    (1'b1)
    ) render_mgr_inst (
        .clk              (clk_render),
        .rst              (rst_render),

        .begin_frame      (frame_start_render),

        .transform_setup  (transform_setup),
        .triangle_valid   (transform_setup_valid),
        .triangle_ready   (renderer_ready),

        .fill_color       (background_color),
        .fill_valid       (1'b1),
        .fill_ready       (/* unused */),

        .out_pixel_x      (rm_x16),
        .out_pixel_y      (rm_y16),
        .out_depth        (rm_depth),
        .out_color        (rm_color),
        .out_compare_depth(rm_use_depth),
        .out_valid        (rm_out_valid),
        .out_ready        (1'b1),
        .busy             (renderer_busy)
    );

    // ----------------------------------------------------------------
    // Depth buffer (inserted here)
    // ----------------------------------------------------------------
    logic [15:0] db_out_x, db_out_y;
    logic [11:0] db_out_color;
    logic        db_out_valid;

    depthbuffer #(
        .FB_WIDTH (FB_WIDTH),
        .FB_HEIGHT(FB_HEIGHT)
    ) depthbuffer_inst (
        .clk             (clk_render),
        .rst             (rst_render),

        .in_valid        (rm_out_valid),
        .in_compare_depth(rm_use_depth),
        .in_color        (rm_color),
        .in_depth        (rm_depth),
        .in_x            (rm_x16),
        .in_y            (rm_y16),

        .out_valid       (db_out_valid),
        .out_color       (db_out_color),
        .out_x           (db_out_x),
        .out_y           (db_out_y)
    );

    // ----------------------------------------------------------------
    // Framebuffer (now fed from depthbuffer)
    // ----------------------------------------------------------------
    double_framebuffer #(
        .FB_WIDTH (FB_WIDTH),
        .FB_HEIGHT(FB_HEIGHT)
    ) framebuffer_inst (
        .clk_write(clk_render),
        .clk_read (clk_pix),
        .swap     (begin_frame),
        .rst      (rst_render),

        .write_enable(db_out_valid),
        .write_x     (db_out_x[7:0]),
        .write_y     (db_out_y[6:0]),
        .write_data  (db_out_color),

        .read_x(fb_read_x),
        .read_y(fb_read_y),
        .read_data(fb_read_data)
    );

    // ----------------------------------------------------------------
    // VGA output
    // ----------------------------------------------------------------
    logic de_q;
    logic [4:0] r5;// = {r4, r4[3]};      // 4 bits -> 5 bits
    logic [5:0] g6;// = {g4, g4[3:2]};    // 4 bits -> 6 bits
    logic [4:0] b5;// = {b4, b4[3]};      // 4 bits -> 5 bits
    assign r5 = {fb_read_data[11:8], fb_read_data[11]};
    assign g6 = {fb_read_data[7:4], fb_read_data[7:6]};
    assign b5 = {fb_read_data[3:0], fb_read_data[3]};
    always_ff @(posedge clk_pix) begin
        de_q      <= de;
        vga_hsync <= hsync;
        vga_vsync <= vsync;
        vga_r     <= de_q ? r5 : 5'h0;
        vga_g     <= de_q ? g6 : 6'h0;
        vga_b     <= de_q ? b5 : 5'h0;
    end
    
endmodule
