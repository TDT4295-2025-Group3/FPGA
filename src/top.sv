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

    // ------------------------------------------------------------------------
    // Pixel clock and display timing
    // ------------------------------------------------------------------------
    logic clk_pix;
    logic clk_pix_locked;
    clock_480p clock_pix_inst (
        .clk_100m,
        .rst(!btn_rst_n),
        .clk_pix,
        /* verilator lint_off PINCONNECTEMPTY */
        .clk_pix_5x(),
        /* verilator lint_on PINCONNECTEMPTY */
        .clk_pix_locked
    );

    // SX/SY are still 640x480 coordinates from display_480p
    localparam CORDW = 10;
    logic [CORDW-1:0] sx, sy;
    logic hsync, vsync, de, frame;

    display_480p display_inst (
        .clk_pix,
        .rst_pix(!clk_pix_locked),
        .hsync,
        .vsync,
        .de,
        .frame,
        /* verilator lint_off PINCONNECTEMPTY */
        .line(),
        /* verilator lint_on PINCONNECTEMPTY */
        .sx,
        .sy
    );

    // ------------------------------------------------------------------------
    // Framebuffer (160x120)
    // ------------------------------------------------------------------------
    // Divide by 4 instead of 2 (>>2) so 640x480 → 160x120 mapping
    logic [7:0]  fb_read_x = sx[9:2];
    logic [6:0]  fb_read_y = sy[8:2];
    logic [11:0] fb_read_data;

    logic [7:0]  renderer_x;
    logic [6:0]  renderer_y;
    q16_16_t renderer_depth;
    logic        renderer_we;
    logic [11:0] renderer_color;
    logic renderer_busy;

    localparam FB_WIDTH  = 80;
    localparam FB_HEIGHT = 60;

    double_framebuffer #(
        .FB_WIDTH (FB_WIDTH),
        .FB_HEIGHT(FB_HEIGHT)
    ) framebuffer_inst (
        .clk_write(clk_100m), // Renderer clock
        .clk_read(clk_pix),   // VGA clock
        .swap(frame), // && !renderer_busy), // swap at start of frame if not busy
        .rst(!btn_rst_n),

        .write_enable(renderer_we),
        .write_x(renderer_x),
        .write_y(renderer_y),
        .write_data(renderer_color),

        .read_x(fb_read_x),
        .read_y(fb_read_y),
        .read_data(fb_read_data)
    );


    point3d_t TRI0;
    always_ff @(posedge clk_100m) begin
        if (!btn_rst_n) begin
            TRI0 <= '{to_q16_16(25), to_q16_16(15), to_q16_16(30)};
        end else if(frame) begin
            if (TRI0.x > to_q16_16(160))
                TRI0.x <= to_q16_16(0);
            else
                TRI0.x <= TRI0.x + to_q16_16(1);
        end
    end

    localparam point3d_t TRI1 = '{to_q16_16(50),  to_q16_16( 90), to_q16_16( 50)};
    localparam point3d_t TRI2 = '{to_q16_16(100), to_q16_16( 30), to_q16_16( 75)};
    localparam point3d_t TRI3 = '{to_q16_16(140), to_q16_16(100), to_q16_16(125)};

    localparam color12_t C0 = '{r:4'hF, g:4'h8, b:4'h0};
    localparam color12_t C1 = '{r:4'h8, g:4'h0, b:4'h5};
    localparam color12_t C2 = '{r:4'h0, g:4'h8, b:4'h8};
    localparam color12_t C3 = '{r:4'hF, g:4'hF, b:4'h0};

    rasterizer #(
        .WIDTH(FB_WIDTH),
        .HEIGHT(FB_HEIGHT)
    ) rasterizer_inst (
        .clk(clk_100m),
        .rst(!btn_rst_n),

        .in_valid(frame),
        .in_ready(renderer_busy),

        .v0('{pos: TRI0, color: C0}),
        .v1('{pos: TRI1, color: C1}),
        .v2('{pos: TRI2, color: C2}),

        .out_pixel_x(renderer_x),
        .out_pixel_y(renderer_y),
        .out_depth(renderer_depth),
        .out_color(renderer_color),
        .out_valid(renderer_we)
    );

    always_ff @(posedge clk_pix) begin
        vga_hsync <= hsync;
        vga_vsync <= vsync;
        vga_r     <= de ? fb_read_data[11:8] : 4'h0;
        vga_g     <= de ? fb_read_data[7:4]  : 4'h0;
        vga_b     <= de ? fb_read_data[3:0]  : 4'h0;
    end

endmodule
