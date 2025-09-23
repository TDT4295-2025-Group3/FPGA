`default_nettype none
`timescale 1ns / 1ps

import color_pkg::color12_t;

module double_framebuffer #(
    parameter int FB_WIDTH  = 160,
    parameter int FB_HEIGHT = 120
) (
    input  wire logic        clk_write,   // clock for writing (renderer)
    input  wire logic        clk_read,    // clock for reading (VGA)
    input  wire logic        swap,        // signal to swap buffers
    input  wire logic        rst,

    // Write interface
    input  wire logic        write_enable,
    input  wire logic [$clog2(FB_WIDTH)-1:0]  write_x,
    input  wire logic [$clog2(FB_HEIGHT)-1:0] write_y,
    input  wire color12_t    write_data,

    // Read interface
    input  wire logic [$clog2(FB_WIDTH)-1:0]  read_x,
    input  wire logic [$clog2(FB_HEIGHT)-1:0] read_y,
    output logic [11:0]      read_data
);

    localparam int FB_DEPTH = FB_WIDTH * FB_HEIGHT;
    localparam int ADDR_WIDTH = $clog2(FB_DEPTH);

    // Compute linear addresses outside memory
    logic [ADDR_WIDTH-1:0] write_addr, read_addr;
    assign write_addr = write_y * FB_WIDTH + write_x;
    assign read_addr  = read_y * FB_WIDTH + read_x;

    // Buffer selection
    typedef enum logic {FB_A, FB_B} fb_select_t;
    fb_select_t fb_write_select, fb_read_select;

    always_ff @(posedge clk_read or posedge rst) begin
        if (rst) begin
            fb_read_select  <= FB_A;
            fb_write_select <= FB_B;
        end else if (swap) begin
            fb_read_select  <= (fb_read_select  == FB_A) ? FB_B : FB_A;
            fb_write_select <= (fb_write_select == FB_A) ? FB_B : FB_A;
        end
    end

    // Read data wires from each framebuffer
    logic [11:0] read_data_A, read_data_B;

    // === Framebuffer A (BRAM) ===
    xpm_memory_tdpram #(
        .MEMORY_SIZE(FB_DEPTH * 12),     // total bits
        .MEMORY_PRIMITIVE("block"),      // force block RAM
        .CLOCKING_MODE("independent_clock"),
        .WRITE_DATA_WIDTH_A(12),
        .READ_DATA_WIDTH_B(12),
        .ADDR_WIDTH_A(ADDR_WIDTH),
        .ADDR_WIDTH_B(ADDR_WIDTH),
        .READ_LATENCY_B(1),              // synchronous read
        .WRITE_MODE_B("read_first")      // typical framebuffer behavior
    ) framebufferA (
        .clka(clk_write),
        .ena(1'b1),
        .wea(write_enable && (fb_write_select == FB_A)),
        .addra(write_addr),
        .dina(write_data),
        .clkb(clk_read),
        .enb(1'b1),
        .addrb(read_addr),
        .doutb(read_data_A)
    );

    // === Framebuffer B (BRAM) ===
    xpm_memory_tdpram #(
        .MEMORY_SIZE(FB_DEPTH * 12),
        .MEMORY_PRIMITIVE("block"),
        .CLOCKING_MODE("independent_clock"),
        .WRITE_DATA_WIDTH_A(12),
        .READ_DATA_WIDTH_B(12),
        .ADDR_WIDTH_A(ADDR_WIDTH),
        .ADDR_WIDTH_B(ADDR_WIDTH),
        .READ_LATENCY_B(1),
        .WRITE_MODE_B("read_first")
    ) framebufferB (
        .clka(clk_write),
        .ena(1'b1),
        .wea(write_enable && (fb_write_select == FB_B)),
        .addra(write_addr),
        .dina(write_data),
        .clkb(clk_read),
        .enb(1'b1),
        .addrb(read_addr),
        .doutb(read_data_B)
    );

    // Select which framebuffer's data goes to output
    always_ff @(posedge clk_read) begin
        read_data <= (fb_read_select == FB_A) ? read_data_A : read_data_B;
    end

endmodule
