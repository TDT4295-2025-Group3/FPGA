`timescale 1ns / 1ps
`default_nettype none

module render_manager #(
    parameter int WIDTH  = 320,
    parameter int HEIGHT = 240
) (
    input  wire logic clk,
    input  wire logic rst,

    input wire logic begin_frame,

    input triangle_t triangle,
    input wire logic triangle_valid,
    output logic triangle_ready,

    input color12_t fill_color,
    input wire logic fill_valid,
    output logic fill_ready,

    output logic [15:0] out_pixel_x,
    output logic [15:0] out_pixel_y,
    output q16_16_t     out_depth,
    output color12_t    out_color,
    output logic        out_compare_depth,
    output logic        out_valid,
    input wire logic    out_ready,
    output logic busy
    );

    // FSM
    typedef enum logic [1:0] {FILL, FILL_WAIT, TRIANGLE} state_t;
    state_t state, next_state;
    

    color12_t fill_color_reg;
    assign fill_ready = 1'b1;
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            fill_color_reg <= 12'b0;
        end else if(fill_valid) begin
            fill_color_reg <= fill_color;
        end
    end
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= FILL;
        end else begin
            state <= next_state;
        end
    end

    logic screen_filler_start;

    always_comb begin
        next_state = state;
        screen_filler_start = 1'b0;

        case (state)
            FILL: begin
                next_state = FILL_WAIT;
                screen_filler_start = 1'b1;
                $display("Render Manager: Starting screen fill");
            end

            FILL_WAIT: begin
                if (!screen_filler_busy && triangle_valid) begin
                    next_state = TRIANGLE;
                    $display("Render Manager: Switching to TRIANGLE state");
                end
            end

            TRIANGLE: begin
                if (begin_frame) begin
                    next_state = FILL;
                    $display("Render Manager: Switching to FILL state");
                end
            end
            default: next_state = FILL;
        endcase
    end

    assign triangle_ready = (state == TRIANGLE) ? rasterizer_in_ready : 1'b0;
    assign busy = (state != TRIANGLE) ? screen_filler_busy : rasterizer_busy;

    always_comb begin
        if (state != TRIANGLE) begin
            out_pixel_x      = screen_filler_x;
            out_pixel_y      = screen_filler_y;
            out_depth        = screen_filler_depth;
            out_color        = screen_filler_color;
            out_compare_depth= 1'b0;
            out_valid        = screen_filler_out_valid;
        end else begin
            out_pixel_x      = rasterizer_x;
            out_pixel_y      = rasterizer_y;
            out_depth        = rasterizer_depth;
            out_color        = rasterizer_color;
            out_compare_depth= 1'b1;
            out_valid        = rasterizer_out_valid;
        end
    end

    logic screen_filler_in_valid, screen_filler_in_ready, screen_filler_busy, screen_filler_out_valid;
    assign screen_filler_in_valid = screen_filler_start;
    logic [15:0]  screen_filler_x, screen_filler_y;
    q16_16_t screen_filler_depth;
    color12_t screen_filler_color;
    screen_filler #(
        .WIDTH (WIDTH),
        .HEIGHT(HEIGHT)
    ) screen_filler_inst (
        .clk(clk),
        .rst(rst),

        .fill_color(fill_color_reg),

        .in_valid(screen_filler_in_valid),
        .in_ready(screen_filler_in_ready),
        .busy    (screen_filler_busy),

        .out_pixel_x(screen_filler_x),
        .out_pixel_y(screen_filler_y),
        .out_color  (screen_filler_color),
        .out_valid  (screen_filler_out_valid),
        .out_ready  (out_ready)
    );
    assign screen_filler_depth = 32'h7FFF_FFFF; // max signed depth


    logic rasterizer_in_valid, rasterizer_in_ready, rasterizer_busy, rasterizer_out_valid;
    assign rasterizer_in_valid = (state == TRIANGLE) ? triangle_valid: 1'b0;
    logic [15:0]  rasterizer_x, rasterizer_y;
    q16_16_t rasterizer_depth;
    color12_t rasterizer_color;
    rasterizer #(
        .WIDTH (WIDTH),
        .HEIGHT(HEIGHT)
    ) rasterizer_inst (
        .clk(clk),
        .rst(rst),

        .in_valid(rasterizer_in_valid),
        .in_ready(rasterizer_in_ready),
        .busy    (rasterizer_busy),

        .v0(triangle.v0),
        .v1(triangle.v1),
        .v2(triangle.v2),

        .out_pixel_x(rasterizer_x),
        .out_pixel_y(rasterizer_y),
        .out_depth  (rasterizer_depth),
        .out_color  (rasterizer_color),
        .out_valid  (rasterizer_out_valid),
        .out_ready  (out_ready)
    );

endmodule
