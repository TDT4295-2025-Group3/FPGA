`default_nettype none
`timescale 1ns / 1ps

module top_sim (
    input  wire logic clk_100m,     // 100 MHz clock
    input  wire logic btn_rst_n,    // reset button
    output      logic vga_hsync,    // VGA horizontal sync
    output      logic vga_vsync,    // VGA vertical sync
    output      logic [3:0] vga_r,  // 4-bit VGA red
    output      logic [3:0] vga_g,  // 4-bit VGA green
    output      logic [3:0] vga_b,  // 4-bit VGA blue
    output      logic clk_pix       // pixel clock for simulation
);

    // Instantiate the original top module
    top top_inst (
        .clk_100m(clk_100m),
        .btn_rst_n(btn_rst_n),
        .vga_hsync(vga_hsync),
        .vga_vsync(vga_vsync),
        .vga_r(vga_r),
        .vga_g(vga_g),
        .vga_b(vga_b)
    );
    
    // Connect to the internal pixel clock for simulation
    // Note: You'll need to make clk_pix public in the top module
    assign clk_pix = top_inst.clock_pix_inst.clk_pix;
endmodule