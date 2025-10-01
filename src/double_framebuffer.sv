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

    input  wire logic        write_enable,
    input  wire logic [$clog2(FB_WIDTH)-1:0]  write_x,
    input  wire logic [$clog2(FB_HEIGHT)-1:0] write_y,
    input  wire color12_t    write_data,

    input  wire logic [$clog2(FB_WIDTH)-1:0]  read_x,
    input  wire logic [$clog2(FB_HEIGHT)-1:0] read_y,
    output logic [11:0]      read_data
);

    localparam int FB_DEPTH = FB_WIDTH * FB_HEIGHT;
    localparam int ADDR_WIDTH = $clog2(FB_DEPTH);

    logic [ADDR_WIDTH-1:0] write_addr, read_addr;
    assign write_addr = write_y * FB_WIDTH + write_x;
    assign read_addr  = read_y * FB_WIDTH + read_x;

    // Buffer selection enums
    typedef enum logic {FB_A, FB_B} fb_select_t;
    fb_select_t fb_write_select;
    fb_select_t fb_read_select; 

    // One-bit signal for crossing (0 = FB_A, 1 = FB_B)
    logic fb_read_sel_wr;
    logic fb_read_sel_rd;

    // Synchronizer flops
    logic sync_ff1, sync_ff2;

    always_ff @(posedge clk_write or posedge rst) begin
        if (rst) begin
            fb_read_sel_wr  <= 1'b0;
            fb_write_select <= FB_B;
        end else if (swap) begin
            fb_read_sel_wr  <= ~fb_read_sel_wr;
            fb_write_select <= (fb_write_select == FB_A) ? FB_B : FB_A;
        end
    end

    // Synchronize the read select signal into the read clock domain
    always_ff @(posedge clk_read or posedge rst) begin
        if (rst) begin
            sync_ff1 <= 0;
            sync_ff2 <= 0;
        end else begin
            sync_ff1 <= fb_read_sel_wr;
            sync_ff2 <= sync_ff1;
        end
    end
    assign fb_read_sel_rd = sync_ff2;

    always_ff @(posedge clk_read or posedge rst) begin
        if (rst)
            fb_read_select <= FB_A;
        else
            fb_read_select <= (fb_read_sel_rd ? FB_B : FB_A);
    end


    logic [11:0] read_data_A, read_data_B;

    // Framebuffer A (BRAM)
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

    // Framebuffer B (BRAM)
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

    always_ff @(posedge clk_read) begin
        read_data <= (fb_read_select == FB_A) ? read_data_A : read_data_B;
    end

endmodule
