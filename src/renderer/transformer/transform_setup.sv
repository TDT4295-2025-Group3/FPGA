`default_nettype none
`timescale 1ns / 1ps

import math_pkg::*;
import vertex_pkg::*;
import transformer_pkg::*;

module transform_setup (
    input  wire logic       clk,
    input  wire logic       rst,

    input  wire transform_setup_t transform_setup,
    input  wire logic       in_valid,
    output logic            in_ready,

    output model_world_t    out_model_world,
    output logic            out_valid,
    input  wire logic       out_ready,

    output logic            busy
    );

    // FSM states
    typedef enum logic [1:0] {IDLE, WAIT, OUTPUT} state_t;
    state_t state;
    
    // Latched transaction
    transform_setup_t transform_setup_r;

    // Rotation parameters
    q16_16_t cx, sx, cy, sy, cz, sz;

    // Rotation matrix
    q16_16_t R11, R12, R13;
    q16_16_t R21, R22, R23;
    q16_16_t R31, R32, R33;

    // Choose sin/cos from right transform
    always_comb begin
        if (transform_setup_r.camera_transform_valid) begin
            sx = transform_setup_r.camera_transform.rot_sin.x; cy = transform_setup_r.camera_transform.rot_cos.y;
            cx = transform_setup_r.camera_transform.rot_cos.x; sz = transform_setup_r.camera_transform.rot_sin.z;
            sy = transform_setup_r.camera_transform.rot_sin.y; cz = transform_setup_r.camera_transform.rot_cos.z;
        end else if (transform_setup_r.model_transform_valid) begin
            sx = transform_setup_r.model_transform.rot_sin.x;  cy = transform_setup_r.model_transform.rot_cos.y;
            cx = transform_setup_r.model_transform.rot_cos.x;  sz = transform_setup_r.model_transform.rot_sin.z;
            sy = transform_setup_r.model_transform.rot_sin.y;  cz = transform_setup_r.model_transform.rot_cos.z;
        end else begin
            sx = '0; cy = '0;
            cx = '0; sz = '0;
            sy = '0; cz = '0;
        end
    end

    // Compute rotation matrix
    always_comb begin
        R11 = mul_matrix_coefficient(cz, cy);
        R12 = mul_matrix_coefficient(mul_transform(cz, sy), sx) - mul_transform(sz, cx);
        R13 = mul_matrix_coefficient(mul_matrix_coefficient(cz, sy), cx) + mul_matrix_coefficient(sz, sx);
        R21 = mul_matrix_coefficient(sz, cy);
        R22 = mul_matrix_coefficient(mul_matrix_coefficient(sz, sy), sx) + mul_matrix_coefficient(cz, cx);
        R23 = mul_matrix_coefficient(mul_matrix_coefficient(sz, sy), cx) - mul_matrix_coefficient(cz, sx);
        R31 = -sy;
        R32 = mul_matrix_coefficient(cy, sx);
        R33 = mul_matrix_coefficient(cy, cx);
    end

    assign in_ready = (state == IDLE);
    assign busy     = (state != IDLE);

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            transform_setup_r <= '0;
            out_valid <= 1'b0;
            out_model_world <= '0;
        end else begin
            case (state)
                IDLE: begin
                    out_valid <= 1'b0;
                    if (in_valid && in_ready) begin
                        // latch transaction
                        transform_setup_r <= transform_setup;
                        state <= WAIT;
                    end
                end

                WAIT: begin
                    // one-cycle compute wait
                    state <= OUTPUT;
                end

                OUTPUT: begin

                    // drive either model or camera fields depending on flags
                    if (transform_setup_r.model_transform_valid) begin
                        out_model_world.triangle    <= transform_setup_r.triangle;
                        out_model_world.model.pos   <= transform_setup_r.model_transform.pos;
                        out_model_world.model.scale <= transform_setup_r.model_transform.scale;
                        out_model_world.model.rot_mtx.R11 <= R11;
                        out_model_world.model.rot_mtx.R12 <= R12;
                        out_model_world.model.rot_mtx.R13 <= R13;
                        out_model_world.model.rot_mtx.R21 <= R21;
                        out_model_world.model.rot_mtx.R22 <= R22;
                        out_model_world.model.rot_mtx.R23 <= R23;
                        out_model_world.model.rot_mtx.R31 <= R31;
                        out_model_world.model.rot_mtx.R32 <= R32;
                        out_model_world.model.rot_mtx.R33 <= R33;

                        // === CHANGE #1: Always assert valid in OUTPUT (triangle-only allowed)
                        out_valid <= 1'b1;

                        // === CHANGE #2: Drain when sink is ready (no dependence on prior out_valid)
                        if (out_ready && out_valid) begin
                            state <= IDLE;
                            out_valid <= 1'b0;
                            transform_setup_r <= '0;
                            transform_setup_r.model_transform_valid <= 1'b0;
                        end

                    end else if (transform_setup_r.camera_transform_valid) begin
                        out_model_world.camera.pos   <= transform_setup_r.camera_transform.pos;
                        out_model_world.camera.scale <= transform_setup_r.camera_transform.scale;
                        out_model_world.camera.rot_mtx.R11 <= R11;
                        out_model_world.camera.rot_mtx.R12 <= R12;
                        out_model_world.camera.rot_mtx.R13 <= R13;
                        out_model_world.camera.rot_mtx.R21 <= R21;
                        out_model_world.camera.rot_mtx.R22 <= R22;
                        out_model_world.camera.rot_mtx.R23 <= R23;
                        out_model_world.camera.rot_mtx.R31 <= R31;
                        out_model_world.camera.rot_mtx.R32 <= R32;
                        out_model_world.camera.rot_mtx.R33 <= R33;
                        state <= IDLE;
                        transform_setup_r.camera_transform_valid <= 1'b0;
                    end
                end

                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end
endmodule
