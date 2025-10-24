`default_nettype none
`timescale 1ns / 1ps

module top (
    input  wire logic clk_100m,
    input  wire logic btn_rst_n,
    output      logic vga_hsync,
    output      logic vga_vsync,
    output      logic [3:0] vga_r,
    output      logic [3:0] vga_g,
    output      logic [3:0] vga_b
);

    import math_pkg::*;
    import color_pkg::*;
    import vertex_pkg::*;
    import transformer_pkg::*;

    // ----------------------------------------------------------------
    // Clocks
    // ----------------------------------------------------------------
    logic clk_pix;
    logic clk_render;
    logic clk_locked;

    gfx_clocks clocks_inst (
        .clk_100m   (clk_100m),
        .rst        (!btn_rst_n),
        .clk_pix    (clk_pix),
        .clk_render (clk_render),
        .clk_locked (clk_locked)
    );

    // ----------------------------------------------------------------
    // VGA timing
    // ----------------------------------------------------------------
    localparam CORDW = 10;
    logic [CORDW-1:0] sx, sy;
    logic hsync, vsync, de, frame;

    display_480p display_inst (
        .clk_pix,
        .rst_pix(!clk_locked),
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
    always_ff @(posedge clk_render or negedge btn_rst_n) begin
        if (!btn_rst_n)
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
    always_ff @(posedge clk_render or negedge btn_rst_n) begin
        if (!btn_rst_n)
            offset_x <= -($signed(FB_WIDTH) <<< 15);
        else if (begin_frame) begin
            if (offset_x >= ($signed(FB_WIDTH) <<< 15))
                offset_x <= -($signed(FB_WIDTH) <<< 15);
            else
                offset_x <= offset_x + (32'sd1 <<< 15);
        end
    end

    always_ff @(posedge clk_render or negedge btn_rst_n) begin
        if (!btn_rst_n)
            offset_y <= 11'd0;
        else if (begin_frame) begin
                if (offset_y >= ($signed(FB_HEIGHT) <<< 15))
                    offset_y <= 11'd0;
                else
                    offset_y <= offset_y + (32'sd1 <<< 13);
            end
    end

    triangle_feeder #(
        .N_TRIS(430),
        .MEMFILE("tris.mem")
    ) feeder_inst (
        .clk        (clk_render),
        .rst        (!btn_rst_n),
        .begin_frame(begin_frame),
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
    localparam color12_t CLEAR_COLOR = 12'h223;
    localparam int       FOCAL_LENGTH  = 256;

    transform_t camera_transform;
    transform_t transform;
    transform_setup_t transform_setup;

    assign camera_transform.pos         = '{x:32'h0000_0000, y:32'h0000_0000, z:32'h0000_0000};
    assign camera_transform.rot_sin     = '{x:32'h0000_0000, y:32'h0000_0000, z:32'h0000_0000};
    assign camera_transform.rot_cos     = '{x:32'h0001_0000, y:32'h0001_0000, z:32'h0001_0000};
    assign camera_transform.scale       = '{x:32'h0001_0000, y:32'h0001_0000, z:32'h0001_0000};

    // assign transform.pos                = '{x:32'h0000_0000, y:32'h0000_0000, z:32'hFFF6_0000}; // pos = (0, 0, -10)
    // assign transform.rot_sin            = '{x:32'h0000_8000, y:32'hFFFF_8000, z:32'h0000_0000}; // sin(rx,ry,rz) = (0.5, -0.5, 0)
    // assign transform.rot_cos            = '{x:32'h0000_DDB4, y:32'h0000_DDB4, z:32'h0001_0000}; // cos(rx,ry,rz) = (0.866025, 0.866025, 1) 
    // assign transform.scale              = '{x:32'h0000_199A, y:32'h0000_199A, z:32'h0000_199A}; // scale = (0.1, 0.1, 0.1)
assign transform.pos                = '{x:32'h0000_0000, y:32'h0000_0000, z:32'hFFF6_0000}; // pos = (0, 0, -10)
assign transform.rot_sin            = '{x:32'h0000_0000, y:32'h0000_0000, z:32'h0000_0000}; // sin(rx,ry,rz) = (0, 0, 0)
assign transform.rot_cos            = '{x:32'h0001_0000, y:32'h0001_0000, z:32'h0001_0000}; // cos(rx,ry,rz) = (1, 1, 1)
assign transform.scale              = '{x:32'h0001_0000, y:32'h0001_0000, z:32'h0001_0000}; // scale = (1, 1, 1)


    // logic has_setup_camera_transform;
    // always_ff @(posedge clk_render or negedge btn_rst_n) begin
    //     if (!btn_rst_n) begin
    //         has_setup_camera_transform <= 1'b0;
    //     end else begin
    //         has_setup_camera_transform <= transform_setup.camera_transform_valid;
    //     end
    // end

    logic test;
    always_ff @(posedge clk_render) begin
        test <= !test;
    end

    assign transform_setup.triangle     = feeder_tri;
    assign transform_setup.model_transform = transform;
    assign transform_setup.model_transform_valid = !test;
    assign transform_setup.camera_transform_valid = test;
    assign transform_setup.camera_transform = camera_transform;

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
        .rst              (!btn_rst_n),

        .begin_frame      (frame_start_render),

        .transform_setup   (transform_setup),
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
    logic [11:0] db_out_color;
    logic        db_out_valid;

    depthbuffer #(
        .FB_WIDTH (FB_WIDTH),
        .FB_HEIGHT(FB_HEIGHT)
    ) depthbuffer_inst (
        .clk             (clk_render),
        .rst             (!btn_rst_n),

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
        .rst      (!btn_rst_n),

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
    always_ff @(posedge clk_pix) begin
        de_q      <= de;
        vga_hsync <= hsync;
        vga_vsync <= vsync;
        vga_r     <= de_q ? fb_read_data[11:8] : 4'h0;
        vga_g     <= de_q ? fb_read_data[7:4]  : 4'h0;
        vga_b     <= de_q ? fb_read_data[3:0]  : 4'h0;
    end

endmodule
