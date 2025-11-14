`timescale 1ns / 1ps
`default_nettype none

module render_manager #(
    parameter int WIDTH  = 320,
    parameter int HEIGHT = 240,
    parameter int FOCAL_LENGTH = 256,
    parameter int SUBPIXEL_BITS = 4,
    parameter int DENOM_INV_BITS = 36,
    parameter int DENOM_INV_FBITS = 35,
    parameter bit BACKFACE_CULLING = 1'b1,
    parameter int NEAR_PLANE = 1,
    parameter int FAR_PLANE  = 1000,
    localparam int N_BITS_FOR_DEPTH = 16 + $clog2(FAR_PLANE-NEAR_PLANE)
) (
    input  wire logic clk,
    input  wire logic rst,

    input wire logic begin_frame,

    input wire transform_setup_t transform_setup,
    input wire logic triangle_valid,
    output logic triangle_ready,

    input wire color12_t fill_color,
    input wire logic fill_valid,
    output logic fill_ready,

    output logic [15:0] out_pixel_x,
    output logic [15:0] out_pixel_y,
    output logic [16 + $clog2(FAR_PLANE-NEAR_PLANE)-1:0] out_depth,
    output color16_t    out_color,
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
            end

            FILL_WAIT: begin
                if (!screen_filler_busy) begin
                    next_state = TRIANGLE;
                end
            end

            TRIANGLE: begin
                if (begin_frame) begin
                    next_state = FILL;
                end
            end
            default: next_state = FILL;
        endcase
    end

    always_comb begin
        unique case (state)
            FILL:       triangle_ready = 1'b0;
            FILL_WAIT:  triangle_ready = 1'b0;
            TRIANGLE:   triangle_ready = transformer_in_ready;
            default:    triangle_ready = 1'b0;
        endcase
    end
    assign busy = (state != TRIANGLE) ? screen_filler_busy : (rasterizer_busy || transformer_busy);

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
    logic [N_BITS_FOR_DEPTH-1:0] screen_filler_depth;
    color16_t screen_filler_color;
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
    assign screen_filler_depth = {N_BITS_FOR_DEPTH{1'b1}}; // max depth in compressed format


    // --- transformer wiring (triangle -> transformer -> rasterizer) ---
    logic        transformer_in_valid, transformer_in_ready, transformer_out_valid, transformer_out_ready, transformer_busy;
    triangle_t   transformer_out_triangle;

    transform_t camera_transform_reg;
    logic       cam_valid_hold;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            camera_transform_reg <= '0;
            cam_valid_hold       <= 1'b0;
        end else begin
            if (transform_setup.camera_transform_valid) begin
                camera_transform_reg <= transform_setup.camera_transform;
                cam_valid_hold       <= 1'b1;
            end
            if (transformer_in_valid && transformer_in_ready && cam_valid_hold) begin
                cam_valid_hold <= 1'b0;
            end
        end
    end

    transform_setup_t transform_setup_stream;
    assign transform_setup_stream.triangle                = transform_setup.triangle;
    assign transform_setup_stream.model_transform         = transform_setup.model_transform;
    assign transform_setup_stream.model_transform_valid   = transform_setup.model_transform_valid;
    assign transform_setup_stream.camera_transform        = camera_transform_reg;
    assign transform_setup_stream.camera_transform_valid  = cam_valid_hold;

    assign transformer_in_valid = (state == TRIANGLE) ? triangle_valid : 1'b0;

    transformer #(
        .WIDTH(WIDTH),
        .HEIGHT(HEIGHT),
        .FOCAL_LENGTH(FOCAL_LENGTH),
        .NEAR_PLANE(NEAR_PLANE),
        .FAR_PLANE(FAR_PLANE)
    ) transformer_inst (
        .clk(clk),
        .rst(rst),

        .transform_setup(transform_setup_stream),

        .in_valid(transformer_in_valid),
        .in_ready(transformer_in_ready),

        .out_triangle(transformer_out_triangle),
        .out_valid(transformer_out_valid),
        .out_ready(transformer_out_ready),

        .busy(transformer_busy)
    );

    // rasterizer now consumes the transformer's output
    logic rasterizer_in_valid, rasterizer_in_ready, rasterizer_busy, rasterizer_out_valid;
    assign rasterizer_in_valid = (state == TRIANGLE) ? transformer_out_valid : 1'b0;
    assign transformer_out_ready = rasterizer_in_ready;

    logic [15:0]  rasterizer_x, rasterizer_y;
    logic [N_BITS_FOR_DEPTH-1:0] rasterizer_depth;
    color16_t rasterizer_color;
    rasterizer #(
        .WIDTH (WIDTH),
        .HEIGHT(HEIGHT),
        .SUBPIXEL_BITS(SUBPIXEL_BITS),
        .DENOM_INV_BITS(DENOM_INV_BITS),
        .DENOM_INV_FBITS(DENOM_INV_FBITS),
        .BACKFACE_CULLING(BACKFACE_CULLING),
        .NEAR_PLANE(NEAR_PLANE),
        .FAR_PLANE(FAR_PLANE)
    ) rasterizer_inst (
        .clk(clk),
        .rst(rst),

        .in_valid(rasterizer_in_valid),
        .in_ready(rasterizer_in_ready),
        .busy    (rasterizer_busy),

        .v0(transformer_out_triangle.v0),
        .v1(transformer_out_triangle.v1),
        .v2(transformer_out_triangle.v2),

        .out_pixel_x(rasterizer_x),
        .out_pixel_y(rasterizer_y),
        .out_depth  (rasterizer_depth),
        .out_color  (rasterizer_color),
        .out_valid  (rasterizer_out_valid),
        .out_ready  (out_ready)
    );

endmodule
