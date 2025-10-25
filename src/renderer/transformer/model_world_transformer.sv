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

    model_world_t model_world_r;
    logic [1:0] vertex_idx;
    logic last_vertex_done;
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            model_world_r <= '0;
            state         <= IDLE;
            vertex_idx    <= 2'd0;
        end else begin
            if (state == IDLE) begin
                if (in_valid && in_ready) begin
                    model_world_r <= model_world;
                    vertex_idx    <= 2'd0;
                    state         <= PROCESS;
                end
            end else if (state == PROCESS) begin
                if (vertex_idx != 2'd3) begin
                    vertex_idx <= vertex_idx + 2'd1;
                end
                if (last_vertex_done) begin
                    state <= DONE;
                end
            end else if (state == DONE) begin
                if (out_ready && out_valid) begin
                    state <= IDLE;
                end
            end
        end
    end 

    vertex_stage_t scaled_vertex, rotated_vertex, translated_vertex;
    vertex_stage_t current_vertex;
    always_comb begin
        if (state == PROCESS && (vertex_idx != 2'd3)) begin
            unique case (vertex_idx)
                2'd0: current_vertex.vertex = model_world_r.triangle.v0;
                2'd1: current_vertex.vertex = model_world_r.triangle.v1;
                2'd2: current_vertex.vertex = model_world_r.triangle.v2;
                default: current_vertex.vertex = '0;
            endcase
            current_vertex.idx   = vertex_idx;
            current_vertex.valid = 1'b1;
        end else begin
            current_vertex.vertex = '0;
            current_vertex.idx   = 2'd0;
            current_vertex.valid = 1'b0;
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            scaled_vertex     <= '0;
            rotated_vertex    <= '0;
            translated_vertex <= '0;
        end else begin
            scaled_vertex.valid     <= 1'b0;
            rotated_vertex.valid    <= 1'b0;
            translated_vertex.valid <= 1'b0;

            if (current_vertex.valid) begin
                scaled_vertex.vertex.pos.x <= mul_transform(current_vertex.vertex.pos.x, model_world_r.model.scale.x);
                scaled_vertex.vertex.pos.y <= mul_transform(current_vertex.vertex.pos.y, model_world_r.model.scale.y);
                scaled_vertex.vertex.pos.z <= mul_transform(current_vertex.vertex.pos.z, model_world_r.model.scale.z);
                scaled_vertex.vertex.color  <= current_vertex.vertex.color;
                scaled_vertex.idx          <= current_vertex.idx;
                scaled_vertex.valid        <= current_vertex.valid;
            end

            if (scaled_vertex.valid) begin
                matrix_t R = model_world_r.model.rot_mtx;
                rotated_vertex.vertex.pos.x <= dot3_transform(R.R11, R.R12, R.R13,
                                                              scaled_vertex.vertex.pos.x,
                                                              scaled_vertex.vertex.pos.y,
                                                              scaled_vertex.vertex.pos.z);
                rotated_vertex.vertex.pos.y <= dot3_transform(R.R21, R.R22, R.R23,
                                                              scaled_vertex.vertex.pos.x,
                                                              scaled_vertex.vertex.pos.y,
                                                              scaled_vertex.vertex.pos.z);
                rotated_vertex.vertex.pos.z <= dot3_transform(R.R31, R.R32, R.R33,
                                                              scaled_vertex.vertex.pos.x,
                                                              scaled_vertex.vertex.pos.y,
                                                              scaled_vertex.vertex.pos.z);
                rotated_vertex.vertex.color  <= scaled_vertex.vertex.color;
                rotated_vertex.idx          <= scaled_vertex.idx;
                rotated_vertex.valid        <= scaled_vertex.valid;
            end

            if (rotated_vertex.valid) begin
                translated_vertex.vertex.pos.x <= rotated_vertex.vertex.pos.x + model_world_r.model.pos.x;
                translated_vertex.vertex.pos.y <= rotated_vertex.vertex.pos.y + model_world_r.model.pos.y;
                translated_vertex.vertex.pos.z <= rotated_vertex.vertex.pos.z + model_world_r.model.pos.z;
                translated_vertex.vertex.color  <= rotated_vertex.vertex.color;
                translated_vertex.idx          <= rotated_vertex.idx;
                translated_vertex.valid        <= rotated_vertex.valid;
            end

            if (translated_vertex.valid) begin
                unique case (translated_vertex.idx)
                    2'd0: model_world_r.triangle.v0   <= translated_vertex.vertex;
                    2'd1: model_world_r.triangle.v1   <= translated_vertex.vertex;
                    2'd2: model_world_r.triangle.v2   <= translated_vertex.vertex;
                    default: ;
                endcase
            end
        end
    end

    assign last_vertex_done = translated_vertex.valid && (translated_vertex.idx == 2'd2);

    assign out_world_camera = '{triangle: model_world_r.triangle, camera: model_world_r.camera};

    assign in_ready       = (state == IDLE);
    assign out_valid      = (state == DONE);
    assign busy           = (state != IDLE);
endmodule
