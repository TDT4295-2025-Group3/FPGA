`default_nettype none
`timescale 1ns / 1ps

import color_pkg::color12_t;

module double_framebuffer #(
    parameter FB_WIDTH = 320,
    parameter FB_HEIGHT = 240
) (
    input  logic        clk_write,   // clock for writing (from renderer)
    input  logic        clk_read,    // clock for reading (to VGA)
    input  logic        swap,        // signal to swap buffers
    input  logic        rst,

    // Write interface (from renderer)
    input  logic        write_enable,
    input  logic [$clog2(FB_WIDTH)-1:0] write_x,
    input  logic [$clog2(FB_HEIGHT)-1:0] write_y,
    input  color12_t write_data,

    // Read interface (to VGA output)
    input  logic [$clog2(FB_WIDTH)-1:0]  read_x,
    input  logic [$clog2(FB_HEIGHT)-1:0] read_y,
    output color12_t read_data
);

    // Two framebuffers
    (* ram_style = "block" *) color12_t framebufferA [0:FB_WIDTH*FB_HEIGHT-1];
    (* ram_style = "block" *) color12_t framebufferB [0:FB_WIDTH*FB_HEIGHT-1];


    typedef enum logic {FB_A, FB_B} fb_select_t;
    fb_select_t fb_write_select;  // which framebuffer is being written to
    fb_select_t fb_read_select;  // which framebuffer is being read from

    // Swap buffers on swap signal
    always_ff @(posedge clk_read or posedge rst) begin
        if (rst) begin
            fb_read_select <= FB_A;
            fb_write_select <= FB_B;
        end else if (swap) begin
            fb_read_select <= (fb_read_select == FB_A) ? FB_B : FB_A;
            fb_write_select <= (fb_write_select == FB_A) ? FB_B : FB_A;
        end
    end


    // Write to the current write framebuffer
    always_ff @(posedge clk_write) begin
        if (write_enable && (write_x < FB_WIDTH) && (write_y < FB_HEIGHT)) begin
            if (fb_write_select == FB_A) begin
                framebufferA[write_y * FB_WIDTH + write_x] <= write_data;
            end else begin
                framebufferB[write_y * FB_WIDTH + write_x] <= write_data;
            end
        end
    end

    // Read from the current read framebuffer
    always_ff @(posedge clk_read) begin
        if (read_x < FB_WIDTH && read_y < FB_HEIGHT) begin
            if (fb_read_select == FB_A) begin
                read_data <= framebufferA[read_y * FB_WIDTH + read_x];
            end else begin
                read_data <= framebufferB[read_y * FB_WIDTH + read_x];
            end
        end else begin
            read_data <= 12'h000; // out of bounds, return black
        end
    end

endmodule
