`default_nettype none
`timescale 1ns / 1ps

import math_pkg::*;
import color_pkg::*;

module pixel_eval #(
    parameter int WIDTH  = 320,
    parameter int HEIGHT = 240,
    parameter int SUBPIXEL_BITS = 4,
    parameter int DENOM_INV_FBITS = 35
) (
    input  wire logic clk,
    input  wire logic rst,

    input  wire logic [$clog2(WIDTH)-1:0]           pixel_x,
    input  wire logic [$clog2(HEIGHT)-1:0]          pixel_y,
    input  wire logic signed [16+SUBPIXEL_BITS-1:0] v0x, v0y,
    input  wire logic signed [16+SUBPIXEL_BITS-1:0] e0x, e0y,
    input  wire logic signed [16+SUBPIXEL_BITS-1:0] e1x, e1y,
    input  wire logic signed [DENOM_INV_FBITS-1:0]  denom_inv,    // signed: 1/denom
    input  wire logic [$clog2(WIDTH)-1:0]           bbox_min_x, bbox_max_x,
    input  wire logic [$clog2(HEIGHT)-1:0]          bbox_min_y, bbox_max_y,
    input  wire color12_t                           v0_color, v1_color, v2_color,
    input  wire q16_16_t                            v0_depth, v1_depth, v2_depth,
    input  wire logic                               in_valid,
    output      logic                               in_ready,

    output      logic [$clog2(WIDTH)-1:0]           out_x,
    output      logic [$clog2(HEIGHT)-1:0]          out_y,
    output      color12_t                           out_color,
    output      q16_16_t                            out_depth,
    output      logic                               out_valid,
    input  wire logic                               out_ready,
    output      logic                               busy
);
    typedef struct packed {
        logic [$clog2(WIDTH)-1:0]           x;
        logic [$clog2(HEIGHT)-1:0]          y;
        logic signed [16+SUBPIXEL_BITS-1:0] v0x, v0y;
        logic signed [16+SUBPIXEL_BITS-1:0] e0x, e0y;
        logic signed [16+SUBPIXEL_BITS-1:0] e1x, e1y;
        logic signed [DENOM_INV_FBITS-1:0]  denom_inv; // signed 1/denom
        logic [$clog2(WIDTH)-1:0]           bbox_min_x, bbox_max_x;
        logic [$clog2(HEIGHT)-1:0]          bbox_min_y, bbox_max_y;
        color12_t                           v0_color, v1_color, v2_color;
        q16_16_t                            v0_depth, v1_depth, v2_depth;
    } pixel_state_t;

    typedef struct packed {
        logic        valid;
        pixel_state_t pixel;
    } pixel_eval_stage1_t;

    typedef struct packed {
        logic        valid;
        pixel_state_t pixel;
        // e2 = p - v0 (in SUBPIXEL units)
        logic signed [16+SUBPIXEL_BITS:0] e2x;
        logic signed [16+SUBPIXEL_BITS:0] e2y;
    } pixel_eval_stage2_t;

    typedef struct packed {
        logic        valid;
        pixel_state_t pixel;
        // numerators in Q(2*SUBPIXEL_BITS)
        logic signed [32+2*SUBPIXEL_BITS-1:0] v_num;
        logic signed [32+2*SUBPIXEL_BITS-1:0] w_num;
        logic signed [32+2*SUBPIXEL_BITS-1:0] u_num;
    } pixel_eval_stage3_t;

    typedef struct packed {
        logic        valid;
        pixel_state_t pixel;
        // Top-Left rule: numerators normalized by sign(denom)
        logic signed [32+2*SUBPIXEL_BITS-1:0] vN, wN, uN;
        logic        is_inside;
    } pixel_eval_stage4_t;

    typedef struct packed {
        logic        valid;
        pixel_state_t pixel;
        color12_t    color;
        q16_16_t     depth;
    } pixel_output_t;

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
        s1_next.valid            = in_valid;
        s1_next.pixel.x          = pixel_x;
        s1_next.pixel.y          = pixel_y;
        s1_next.pixel.v0x        = v0x;
        s1_next.pixel.v0y        = v0y;
        s1_next.pixel.e0x        = e0x;
        s1_next.pixel.e0y        = e0y;
        s1_next.pixel.e1x        = e1x;
        s1_next.pixel.e1y        = e1y;
        s1_next.pixel.denom_inv  = denom_inv;     // signed 1/denom
        s1_next.pixel.bbox_min_x = bbox_min_x;
        s1_next.pixel.bbox_max_x = bbox_max_x;
        s1_next.pixel.bbox_min_y = bbox_min_y;
        s1_next.pixel.bbox_max_y = bbox_max_y;
        s1_next.pixel.v0_color   = v0_color;
        s1_next.pixel.v1_color   = v1_color;
        s1_next.pixel.v2_color   = v2_color;
        s1_next.pixel.v0_depth   = v0_depth;
        s1_next.pixel.v1_depth   = v1_depth;
        s1_next.pixel.v2_depth   = v2_depth;
    end
    always_ff @(posedge clk or posedge rst) begin
        if (rst) s1_reg <= '0;
        else if (s1_ready) s1_reg <= s1_next;
    end

    // Stage 2: e2 = p - v0 (pixel center)
    always_comb begin
        logic signed [16+SUBPIXEL_BITS:0] px_sp, py_sp;
        s2_next.valid = s1_reg.valid;
        s2_next.pixel = s1_reg.pixel;

        px_sp = $signed({1'b0, s1_reg.pixel.x}) <<< SUBPIXEL_BITS;
        py_sp = $signed({1'b0, s1_reg.pixel.y}) <<< SUBPIXEL_BITS;

        s2_next.e2x = (px_sp + $signed(1 <<< (SUBPIXEL_BITS-1))) - $signed(s1_reg.pixel.v0x);
        s2_next.e2y = (py_sp + $signed(1 <<< (SUBPIXEL_BITS-1))) - $signed(s1_reg.pixel.v0y);
    end
    always_ff @(posedge clk or posedge rst) begin
        if (rst) s2_reg <= '0;
        else if (s2_ready) s2_reg <= s2_next;
    end

    // Stage 3: area2 numerators (cross products)
    // v_num = cross(e2, e1); w_num = cross(e0, e2); u_num = denom - v_num - w_num
    always_comb begin
        logic signed [32+2*SUBPIXEL_BITS-1:0] e2x_e1y, e2y_e1x, e0x_e2y, e0y_e2x;
        logic signed [32+2*SUBPIXEL_BITS-1:0] denom_local;

        s3_next.valid = s2_reg.valid;
        s3_next.pixel = s2_reg.pixel;

        e2x_e1y = $signed(s2_reg.e2x) * $signed(s2_reg.pixel.e1y);
        e2y_e1x = $signed(s2_reg.e2y) * $signed(s2_reg.pixel.e1x);
        e0x_e2y = $signed(s2_reg.pixel.e0x) * $signed(s2_reg.e2y);
        e0y_e2x = $signed(s2_reg.pixel.e0y) * $signed(s2_reg.e2x);

        s3_next.v_num = e2x_e1y - e2y_e1x;
        s3_next.w_num = e0x_e2y - e0y_e2x;

        denom_local = $signed(s2_reg.pixel.e0x) * $signed(s2_reg.pixel.e1y)
                    - $signed(s2_reg.pixel.e0y) * $signed(s2_reg.pixel.e1x);

        s3_next.u_num = denom_local - s3_next.v_num - s3_next.w_num;
    end
    always_ff @(posedge clk or posedge rst) begin
        if (rst) s3_reg <= '0;
        else if (s3_ready) s3_reg <= s3_next;
    end

    // Stage 4: inside test (Top-Left), normalize by sign(denom)
    always_comb begin
        logic denom_neg; // sign(denom) == sign(denom_inv)
        logic signed [16+SUBPIXEL_BITS:0] edge_u_dx, edge_u_dy;
        logic signed [16+SUBPIXEL_BITS:0] edge_v_dx, edge_v_dy;
        logic signed [16+SUBPIXEL_BITS:0] edge_w_dx, edge_w_dy;
        logic inc_u, inc_v, inc_w;
        logic v_ok, w_ok, u_ok;

        s4_next.valid = s3_reg.valid;
        s4_next.pixel = s3_reg.pixel;

        denom_neg = ($signed(s3_reg.pixel.denom_inv) < 0);

        // Normalize numerators for TL rule with sign(denom)
        s4_next.vN = denom_neg ? -s3_reg.v_num : s3_reg.v_num;
        s4_next.wN = denom_neg ? -s3_reg.w_num : s3_reg.w_num;
        s4_next.uN = denom_neg ? -s3_reg.u_num : s3_reg.u_num;

        // Edge vectors for TL rule
        edge_u_dx = $signed(s3_reg.pixel.e1x) - $signed(s3_reg.pixel.e0x);
        edge_u_dy = $signed(s3_reg.pixel.e1y) - $signed(s3_reg.pixel.e0y);
        edge_v_dx = -$signed(s3_reg.pixel.e1x);
        edge_v_dy = -$signed(s3_reg.pixel.e1y);
        edge_w_dx =  $signed(s3_reg.pixel.e0x);
        edge_w_dy =  $signed(s3_reg.pixel.e0y);

        // Top-Left include rule
        inc_u = (edge_u_dy < 0) || ((edge_u_dy == 0) && (edge_u_dx > 0));
        inc_v = (edge_v_dy < 0) || ((edge_v_dy == 0) && (edge_v_dx > 0));
        inc_w = (edge_w_dy < 0) || ((edge_w_dy == 0) && (edge_w_dx > 0));

        v_ok = (s4_next.vN > 0) || ((s4_next.vN == 0) && inc_v);
        w_ok = (s4_next.wN > 0) || ((s4_next.wN == 0) && inc_w);
        u_ok = (s4_next.uN > 0) || ((s4_next.uN == 0) && inc_u);

        s4_next.is_inside = v_ok && w_ok && u_ok;
    end
    always_ff @(posedge clk or posedge rst) begin
        if (rst) s4_reg <= '0;
        else if (s4_ready) s4_reg <= s4_next;
    end

    // Stage 5: weights, interpolation with signed denom_inv (1/denom)
    localparam int WEIGHT_SHIFT = 2*SUBPIXEL_BITS + DENOM_INV_FBITS - 16;

    q16_16_t v_w, w_w, u_w;

    always_comb begin
        s5_next.valid = s4_reg.valid & s4_reg.is_inside;
        s5_next.pixel = s4_reg.pixel;

        if (s4_reg.is_inside) begin
            // Signed multiply: num * (1/denom). For interior pixels this is >=0.
            logic signed [32+2*SUBPIXEL_BITS+DENOM_INV_FBITS+1:0] v_mul, w_mul;

            v_mul = $signed(s3_reg.v_num) * $signed(s4_reg.pixel.denom_inv);
            w_mul = $signed(s3_reg.w_num) * $signed(s4_reg.pixel.denom_inv);

            if (WEIGHT_SHIFT > 0) begin
                // round-to-nearest
                v_w = q16_16_t'((v_mul + (1 <<< (WEIGHT_SHIFT-1))) >>> WEIGHT_SHIFT);
                w_w = q16_16_t'((w_mul + (1 <<< (WEIGHT_SHIFT-1))) >>> WEIGHT_SHIFT);
            end else begin
                v_w = q16_16_t'(v_mul <<< (-WEIGHT_SHIFT));
                w_w = q16_16_t'(w_mul <<< (-WEIGHT_SHIFT));
            end

            // guard against tiny negative due to ties/rounding
            if ($signed(v_w) < 0) v_w = '0;
            if ($signed(w_w) < 0) w_w = '0;

            u_w = q16_16_t'(32'h0001_0000) - v_w - w_w;
            if ($signed(u_w) < 0) u_w = '0;

            // interpolate color (RGB444) and depth (Q16.16)
            s5_next.color[11:8] = ((u_w * $unsigned(s4_reg.pixel.v0_color[11:8])) +
                                   (v_w * $unsigned(s4_reg.pixel.v1_color[11:8])) +
                                   (w_w * $unsigned(s4_reg.pixel.v2_color[11:8])) + 32'h0000_8000) >>> 16;

            s5_next.color[7:4]  = ((u_w * $unsigned(s4_reg.pixel.v0_color[7:4])) +
                                   (v_w * $unsigned(s4_reg.pixel.v1_color[7:4])) +
                                   (w_w * $unsigned(s4_reg.pixel.v2_color[7:4])) + 32'h0000_8000) >>> 16;

            s5_next.color[3:0]  = ((u_w * $unsigned(s4_reg.pixel.v0_color[3:0])) +
                                   (v_w * $unsigned(s4_reg.pixel.v1_color[3:0])) +
                                   (w_w * $unsigned(s4_reg.pixel.v2_color[3:0])) + 32'h0000_8000) >>> 16;

            s5_next.depth       = ((u_w * s4_reg.pixel.v0_depth) +
                                   (v_w * s4_reg.pixel.v1_depth) +
                                   (w_w * s4_reg.pixel.v2_depth) + 32'h0000_8000) >>> 16;
        end else begin
            s5_next.color = '0;
            s5_next.depth = '0;
        end
    end

    // Stage 5 reg (output register)
    always_ff @(posedge clk or posedge rst) begin
        if (rst) s5_reg <= '0;
        else if (s5_ready) s5_reg <= s5_next;
    end

    // outputs
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
