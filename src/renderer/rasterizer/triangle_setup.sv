`timescale 1ns / 1ps
`default_nettype none

import rasterizer_pkg::*;
import vertex_pkg::*;
import math_pkg::*;

module triangle_setup #(
    parameter int WIDTH  = 320,
    parameter int HEIGHT = 240
) (
    input  wire logic clk,
    input  wire logic rst,

    input  wire vertex_t v0,
    input  wire vertex_t v1,
    input  wire vertex_t v2,

    input  wire logic    in_valid,
    output logic         in_ready,

    output triangle_state_t out_state,
    output logic            out_valid,
    input  wire logic       out_ready,
    output logic            busy
);

    // handshake
    logic s1_ready, s2_ready, s3_ready, s4_ready, s5_ready, s6_ready;
    triangle_setup_stage1_t s1_reg, s1_next;
    triangle_setup_stage2_t s2_reg, s2_next;
    triangle_setup_stage3_t s3_reg, s3_next;
    triangle_setup_stage4_t s4_reg, s4_next;
    triangle_setup_stage5_t s5_reg, s5_next;

    // divider
    logic        div_valid;
    logic        div_divisor_ready, div_dividend_ready;
    logic        div_ready = div_divisor_ready & div_dividend_ready;
    logic [63:0] div_divisor, div_dividend;
    logic        div_out_valid;
    logic [86:0] div_out_data;

    // output reg
    triangle_state_t out_reg;
    logic            out_vld;

    // inflight
    logic div_busy;
    triangle_setup_stage5_t s5_hold;

    // produce flags
    logic produce_div;
    logic produce_degen;
    logic produce_any;

    // connections
    assign in_ready  = s1_ready;
    assign out_state = out_reg;
    assign out_valid = out_vld;
    assign s6_ready  = !out_vld || out_ready;
    assign busy      = s1_reg.valid || s2_reg.valid || s3_reg.valid || s4_reg.valid || s5_reg.valid || out_vld || div_busy;

    // stage readiness
    assign s1_ready = !s1_reg.valid || s2_ready;
    assign s2_ready = !s2_reg.valid || s3_ready;
    assign s3_ready = !s3_reg.valid || s4_ready;
    assign s4_ready = !s4_reg.valid || s5_ready;

    // Stage 1
    always_comb begin
        s1_next.valid      = in_valid;
        s1_next.v0         = v0;
        s1_next.v1         = v1;
        s1_next.v2         = v2;
        s1_next.bbox_min_x = clamp(q16_16_floor(min3(v0.pos.x, v1.pos.x, v2.pos.x)), 0, WIDTH-1);
        s1_next.bbox_max_x = clamp(q16_16_ceil(max3(v0.pos.x, v1.pos.x, v2.pos.x)),  0, WIDTH-1);
        s1_next.bbox_min_y = clamp(q16_16_floor(min3(v0.pos.y, v1.pos.y, v2.pos.y)), 0, HEIGHT-1);
        s1_next.bbox_max_y = clamp(q16_16_ceil(max3(v0.pos.y, v1.pos.y, v2.pos.y)),  0, HEIGHT-1);
    end
    always_ff @(posedge clk or posedge rst) begin
        if (rst) s1_reg <= '0;
        else if (s1_ready) s1_reg <= s1_next;
    end

    // Stage 2
    always_comb begin
        logic signed [18:0] v0x, v0y, v1x, v1y, v2x, v2y;
        logic signed [18:0] e0x, e0y, e1x, e1y;

        v0x = $signed(s1_reg.v0.pos.x[31:13]);
        v0y = $signed(s1_reg.v0.pos.y[31:13]);
        v1x = $signed(s1_reg.v1.pos.x[31:13]);
        v1y = $signed(s1_reg.v1.pos.y[31:13]);
        v2x = $signed(s1_reg.v2.pos.x[31:13]);
        v2y = $signed(s1_reg.v2.pos.y[31:13]);
        e0x = v1x - v0x;
        e0y = v1y - v0y;
        e1x = v2x - v0x;
        e1y = v2y - v0y;

        s2_next.valid      = s1_reg.valid;
        s2_next.v0x        = v0x;  s2_next.v0y = v0y;
        s2_next.v1x        = v1x;  s2_next.v1y = v1y;
        s2_next.v2x        = v2x;  s2_next.v2y = v2y;
        s2_next.e0x        = e0x;  s2_next.e0y = e0y;
        s2_next.e1x        = e1x;  s2_next.e1y = e1y;
        s2_next.bbox_min_x = s1_reg.bbox_min_x;
        s2_next.bbox_max_x = s1_reg.bbox_max_x;
        s2_next.bbox_min_y = s1_reg.bbox_min_y;
        s2_next.bbox_max_y = s1_reg.bbox_max_y;
        s2_next.v0_color   = s1_reg.v0.color;
        s2_next.v1_color   = s1_reg.v1.color;
        s2_next.v2_color   = s1_reg.v2.color;
        s2_next.v0_depth   = s1_reg.v0.pos.z;
        s2_next.v1_depth   = s1_reg.v1.pos.z;
        s2_next.v2_depth   = s1_reg.v2.pos.z;
    end
    always_ff @(posedge clk or posedge rst) begin
        if (rst) s2_reg <= '0;
        else if (s2_ready) s2_reg <= s2_next;
    end

    // Stage 3
    always_comb begin
        logic signed [37:0] d00, d01, d11;
        d00 = s2_reg.e0x*s2_reg.e0x + s2_reg.e0y*s2_reg.e0y;
        d01 = s2_reg.e0x*s2_reg.e1x + s2_reg.e0y*s2_reg.e1y;
        d11 = s2_reg.e1x*s2_reg.e1x + s2_reg.e1y*s2_reg.e1y;

        s3_next.valid      = s2_reg.valid;
        s3_next.v0x        = s2_reg.v0x;  s3_next.v0y = s2_reg.v0y;
        s3_next.e0x        = s2_reg.e0x;  s3_next.e0y = s2_reg.e0y;
        s3_next.e1x        = s2_reg.e1x;  s3_next.e1y = s2_reg.e1y;
        s3_next.d00        = d00;
        s3_next.d01        = d01;
        s3_next.d11        = d11;
        s3_next.bbox_min_x = s2_reg.bbox_min_x;
        s3_next.bbox_max_x = s2_reg.bbox_max_x;
        s3_next.bbox_min_y = s2_reg.bbox_min_y;
        s3_next.bbox_max_y = s2_reg.bbox_max_y;
        s3_next.v0_color   = s2_reg.v0_color;
        s3_next.v1_color   = s2_reg.v1_color;
        s3_next.v2_color   = s2_reg.v2_color;
        s3_next.v0_depth   = s2_reg.v0_depth;
        s3_next.v1_depth   = s2_reg.v1_depth;
        s3_next.v2_depth   = s2_reg.v2_depth;
    end
    always_ff @(posedge clk or posedge rst) begin
        if (rst) s3_reg <= '0;
        else if (s3_ready) s3_reg <= s3_next;
    end

    // Stage 4
    always_comb begin
        logic signed [75:0] denom;
        denom = s3_reg.d00*s3_reg.d11 - s3_reg.d01*s3_reg.d01;

        s4_next.valid      = s3_reg.valid;
        s4_next.v0x        = s3_reg.v0x;  s4_next.v0y = s3_reg.v0y;
        s4_next.e0x        = s3_reg.e0x;  s4_next.e0y = s3_reg.e0y;
        s4_next.e1x        = s3_reg.e1x;  s4_next.e1y = s3_reg.e1y;
        s4_next.d00        = s3_reg.d00;
        s4_next.d01        = s3_reg.d01;
        s4_next.d11        = s3_reg.d11;
        s4_next.denom      = denom;
        s4_next.bbox_min_x = s3_reg.bbox_min_x;
        s4_next.bbox_max_x = s3_reg.bbox_max_x;
        s4_next.bbox_min_y = s3_reg.bbox_min_y;
        s4_next.bbox_max_y = s3_reg.bbox_max_y;
        s4_next.v0_color   = s3_reg.v0_color;
        s4_next.v1_color   = s3_reg.v1_color;
        s4_next.v2_color   = s3_reg.v2_color;
        s4_next.v0_depth   = s3_reg.v0_depth;
        s4_next.v1_depth   = s3_reg.v1_depth;
        s4_next.v2_depth   = s3_reg.v2_depth;
    end
    always_ff @(posedge clk or posedge rst) begin
        if (rst) s4_reg <= '0;
        else if (s4_ready) s4_reg <= s4_next;
    end

    // Stage 5
    logic s5_can_fire_div, s5_fire_div, s5_fire_degen;
    logic div_divisor_ready_2, div_dividend_ready_2, s5_valid_2, not_busy_2, div_ready_2, divisor_nonzero_2;

    // helper: bit length of 76-bit number
    function automatic int bitlen76(input logic [75:0] x);
        int i;
        begin
            for (i = 75; i >= 0; i--) if (x[i]) return i+1;
            return 0;
        end
    endfunction

    // scaled operands (low 32 bits used)
    logic [31:0] divu_a_32;  // dividend
    logic [31:0] divu_b_32;  // divisor
    logic [31:0] divu_val;   // full WIDTH result from divu (Q0.16 in [15:0])

    // 'divu' control
    logic divu_start, divu_busy, divu_done, divu_valid, divu_dbz, divu_ovf;

    // legacy ready signals: always ready (we emulate AXIS with a 1-deep hold)
    assign div_divisor_ready  = 1'b1;
    assign div_dividend_ready = 1'b1;

    always_comb begin
        logic signed [75:0] denom_abs, denom_abs_rounded;
        int bl;
        int k0;
        int k;

        denom_abs          = s4_reg.denom[75] ? (~s4_reg.denom + 1) : s4_reg.denom;
        denom_abs_rounded  = denom_abs + 76'd2048; // +0.5 ulp before >>12

        bl  = bitlen76(denom_abs_rounded);
        k0  = (bl > 32) ? (bl - 32) : 0;      // minimum shift to fit 32-bit
        k   = (k0 > 28) ? 28 : k0;            // clamp so (28 - k) >= 0

        divu_b_32 = (denom_abs_rounded == 76'd0) ? 32'd0 : (denom_abs_rounded >> k);
        divu_a_32 = (denom_abs_rounded == 76'd0) ? 32'd0 : (32'd1 << (28 - k));

        s5_next.valid       = s4_reg.valid;
        s5_next.v0x         = s4_reg.v0x;  s5_next.v0y = s4_reg.v0y;
        s5_next.e0x         = s4_reg.e0x;  s5_next.e0y = s4_reg.e0y;
        s5_next.e1x         = s4_reg.e1x;  s5_next.e1y = s4_reg.e1y;
        s5_next.d00         = s4_reg.d00;
        s5_next.d01         = s4_reg.d01;
        s5_next.d11         = s4_reg.d11;
        s5_next.div_divisor = denom_abs_rounded[75:12]; // Q64.0
        s5_next.denom_neg   = s4_reg.denom[75];
        s5_next.bbox_min_x  = s4_reg.bbox_min_x;
        s5_next.bbox_max_x  = s4_reg.bbox_max_x;
        s5_next.bbox_min_y  = s4_reg.bbox_min_y;
        s5_next.bbox_max_y  = s4_reg.bbox_max_y;
        s5_next.v0_color    = s4_reg.v0_color;
        s5_next.v1_color    = s4_reg.v1_color;
        s5_next.v2_color    = s4_reg.v2_color;
        s5_next.v0_depth    = s4_reg.v0_depth;
        s5_next.v1_depth    = s4_reg.v1_depth;
        s5_next.v2_depth    = s4_reg.v2_depth;

        // Harden divider handshake 
        div_divisor_ready_2  = 1'b1;
        div_dividend_ready_2 = 1'b1;
        s5_valid_2           = (s5_reg.valid       === 1'b1);
        not_busy_2           = (div_busy           === 1'b0);
        div_ready_2          = div_divisor_ready_2 & div_dividend_ready_2;
        divisor_nonzero_2    = (divu_b_32 != 32'd0);

        s5_can_fire_div = s5_valid_2 && divisor_nonzero_2 && not_busy_2 && div_ready_2;
        s5_fire_div     = s5_can_fire_div;
        s5_fire_degen   = s5_reg.valid && (divu_b_32 == 32'd0) && s6_ready && !div_out_valid; // true-degenerate only
    end
    always_ff @(posedge clk or posedge rst) begin
        if (rst) s5_reg <= '0;
        else if (!s5_reg.valid || s5_fire_div || s5_fire_degen) s5_reg <= s5_next;
    end

    // s5 readiness
    assign s5_ready    = (!s5_reg.valid) || s5_fire_div || s5_fire_degen;

    // divider IO (carry scaled operands in legacy 64b wires' low halves)
    assign div_divisor  = {32'd0, divu_b_32};
    assign div_dividend = {32'd0, divu_a_32};
    assign div_valid    = s5_fire_div;
    assign divu_start   = s5_fire_div;

    // 'divu' instance (unsigned, Q0.16 result in val[15:0])
    divu #(.WIDTH(32), .FBITS(16)) u_divu (
        .clk   (clk),
        .rst   (rst),
        .start (divu_start),
        .busy  (divu_busy),
        .done  (divu_done),
        .valid (divu_valid),
        .dbz   (),
        .ovf   (),
        .a     (divu_a_32),
        .b     (divu_b_32),
        .val   (divu_val)
    );

    // emulate vendor AXIS outputs with a 1-deep hold
    logic        div_hold_valid;
    logic [15:0] div_hold_q16;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            div_busy       <= 1'b0;
            s5_hold        <= '0;
            out_reg        <= '0;
            out_vld        <= 1'b0;
            div_hold_valid <= 1'b0;
            div_hold_q16   <= 16'd0;
        end else begin
            if (s5_fire_div) begin
                s5_hold  <= s5_reg;
                div_busy <= 1'b1;
            end

            if (divu_done) begin
                div_hold_q16   <= divu_val[15:0]; // Q0.16
                div_hold_valid <= 1'b1;
            end
            if (div_hold_valid && s6_ready) begin
                div_hold_valid <= 1'b0;
            end
        end
    end

    assign div_out_valid = div_hold_valid;
    assign div_out_data  = {71'd0, div_hold_q16}; // pack denom_inv in [15:0]

    // produce flags
    always_comb begin
        produce_div   = div_out_valid && s6_ready;
        produce_degen = s5_fire_degen;
        produce_any   = produce_div || produce_degen;
    end

    // inflight + output
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            // already reset above
        end else begin
            if (s5_fire_div) begin
                s5_hold  <= s5_reg;
                div_busy <= 1'b1;
            end

            if (produce_degen) begin
                out_reg.v0x        <= s5_reg.v0x;
                out_reg.v0y        <= s5_reg.v0y;
                out_reg.e0x        <= s5_reg.e0x;
                out_reg.e0y        <= s5_reg.e0y;
                out_reg.e1x        <= s5_reg.e1x;
                out_reg.e1y        <= s5_reg.e1y;
                out_reg.d00        <= s5_reg.d00;
                out_reg.d01        <= s5_reg.d01;
                out_reg.d11        <= s5_reg.d11;
                out_reg.denom_inv  <= 16'd0;
                out_reg.denom_neg  <= 1'b0;
                out_reg.bbox_min_x <= s5_reg.bbox_min_x;
                out_reg.bbox_max_x <= s5_reg.bbox_max_x;
                out_reg.bbox_min_y <= s5_reg.bbox_min_y;
                out_reg.bbox_max_y <= s5_reg.bbox_max_y;
                out_reg.v0_color   <= s5_reg.v0_color;
                out_reg.v1_color   <= s5_reg.v1_color;
                out_reg.v2_color   <= s5_reg.v2_color;
                out_reg.v0_depth   <= s5_reg.v0_depth;
                out_reg.v1_depth   <= s5_reg.v1_depth;
                out_reg.v2_depth   <= s5_reg.v2_depth;
            end
            if (produce_div) begin
                out_reg.v0x        <= s5_hold.v0x;
                out_reg.v0y        <= s5_hold.v0y;
                out_reg.e0x        <= s5_hold.e0x;
                out_reg.e0y        <= s5_hold.e0y;
                out_reg.e1x        <= s5_hold.e1x;
                out_reg.e1y        <= s5_hold.e1y;
                out_reg.d00        <= s5_hold.d00;
                out_reg.d01        <= s5_hold.d01;
                out_reg.d11        <= s5_hold.d11;
                out_reg.denom_inv  <= div_out_data[15:0]; // unchanged downstream read
                out_reg.denom_neg  <= s5_hold.denom_neg;
                out_reg.bbox_min_x <= s5_hold.bbox_min_x;
                out_reg.bbox_max_x <= s5_hold.bbox_max_x;
                out_reg.bbox_min_y <= s5_hold.bbox_min_y;
                out_reg.bbox_max_y <= s5_hold.bbox_max_y;
                out_reg.v0_color   <= s5_hold.v0_color;
                out_reg.v1_color   <= s5_hold.v1_color;
                out_reg.v2_color   <= s5_hold.v2_color;
                out_reg.v0_depth   <= s5_hold.v0_depth;
                out_reg.v1_depth   <= s5_hold.v1_depth;
                out_reg.v2_depth   <= s5_hold.v2_depth;
                div_busy           <= 1'b0;
            end

            out_vld <= (out_vld && !out_ready) || produce_any;
        end
    end

endmodule
