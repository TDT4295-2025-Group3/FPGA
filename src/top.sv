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


    import fixed_pkg::*;
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
    logic        renderer_we;
    logic [11:0] renderer_color;

    double_framebuffer #(
        .FB_WIDTH (160),
        .FB_HEIGHT(120)
    ) framebuffer_inst (
        .clk_write(clk_100m), // Renderer clock
        .clk_read(clk_pix),   // VGA clock
        .swap(frame),
        .rst(!btn_rst_n),

        .write_enable(renderer_we),
        .write_x(renderer_x),
        .write_y(renderer_y),
        .write_data(renderer_color),

        .read_x(fb_read_x),
        .read_y(fb_read_y),
        .read_data(fb_read_data)
    );

    // ------------------------------------------------------------------------
    // Triangle setup
    // ------------------------------------------------------------------------
    localparam color12_t BG_COLOR = '{r:4'h1, g:4'h2, b:4'h3};

    point3d_t TRI0;
    logic [7:0] anim_cnt;

    always_ff @(posedge clk_100m or negedge btn_rst_n) begin
        if (!btn_rst_n)
            anim_cnt <= 0;
        else if (frame)
            anim_cnt <= anim_cnt + 1;
    end

    always_comb begin
        TRI0.x = to_q16_16(25) + to_q16_16($signed(anim_cnt));
        TRI0.y = to_q16_16(15) + to_q16_16($signed(anim_cnt >> 1));
        TRI0.z = to_q16_16(30);
    end

    // Adjust triangle coordinates to fit in 160x120 space
    localparam point3d_t TRI1 = '{to_q16_16(50),  to_q16_16( 90), to_q16_16( 50)};
    localparam point3d_t TRI2 = '{to_q16_16(100), to_q16_16( 30), to_q16_16( 75)};
    localparam point3d_t TRI3 = '{to_q16_16(140), to_q16_16(100), to_q16_16(125)};

    localparam color12_t C0 = '{r:4'hF, g:4'h8, b:4'h0};
    localparam color12_t C1 = '{r:4'h8, g:4'h0, b:4'h5};
    localparam color12_t C2 = '{r:4'h0, g:4'h8, b:4'h8};
    localparam color12_t C3 = '{r:4'hF, g:4'hF, b:4'h0};

    point2d_t p;
    color12_t paint_color;
    logic p_inside1, p_inside2;
    color12_t p_color1, p_color2;
    q16_16_t pz1, pz2;

    triangle_pixel_eval tri_fill_inst1 (
        .a(TRI0), .b(TRI1), .c(TRI2),
        .a_color(C0), .b_color(C1), .c_color(C2),
        .p(p), .p_z(pz1), .p_inside(p_inside1), .p_color(p_color1)
    );

    triangle_pixel_eval tri_fill_inst2 (
        .a(TRI1), .b(TRI2), .c(TRI3),
        .a_color(C1), .b_color(C2), .c_color(C3),
        .p(p), .p_z(pz2), .p_inside(p_inside2), .p_color(p_color2)
    );

    // ------------------------------------------------------------------------
    // Renderer FSM (runs on clk_100m)
    // ------------------------------------------------------------------------
    typedef enum logic [1:0] {IDLE, DRAWING, WAIT_SWAP} render_state_t;
    render_state_t state;

    always_ff @(posedge clk_100m or negedge btn_rst_n) begin
        if (!btn_rst_n) begin
            state <= IDLE;
            renderer_x <= 0;
            renderer_y <= 0;
            renderer_we <= 0;
            renderer_color <= 12'h000;
            paint_color <= BG_COLOR;
            p.x <= 0;
            p.y <= 0;
        end else begin
            case (state)
                IDLE: begin
                    renderer_we <= 0;
                    if (frame) begin
                        renderer_x <= 0;
                        renderer_y <= 0;
                        state <= DRAWING;
                    end
                end

                DRAWING: begin
                    p.x <= to_q16_16(renderer_x <<< 2); // scale up to match 640x480
                    p.y <= to_q16_16(renderer_y <<< 2);

                    if (p_inside1)      paint_color <= p_color1;
                    else if (p_inside2) paint_color <= p_color2;
                    else                paint_color <= BG_COLOR;

                    renderer_color <= {paint_color.r, paint_color.g, paint_color.b};
                    renderer_we <= 1'b1;

                    if (renderer_x == 159) begin
                        renderer_x <= 0;
                        if (renderer_y == 119) begin
                            renderer_y <= 0;
                            renderer_we <= 0;
                            state <= WAIT_SWAP;
                        end else begin
                            renderer_y <= renderer_y + 1;
                        end
                    end else begin
                        renderer_x <= renderer_x + 1;
                    end
                end

                WAIT_SWAP: begin
                    renderer_we <= 0;
                    if (frame) state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

    // ------------------------------------------------------------------------
    // VGA Output (read side)
    // ------------------------------------------------------------------------
    always_ff @(posedge clk_pix) begin
        vga_hsync <= hsync;
        vga_vsync <= vsync;
        vga_r     <= de ? fb_read_data[11:8] : 4'h0;
        vga_g     <= de ? fb_read_data[7:4]  : 4'h0;
        vga_b     <= de ? fb_read_data[3:0]  : 4'h0;
    end

endmodule
