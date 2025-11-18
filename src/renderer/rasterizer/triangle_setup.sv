import vertex_pkg::*;
import math_pkg::*;
import color_pkg::*;
module triangle_setup #(
    parameter int WIDTH  = 320,
    parameter int HEIGHT = 240,
    parameter int SUBPIXEL_BITS = 4,
    parameter int DENOM_INV_BITS = 36,
    parameter int DENOM_INV_FBITS = 35,
    parameter bit BACKFACE_CULLING = 1'b1
) (
    input  wire logic clk,
    input  wire logic rst,

    input  wire vertex_t v0,
    input  wire vertex_t v1,
    input  wire vertex_t v2,

    input  wire logic    in_valid,
    output logic         in_ready,

    output logic signed [16+SUBPIXEL_BITS-1:0] out_v0x, out_v0y,
    output logic signed [16+SUBPIXEL_BITS-1:0] out_e0x, out_e0y,
    output logic signed [16+SUBPIXEL_BITS-1:0] out_e1x, out_e1y,
    output logic signed [DENOM_INV_BITS-1:0] out_denom_inv,
    output logic [$clog2(WIDTH)-1:0]  out_bbox_min_x, out_bbox_max_x,
    output logic [$clog2(HEIGHT)-1:0] out_bbox_min_y, out_bbox_max_y,
    output color12_t out_v0_color, out_v1_color, out_v2_color,
    output q16_16_t out_v0_depth, out_v1_depth, out_v2_depth,

    output logic            out_valid,
    input  wire logic       out_ready,
    output logic            busy
);

    typedef struct packed {
        logic        valid;
        vertex_t     v0, v1, v2;
        logic [$clog2(WIDTH)-1:0]  bbox_min_x, bbox_max_x;
        logic [$clog2(HEIGHT)-1:0] bbox_min_y, bbox_max_y;
    } triangle_setup_stage1_t;

    typedef struct packed {
        logic valid;
        logic signed [16+SUBPIXEL_BITS-1:0] v0x, v0y;
        logic signed [16+SUBPIXEL_BITS-1:0] v1x, v1y;
        logic signed [16+SUBPIXEL_BITS-1:0] v2x, v2y;
        logic signed [16+SUBPIXEL_BITS-1:0] e0x, e0y;
        logic signed [16+SUBPIXEL_BITS-1:0] e1x, e1y;
        logic [$clog2(WIDTH)-1:0]  bbox_min_x, bbox_max_x;
        logic [$clog2(HEIGHT)-1:0] bbox_min_y, bbox_max_y;
        color12_t     v0_color, v1_color, v2_color;
        q16_16_t      v0_depth, v1_depth, v2_depth;
    } triangle_setup_stage2_t;

    typedef struct packed {
        logic valid;
        logic signed [16+SUBPIXEL_BITS-1:0] v0x, v0y;
        logic signed [16+SUBPIXEL_BITS-1:0] e0x, e0y;
        logic signed [16+SUBPIXEL_BITS-1:0] e1x, e1y;
        logic signed [32+2*SUBPIXEL_BITS-1:0] denom; 
        logic [$clog2(WIDTH)-1:0]  bbox_min_x, bbox_max_x;
        logic [$clog2(HEIGHT)-1:0] bbox_min_y, bbox_max_y;
        color12_t     v0_color, v1_color, v2_color;
        q16_16_t      v0_depth, v1_depth, v2_depth;
    } triangle_setup_stage3_t;

    // handshake
    logic s1_ready, s2_ready, s3_ready;
    triangle_setup_stage1_t s1_reg, s1_next;
    triangle_setup_stage2_t s2_reg, s2_next;
    triangle_setup_stage3_t s3_reg, s3_next;

    // inverse module signals
    logic        inv_start;
    logic        inv_busy;
    logic        inv_done;
    logic        inv_valid;
    logic inv_dbz, inv_ovf;
    logic signed [32+2*SUBPIXEL_BITS-1:0] inv_x;
    logic signed [DENOM_INV_BITS-1:0] inv_y;

    // divider output
    logic        div_out_valid;
    logic signed [DENOM_INV_BITS-1:0] div_out_data;

    // inflight
    logic div_busy;
    triangle_setup_stage3_t s3_hold;

    // produce flags
    logic produce_div;

    // connections
    assign in_ready  = s1_ready;
    assign busy      = s1_reg.valid || s2_reg.valid || s3_reg.valid || out_valid || div_busy;

    // stage readiness
    assign s1_ready = !s1_reg.valid || s2_ready;
    assign s2_ready = !s2_reg.valid || s3_ready;

    // inverse instance (replaces iterative divider)
    inv #(
        .IN_BITS(32+2*SUBPIXEL_BITS),
        .IN_FBITS(2*SUBPIXEL_BITS),
        .OUT_BITS(DENOM_INV_BITS),
        .OUT_FBITS(DENOM_INV_FBITS)
    ) inv_inst (
        .clk   (clk),
        .rst   (rst),
        .start (inv_start),
        .x     (inv_x),
        .busy  (inv_busy),
        .done  (inv_done),
        .valid (inv_valid),
        .dbz   (inv_dbz),
        .ovf   (inv_ovf),
        .y     (inv_y)
    );

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
        logic signed [16+SUBPIXEL_BITS-1:0] v0x, v0y, v1x, v1y, v2x, v2y;
        logic signed [16+SUBPIXEL_BITS-1:0] e0x, e0y, e1x, e1y;

        v0x = $signed(s1_reg.v0.pos.x[31:16-SUBPIXEL_BITS]);
        v0y = $signed(s1_reg.v0.pos.y[31:16-SUBPIXEL_BITS]);
        v1x = $signed(s1_reg.v1.pos.x[31:16-SUBPIXEL_BITS]);
        v1y = $signed(s1_reg.v1.pos.y[31:16-SUBPIXEL_BITS]);
        v2x = $signed(s1_reg.v2.pos.x[31:16-SUBPIXEL_BITS]);
        v2y = $signed(s1_reg.v2.pos.y[31:16-SUBPIXEL_BITS]);
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
        logic signed [32+2*SUBPIXEL_BITS-1:0] denom;
        denom  = s2_reg.e0x*s2_reg.e1y - s2_reg.e0y*s2_reg.e1x;
        s3_next.valid = s2_reg.valid && (denom != 0) && ((!BACKFACE_CULLING) || (denom > 0));
        s3_next.v0x        = s2_reg.v0x;  s3_next.v0y = s2_reg.v0y;
        s3_next.e0x        = s2_reg.e0x;  s3_next.e0y = s2_reg.e0y;
        s3_next.e1x        = s2_reg.e1x;  s3_next.e1y = s2_reg.e1y;
        s3_next.denom      = denom;
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
    // s3 readiness
    assign s3_ready = (!s3_reg.valid) || (s3_reg.valid && !div_busy && !inv_busy && !div_out_valid);
    always_ff @(posedge clk or posedge rst) begin
        if (rst) s3_reg <= '0;
        else if (s3_ready) s3_reg <= s3_next;
    end

    // inverse IO mapping
    assign inv_x     = s3_reg.denom; // denominator as input

    logic launch_inv;
    assign launch_inv = s3_reg.valid && !div_busy && !inv_busy && !div_out_valid;

    assign inv_start = launch_inv;

    // One-deep result buffer (skid)
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            div_out_valid <= 1'b0;
            div_out_data  <= '0;
        end else begin
            if (inv_done && inv_valid) begin
                div_out_valid <= 1'b1;
                div_out_data  <= inv_y;
            end
            
            if (div_out_valid && (!out_valid || out_ready)) begin
                div_out_valid <= 1'b0;
            end
        end
    end

    // produce flags
    assign produce_div = div_out_valid && (!out_valid || out_ready);

    // inflight + output
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            div_busy <= 1'b0;
            s3_hold  <= '0;
            out_valid  <= 1'b0;
        end else begin
            if (launch_inv) begin
                s3_hold  <= s3_reg;
                div_busy <= 1'b1;
            end

            if (produce_div) begin
                out_v0x        <= s3_hold.v0x;
                out_v0y        <= s3_hold.v0y;
                out_e0x        <= s3_hold.e0x;
                out_e0y        <= s3_hold.e0y;
                out_e1x        <= s3_hold.e1x;
                out_e1y        <= s3_hold.e1y;
                out_denom_inv  <= div_out_data;
                out_bbox_min_x <= s3_hold.bbox_min_x;
                out_bbox_max_x <= s3_hold.bbox_max_x;
                out_bbox_min_y <= s3_hold.bbox_min_y;
                out_bbox_max_y <= s3_hold.bbox_max_y;
                out_v0_color   <= s3_hold.v0_color;
                out_v1_color   <= s3_hold.v1_color;
                out_v2_color   <= s3_hold.v2_color;
                out_v0_depth   <= s3_hold.v0_depth;
                out_v1_depth   <= s3_hold.v1_depth;
                out_v2_depth   <= s3_hold.v2_depth;
                div_busy           <= 1'b0;
            end
            
            if (inv_done && !inv_valid) begin
                div_busy <= 1'b0;
            end

            out_valid <= (out_valid && !out_ready) || produce_div;
        end
    end

endmodule
