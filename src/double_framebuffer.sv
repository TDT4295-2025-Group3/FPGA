`default_nettype none
`timescale 1ns / 1ps

module double_framebuffer #(
    parameter FB_WIDTH = 320,
    parameter FB_HEIGHT = 240,
    parameter VGA_WIDTH  = 640,
    parameter VGA_HEIGHT = 480
) (
    input  logic        clk_pix,
    input  logic        clk_sys,     // system clock for rendering
    input  logic        vsync,        // VGA VSYNC pulse
    input  logic        rst,

    // Write interface (from renderer)
    input  logic        write_enable,
    input  logic [$clog2(FB_WIDTH)-1:0] render_x,
    input  logic [$clog2(FB_HEIGHT)-1:0] render_y,
    input  logic [11:0] render_data,

    // Read interface (to VGA output)
    input  logic [$clog2(VGA_WIDTH)-1:0]  display_x,
    input  logic [$clog2(VGA_HEIGHT)-1:0] display_y,
    output logic [11:0] display_data
);

    // Two framebuffers
    logic [11:0] framebufferA [0:FB_WIDTH*FB_HEIGHT-1];
    logic [11:0] framebufferB [0:FB_WIDTH*FB_HEIGHT-1];

    typedef enum logic {FB_A, FB_B} fb_select_t;
    fb_select_t fb_display_select; // which framebuffer is being displayed
    fb_select_t fb_render_select;  // which framebuffer is being rendered to

    // On VSYNC, swap framebuffers
    always_ff @(posedge clk_pix or posedge rst) begin
        if (rst) begin
            fb_display_select <= FB_A;
            fb_render_select <= FB_B;
        end else if (vsync) begin
            fb_display_select <= (fb_display_select == FB_A) ? FB_B : FB_A;
            fb_render_select <= (fb_render_select == FB_A) ? FB_B : FB_A;
        end
    end

    // Write to the render framebuffer
    always_ff @(posedge clk_sys) begin
        if (write_enable && (render_x < FB_WIDTH) && (render_y < FB_HEIGHT)) begin
            if (fb_render_select == FB_A) begin
                framebufferA[render_y * FB_WIDTH + render_x] <= render_data;
            end else begin
                framebufferB[render_y * FB_WIDTH + render_x] <= render_data;
            end
        end
    end

    // Read from the display framebuffer
    always_comb begin
        // Map VGA coordinates to framebuffer coordinates
        logic [$clog2(FB_WIDTH)-1:0] fb_x;
        logic [$clog2(FB_HEIGHT)-1:0] fb_y;

        fb_x = (display_x * FB_WIDTH) / VGA_WIDTH;
        fb_y = (display_y * FB_HEIGHT) / VGA_HEIGHT;

        if (fb_display_select == FB_A) begin
            display_data = framebufferA[fb_y * FB_WIDTH + fb_x];
        end else begin
            display_data = framebufferB[fb_y * FB_WIDTH + fb_x];
        end
    end

endmodule
