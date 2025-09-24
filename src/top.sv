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
    logic renderer_ready;
    logic renderer_busy;

    logic begin_frame;
    assign begin_frame = frame && !renderer_busy;

    localparam FB_WIDTH  = 160;
    localparam FB_HEIGHT = 120;

    double_framebuffer #(
        .FB_WIDTH (FB_WIDTH),
        .FB_HEIGHT(FB_HEIGHT)
    ) framebuffer_inst (
        .clk_write(clk_100m), // Renderer clock
        .clk_read(clk_pix),   // VGA clock
        .swap(begin_frame),
        .rst(!btn_rst_n),

        .write_enable(renderer_we),
        .write_x(renderer_x),
        .write_y(renderer_y),
        .write_data(renderer_color),

        .read_x(fb_read_x),
        .read_y(fb_read_y),
        .read_data(fb_read_data)
    );


    localparam color12_t C0 = '{r:4'hF, g:4'h8, b:4'h0};
    localparam color12_t C1 = '{r:4'h8, g:4'h0, b:4'h5};
    localparam color12_t C2 = '{r:4'h0, g:4'h8, b:4'h8};
    localparam color12_t C3 = '{r:4'hF, g:4'hF, b:4'h0};

    triangle_t tris [0:3];
    always_ff @(posedge clk_100m) begin
        // if (!btn_rst_n) begin
            tris[0] <= '{'{pos: '{to_q16_16(25),  to_q16_16(40), to_q16_16(30)},  color: C0},
                        '{pos: '{to_q16_16(50),  to_q16_16(90), to_q16_16(50)},  color: C1},
                        '{pos: '{to_q16_16(100), to_q16_16(30), to_q16_16(75)},  color: C2}};
            tris[1] <= '{'{pos: '{to_q16_16(60),  to_q16_16(20), to_q16_16(20)},  color: C1},
                        '{pos: '{to_q16_16(120), to_q16_16(80), to_q16_16(60)},  color: C2},
                        '{pos: '{to_q16_16(140), to_q16_16(10), to_q16_16(90)},  color: C3}};
            tris[2] <= '{'{pos: '{to_q16_16(10),  to_q16_16(100), to_q16_16(10)},  color: C2},
                        '{pos: '{to_q16_16(30),  to_q16_16(140), to_q16_16(30)},  color: C3},
                        '{pos: '{to_q16_16(80),  to_q16_16(120), to_q16_16(50)},  color: C0}};
            tris[3] <= '{'{pos: '{to_q16_16(90),  to_q16_16(60), to_q16_16(40)},  color: C3},
                        '{pos: '{to_q16_16(130), to_q16_16(90), to_q16_16(70)},  color: C0},
                        '{pos: '{to_q16_16(150), to_q16_16(130), to_q16_16(100)}, color: C1}};
        // end
    end

    // Drive triangles into rasterizer one by one
    logic [1:0] tri_index;
    logic      renderer_valid;
    always_ff @(posedge clk_100m) begin
        if (!btn_rst_n) begin
            tri_index <= 0;
            renderer_valid <= 0;
        end else if (begin_frame) begin
            tri_index <= 0; // start over at new frame
            renderer_valid <= 1;
            $display("New frame at time %0t", $time);
        end else if (renderer_ready) begin
            if (tri_index == 3)
                renderer_valid <= 0; // all done for this frame
            else begin
                $display("Starting rasterization of triangle %0d at time %0t", tri_index, $time);
                tri_index <= tri_index + 1;
                renderer_valid <= 1;
            end

        end
        else begin
            renderer_valid <= 0; // all done for this frame
        end

    end

    rasterizer #(
        .WIDTH(FB_WIDTH),
        .HEIGHT(FB_HEIGHT)
    ) rasterizer_inst (
        .clk(clk_100m),
        .rst(!btn_rst_n),

        .in_valid(renderer_valid),
        .in_ready(renderer_ready),
        .busy(renderer_busy),

        .v0(tris[tri_index].v0),
        .v1(tris[tri_index].v1),
        .v2(tris[tri_index].v2),

        .out_pixel_x(renderer_x),
        .out_pixel_y(renderer_y),
        .out_depth(renderer_depth),
        .out_color(renderer_color),
        .out_valid(renderer_we),
        .out_ready(1'b1) // Always ready
    );

    always_ff @(posedge clk_pix) begin
        vga_hsync <= hsync;
        vga_vsync <= vsync;
        vga_r     <= de ? fb_read_data[11:8] : 4'h0;
        vga_g     <= de ? fb_read_data[7:4]  : 4'h0;
        vga_b     <= de ? fb_read_data[3:0]  : 4'h0;
    end

endmodule
