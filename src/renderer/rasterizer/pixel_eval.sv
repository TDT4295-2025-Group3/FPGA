`default_nettype none
`timescale 1ns / 1ps

import rasterizer_pkg::*;
import math_pkg::*;
import color_pkg::*;

module pixel_eval #(
    parameter int WIDTH  = 320,
    parameter int HEIGHT = 240
) (
    input  wire logic clk,
    input  wire logic rst,

    input  wire pixel_state_t in_pixel,
    input  wire logic         in_valid,
    output wire logic         in_ready,

    output logic [15:0] out_x,
    output logic [15:0] out_y,
    output color12_t    out_color,
    output q16_16_t     out_depth,
    output logic        out_valid,
    input  wire logic   out_ready,
    output logic        busy
);

    // handshake
    logic s1_ready, s2_ready, s3_ready, s4_ready, s5_ready;
    pixel_eval_stage1_t s1_reg, s1_next;
    pixel_eval_stage2_t s2_reg, s2_next;
    pixel_eval_stage3_t s3_reg, s3_next;
    pixel_eval_stage4_t s4_reg, s4_next;
    pixel_output_t      s5_reg, s5_next;

    assign s1_ready = !s1_reg.valid || s2_ready;
    assign s2_ready = !s2_reg.valid || s3_ready;
    assign s3_ready = !s3_reg.valid || s4_ready;
    assign s4_ready = !s4_reg.valid || s5_ready;
    assign s5_ready = !s5_reg.valid || out_ready;

    assign in_ready = s1_ready;
    assign busy     = s1_reg.valid || s2_reg.valid || s3_reg.valid || s4_reg.valid || s5_reg.valid || out_valid;

    // Stage 1
    always_comb begin
        s1_next.valid = in_valid;
        s1_next.pixel = in_pixel;
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            s1_reg <= '0;
        end else if (s1_ready) begin
            s1_reg <= s1_next;
        end
    end

    // Stage 2
    logic signed [18:0] e2x, e2y;                 // Q16.3
    // sample at pixel center: (x+0.5, y+0.5) => +4 in Q16.3
    assign e2x = {s1_reg.pixel.x,3'b0} + 19'sd4 - s1_reg.pixel.triangle.v0x;
    assign e2y = {s1_reg.pixel.y,3'b0} + 19'sd4 - s1_reg.pixel.triangle.v0y;

    always_comb begin
        s2_next.valid = s1_reg.valid;
        s2_next.pixel = s1_reg.pixel;
        s2_next.d20   = e2x * s1_reg.pixel.triangle.e0x + e2y * s1_reg.pixel.triangle.e0y; // Q32.6
        s2_next.d21   = e2x * s1_reg.pixel.triangle.e1x + e2y * s1_reg.pixel.triangle.e1y; // Q32.6
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            s2_reg <= '0;
        end else if (s2_ready) begin
            s2_reg <= s2_next;
        end
    end

    // Stage 3
    logic signed [75:0] v_num_c, w_num_c, denom_c; // Q64.12
    always_comb begin
        v_num_c = s2_reg.pixel.triangle.d11 * s2_reg.d20 - s2_reg.pixel.triangle.d01 * s2_reg.d21;
        w_num_c = s2_reg.pixel.triangle.d00 * s2_reg.d21 - s2_reg.pixel.triangle.d01 * s2_reg.d20;
        denom_c = s2_reg.pixel.triangle.d00 * s2_reg.pixel.triangle.d11
                - s2_reg.pixel.triangle.d01 * s2_reg.pixel.triangle.d01;

        s3_next.valid = s2_reg.valid;
        s3_next.pixel = s2_reg.pixel;
        s3_next.v_num = v_num_c;
        s3_next.w_num = w_num_c;
        s3_next.denom = denom_c;
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            s3_reg <= '0;
        end else if (s3_ready) begin
            s3_reg <= s3_next;
        end
    end

    // Stage 4 comb: inside test (sign-aware)
    logic signed [75:0] u_num_c;                  // Q64.12
    logic inside_c;

    // Top-Left rule helpers (reconstruct edge vectors for the three edges)
    // Using only data already present in triangle: v1 = v0 + e0, v2 = v0 + e1
    // Edges opposite each barycentric:
    //   u (at v0) : edge v1->v2  = (e1 - e0)
    //   v (at v1) : edge v2->v0  = (-e1)
    //   w (at v2) : edge v0->v1  = (e0)
    logic signed [18:0] edge_u_dx, edge_u_dy;
    logic signed [18:0] edge_v_dx, edge_v_dy;
    logic signed [18:0] edge_w_dx, edge_w_dy;

    logic inc_u, inc_v, inc_w; // Top-Left inclusion flags

    logic signed [75:0] vN, wN, uN;
    logic v_ok, w_ok, u_ok; // Top-Left rule with tie-breaks per edge
    always_comb begin
        u_num_c = s3_reg.denom - s3_reg.v_num - s3_reg.w_num;

        // Edge vectors
        edge_u_dx = s3_reg.pixel.triangle.e1x - s3_reg.pixel.triangle.e0x;
        edge_u_dy = s3_reg.pixel.triangle.e1y - s3_reg.pixel.triangle.e0y;

        edge_v_dx = -s3_reg.pixel.triangle.e1x;
        edge_v_dy = -s3_reg.pixel.triangle.e1y;

        edge_w_dx = s3_reg.pixel.triangle.e0x;
        edge_w_dy = s3_reg.pixel.triangle.e0y;

        // Top-Left test: include when (dy < 0) || (dy == 0 && dx > 0)
        inc_u = (edge_u_dy < 0) || ((edge_u_dy == 0) && (edge_u_dx > 0));
        inc_v = (edge_v_dy < 0) || ((edge_v_dy == 0) && (edge_v_dx > 0));
        inc_w = (edge_w_dy < 0) || ((edge_w_dy == 0) && (edge_w_dx > 0));
        // Normalize numerators to a positive-denominator space for consistent comparisons
        if (s3_reg.pixel.triangle.denom_neg) begin
            vN = -s3_reg.v_num;
            wN = -s3_reg.w_num;
            uN = -u_num_c;
        end else begin
            vN =  s3_reg.v_num;
            wN =  s3_reg.w_num;
            uN =  u_num_c;
        end

        // Top-Left rule with tie-breaks per edge
        v_ok = (vN > 0) || ((vN == 0) && inc_v);
        w_ok = (wN > 0) || ((wN == 0) && inc_w);
        u_ok = (uN > 0) || ((uN == 0) && inc_u);
        inside_c = v_ok && w_ok && u_ok;

        s4_next.valid     = s3_reg.valid;
        s4_next.pixel     = s3_reg.pixel;
        s4_next.v_num     = s3_reg.v_num;
        s4_next.w_num     = s3_reg.w_num;
        s4_next.u_num     = u_num_c;
        s4_next.is_inside = inside_c;
    end

    // Stage 4 reg
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            s4_reg <= '0;
        end else if (s4_ready) begin
            s4_reg <= s4_next;
        end
    end

    // Stage 5 comb: weights, interpolation
    // abs numerators since denom_inv = 1/abs(denom)
    logic signed [75:0] v_num_abs, w_num_abs, u_num_abs; // Q64.12
    logic signed [110:0] v_mul, w_mul, u_mul;             // Q64.12 * Q0.35 = Q64.47
    q16_16_t v_w, w_w, u_w;                              // Q16.16

    always_comb begin
        v_num_abs = s4_reg.pixel.triangle.denom_neg ? -s4_reg.v_num : s4_reg.v_num;
        w_num_abs = s4_reg.pixel.triangle.denom_neg ? -s4_reg.w_num : s4_reg.w_num;
        u_num_abs = s4_reg.pixel.triangle.denom_neg ? -s4_reg.u_num : s4_reg.u_num;

        v_mul = v_num_abs * $signed(s4_reg.pixel.triangle.denom_inv); // Q64.12 * Q0.35 = Q64.47
        w_mul = w_num_abs * $signed(s4_reg.pixel.triangle.denom_inv); // Q64.12 * Q0.35 = Q64.47
        u_mul = u_num_abs * $signed(s4_reg.pixel.triangle.denom_inv); // Q64.12 * Q0.35 = Q64.47
        if (s4_reg.pixel.triangle.denom_inv == 16'sd0 && s4_reg.valid && s4_reg.is_inside) begin
            $display("Warning: denom_inv is zero for pixel (%0d, %0d)", s4_reg.pixel.x, s4_reg.pixel.y);
            // keep products as-is (multiplying by 0); u_w will become ~1 after rounding below
        end

        // round-to-nearest
        v_w = q16_16_t'((v_mul + (1 << 30)) >>> 31);
        w_w = q16_16_t'((w_mul + (1 << 30)) >>> 31);

        if ($signed(v_w) < 0) v_w = '0;
        if ($signed(w_w) < 0) w_w = '0;

        u_w = q16_16_t'(32'h0001_0000) - v_w - w_w;
        if ($signed(u_w) < 0) u_w = '0;

        s5_next.valid = s4_reg.valid & s4_reg.is_inside;
        s5_next.pixel = s4_reg.pixel;

        if (s4_reg.is_inside) begin
            s5_next.color[11:8] = ((u_w * $unsigned(s4_reg.pixel.triangle.v0_color[11:8])) +
                                   (v_w * $unsigned(s4_reg.pixel.triangle.v1_color[11:8])) +
                                   (w_w * $unsigned(s4_reg.pixel.triangle.v2_color[11:8])) + 32'h0000_8000) >>> 16;

            s5_next.color[7:4]  = ((u_w * $unsigned(s4_reg.pixel.triangle.v0_color[7:4])) +
                                   (v_w * $unsigned(s4_reg.pixel.triangle.v1_color[7:4])) +
                                   (w_w * $unsigned(s4_reg.pixel.triangle.v2_color[7:4])) + 32'h0000_8000) >>> 16;

            s5_next.color[3:0]  = ((u_w * $unsigned(s4_reg.pixel.triangle.v0_color[3:0])) +
                                   (v_w * $unsigned(s4_reg.pixel.triangle.v1_color[3:0])) +
                                   (w_w * $unsigned(s4_reg.pixel.triangle.v2_color[3:0])) + 32'h0000_8000) >>> 16;

            s5_next.depth       = ((u_w * s4_reg.pixel.triangle.v0_depth) +
                                   (v_w * s4_reg.pixel.triangle.v1_depth) +
                                   (w_w * s4_reg.pixel.triangle.v2_depth) + 32'h0000_8000) >>> 16;
        end else begin
            s5_next.color = '0;
            s5_next.depth = '0;
        end
    end

    // Stage 5 reg (output register)
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            s5_reg <= '0;
        end else if (s5_ready) begin
            s5_reg <= s5_next;
        end
    end

    // drive outputs
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            out_valid <= 1'b0;
            out_x     <= '0;
            out_y     <= '0;
            out_color <= '0;
            out_depth <= '0;
        end else if (!out_valid || out_ready) begin
            out_valid <= s5_reg.valid;
            out_x     <= s5_reg.pixel.x;
            out_y     <= s5_reg.pixel.y;
            out_color <= s5_reg.color;
            out_depth <= s5_reg.depth;
        end
    end

endmodule
