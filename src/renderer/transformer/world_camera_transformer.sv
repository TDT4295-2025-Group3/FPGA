`timescale 1ns / 1ps
`default_nettype none
import math_pkg::*;
import vertex_pkg::*;
import transformer_pkg::*;

module world_camera_transformer(
    input  wire logic        clk,
    input  wire logic        rst,

    input  wire world_camera_t world_camera,
    input  wire logic          in_valid,
    output      logic          in_ready,

    output      triangle_t     out_triangle,
    output      logic          out_valid,
    input  wire logic          out_ready,

    output      logic          busy
);

    typedef struct packed {
        vertex_t    vertex;
        logic [1:0] idx;
        logic       valid;
    } vertex_stage_t;

    typedef enum logic [1:0] {IDLE, PROCESS, DONE} state_t;
    state_t state;

    // Latched transaction
    world_camera_t world_camera_in_r;
    triangle_t     triangle_r;

    // Vertex index being *issued* into the pipeline
    logic [1:0] vertex_idx;
    logic       last_vertex_done;

    // FSM: drive per-triangle sequencing (3 vertices)
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            world_camera_in_r <= '0;
            state             <= IDLE;
            vertex_idx        <= 2'd0;
        end else begin
            unique case (state)
                IDLE: begin
                    if (in_valid && in_ready) begin
                        world_camera_in_r <= world_camera;
                        vertex_idx        <= 2'd0;
                        state             <= PROCESS;
                    end
                end

                PROCESS: begin
                    // Issue next vertex while there are any left (0,1,2)
                    if (vertex_idx != 2'd3) begin
                        vertex_idx <= vertex_idx + 2'd1;
                    end
                    // Go DONE once last vertex has passed through the pipeline
                    if (last_vertex_done) begin
                        state <= DONE;
                    end
                end

                DONE: begin
                    // Wait for downstream to accept the triangle
                    if (out_ready && out_valid) begin
                        state <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

    // Select current vertex based on vertex_idx
    vertex_stage_t current_vertex;
    always_comb begin
        current_vertex = '0;
        if (state == PROCESS && (vertex_idx != 2'd3)) begin
            unique case (vertex_idx)
                2'd0: current_vertex.vertex = world_camera_in_r.triangle.v0;
                2'd1: current_vertex.vertex = world_camera_in_r.triangle.v1;
                2'd2: current_vertex.vertex = world_camera_in_r.triangle.v2;
                default: current_vertex.vertex = '0;
            endcase
            current_vertex.idx   = vertex_idx;
            current_vertex.valid = 1'b1;
        end
    end

    // Two-stage pipeline: translate -> rotate (R^T)
    vertex_stage_t translated_vertex, rotated_vertex;
    vertex_stage_t translated_vertex_d, rotated_vertex_d;
    triangle_t     triangle_r_d;

    always_comb begin
        translated_vertex_d = '0;
        rotated_vertex_d    = '0;
        triangle_r_d        = triangle_r; // hold by default

        // Clear accumulator on new transaction
        if (state == IDLE && in_valid && in_ready) begin
            triangle_r_d = '0;
        end

        // Stage 0: translate into camera-centered coordinates (p_world - C)
        if (current_vertex.valid) begin
            translated_vertex_d.vertex.pos.x =
                current_vertex.vertex.pos.x - world_camera_in_r.camera.pos.x;
            translated_vertex_d.vertex.pos.y =
                current_vertex.vertex.pos.y - world_camera_in_r.camera.pos.y;
            translated_vertex_d.vertex.pos.z =
                current_vertex.vertex.pos.z - world_camera_in_r.camera.pos.z;

            translated_vertex_d.vertex.color = current_vertex.vertex.color;
            translated_vertex_d.idx          = current_vertex.idx;
            translated_vertex_d.valid        = 1'b1;
        end

        // Stage 1: rotate by R^T (camera rotation inverse)
        if (translated_vertex.valid) begin
            matrix_t R = world_camera_in_r.camera.rot_mtx;

            // R^T rows are the columns of R
            rotated_vertex_d.vertex.pos.x = dot3_transform(
                R.R11, R.R21, R.R31,
                translated_vertex.vertex.pos.x,
                translated_vertex.vertex.pos.y,
                translated_vertex.vertex.pos.z
            );
            rotated_vertex_d.vertex.pos.y = dot3_transform(
                R.R12, R.R22, R.R32,
                translated_vertex.vertex.pos.x,
                translated_vertex.vertex.pos.y,
                translated_vertex.vertex.pos.z
            );
            rotated_vertex_d.vertex.pos.z = dot3_transform(
                R.R13, R.R23, R.R33,
                translated_vertex.vertex.pos.x,
                translated_vertex.vertex.pos.y,
                translated_vertex.vertex.pos.z
            );

            rotated_vertex_d.vertex.color = translated_vertex.vertex.color;
            rotated_vertex_d.idx          = translated_vertex.idx;
            rotated_vertex_d.valid        = 1'b1;
        end

        // Accumulate rotated vertices into triangle_r_d
        if (rotated_vertex.valid) begin
            unique case (rotated_vertex.idx)
                2'd0: triangle_r_d.v0 = rotated_vertex.vertex;
                2'd1: triangle_r_d.v1 = rotated_vertex.vertex;
                2'd2: triangle_r_d.v2 = rotated_vertex.vertex;
                default: ;
            endcase
        end
    end

    // Pipeline registers
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            translated_vertex <= '0;
            rotated_vertex    <= '0;
            triangle_r        <= '0;
        end else begin
            translated_vertex <= translated_vertex_d;
            rotated_vertex    <= rotated_vertex_d;
            triangle_r        <= triangle_r_d;
        end
    end

    // Last vertex has completed rotation stage
    assign last_vertex_done = rotated_vertex.valid && (rotated_vertex.idx == 2'd2);

    // Handshake + outputs
    assign out_triangle = triangle_r;
    assign in_ready     = (state == IDLE);
    assign out_valid    = (state == DONE);
    assign busy         = (state != IDLE);

endmodule