`timescale 1ns / 1ps
`default_nettype none
import math_pkg::*;
import vertex_pkg::*;
import transformer_pkg::*;

module model_world_transformer(
    input  wire logic         clk,
    input  wire logic         rst,

    input  wire model_world_t model_world,
    input  wire logic         in_valid,
    output      logic         in_ready,

    output      world_camera_t out_world_camera,
    output      logic          out_valid,
    input  wire logic          out_ready,
    output      logic          busy
);

    typedef struct packed {
        vertex_t vertex;
        logic [1:0]  idx;
        logic    valid;
    } vertex_stage_t;

    typedef enum logic [1:0] {IDLE, PROCESS, DONE} state_t;

    state_t state;

    model_world_t model_world_in_r;
    triangle_t    triangle_r;
    logic [1:0] vertex_idx;
    logic last_vertex_done;
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            model_world_in_r <= '0;
            triangle_r       <= '0;
            state            <= IDLE;
            vertex_idx       <= 2'd0;
        end else begin
            unique case (state)
            IDLE: begin
                if (in_valid && in_ready) begin
                    model_world_in_r <= model_world;
                    triangle_r       <= '0;
                    vertex_idx       <= 2'd0;
                    state            <= PROCESS;
                end
            end
            PROCESS: begin
                if (vertex_idx != 2'd3) begin
                    vertex_idx <= vertex_idx + 2'd1;
                end
                if (last_vertex_done) begin
                    state <= DONE;
                end
            end
            DONE: begin
                if (out_ready && out_valid) begin
                    state <= IDLE;
                end
            end
            default: state <= IDLE;
            endcase
        end
    end 

    vertex_stage_t current_vertex;
    always_comb begin
        current_vertex = '0;
        if (state == PROCESS && (vertex_idx != 2'd3)) begin
            unique case (vertex_idx)
                2'd0: current_vertex.vertex = model_world_in_r.triangle.v0;
                2'd1: current_vertex.vertex = model_world_in_r.triangle.v1;
                2'd2: current_vertex.vertex = model_world_in_r.triangle.v2;
                default: current_vertex.vertex = '0;
            endcase
            current_vertex.idx   = vertex_idx;
            current_vertex.valid = 1'b1;
        end
    end
    vertex_stage_t scaled_vertex, rotated_vertex, translated_vertex;

    vertex_stage_t scaled_vertex_d, rotated_vertex_d, translated_vertex_d;
    triangle_t     triangle_r_d;
    always_comb begin
        scaled_vertex_d     = '0;
        rotated_vertex_d    = '0;
        translated_vertex_d = '0;
        triangle_r_d        = triangle_r; // hold by default

        // Scale
        if (current_vertex.valid) begin
            scaled_vertex_d.vertex.pos.x = mul_transform(current_vertex.vertex.pos.x, model_world_in_r.model.scale.x);
            scaled_vertex_d.vertex.pos.y = mul_transform(current_vertex.vertex.pos.y, model_world_in_r.model.scale.y);
            scaled_vertex_d.vertex.pos.z = mul_transform(current_vertex.vertex.pos.z, model_world_in_r.model.scale.z);
            scaled_vertex_d.vertex.color = current_vertex.vertex.color;
            scaled_vertex_d.idx          = current_vertex.idx;
            scaled_vertex_d.valid        = 1'b1;
        end

        // Rotate
        if (scaled_vertex.valid) begin
            matrix_t R = model_world_in_r.model.rot_mtx;
            rotated_vertex_d.vertex.pos.x = dot3_transform(R.R11, R.R12, R.R13,
                                                           scaled_vertex.vertex.pos.x,
                                                           scaled_vertex.vertex.pos.y,
                                                           scaled_vertex.vertex.pos.z);
            rotated_vertex_d.vertex.pos.y = dot3_transform(R.R21, R.R22, R.R23,
                                                           scaled_vertex.vertex.pos.x,
                                                           scaled_vertex.vertex.pos.y,
                                                           scaled_vertex.vertex.pos.z);
            rotated_vertex_d.vertex.pos.z = dot3_transform(R.R31, R.R32, R.R33,
                                                           scaled_vertex.vertex.pos.x,
                                                           scaled_vertex.vertex.pos.y,
                                                           scaled_vertex.vertex.pos.z);
            rotated_vertex_d.vertex.color = scaled_vertex.vertex.color;
            rotated_vertex_d.idx          = scaled_vertex.idx;
            rotated_vertex_d.valid        = 1'b1;
        end

        // Translate
        if (rotated_vertex.valid) begin
            translated_vertex_d.vertex.pos.x = rotated_vertex.vertex.pos.x + model_world_in_r.model.pos.x;
            translated_vertex_d.vertex.pos.y = rotated_vertex.vertex.pos.y + model_world_in_r.model.pos.y;
            translated_vertex_d.vertex.pos.z = rotated_vertex.vertex.pos.z + model_world_in_r.model.pos.z;
            translated_vertex_d.vertex.color = rotated_vertex.vertex.color;
            translated_vertex_d.idx          = rotated_vertex.idx;
            translated_vertex_d.valid        = 1'b1;
        end

        // Writeback to triangle accumulator (single writer)
        if (translated_vertex.valid) begin
            unique case (translated_vertex.idx)
                2'd0: triangle_r_d.v0 = translated_vertex.vertex;
                2'd1: triangle_r_d.v1 = translated_vertex.vertex;
                2'd2: triangle_r_d.v2 = translated_vertex.vertex;
                default: ;
            endcase
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            scaled_vertex     <= '0;
            rotated_vertex    <= '0;
            translated_vertex <= '0;
        end else begin
            scaled_vertex     <= scaled_vertex_d;
            rotated_vertex    <= rotated_vertex_d;
            translated_vertex <= translated_vertex_d;
            triangle_r        <= triangle_r_d;
        end
    end

    assign last_vertex_done = translated_vertex.valid && (translated_vertex.idx == 2'd2);

    assign out_world_camera = '{triangle: triangle_r, camera: model_world_in_r.camera };

    assign in_ready       = (state == IDLE);
    assign out_valid      = (state == DONE);
    assign busy           = (state != IDLE);
endmodule
