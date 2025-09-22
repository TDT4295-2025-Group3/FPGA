    `default_nettype none
    `timescale 1ns / 1ps

    import rasterizer_pkg::*;
    import math_pkg::*;

    module pixel_traversal (
        input  logic                 clk,
        input  logic                 rst,

        input  logic                 in_valid,
        input  triangle_state_t      in_state,
        output logic                 in_ready,

        output logic                 out_valid,
        output pixel_state_t         out_pixel,
        input  logic                 out_ready
    );

        typedef enum logic [1:0] {IDLE, RUN, WAIT_OUT} state_t;
        state_t state;

        triangle_state_t tri_reg;

        logic [15:0] current_x, current_y;
        logic [15:0] out_x, out_y;
        q32_32_t w0, w1, w2;

        assign in_ready = (state == IDLE);


        // Output pixel data
        assign out_valid = (state == RUN) || (state == WAIT_OUT);

        always_comb begin
            out_pixel.x          = out_x;
            out_pixel.y          = out_y;
            out_pixel.v0_color   = tri_reg.v0_color;
            out_pixel.v1_color   = tri_reg.v1_color;
            out_pixel.v2_color   = tri_reg.v2_color;
            out_pixel.v0_depth   = tri_reg.v0_depth;
            out_pixel.v1_depth   = tri_reg.v1_depth;
            out_pixel.v2_depth   = tri_reg.v2_depth;
            out_pixel.v0         = tri_reg.v0;
            out_pixel.v1         = tri_reg.v1;
            out_pixel.v2         = tri_reg.v2;
        end

        // // Pixel stepping logic
        always_ff @(posedge clk or posedge rst) begin

            if (rst) begin
                state <= IDLE;
            end else if (state == IDLE && in_valid) begin
                state <= RUN;
                tri_reg <= in_state;
                current_x   <= in_state.bbox_min_x;
                current_y   <= in_state.bbox_min_y;
            end else if (state == RUN && !out_ready) begin
                state <= WAIT_OUT;
            end else if (state == WAIT_OUT && out_ready) begin
                state <= RUN;
            end else if (state == RUN && out_ready) begin
                out_x <= current_x;
                out_y <= current_y;
                if (current_x < tri_reg.bbox_max_x) begin
                    current_x <= current_x + 1;
                end else begin
                    current_x <= tri_reg.bbox_min_x;
                    if (current_y < tri_reg.bbox_max_y) begin
                        current_y <= current_y + 1;
                    end else begin
                        state <= IDLE;
                    end
                end
            end
            
        end
    endmodule