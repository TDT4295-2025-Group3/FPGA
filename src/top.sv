`default_nettype none
`timescale 1ns / 1ps

module top (
    input  wire logic clk_100m,     // 100 MHz clock
    input  wire logic btn_rst_n,    // reset button
    output      logic vga_hsync,    // VGA horizontal sync
    output      logic vga_vsync,    // VGA vertical sync
    output      logic [3:0] vga_r,  // 4-bit VGA red
    output      logic [3:0] vga_g,  // 4-bit VGA green
    output      logic [3:0] vga_b   // 4-bit VGA blue
    );

    // generate pixel clock
    logic clk_pix;
    logic clk_pix_locked;
    clock_480p clock_pix_inst (
       .clk_100m,
       .rst(!btn_rst_n),  // reset button is active low
       .clk_pix,
       /* verilator lint_off PINCONNECTEMPTY */
       .clk_pix_5x(),  // not used for VGA output
       /* verilator lint_on PINCONNECTEMPTY */
       .clk_pix_locked
    );

    // display sync signals and coordinates
    localparam CORDW = 10;  // screen coordinate width in bits
    logic [CORDW-1:0] sx, sy;
    logic hsync, vsync, de;
    simple_480p display_inst (
        .clk_pix,
        .rst_pix(!clk_pix_locked),  // wait for clock lock
        .sx,
        .sy,
        .hsync,
        .vsync,
        .de
    );



    localparam WIDTH  = 640;
    localparam HEIGHT = 480;

    localparam SQUARE_HEIGHT  = 100;
    localparam SQUARE_WIDTH   = 100;

    localparam SPEED = 1; // pixels per frame

    logic signed [10:0] square_x;
    logic signed [10:0] square_y;

    logic dir_x;
    logic dir_y;

logic vsync_prev;

always_ff @(posedge clk_pix or negedge btn_rst_n) begin
    if (!btn_rst_n) begin
        square_x <= 0;
        square_y <= 0;
        dir_x <= 0;
        dir_y <= 0;
        vsync_prev <= 0;
    end else begin
        vsync_prev <= vsync;  // store previous frame's vsync

        // rising edge detection
        if (~vsync_prev & vsync)begin

            logic signed [10:0] next_x, next_y;

            next_x = square_x + (dir_x ? SPEED : -SPEED);
            next_y = square_y + (dir_y ? SPEED : -SPEED);

            // Clamp and change direction
            if (next_x < 0) begin
                square_x <= 0;
                dir_x <= 1;
            end else if (next_x > WIDTH - SQUARE_WIDTH) begin
                square_x <= WIDTH - SQUARE_WIDTH;
                dir_x <= 0;
            end else
                square_x <= next_x;

            if (next_y < 0) begin
                square_y <= 0;
                dir_y <= 1;
            end else if (next_y > HEIGHT - SQUARE_HEIGHT) begin
                square_y <= HEIGHT - SQUARE_HEIGHT;
                dir_y <= 0;
            end else
                square_y <= next_y;


        end
    end
end



    // define a square with screen coordinates
    logic square;
    always_comb begin
        square = ($unsigned(sx) >= square_x) && ($unsigned(sx) < square_x + SQUARE_WIDTH) &&
         ($unsigned(sy) >= square_y) && ($unsigned(sy) < square_y + SQUARE_HEIGHT);

    end

    // paint colour: white inside square, blue outside
    logic [3:0] paint_r, paint_g, paint_b;
    logic [3:0] background_r, background_g, background_b;
    always_comb begin

        //background should be gradient
        background_r = sx[7:4];
        background_g = sy[7:4];
        background_b = 4'h4;

        paint_r = (square) ? background_r : background_b;
        paint_g = (square) ? background_g : background_r;
        paint_b = (square) ? background_b : background_g;
    end

    // display colour: paint colour but black in blanking interval
    logic [3:0] display_r, display_g, display_b;
    always_comb begin
        display_r = (de) ? paint_r : 4'h0;
        display_g = (de) ? paint_g : 4'h0;
        display_b = (de) ? paint_b : 4'h0;
    end

    // VGA Pmod output
    always_ff @(posedge clk_pix) begin
        vga_hsync <= hsync;
        vga_vsync <= vsync;
        vga_r <= display_r;
        vga_g <= display_g;
        vga_b <= display_b;
    end
endmodule
