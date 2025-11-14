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

    // General Purpose I/O
    inout wire logic [5:0] gp_io,  

    // SRAM Left
    inout       wire  [15:0] sram_l_dq,
    output      logic [20:0] sram_l_addr,
    output      logic        sram_l_cs_n,
    output      logic        sram_l_we_n,
    output      logic        sram_l_oe_n,
    output      logic        sram_l_ub_n,
    output      logic        sram_l_lb_n,

    // SRAM Right
    inout       wire  [15:0] sram_r_dq,
    output      logic [20:0] sram_r_addr,
    output      logic        sram_r_cs_n,
    output      logic        sram_r_we_n,
    output      logic        sram_r_oe_n,
    output      logic        sram_r_ub_n,
    output      logic        sram_r_lb_n
);

    import math_pkg::*;
    import color_pkg::*;
    import vertex_pkg::*;
    import transformer_pkg::*;
    // import opcode_defs::*;
    // import buffer_id_pkg::*;
    logic rst_n = 1'b1; // active low reset

    // ----------------------------------------------------------------
    // Clocks
    // ----------------------------------------------------------------
    logic clk_100m;
    logic clk_render;
    logic clk_sram;
    logic clk_locked;

    // new per-domain synchronous resets
    logic rst_100m;
    logic rst_render;
    logic rst_sram;
    logic rst;
    logic rst_pix;

    assign rst = !rst_n;
    assign rst_pix = rst || !clk_locked;

    gfx_clocks clocks_inst (
        .clk_pix    (clk_pix),
        .rst        (!rst_n),
        .clk_100m   (clk_100m),
        .clk_render (clk_render),
        .clk_sram   (clk_sram),
        .clk_locked (clk_locked),
        .rst_100m   (rst_100m),
        .rst_render (rst_render),
        .rst_sram   (rst_sram)
    );

    // // Sck reset pulse with protection flag needed for spi_state during WIPE_ALL opcode
    // always_ff @(posedge sck or posedge rst) begin
    //     if(rst) begin
    //         rst_ctr <= 0;
    //         rst_protect    <= 0;
    //         reset_sck_sync <= 0;
    //     end else begin 
    //         if (rst_ctr == 3) begin           // protect signal an extra cycle
    //             rst_protect    <= 0;
    //             rst_ctr        <= 0;
    //         end else if(rst_ctr == 2) begin   // deasert the reset pulse
    //             reset_sck_sync <= 0;
    //             rst_ctr        <= rst_ctr +1;
    //         end else if(rst_ctr == 1) begin   // system spi_driver ready to be reset
    //             rst_protect    <= 1;
    //             reset_sck_sync <= 1;
    //             rst_ctr        <= rst_ctr +1;
    //         end else if(soft_reset) begin     // if soft reset, start counting
    //             reset_sck_sync <= 0;
    //             rst_ctr        <= rst_ctr +1;
    //         end
    //     end
    // end
    
    // logic rst_sck;
    // assign rst_sck    = rst || reset_sck_sync;
    
    // // =========================================================
    // // SPI clock synchronization and glitch filtering
    // // =========================================================
    // logic sck_sync_level;
    // logic sck_rise_pulse;
    // logic sck_fall_pulse;

    // spi_sck_sync #(
    //     .MIN_PERIOD_CYCLES(SCK_FILTER)   // we want a min period of n_max = T_raw/(2*T_ref)
    // ) u_spi_sck_sync (
    //     .clk_ref(clk_100m),     // reference clock (100 MHz domain)
    //     .rst_n(rst_n),
    //     .sck_raw(sck),          // raw external SCK input
    //     .sck_level(sck_sync_level), // stable version of SCK (optional use)
    //     .sck_rise_pulse(sck_rise_pulse),
    //     .sck_fall_pulse(sck_fall_pulse)
    // );

    // ----------------------------------------------------------------
    // VGA timing
    // ----------------------------------------------------------------
    localparam CORDW = 10;
    logic [CORDW-1:0] sx, sy;
    logic hsync, vsync, de, frame;

    display_480p display_inst (
        .clk_pix,
        .rst_pix(rst_pix),
        .hsync,
        .vsync,
        .de,
        .frame,
        .line(),
        .sx,
        .sy
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
    localparam FB_WIDTH  = 320;
    localparam FB_HEIGHT = 240;

    logic [8:0]  fb_read_x;
    logic [7:0]  fb_read_y;

    color16_t fb_read_data;

    assign fb_read_x = sx[9:1];
    assign fb_read_y = sy[8:1];
    
    // ----------------------------------------------------------------
    // Renderer outputs (render_manager -> depthbuffer)
    // ----------------------------------------------------------------
    logic [15:0] rm_x16, rm_y16;
    q16_16_t     rm_depth;
    color16_t    rm_color;
    logic        rm_use_depth;
    logic        rm_out_valid;
    logic        renderer_busy;
    logic        renderer_ready;

    logic begin_frame;
    always_ff @(posedge clk_render or posedge rst_render) begin
        if (rst_render)
            begin_frame <= 1'b0;
        else
            begin_frame <= frame_start_render && !renderer_busy;
    end

    // ----------------------------------------------------------------
    // Triangle feeder (memory based)
    // ----------------------------------------------------------------
    triangle_t feeder_tri;
    logic feeder_valid, feeder_busy;

    q16_16_t offset_x, offset_y;
    assign offset_x = 32'sd0;
    assign offset_y = 32'sd0;
    // always_ff @(posedge clk_render or posedge rst_render) begin
    //     if (rst_render)
    //         offset_x <= -($signed(FB_WIDTH) <<< 15);
    //     else if (begin_frame) begin
    //         if (offset_x >= ($signed(FB_WIDTH) <<< 15))
    //             offset_x <= -($signed(FB_WIDTH) <<< 15);
    //         else
    //             offset_x <= offset_x + (32'sd1 <<< 15);
    //     end
    // end

    // always_ff @(posedge clk_render or posedge rst_render) begin
    //     if (rst_render)
    //         offset_y <= 11'd0;
    //     else if (begin_frame) begin
    //         if (offset_y >= ($signed(FB_HEIGHT) <<< 15))
    //             offset_y <= 11'd0;
    //         else
    //             offset_y <= offset_y + (32'sd1 <<< 13);
    //     end
    // end

    // ---------- Camera-first sequencing ----------
    // 1) Generate a one-cycle camera pulse at frame start
    logic cam_req;
    always_ff @(posedge clk_render or posedge rst_render) begin
        if (rst_render)
            cam_req <= 1'b0;
        else if (frame_start_render && !renderer_busy)
            cam_req <= 1'b1;   // request camera this frame
        else if (cam_req)
            cam_req <= 1'b0;   // one-shot
    end
    wire cam_pulse = cam_req;   // 1-cycle camera_transform_valid

    // 2) Start feeder one cycle AFTER the camera pulse
    logic feeder_begin_frame;
    always_ff @(posedge clk_render or posedge rst_render) begin
        if (rst_render)
            feeder_begin_frame <= 1'b0;
        else
            feeder_begin_frame <= cam_pulse; // delayed kick for feeder
    end
    // --------------------------------------------

    triangle_feeder #(
        .N_TRIS(712),
        .MEMFILE("tris.mem")
    ) feeder_inst (
        .clk        (clk_render),
        .rst        (rst_render),
        .begin_frame(feeder_begin_frame), // was begin_frame
        .out_valid  (feeder_valid),
        .out_ready  (renderer_ready),
        .offset_x   (offset_x),
        .offset_y   (offset_y),
        .busy       (feeder_busy),
        .out_tri    (feeder_tri)
    );
    

    // ----------------------------------------------------------------
    // Render manager (clear + triangles)
    // ----------------------------------------------------------------



    wire sw_x_en   ='d0; // rotate X when high
    wire sw_y_en   ='d1; // rotate Y when high
    wire sw_z_en   ='d0; // rotate Z when high
    wire sw_cam_en ='d0;

    localparam int N_ANGLES = 256;
    logic [$clog2(N_ANGLES)-1:0] ang_x, ang_y, ang_z;
    logic [$clog2(N_ANGLES)-1:0] ang_cam_x, ang_cam_y, ang_cam_z;

    always_ff @(posedge clk_render or posedge rst_render) begin
        if (rst_render) begin
            ang_x     <= 8'd10;
            ang_y     <= 8'd0;
            ang_z     <= 8'd0;
            ang_cam_x <= 8'd0;
            ang_cam_y <= 8'd0;
            ang_cam_z <= 8'd0;
        end else if (frame_start_render) begin
            if (!sw_cam_en) begin
                if (sw_x_en) ang_x <= ang_x + 1'b1;
                if (sw_y_en) ang_y <= ang_y + 1'b1;
                if (sw_z_en) ang_z <= ang_z + 1'b1;
            end else begin
                if (sw_x_en) ang_cam_x <= ang_cam_x + 1'b1;
                if (sw_y_en) ang_cam_y <= ang_cam_y + 1'b1;
                if (sw_z_en) ang_cam_z <= ang_cam_z + 1'b1;
            end
        end
    end

    q16_16_t sin_x, cos_x, sin_y, cos_y, sin_z, cos_z;
    q16_16_t sin_cam_x, cos_cam_x, sin_cam_y, cos_cam_y, sin_cam_z, cos_cam_z;

    sincos_feeder #(.N_ANGLES(N_ANGLES), .MEMFILE("sincos.mem")) sincos_x (
        .clk(clk_render), .rst(rst_render), .angle_idx(ang_x), .out_sin(sin_x), .out_cos(cos_x)
    );
    sincos_feeder #(.N_ANGLES(N_ANGLES), .MEMFILE("sincos.mem")) sincos_y (
        .clk(clk_render), .rst(rst_render), .angle_idx(ang_y), .out_sin(sin_y), .out_cos(cos_y)
    );
    sincos_feeder #(.N_ANGLES(N_ANGLES), .MEMFILE("sincos.mem")) sincos_z (
        .clk(clk_render), .rst(rst_render), .angle_idx(ang_z), .out_sin(sin_z), .out_cos(cos_z)
    );

    sincos_feeder #(.N_ANGLES(N_ANGLES), .MEMFILE("sincos.mem")) sincos_cam_x (
        .clk(clk_render), .rst(rst_render), .angle_idx(ang_cam_x), .out_sin(sin_cam_x), .out_cos(cos_cam_x)
    );
    sincos_feeder #(.N_ANGLES(N_ANGLES), .MEMFILE("sincos.mem")) sincos_cam_y (
        .clk(clk_render), .rst(rst_render), .angle_idx(ang_cam_y), .out_sin(sin_cam_y), .out_cos(cos_cam_y)
    );
    sincos_feeder #(.N_ANGLES(N_ANGLES), .MEMFILE("sincos.mem")) sincos_cam_z (
        .clk(clk_render), .rst(rst_render), .angle_idx(ang_cam_z), .out_sin(sin_cam_z), .out_cos(cos_cam_z)
    );

    localparam color12_t CLEAR_COLOR = 12'h223;
    localparam int       FOCAL_LENGTH  = 256;

    transform_t camera_transform;
    transform_t transform;
    transform_setup_t transform_setup;

    assign camera_transform.pos         = '{x:32'h0000_0000, y:32'h0000_0000, z:32'h0000_0000};
    assign camera_transform.rot_sin     = '{x:sin_cam_x, y:sin_cam_y, z:sin_cam_z};
    assign camera_transform.rot_cos     = '{x:cos_cam_x, y:cos_cam_y, z:cos_cam_z};
    assign camera_transform.scale       = '{x:32'h0001_0000, y:32'h0001_0000, z:32'h0001_0000};

    assign transform.pos                = '{x:32'h0000_0000, y:32'h0000_0000, z:32'h0100_0000}; // pos = (0, 0, 16)
    assign transform.rot_sin            = '{x:sin_x, y:sin_y, z:sin_z};
    assign transform.rot_cos            = '{x:cos_x, y:cos_y, z:cos_z};
    assign transform.scale              = '{x:32'h0000_4000, y:32'h0000_4000, z:32'h0000_4000}; // scale = (0.25, 0.25, 0.25)



    // Track first triangle of each frame (for camera setup)
    logic first_tri_this_frame;
    always_ff @(posedge clk_render or posedge rst_render) begin
        if (rst_render)
            first_tri_this_frame <= 1'b1;
        else if (begin_frame)
            first_tri_this_frame <= 1'b1;            // new frame: next triangle is camera packet
        else if (feeder_valid && renderer_ready)
            first_tri_this_frame <= 1'b0;            // after first tri handshake, only model packets
    end

    // Fill transform_setup bus: camera first (first triangle), then triangles with model transform
    assign transform_setup.triangle                 = feeder_tri;
    assign transform_setup.model_transform          = transform;
    assign transform_setup.model_transform_valid    = feeder_valid && !first_tri_this_frame;  // all but first triangle
    assign transform_setup.camera_transform_valid   = feeder_valid &&  first_tri_this_frame;  // first triangle per frame
    assign transform_setup.camera_transform         = camera_transform;

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
        .triangle_valid   (feeder_valid),
        .triangle_ready   (renderer_ready),

        .fill_color       (CLEAR_COLOR),
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
    color16_t    db_out_color;
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
        .write_x     (db_out_x[8:0]),
        .write_y     (db_out_y[7:0]),
        .write_data  (db_out_color),

        .read_x(fb_read_x),
        .read_y(fb_read_y),
        .read_data(fb_read_data),

        // SRAM Left (buffer A)
        .sram_l_addr (sram_l_addr),
        .sram_l_dq   (sram_l_dq),
        .sram_l_cs_n (sram_l_cs_n),
        .sram_l_we_n (sram_l_we_n),
        .sram_l_oe_n (sram_l_oe_n),
        .sram_l_ub_n (sram_l_ub_n),
        .sram_l_lb_n (sram_l_lb_n),

        // SRAM Right (buffer B)
        .sram_r_addr (sram_r_addr),
        .sram_r_dq   (sram_r_dq),
        .sram_r_cs_n (sram_r_cs_n),
        .sram_r_we_n (sram_r_we_n),
        .sram_r_oe_n (sram_r_oe_n),
        .sram_r_ub_n (sram_r_ub_n),
        .sram_r_lb_n (sram_r_lb_n)
    );

    // ----------------------------------------------------------------
    // VGA output
    // ----------------------------------------------------------------
    logic de_q;
    always_ff @(posedge clk_pix) begin
        de_q      <= de;
        vga_hsync <= hsync;
        vga_vsync <= vsync;
        vga_r     <= de_q ? fb_read_data.r : 5'd0;
        vga_g     <= de_q ? fb_read_data.g : 6'd0;
        vga_b     <= de_q ? fb_read_data.b : 5'd0;
    end

endmodule
