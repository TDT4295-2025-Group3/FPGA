`timescale 1ns / 1ps
`default_nettype wire
import vertex_pkg::*;
import math_pkg::*;

module vertex_projector(
    input  logic clk,
    input  logic rst,

    input  vertex_t   vertex,
    input  logic      in_valid,
    output logic      in_ready,

    input  q16_16_t   focal_length,

    output vertex_t   out_vertex,
    output logic      out_valid,
    input  logic      out_ready,
    output logic      busy
);

    // ----------------------------
    // Pipeline registers / control
    // ----------------------------
    vertex_t load_v, div_v, proj_v;
    q16_16_t z_inv_reg;

    // stage flags
    logic load_done;      // stage 0: input latched
    logic load_div_done;  // stage 1: divider kicked
    logic latch_done;     // stage 2: inv result latched
    logic proj_done;      // stage 3: projection complete
    logic output_pending; // waiting for downstream to accept

    // Divider interface (uses SIGNED z directly)
    logic    div_busy, div_done, div_valid;
    q16_16_t div_b;     // signed z going into inv/div
    q16_16_t div_val;   // 1/z in Q16.16 from inv
    q16_16_t z_inv;

    // Small epsilon to avoid division blow-ups near z=0 (Q16.16)
    localparam q16_16_t Z_EPS = 32'sh00000400; // ~1/1024, tune as needed

    // ---------- Reciprocal (signed) ----------
    // Keep your 'inv' wrapper; it is signed, so no manual sign twiddling needed.
    inv #(
        .IN_BITS   (32),
        .IN_FBITS  (16),
        .OUT_BITS  (32),
        .OUT_FBITS (16)
    ) u_divu (
        .clk   (clk),
        .rst   (rst),
        .start (load_div_done),
        .x     ($signed(div_b)),  // feed signed z (guarded)
        .busy  (div_busy),
        .done  (div_done),
        .valid (div_valid),
        .dbz   (),                // unused
        .ovf   (),                // unused
        .y     (div_val)
    );

    assign z_inv = q16_16_t'(div_val);

    // Busy / ready
    assign busy     = load_done || load_div_done || div_done || div_busy || latch_done || proj_done || output_pending;
    assign in_ready = !busy;

    // ----------------
    // Stage 0: Load in
    // ----------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            load_done <= 1'b0;
        end else begin
            if (in_valid && in_ready) begin
                load_v    <= vertex;
                load_done <= 1'b1;
            end else begin
                load_done <= 1'b0;
            end
        end
    end

    // --------------------------------------
    // Stage 1: Prepare signed z and start inv
    // --------------------------------------
    q16_16_t z_signed, z_guard;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            load_div_done <= 1'b0;
            div_b         <= '0;
            z_signed      <= '0;
            z_guard       <= '0;
            div_v         <= '0;
        end else begin
            if (load_done) begin
                q16_16_t z_now, z_g;
                // Latch current z for observability (unchanged name/role)
                z_signed <= load_v.pos.z;

                // Guard |z| away from 0 while preserving sign — computed from *current* input z
                z_now = load_v.pos.z;

                if      (z_now == 32'sd0)                 z_g = Z_EPS;
                else if (z_now >  0 && z_now <  Z_EPS)    z_g = Z_EPS;
                else if (z_now <  0 && z_now > -Z_EPS)    z_g = -Z_EPS;
                else                                      z_g = z_now;

                z_guard       <= z_g;      // keep original register for debug/visibility
                div_b         <= z_g;      // *** signed, guarded z into inv ***
                load_div_done <= 1'b1;
                div_v         <= load_v;   // carry attrs forward
            end else begin
                load_div_done <= 1'b0;
            end
        end
    end

    // -----------------------------
    // Stage 2: Latch 1/z from inv
    // -----------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            z_inv_reg  <= '0;
            latch_done <= 1'b0;
        end else begin
            if (div_done) begin
                z_inv_reg  <= z_inv;
                latch_done <= 1'b1;
            end else begin
                latch_done <= 1'b0;
            end
        end
    end

    // ---------------------------------------
    // Stage 3: Perspective projection (pure)
    // x' = f * x / z, y' = f * y / z
    // ---------------------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            proj_done <= 1'b0;
            proj_v    <= '0;
        end else begin
            if (latch_done) begin
                // No manual sign flip — z_inv already has the sign
                proj_v.pos.x <= project_q16_16(focal_length, div_v.pos.x, z_inv_reg);
                proj_v.pos.y <= project_q16_16(focal_length, div_v.pos.y, z_inv_reg);
                proj_v.pos.z <= div_v.pos.z;   // keep original z for depth
                proj_v.color <= div_v.color;
                proj_done    <= 1'b1;
            end else begin
                proj_done <= 1'b0;
            end
        end
    end

    // -------------------------
    // Output staging / handshake
    // -------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            out_valid       <= 1'b0;
            output_pending  <= 1'b0;
            out_vertex      <= '0;
        end else begin
            if (proj_done) begin
                out_vertex     <= proj_v;
                out_valid      <= 1'b1;
                output_pending <= 1'b1;
            end else if (out_ready && out_valid) begin
                out_valid      <= 1'b0;
                output_pending <= 1'b0;
            end
        end
    end

endmodule