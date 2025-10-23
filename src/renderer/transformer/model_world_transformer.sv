// `default_nettype none
// `timescale 1ns / 1ps

// import math_pkg::*;
// import vertex_pkg::*;
// import transformer_pkg::*;

// module model_world_transformer(
//     input  wire logic        clk,
//     input  wire logic        rst,

//     input  wire q16_16_t    focal_length,
//     input  wire transform_t camera_transform,

//     input  wire transform_t  transform,
//     input  wire triangle_t   triangle,
//     input  wire logic        in_valid,
//     output      logic        in_ready,

//     output      q16_16_t     out_focal_length,
//     output      transform_t  out_camera_transform,
//     output      triangle_t   out_triangle,
//     output      logic        out_valid,
//     input       logic        out_ready,

//     output      logic        busy
// );

//     // Per-triangle capture
//     q16_16_t     pass_focal_length;
//     transform_t  pass_camera_transform;

//     // Book-keeping
//     logic [1:0]  vert_ctr_in;
//     logic        load_vert;
//     logic [1:0]  load_vert_ctr;

//     // Pipeline valid tracker
//     logic [2:0]  valid_pipe;

//     // Output sticky valid + stall
//     logic        out_valid_r;
//     logic        stall;

//     // Working registers (stage data)
//     vertex_t     load_v;    // stage -1
//     vertex_t     world_v0;  // stage 0 (rotation)
//     vertex_t     world_v;   // stage 1 (translation -> world)

//     // ===== Added latches to prevent mixing across triangles =====
//     triangle_t   tri_r;
//     transform_t  transform_r;

//     // ===== NEW: carry vertex index through the pipe =====
//     logic [1:0]  idx_load;     // index at loader beat (0/1/2)
//     logic [1:0]  idx_pipe0;    // stage 0 index
//     logic [1:0]  idx_pipe1;    // stage 1 index
//     logic [1:0]  idx_pipe2;    // stage 2 index (writeback)

//     // Outputs
//     assign out_valid            = out_valid_r;
//     assign busy                 = (|valid_pipe) || out_valid_r;
//     assign stall                = out_valid_r && !out_ready;

//     // Handshake once per triangle (not per-vertex)
//     // (tighten) don't accept a new triangle while anything is in flight
//     assign in_ready             = (vert_ctr_in == 2'd0) && !stall && !busy;

//     assign out_focal_length     = pass_focal_length;
//     assign out_camera_transform = pass_camera_transform;

//     // ===== Arithmetic helpers (unchanged) =====

//     // --- local helpers for Q16.16 ---
//     function automatic q16_16_t mul_q(input q16_16_t a, input q16_16_t b);
//         // Force signed multiply and arithmetic shift
//         q32_32_t wide = $signed(a) * $signed(b);
//         return q16_16_t'($signed(wide) >>> 16);
//     endfunction

//     function automatic q16_16_t add_q(input q16_16_t a, input q16_16_t b);
//         return q16_16_t'($signed(a) + $signed(b));
//     endfunction

//     function automatic q16_16_t sub_q(input q16_16_t a, input q16_16_t b);
//         return q16_16_t'($signed(a) - $signed(b));
//     endfunction

//     function automatic point3d_t scale3(input point3d_t p, input point3d_t s);
//         point3d_t r;
//         r.x = mul_q(p.x, s.x);
//         r.y = mul_q(p.y, s.y);
//         r.z = mul_q(p.z, s.z);
//         return r;
//     endfunction

//     // ZYX Euler rotation using precomputed sin/cos in transform_r
//     function automatic point3d_t rotate_zyx(
//         input point3d_t p,
//         input point3d_t sinv,
//         input point3d_t cosv
//     );
//         point3d_t r;
//         // Rz
//         q16_16_t x1 = sub_q(mul_q(cosv.z, p.x), mul_q(sinv.z, p.y));
//         q16_16_t y1 = add_q(mul_q(sinv.z, p.x), mul_q(cosv.z, p.y));
//         q16_16_t z1 = p.z;
//         // Ry
//         q16_16_t x2 = add_q(mul_q(cosv.y, x1), mul_q(sinv.y, z1));
//         q16_16_t y2 = y1;
//         q16_16_t z2 = sub_q(mul_q(cosv.y, z1), mul_q(sinv.y, x1));
//         // Rx
//         r.x = x2;
//         r.y = sub_q(mul_q(cosv.x, y2), mul_q(sinv.x, z2));
//         r.z = add_q(mul_q(sinv.x, y2), mul_q(cosv.x, z2));
//         return r;
//     endfunction

//     always_ff @(posedge clk or posedge rst) begin
//         if (rst) begin
//             vert_ctr_in            <= 2'd0;
//             load_vert              <= 1'b0;
//             load_vert_ctr          <= 2'd0;
//             valid_pipe             <= 3'b000;

//             pass_focal_length      <= '0;
//             pass_camera_transform  <= '0;

//             load_v                 <= '0;
//             world_v0               <= '0;
//             world_v                <= '0;

//             tri_r                  <= '0;
//             transform_r            <= '0;

//             out_valid_r            <= 1'b0;

//             // NEW: index pipe reset
//             idx_load               <= 2'd0;
//             idx_pipe0              <= 2'd0;
//             idx_pipe1              <= 2'd0;
//             idx_pipe2              <= 2'd0;
//         end else begin
//             // Clear sticky out_valid when accepted
//             if (out_valid_r && out_ready)
//                 out_valid_r <= 1'b0;

//             // Start-of-triangle capture (3-cycle stretch), unchanged structure
//             if (in_valid && in_ready && (vert_ctr_in == 2'd0)) begin
//                 load_vert              <= 1'b1;
//                 load_vert_ctr          <= 2'd0; // start at 0 to produce 3 internal load cycles (0,1,2)

//                 // Latch all per-triangle inputs on the single upstream handshake
//                 pass_camera_transform  <= camera_transform; // forward camera data alongside
//                 pass_focal_length      <= focal_length;
//                 tri_r                  <= triangle;
//                 transform_r            <= transform;
//             end else if (load_vert) begin
//                 if (!stall) begin
//                     if (load_vert_ctr == 2'd2) begin
//                         load_vert     <= 1'b0;
//                         load_vert_ctr <= 2'd0;
//                     end else begin
//                         load_vert_ctr <= load_vert_ctr + 2'd1;
//                     end
//                 end
//             end

//             // Advance valid pipe only when not stalled
//             if (!stall)
//                 // Push a '1' only when the internal loader is active.
//                 // This avoids sampling tri_r/transform_r on the handshake edge.
//                 valid_pipe <= { valid_pipe[1:0], load_vert };

//             // Loader (-1): choose incoming vertex (only when not stalled)
//             if (!stall && load_vert) begin
//                 unique case (vert_ctr_in)
//                     2'd0: begin load_v <= tri_r.v0; idx_load <= 2'd0; end
//                     2'd1: begin load_v <= tri_r.v1; idx_load <= 2'd1; end
//                     2'd2: begin load_v <= tri_r.v2; idx_load <= 2'd2; end
//                     default: /* no-op */ ;
//                 endcase
//                 vert_ctr_in <= vert_ctr_in + 2'd1;
//             end

//             // === NEW: index pipe marches with valid_pipe and stalls ===
//             if (!stall) begin
//                 if (load_vert) begin
//                     // when we push valid_pipe[0] we also capture the index into stage0
//                     idx_pipe0 <= idx_load;
//                 end
//                 // shift indices only when corresponding stage is valid (mirrors stage enables)
//                 if (valid_pipe[0]) idx_pipe1 <= idx_pipe0;
//                 if (valid_pipe[1]) idx_pipe2 <= idx_pipe1;
//             end

//             // Stage 0: rotation into intermediate world_v0 (only when its valid bit & not stalled)
//             if (!stall && valid_pipe[0]) begin
//                 // ======= BEGIN ORIGINAL MATH (rotation) =======
//                 vertex_t tmp0;
//                 tmp0               = load_v; // pass-through color etc.
//                 tmp0.pos           = rotate_zyx(
//                                         scale3(load_v.pos, transform_r.scale),
//                                         transform_r.rot_sin,
//                                         transform_r.rot_cos
//                                      );
//                 world_v0 <= tmp0; // single write to the stage register
//                 // ======= END ORIGINAL MATH =======
//             end

//             // Stage 1: translation into world_v (only when its valid bit & not stalled)
//             if (!stall && valid_pipe[1]) begin
//                 // ======= BEGIN ORIGINAL MATH (translation) =======
//                 vertex_t tmp1;
//                 tmp1       = world_v0;
//                 tmp1.pos.x = add_q(world_v0.pos.x, transform_r.pos.x);
//                 tmp1.pos.y = add_q(world_v0.pos.y, transform_r.pos.y);
//                 tmp1.pos.z = add_q(world_v0.pos.z, transform_r.pos.z);
//                 world_v <= tmp1; // single write to the stage register
//                 // ======= END ORIGINAL MATH =======
//             end

//             // Stage 2 / output writeback and triangle assembly (only when not stalled)
//             if (!stall && valid_pipe[2]) begin
//                 unique case (idx_pipe2)
//                     2'd0: out_triangle.v0 <= world_v;
//                     2'd1: out_triangle.v1 <= world_v;
//                     2'd2: begin
//                         out_triangle.v2 <= world_v;

//                         out_valid_r     <= 1'b1;          // sticky valid until sink accepts
//                         vert_ctr_in     <= 2'd0;
//                         valid_pipe      <= 3'b000;        // complete this triangle atomically
//                     end
//                     default: /* no-op */ ;
//                 endcase
//             end
//         end
//     end

//     // ----------------------------------------------------------------
//     // Assertions to guard protocol and math sanity
//     // ----------------------------------------------------------------
//     // Loader only runs exactly 3 cycles
//     assert property (@(posedge clk) disable iff (rst)
//         load_vert |-> (load_vert_ctr <= 2)
//     );

//     // No new handshake while result is stalled downstream
//     assert property (@(posedge clk) disable iff (rst)
//         (out_valid_r && !out_ready) |-> !in_ready
//     );

//     // Transform remains stable during the 3-beat internal load
//     assert property (@(posedge clk) disable iff (rst)
//         (load_vert && (load_vert_ctr != 2'd0)) |-> (transform_r == $past(transform_r))
//     );

//     // world_v.z must equal world_v0.z + transform_r.pos.z (with pipeline latency)
//     assert property (@(posedge clk) disable iff (rst)
//         valid_pipe[1] |-> (world_v.pos.z == q16_16_t'($signed($past(world_v0.pos.z)) + $signed(transform_r.pos.z)))
//     );

//     // NEW: writeback indices must be 0,1,2 in order per triangle (procedural assert for Verilator)
//     logic [1:0] last_idx;
//     always_ff @(posedge clk or posedge rst) begin
//         if (rst) begin
//             last_idx <= 2'd2; // so first must be 0
//         end else if (!stall && valid_pipe[2]) begin
//             assert ( (idx_pipe2 == 2'd0 && last_idx == 2'd2) ||
//                      (idx_pipe2 == (last_idx + 2'd1)) )
//                 else $error("Writeback index out of order: got %0d after %0d", idx_pipe2, last_idx);
//             last_idx <= idx_pipe2;
//         end
//     end

// endmodule


`default_nettype none
`timescale 1ns / 1ps

import math_pkg::*;
import vertex_pkg::*;
import transformer_pkg::*;

module model_world_transformer(
    input  wire logic        clk,
    input  wire logic        rst,

    input  wire q16_16_t    focal_length,
    input  wire transform_t camera_transform,

    input  wire transform_t  transform,
    input  wire triangle_t   triangle,
    input  wire logic        in_valid,
    output      logic        in_ready,

    output      q16_16_t     out_focal_length,
    output      transform_t  out_camera_transform,
    output      triangle_t   out_triangle,
    output      logic        out_valid,
    input       logic        out_ready,

    output      logic        busy
);

        function real q2r(input q16_16_t q); q2r = $itor(q) / 65536.0; endfunction

    task automatic print_tri(input string tag, input triangle_t t);
        $display("[%s] v0=(%0f,%0f,%0f)  v1=(%0f,%0f,%0f)  v2=(%0f,%0f,%0f)  avgZ=%0f",
            tag,
            q2r(t.v0.pos.x), q2r(t.v0.pos.y), q2r(t.v0.pos.z),
            q2r(t.v1.pos.x), q2r(t.v1.pos.y), q2r(t.v1.pos.z),
            q2r(t.v2.pos.x), q2r(t.v2.pos.y), q2r(t.v2.pos.z),
            (q2r(t.v0.pos.z)+q2r(t.v1.pos.z)+q2r(t.v2.pos.z))/3.0
        );
    endtask

    assign out_valid            = in_valid;          // present data when input is valid
    assign in_ready             = out_ready;         // accept input only if downstream ready
    assign busy                 = in_valid && !out_ready; // busy when we have data but sink stalls

    // Pass-through sideband
    assign out_focal_length     = focal_length;
    assign out_camera_transform = camera_transform;

    triangle_t scaled_triangle;

    always_comb begin
        scaled_triangle = triangle;

        scaled_triangle.v0.pos.x = mul_transform(triangle.v0.pos.x, transform.scale.x);
        scaled_triangle.v0.pos.y = mul_transform(triangle.v0.pos.y, transform.scale.y);
        scaled_triangle.v0.pos.z = mul_transform(triangle.v0.pos.z, transform.scale.z);

        scaled_triangle.v1.pos.x = mul_transform(triangle.v1.pos.x, transform.scale.x);
        scaled_triangle.v1.pos.y = mul_transform(triangle.v1.pos.y, transform.scale.y);
        scaled_triangle.v1.pos.z = mul_transform(triangle.v1.pos.z, transform.scale.z);

        scaled_triangle.v2.pos.x = mul_transform(triangle.v2.pos.x, transform.scale.x);
        scaled_triangle.v2.pos.y = mul_transform(triangle.v2.pos.y, transform.scale.y);
        scaled_triangle.v2.pos.z = mul_transform(triangle.v2.pos.z, transform.scale.z);
    end

        // Compute rotation matrix R (ZYX)
    q16_16_t R11, R12, R13;
    q16_16_t R21, R22, R23;
    q16_16_t R31, R32, R33;
    always_comb begin
        // get sin/cos from transform
        q16_16_t cz = transform.rot_cos.z;
        q16_16_t sz = transform.rot_sin.z;
        q16_16_t cy = transform.rot_cos.y;
        q16_16_t sy = transform.rot_sin.y;
        q16_16_t cx = transform.rot_cos.x;
        q16_16_t sx = transform.rot_sin.x;

        R11 = mul_transform(cz, cy);
        R12 = mul_transform(mul_transform(cz, sy), sx) - mul_transform(sz, cx);
        R13 = mul_transform(mul_transform(cz, sy), cx) + mul_transform(sz, sx);
        R21 = mul_transform(sz, cy);
        R22 = mul_transform(mul_transform(sz, sy), sx) + mul_transform(cz, cx);
        R23 = mul_transform(mul_transform(sz, sy), cx) - mul_transform(cz, sx);
        R31 = -sy;
        R32 = mul_transform(cy, sx);
        R33 = mul_transform(cy, cx);
    end

    triangle_t rotated_triangle;

    always_comb begin
        rotated_triangle = scaled_triangle;
        rotated_triangle.v0.pos.x = dot3_transform(R11, R12, R13,
                                        scaled_triangle.v0.pos.x,
                                        scaled_triangle.v0.pos.y,
                                        scaled_triangle.v0.pos.z);
        rotated_triangle.v0.pos.y = dot3_transform(R21, R22, R23,
                                        scaled_triangle.v0.pos.x,
                                        scaled_triangle.v0.pos.y,
                                        scaled_triangle.v0.pos.z);
        rotated_triangle.v0.pos.z = dot3_transform(R31, R32, R33,
                                        scaled_triangle.v0.pos.x,
                                        scaled_triangle.v0.pos.y,
                                        scaled_triangle.v0.pos.z);

        rotated_triangle.v1.pos.x = dot3_transform(R11, R12, R13,
                                        scaled_triangle.v1.pos.x,
                                        scaled_triangle.v1.pos.y,
                                        scaled_triangle.v1.pos.z);
        rotated_triangle.v1.pos.y = dot3_transform(R21, R22, R23,
                                        scaled_triangle.v1.pos.x,
                                        scaled_triangle.v1.pos.y,
                                        scaled_triangle.v1.pos.z);
        rotated_triangle.v1.pos.z = dot3_transform(R31, R32, R33,
                                        scaled_triangle.v1.pos.x,
                                        scaled_triangle.v1.pos.y,
                                        scaled_triangle.v1.pos.z);

        rotated_triangle.v2.pos.x = dot3_transform(R11, R12, R13,
                                        scaled_triangle.v2.pos.x,
                                        scaled_triangle.v2.pos.y,
                                        scaled_triangle.v2.pos.z);
        rotated_triangle.v2.pos.y = dot3_transform(R21, R22, R23,
                                        scaled_triangle.v2.pos.x,
                                        scaled_triangle.v2.pos.y,
                                        scaled_triangle.v2.pos.z);
        rotated_triangle.v2.pos.z = dot3_transform(R31, R32, R33,
                                        scaled_triangle.v2.pos.x,
                                        scaled_triangle.v2.pos.y,
                                        scaled_triangle.v2.pos.z);
    end


    triangle_t translated_triangle;

    always_comb begin
        translated_triangle = rotated_triangle;

        translated_triangle.v0.pos.x = rotated_triangle.v0.pos.x + transform.pos.x;
        translated_triangle.v0.pos.y = rotated_triangle.v0.pos.y + transform.pos.y;
        translated_triangle.v0.pos.z = rotated_triangle.v0.pos.z + transform.pos.z;

        translated_triangle.v1.pos.x = rotated_triangle.v1.pos.x + transform.pos.x;
        translated_triangle.v1.pos.y = rotated_triangle.v1.pos.y + transform.pos.y;
        translated_triangle.v1.pos.z = rotated_triangle.v1.pos.z + transform.pos.z;

        translated_triangle.v2.pos.x = rotated_triangle.v2.pos.x + transform.pos.x;
        translated_triangle.v2.pos.y = rotated_triangle.v2.pos.y + transform.pos.y;
        translated_triangle.v2.pos.z = rotated_triangle.v2.pos.z + transform.pos.z;
    end
    
    always_comb begin
        if (in_valid && out_ready) begin
            print_tri("IN ", triangle);
            print_tri("SCALED ", scaled_triangle);
            print_tri("ROTATED ", rotated_triangle);
            print_tri("TRANSLATED ", translated_triangle);
        end
    end

    // Drive triangle output from scaled vertices
    assign out_triangle = translated_triangle;

endmodule
