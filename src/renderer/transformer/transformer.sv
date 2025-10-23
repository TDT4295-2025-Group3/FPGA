// `default_nettype none
// `timescale 1ns / 1ps

// import math_pkg::*;
// import vertex_pkg::*;
// import transformer_pkg::*;

// module transformer (
//     input  wire logic       clk,
//     input  wire logic       rst,

//     input  wire q16_16_t    focal_length,
//     input  wire transform_t camera_transform,
    
//     input  wire transform_t transform,
//     input  wire triangle_t  triangle,
//     input  wire logic       in_valid,
//     output       logic       in_ready,

//     output triangle_t  out_triangle,
//     output logic       out_valid,
//     input  wire logic  out_ready,

//     output logic       busy
// );

//     // Stage 1: model -> world
//     triangle_t mw_out_triangle;
//     logic      mw_out_valid, mw_out_ready, mw_busy;

//     // pass-through sideband from stage 1
//     q16_16_t    mw_out_focal_length;
//     transform_t mw_out_camera_transform;

//     model_world_transformer mw_inst (
//         .clk               (clk),
//         .rst               (rst),

//         // new pass-through inputs
//         .focal_length      (focal_length),
//         .camera_transform  (camera_transform),

//         .transform         (transform),
//         .triangle          (triangle),

//         .in_valid          (in_valid),
//         .in_ready          (in_ready),

//         // new pass-through outputs
//         .out_focal_length  (mw_out_focal_length),
//         .out_camera_transform(mw_out_camera_transform),

//         .out_triangle      (mw_out_triangle),
//         .out_valid         (mw_out_valid),
//         .out_ready         (mw_out_ready),

//         .busy              (mw_busy)
//     );

//     // Stage 2: world -> camera
//     triangle_t wc_out_triangle;
//     logic      wc_out_valid, wc_out_ready, wc_busy;

//     // pass-through sideband from stage 2
//     q16_16_t   wc_out_focal_length;

//     world_camera_transformer wc_inst (
//         .clk               (clk),
//         .rst               (rst),

//         // pass-through in
//         .focal_length      (mw_out_focal_length),
//         .camera_transform  (mw_out_camera_transform),

//         .triangle          (mw_out_triangle),
//         .in_valid          (mw_out_valid),
//         .in_ready          (mw_out_ready),

//         // pass-through out
//         .out_focal_length  (wc_out_focal_length),

//         .out_triangle      (wc_out_triangle),
//         .out_valid         (wc_out_valid),
//         .out_ready         (wc_out_ready),
//         .busy              (wc_busy)
//     );

//     // Stage 3: camera -> projected (perspective)
//     logic proj_busy;

//     triangle_projector proj_inst (
//         .clk          (clk),
//         .rst          (rst),

//         .triangle     (wc_out_triangle),
//         .in_valid     (wc_out_valid),
//         .in_ready     (wc_out_ready),

//         // use focal length passed through stage 2
//         .focal_length (wc_out_focal_length),

//         .out_triangle (out_triangle),
//         .out_valid    (out_valid),
//         .out_ready    (out_ready),

//         .busy         (proj_busy)
//     );

//     assign busy = mw_busy || wc_busy || proj_busy;

//     // --------------------------
//     // Unconditional debug helpers
//     // --------------------------
//     function real q2r(input q16_16_t q); q2r = $itor(q) / 65536.0; endfunction

//     task automatic print_tri(input string tag, input triangle_t t);
//         $display("[%s] v0=(%0f,%0f,%0f)  v1=(%0f,%0f,%0f)  v2=(%0f,%0f,%0f)  avgZ=%0f",
//             tag,
//             q2r(t.v0.pos.x), q2r(t.v0.pos.y), q2r(t.v0.pos.z),
//             q2r(t.v1.pos.x), q2r(t.v1.pos.y), q2r(t.v1.pos.z),
//             q2r(t.v2.pos.x), q2r(t.v2.pos.y), q2r(t.v2.pos.z),
//             (q2r(t.v0.pos.z)+q2r(t.v1.pos.z)+q2r(t.v2.pos.z))/3.0
//         );
//     endtask

//     // ----------------------------------------------------------------
//     // Handoffs: print exactly when each stage is ACCEPTED downstream
//     // ----------------------------------------------------------------
//     // MW -> WC
//     always_ff @(posedge clk) begin
//         if (mw_out_valid && mw_out_ready) begin
//             $display("T=%0t ns  --- MODEL→WORLD accepted ---", $time);
//             print_tri("MW", mw_out_triangle);
//             $display("       FOCAL @MW handoff: in=%0f  mw_out=%0f",
//                 q2r(focal_length), q2r(mw_out_focal_length));
//             $display("       transform.pos=(%0f,%0f,%0f)  scale=(%0f,%0f,%0f)",
//                 q2r(transform.pos.x), q2r(transform.pos.y), q2r(transform.pos.z),
//                 q2r(transform.scale.x), q2r(transform.scale.y), q2r(transform.scale.z));
//         end
//     end

//     // WC -> PROJ
//     always_ff @(posedge clk) begin
//         if (wc_out_valid && wc_out_ready) begin
//             $display("T=%0t ns  --- WORLD→CAMERA accepted ---", $time);
//             print_tri("WC", wc_out_triangle);
//             $display("       FOCAL @WC handoff: in=%0f  wc_out=%0f",
//                 q2r(mw_out_focal_length), q2r(wc_out_focal_length));
//             $display("       camera.pos=(%0f,%0f,%0f)",
//                 q2r(mw_out_camera_transform.pos.x),
//                 q2r(mw_out_camera_transform.pos.y),
//                 q2r(mw_out_camera_transform.pos.z));
//         end
//     end

//     // PROJ -> downstream
//     always_ff @(posedge clk) begin
//         if (out_valid && out_ready) begin
//             $display("T=%0t ns  --- PROJECTED accepted ---", $time);
//             print_tri("PRJ", out_triangle);
//         end
//     end

//     // ----------------------------------------------------------------
//     // Stall diagnostics: print if a condition persists (low noise)
//     // ----------------------------------------------------------------
//     logic [15:0] st_inhold, st_mwhold, st_wchold, st_projhold;

//     always_ff @(posedge clk or posedge rst) begin
//         if (rst) begin
//             st_inhold   <= '0;
//             st_mwhold   <= '0;
//             st_wchold   <= '0;
//             st_projhold <= '0;
//         end else begin
//             // upstream has work; transformer can't accept
//             if (in_valid && !in_ready) begin
//                 st_inhold <= st_inhold + 16'd1;
//                 if (&st_inhold) begin
//                     $display("T=%0t ns  [STALL] upstream in_valid=1, in_ready=0 (transformer input back-pressured)", $time);
//                     st_inhold <= '0;
//                 end
//             end else st_inhold <= '0;

//             // MW produced a triangle; WC not ready
//             if (mw_out_valid && !mw_out_ready) begin
//                 st_mwhold <= st_mwhold + 16'd1;
//                 if (&st_mwhold) begin
//                     $display("T=%0t ns  [STALL] MW→WC: mw_out_valid=1, mw_out_ready=0 (WC back-pressured)", $time);
//                     $display("             MW focal_out=%0f  cam.pos=(%0f,%0f,%0f)",
//                         q2r(mw_out_focal_length),
//                         q2r(mw_out_camera_transform.pos.x),
//                         q2r(mw_out_camera_transform.pos.y),
//                         q2r(mw_out_camera_transform.pos.z));
//                     st_mwhold <= '0;
//                 end
//             end else st_mwhold <= '0;

//             // WC produced a triangle; PROJ not ready
//             if (wc_out_valid && !wc_out_ready) begin
//                 st_wchold <= st_wchold + 16'd1;
//                 if (&st_wchold) begin
//                     $display("T=%0t ns  [STALL] WC→PROJ: wc_out_valid=1, wc_out_ready=0 (Projector back-pressured)", $time);
//                     $display("             WC focal_out=%0f", q2r(wc_out_focal_length));
//                     st_wchold <= '0;
//                 end
//             end else st_wchold <= '0;

//             // PROJ produced a triangle; downstream not ready
//             if (out_valid && !out_ready) begin
//                 st_projhold <= st_projhold + 16'd1;
//                 if (&st_projhold) begin
//                     $display("T=%0t ns  [STALL] PROJ→downstream: out_valid=1, out_ready=0 (sink back-pressured)", $time);
//                     st_projhold <= '0;
//                 end
//             end else st_projhold <= '0;
//         end
//     end

// endmodule

`default_nettype none
`timescale 1ns / 1ps

import math_pkg::*;
import vertex_pkg::*;
import transformer_pkg::*;

module transformer (
    input  wire logic       clk,
    input  wire logic       rst,

    input  wire q16_16_t    focal_length,
    input  wire transform_t camera_transform,

    input  wire transform_t transform,
    input  wire triangle_t  triangle,
    input  wire logic       in_valid,
    output       logic      in_ready,

    output triangle_t       out_triangle,
    output logic            out_valid,
    input  wire logic       out_ready,

    output logic            busy
);

    // --------------------------
    // Stage 1: model -> world
    // --------------------------
    triangle_t mw_out_triangle;
    logic      mw_out_valid, mw_out_ready, mw_busy;

    // pass-through sideband (still produced by MW)
    q16_16_t    mw_out_focal_length;
    transform_t mw_out_camera_transform;

    model_world_transformer mw_inst (
        .clk                  (clk),
        .rst                  (rst),

        // pass-through inputs
        .focal_length         (focal_length),
        .camera_transform     (camera_transform),

        .transform            (transform),
        .triangle             (triangle),

        .in_valid             (in_valid),
        .in_ready             (in_ready),

        // pass-through outputs (unused by this top, but handy to observe)
        .out_focal_length     (mw_out_focal_length),
        .out_camera_transform (mw_out_camera_transform),

        .out_triangle         (mw_out_triangle),
        .out_valid            (mw_out_valid),
        .out_ready            (mw_out_ready),

        .busy                 (mw_busy)
    );

    // --------------------------
    // Bypass WC/PROJ completely
    // --------------------------
    assign out_triangle = mw_out_triangle;
    assign out_valid    = mw_out_valid;
    assign mw_out_ready = out_ready;

    assign busy = mw_busy;

    // --------------------------
    // Unconditional debug helpers
    // --------------------------
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

    // // ----------------------------------------------------------------
    // // Handoffs: print exactly when MW result is accepted downstream
    // // ----------------------------------------------------------------
    // // MW -> downstream (since we bypass)
    // always_ff @(posedge clk) begin
    //     if (mw_out_valid && mw_out_ready) begin
    //         $display("T=%0t ns  --- MODEL→WORLD accepted ---", $time);
    //         print_tri("MW", mw_out_triangle);
    //         $display("       FOCAL @MW handoff: in=%0f  mw_out=%0f",
    //             q2r(focal_length), q2r(mw_out_focal_length));
    //         $display("       transform.pos=(%0f,%0f,%0f)  scale=(%0f,%0f,%0f)",
    //             q2r(transform.pos.x), q2r(transform.pos.y), q2r(transform.pos.z),
    //             q2r(transform.scale.x), q2r(transform.scale.y), q2r(transform.scale.z));
    //         $display("       camera.pos(pass-through)=(%0f,%0f,%0f)",
    //             q2r(mw_out_camera_transform.pos.x),
    //             q2r(mw_out_camera_transform.pos.y),
    //             q2r(mw_out_camera_transform.pos.z));
    //     end
    // end

    // // Downstream accept (same as above condition, but mirrors original structure)
    // always_ff @(posedge clk) begin
    //     if (out_valid && out_ready) begin
    //         $display("T=%0t ns  --- DOWNSTREAM accepted (MW output) ---", $time);
    //         print_tri("OUT", out_triangle);
    //     end
    // end

    // // ----------------------------------------------------------------
    // // Stall diagnostics (reduced to input and output only)
    // // ----------------------------------------------------------------
    // logic [15:0] st_inhold, st_out_hold;

    // always_ff @(posedge clk or posedge rst) begin
    //     if (rst) begin
    //         st_inhold   <= '0;
    //         st_out_hold <= '0;
    //     end else begin
    //         // upstream has work; MW can't accept
    //         if (in_valid && !in_ready) begin
    //             st_inhold <= st_inhold + 16'd1;
    //             if (&st_inhold) begin
    //                 $display("T=%0t ns  [STALL] upstream in_valid=1, in_ready=0 (MW back-pressured)", $time);
    //                 st_inhold <= '0;
    //             end
    //         end else st_inhold <= '0;

    //         // MW produced a triangle; downstream not ready
    //         if (out_valid && !out_ready) begin
    //             st_out_hold <= st_out_hold + 16'd1;
    //             if (&st_out_hold) begin
    //                 $display("T=%0t ns  [STALL] MW→downstream: out_valid=1, out_ready=0 (sink back-pressured)", $time);
    //                 $display("             MW focal_out=%0f  cam.pos=(%0f,%0f,%0f)",
    //                     q2r(mw_out_focal_length),
    //                     q2r(mw_out_camera_transform.pos.x),
    //                     q2r(mw_out_camera_transform.pos.y),
    //                     q2r(mw_out_camera_transform.pos.z));
    //                 st_out_hold <= '0;
    //             end
    //         end else st_out_hold <= '0;
    //     end
    // end

endmodule