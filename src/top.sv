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
    import fixed_pkg::*;

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


    localparam logic signed [31:0] TRI_X0 = to_q16_16(100);
    localparam logic signed [31:0] TRI_Y0 = to_q16_16(50);
    localparam logic signed [31:0] TRI_Z0 = to_q16_16(100);
    localparam logic signed [31:0] TRI_X1 = to_q16_16(200);
    localparam logic signed [31:0] TRI_Y1 = to_q16_16(300);
    localparam logic signed [31:0] TRI_Z1 = to_q16_16(200);
    localparam logic signed [31:0] TRI_X2 = to_q16_16(300);
    localparam logic signed [31:0] TRI_Y2 = to_q16_16(100);
    localparam logic signed [31:0] TRI_Z2 = to_q16_16(150);
    localparam logic signed [31:0] TRI_X3 = to_q16_16(250);
    localparam logic signed [31:0] TRI_Y3 = to_q16_16(310);
    localparam logic signed [31:0] TRI_Z3 = to_q16_16(250);
    localparam TRI_C0 = 12'hF00; // red
    localparam TRI_C1 = 12'h0F0; // green
    localparam TRI_C2 = 12'h00F; // blue
    localparam TRI_C3 = 12'hFF0; // yellow

    logic signed [31:0] px_q, py_q;
    always_comb begin
        px_q = sx <<< 16;
        py_q = sy <<< 16;
    end

    logic p_inside1;
    logic [11:0] p_color1;
    logic signed [31:0] pz1;
    triangle_pixel_eval tri_fill_inst1 (
        .ax(TRI_X0), .ay(TRI_Y0), .az(TRI_Z0),
        .bx(TRI_X1), .by(TRI_Y1), .bz(TRI_Z1),
        .cx(TRI_X2), .cy(TRI_Y2), .cz(TRI_Z2),
        .a_color(TRI_C0), .b_color(TRI_C1), .c_color(TRI_C2),
        .px(px_q), .py(py_q),
        .pz(pz1),
        .p_inside(p_inside1),
        .p_color(p_color1)
    );

    logic p_inside2;
    logic [11:0] p_color2;
    logic signed [31:0] pz2;
    triangle_pixel_eval tri_fill_inst2 (
        .ax(TRI_X1), .ay(TRI_Y1), .az(TRI_Z1),
        .bx(TRI_X2), .by(TRI_Y2), .bz(TRI_Z2),
        .cx(TRI_X3), .cy(TRI_Y3), .cz(TRI_Z3),
        .a_color(TRI_C1), .b_color(TRI_C2), .c_color(TRI_C3),
        .px(px_q), .py(py_q),
        .pz(pz2),
        .p_inside(p_inside2),
        .p_color(p_color2)
    );

    // paint colour: white inside square, blue outside
    logic [3:0] paint_r, paint_g, paint_b;
    always_comb begin
        if (p_inside1) begin
            paint_r = p_color1[11:8];
            paint_g = p_color1[7:4];
            paint_b = p_color1[3:0];
        end else if (p_inside2) begin
            paint_r = p_color2[11:8];
            paint_g = p_color2[7:4];
            paint_b = p_color2[3:0];
        end else begin
            paint_r = 4'h0;
            paint_g = 4'h0;
            paint_b = 4'h8;
        end
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
