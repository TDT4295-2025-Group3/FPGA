`timescale 1ns / 1ps
`default_nettype none

import math_pkg::*;
import vertex_pkg::*;
import transformer_pkg::*;

// p_cam = R^T * (p_world - C), scale is ignored (camera scale = 1)
module world_camera_transformer(
    input  clk,
    input  rst,

    input  q16_16_t    focal_length,
    input  transform_t camera_transform,
    input  triangle_t  triangle,
    input  logic       in_valid,
    output logic       in_ready,

    output q16_16_t    out_focal_length,
    output triangle_t  out_triangle,
    output logic       out_valid,
    input  logic       out_ready,

    output logic       busy
);

    // Per-triangle capture
    q16_16_t    pass_focal_length;
    transform_t pass_camera_transform;
    triangle_t  pass_triangle; // NEW: latch the triangle per transaction

    // Book-keeping
    logic [1:0] vert_ctr_in;
    logic [1:0] vert_ctr_out;
    logic       load_vert;
    logic [1:0] load_vert_ctr;

    // Pipeline valid tracker
    logic [2:0] valid_pipe;

    // Output sticky valid + stall
    logic out_valid_r;
    logic stall;

    // Working registers (stage data)
    vertex_t    load_v;   // stage -1 (loader)
    vertex_t    temp_v;   // stage 0 (translate)
    vertex_t    cam_v;    // stage 1 (rotate / to camera)

    // Ready/Busy/Valid wiring
    assign stall                = out_valid_r && !out_ready;         // output stage holds data but sink not ready
    assign busy                 = (|valid_pipe) || out_valid_r || load_vert || (vert_ctr_in != 2'd0) || (vert_ctr_out != 2'd0); // busy if anything in pipe or output pending or mid-load
    assign in_ready             = (vert_ctr_in == 2'd0) && !stall && !load_vert && (valid_pipe == 3'b000) && !out_valid_r; // accept only when able to start a new triangle
    assign out_valid            = out_valid_r;
    assign out_focal_length     = pass_focal_length;

    // ===== Arithmetic helpers (unchanged) =====
    // These are placeholders to preserve structure. Keep your original math for:
    //  - Computing translation (p_world - C) into temp_v
    //  - Applying R^T to produce cam_v
    //
    // Expected to read camera_transform.{tx,ty,tz,rx,ry,rz}, etc., and use your math_pkg ops.

    // --- local helpers for Q16.16 ---
    function automatic q16_16_t mul_q(input q16_16_t a, input q16_16_t b);
        q32_32_t wide = q32_32_t'(a) * q32_32_t'(b);
        return q16_16_t'(wide >>> 16);
    endfunction

    // ZYX Euler rotation with transpose of camera rotation.
    // Using sin(-θ) = -sin(θ), cos(-θ) = cos(θ)
    function automatic point3d_t rotate_zyx_transpose(
        input point3d_t p,
        input point3d_t cam_sin,
        input point3d_t cam_cos
    );
        // Apply Rx(-x) * Ry(-y) * Rz(-z)
        point3d_t r;

        // Rz(-z): sin -> -sin_z
        q16_16_t sZ = -cam_sin.z;
        q16_16_t cZ =  cam_cos.z;
        q16_16_t x1 = q16_16_t'(mul_q(cZ, p.x) - mul_q(sZ, p.y));
        q16_16_t y1 = q16_16_t'(mul_q(sZ, p.x) + mul_q(cZ, p.y));
        q16_16_t z1 = p.z;

        // Ry(-y): sin -> -sin_y
        q16_16_t sY = -cam_sin.y;
        q16_16_t cY =  cam_cos.y;
        q16_16_t x2 = q16_16_t'(mul_q(cY, x1) + mul_q(sY, z1));
        q16_16_t y2 = y1;
        q16_16_t z2 = q16_16_t'(-mul_q(sY, x1) + mul_q(cY, z1));

        // Rx(-x): sin -> -sin_x
        q16_16_t sX = -cam_sin.x;
        q16_16_t cX =  cam_cos.x;
        r.x = x2;
        r.y = q16_16_t'(mul_q(cX, y2) - mul_q(sX, z2));
        r.z = q16_16_t'(mul_q(sX, y2) + mul_q(cX, z2));

        return r;
    endfunction

    // ---------------- Reset / Main ----------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            vert_ctr_in        <= 2'd0;
            vert_ctr_out       <= 2'd0;
            load_vert          <= 1'b0;
            load_vert_ctr      <= 2'd0;
            valid_pipe         <= 3'b000;

            pass_focal_length  <= '0;
            pass_camera_transform <= '0;
            pass_triangle      <= '0;

            load_v             <= '0;
            temp_v             <= '0;
            cam_v              <= '0;

            out_valid_r        <= 1'b0;
        end else begin
            // Clear sticky out_valid once accepted
            if (out_valid_r && out_ready)
                out_valid_r <= 1'b0;

            // Start-of-triangle stretch (3-cycle replicate of first accept), unchanged structure
            if (in_valid && in_ready && (vert_ctr_in == 2'd0)) begin
                load_vert             <= 1'b1;
                load_vert_ctr         <= 2'd1;
                pass_camera_transform <= camera_transform; // capture once per triangle
                pass_focal_length     <= focal_length;
                pass_triangle         <= triangle;         // NEW: capture entire triangle atomically
            end else if (load_vert) begin
                if (load_vert_ctr == 2'd2) begin
                    load_vert     <= 1'b0;
                    load_vert_ctr <= 2'd0;
                end else begin
                    load_vert_ctr <= load_vert_ctr + 2'd1;
                end
            end

            // Advance valid pipe only when not stalled
            if (!stall) begin
                // If we are finishing a triangle this cycle at stage 2 (see below), don't also shift
                if (valid_pipe[2] && (vert_ctr_out == 2'd2)) begin
                    valid_pipe <= 3'b000; // complete triangle atomically
                end else begin
                    valid_pipe <= { valid_pipe[1:0], ((in_valid && in_ready) || load_vert) };
                end
            end

            // Loader (-1): choose incoming vertex (only when not stalled)
            if (!stall && ((in_valid && in_ready) || load_vert)) begin
                unique case (vert_ctr_in)
                    2'd0: load_v <= (in_valid && in_ready) ? triangle.v0 : pass_triangle.v0; // first beat uses current triangle; subsequent use latched
                    2'd1: load_v <= pass_triangle.v1;
                    2'd2: load_v <= pass_triangle.v2;
                    default: /* no-op */ ;
                endcase
                vert_ctr_in <= vert_ctr_in + 2'd1;
            end

            // Stage 0: translation p_world - C  (only when its valid bit & not stalled)
            if (!stall && valid_pipe[0]) begin
                // ======= BEGIN ORIGINAL MATH (translation) =======
                // temp_v.x = sub_transform(load_v.x, pass_camera_transform.tx);
                // temp_v.y = sub_transform(load_v.y, pass_camera_transform.ty);
                // temp_v.z = sub_transform(load_v.z, pass_camera_transform.tz);
                temp_v        <= load_v; // preserve color
                temp_v.pos.x  <= load_v.pos.x - pass_camera_transform.pos.x;
                temp_v.pos.y  <= load_v.pos.y - pass_camera_transform.pos.y;
                temp_v.pos.z  <= load_v.pos.z - pass_camera_transform.pos.z;
                // ======= END ORIGINAL MATH =======
            end

            // Stage 1: rotation cam = R^T * temp  (only when its valid bit & not stalled)
            if (!stall && valid_pipe[1]) begin
                // ======= BEGIN ORIGINAL MATH (rotation) =======
                // cam_v = rotate_into_camera_space(temp_v, pass_camera_transform);
                cam_v       <= temp_v;
                cam_v.pos   <= rotate_zyx_transpose(
                                  temp_v.pos,
                                  pass_camera_transform.rot_sin,
                                  pass_camera_transform.rot_cos
                               );
                // ======= END ORIGINAL MATH =======
            end

            // Stage 2 / output writeback and triangle assembly (only when not stalled)
            if (!stall && valid_pipe[2]) begin
                unique case (vert_ctr_out)
                    2'd0: out_triangle.v0 <= cam_v;
                    2'd1: out_triangle.v1 <= cam_v;
                    2'd2: begin
                        out_triangle.v2 <= cam_v;
                        out_valid_r     <= 1'b1;          // sticky valid until taken
                        vert_ctr_out    <= 2'd0;
                        vert_ctr_in     <= 2'd0;
                        // valid_pipe is cleared above in the mutually exclusive branch
                    end
                    default: /* no-op */ ;
                endcase

                if (vert_ctr_out != 2'd2)
                    vert_ctr_out <= vert_ctr_out + 2'd1;
            end
        end
    end
endmodule
