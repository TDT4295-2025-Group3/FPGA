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

    always_ff @(posedge clk_pix or negedge btn_rst_n) begin
        if (!btn_rst_n) begin
            fb_read_x <= 8'd0;
            fb_read_y <= 7'd0;
        end else begin
            if (sx < (FB_WIDTH << 2))
                fb_read_x <= sx[9:2];
            else
                fb_read_x <= FB_WIDTH-1;

            if (sy < (FB_HEIGHT << 2))
                fb_read_y <= sy[8:2];
            else
                fb_read_y <= FB_HEIGHT-1;
        end
    end
    
    // Render outputs (now driven by render_manager)
    logic  [7:0]  renderer_x;
    logic  [6:0]  renderer_y;
    q16_16_t      renderer_depth;
    logic         renderer_we;
    logic [11:0]  renderer_color;
    logic         renderer_ready;
    logic         renderer_busy;

    logic begin_frame;
    always_ff @(posedge clk_render or negedge btn_rst_n) begin
        if (!btn_rst_n)
            begin_frame <= 1'b0;
        else
            begin_frame <= frame_start_render && !renderer_busy;
    end

    double_framebuffer #(
        .FB_WIDTH (FB_WIDTH),
        .FB_HEIGHT(FB_HEIGHT)
    ) framebuffer_inst (
        .clk_write(clk_render),
        .clk_read (clk_pix),
        .swap     (begin_frame),
        .rst      (!btn_rst_n),

        .write_enable(renderer_we),
        .write_x     (renderer_x),
        .write_y     (renderer_y),
        .write_data  (renderer_color),

        .read_x(fb_read_x),
        .read_y(fb_read_y),
        .read_data(fb_read_data)
    );

    // ----------------------------------------------------------------
    // Triangle feeder (memory based)
    // ----------------------------------------------------------------
    triangle_t feeder_tri;
    logic feeder_valid, feeder_busy;

    q16_16_t offset_x, offset_y;
    // Offset X: sweep from -FB_WIDTH/2 to +FB_WIDTH/2 in q16.16 format
    always_ff @(posedge clk_render or negedge btn_rst_n) begin
        if (!btn_rst_n)
            offset_x <= -($signed(FB_WIDTH) <<< 15); // -FB_WIDTH/2 in q16.16
        else if (begin_frame) begin
            if (offset_x >= ($signed(FB_WIDTH) <<< 15)) // +FB_WIDTH/2 in q16.16
                offset_x <= -($signed(FB_WIDTH) <<< 15);
            else
                offset_x <= offset_x + (32'sd1 <<< 15);
        end
    end

    always_ff @(posedge clk_render or negedge btn_rst_n) begin
        if (!btn_rst_n)
            offset_y <= 11'd0; // Fixed
        else
            offset_y <= 11'd0; // Fixed
    end

    triangle_feeder #(
        .N_TRIS(968),
        .MEMFILE("tris.mem")
    ) feeder_inst (
        .clk        (clk_render),
        .rst        (!btn_rst_n),
        .begin_frame(begin_frame),
        .out_valid  (feeder_valid),
        .out_ready  (renderer_ready), // from render_manager now
        .offset_x   (offset_x),
        .offset_y   (offset_y),
        .busy       (feeder_busy),
        .out_tri    (feeder_tri)
    );

    // ----------------------------------------------------------------
    // Render manager (clear + triangles)
    // ----------------------------------------------------------------
    logic [15:0] rm_x16, rm_y16;
    q16_16_t     rm_depth;
    logic [11:0] rm_color;
    logic        rm_use_depth;
    logic        rm_out_valid;

    // Choose your clear color here (e.g., black)
    localparam color12_t CLEAR_COLOR = 12'h000;

    render_manager #(
        .WIDTH (FB_WIDTH),
        .HEIGHT(FB_HEIGHT)
    ) render_mgr_inst (
        .clk              (clk_render),
        .rst              (!btn_rst_n),

        .begin_frame      (frame_start_render),

        // Triangle path from feeder
        .triangle         (feeder_tri),
        .triangle_valid   (feeder_valid),
        .triangle_ready   (renderer_ready),

        // Fill configuration (constant color, always valid)
        .fill_color       (CLEAR_COLOR),
        .fill_valid       (1'b1),
        .fill_ready       (/* unused */),

        // Unified render outputs
        .out_pixel_x      (rm_x16),
        .out_pixel_y      (rm_y16),
        .out_depth        (rm_depth),
        .out_color        (rm_color),
        .out_compare_depth(rm_use_depth),
        .out_valid        (rm_out_valid),
        .out_ready        (1'b1),          // framebuffer write is always ready
        .busy             (renderer_busy)
    );

    // Downsize manager coords to FB address widths
    assign renderer_x     = rm_x16[7:0];
    assign renderer_y     = rm_y16[6:0];
    assign renderer_color = rm_color;
    assign renderer_we    = rm_out_valid;
    assign renderer_depth = rm_depth; // not used by framebuffer, but kept for completeness

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
