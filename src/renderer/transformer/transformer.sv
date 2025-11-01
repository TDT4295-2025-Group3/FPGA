`default_nettype none
`timescale 1ns / 1ps

import math_pkg::*;
import vertex_pkg::*;
import transformer_pkg::*;

module transformer #(
    parameter int WIDTH  = 320,
    parameter int HEIGHT = 240,
    parameter int FOCAL_LENGTH = 256
) (
    input  wire  logic             clk,
    input  wire  logic             rst,

    input  wire  transform_setup_t transform_setup,
    input  wire  logic             in_valid,
    output       logic             in_ready,

    output       triangle_t        out_triangle,
    output       logic             out_valid,
    input  wire  logic             out_ready,

    output       logic             busy
);

    model_world_t ts_out_model_world;
    logic         ts_out_valid, ts_out_ready, ts_busy;

    transform_setup u_transform_setup (
        .clk             (clk),
        .rst             (rst),

        .transform_setup (transform_setup),
        .in_valid        (in_valid),
        .in_ready        (in_ready),

        .out_model_world (ts_out_model_world),
        .out_valid       (ts_out_valid),
        .out_ready       (ts_out_ready),

        .busy            (ts_busy)
    );

    world_camera_t mw_out_world_camera;
    logic          mw_out_valid, mw_out_ready, mw_busy;

    model_world_transformer u_model_world_transformer (
        .clk             (clk),
        .rst             (rst),

        .model_world     (ts_out_model_world),
        .in_valid        (ts_out_valid),
        .in_ready        (ts_out_ready),

        .out_world_camera(mw_out_world_camera),
        .out_valid       (mw_out_valid),
        .out_ready       (mw_out_ready),

        .busy            (mw_busy)
    );

    triangle_t  tp_out_triangle;
    logic       tp_out_valid, tp_out_ready, tp_busy;
    triangle_projector #(
        .FOCAL_LENGTH(FOCAL_LENGTH)
    ) u_triangle_projector (
        .clk          (clk),
        .rst          (rst),

        .triangle     (mw_out_world_camera.triangle),
        .in_valid     (mw_out_valid),
        .in_ready     (mw_out_ready),


        .out_triangle (tp_out_triangle),
        .out_valid    (tp_out_valid),
        .out_ready    (tp_out_ready),
        .busy         (tp_busy)
    );

    triangle_t sn_out_triangle;
    logic      sn_out_valid, sn_out_ready, sn_busy;

    screen_normalizer #(
        .WIDTH  (WIDTH),
        .HEIGHT (HEIGHT)
    ) u_screen_normalizer (
        .clk         (clk),
        .rst         (rst),

        .triangle    (tp_out_triangle),
        .in_valid    (tp_out_valid),
        .in_ready    (tp_out_ready),

        .out_triangle(sn_out_triangle),
        .out_valid   (sn_out_valid),
        .out_ready   (sn_out_ready),

        .busy        (sn_busy)
    );

    function real q2r(input q16_16_t q); q2r = $itor(q) / 65536.0; endfunction

    task automatic print_tri(input string tag, input triangle_t t);
        $display("[%s] v0=(%0f,%0f,%0f)  v1=(%0f,%0f,%0f)  v2=(%0f,%0f,%0f)",
            tag,
            q2r(t.v0.pos.x), q2r(t.v0.pos.y), q2r(t.v0.pos.z),
            q2r(t.v1.pos.x), q2r(t.v1.pos.y), q2r(t.v1.pos.z),
            q2r(t.v2.pos.x), q2r(t.v2.pos.y), q2r(t.v2.pos.z)
        );
    endtask

    task automatic print_mtx(input string tag, input matrix_t m);
        $display("[%s] R = [%0f %0f %0f; %0f %0f %0f; %0f %0f %0f]",
            tag,
            q2r(m.R11), q2r(m.R12), q2r(m.R13),
            q2r(m.R21), q2r(m.R22), q2r(m.R23),
            q2r(m.R31), q2r(m.R32), q2r(m.R33)
        );
    endtask

    task automatic print_mtx_tr(input string tag, input matrix_transform_t mt);
        $display("[%s] pos=(%0f,%0f,%0f)  scale=(%0f,%0f,%0f)",
            tag,
            q2r(mt.pos.x), q2r(mt.pos.y), q2r(mt.pos.z),
            q2r(mt.scale.x), q2r(mt.scale.y), q2r(mt.scale.z)
        );
        print_mtx({tag, " rot_mtx"}, mt.rot_mtx);
    endtask

    task automatic print_model_world(input string tag, input model_world_t mw);
        print_tri({tag, " TRIANGLE"}, mw.triangle);
        print_mtx_tr({tag, " MODEL"}, mw.model);
        print_mtx_tr({tag, " CAMERA"}, mw.camera);
    endtask


    // always_ff @(posedge clk) begin        
    //     if (in_valid && in_ready) begin
    //         print_tri("TRANSFORM_SETUP", transform_setup.triangle);
    //     end
        
    //     if (ts_out_valid && ts_out_ready) begin
    //         print_model_world("MODEL_WORLD", ts_out_model_world);
    //     end
    //     if (mw_out_valid && mw_out_ready) begin
    //         print_tri("WORLD_CAMERA", mw_out_world_camera.triangle);
    //     end
    //     if (sn_out_valid && sn_out_ready) begin
    //         print_tri("TRANSFORMED", sn_out_triangle);
    //     end
    // end

    assign out_triangle = sn_out_triangle;
    assign out_valid    = sn_out_valid;
    assign sn_out_ready = out_ready;

    assign busy = ts_busy | mw_busy | tp_busy | sn_busy;

endmodule
