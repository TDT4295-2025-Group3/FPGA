`timescale 1ns / 1ps
`default_nettype none

import math_pkg::*;
import vertex_pkg::*;

module model_world_transformer(
    input  logic        clk,
    input  logic        rst,

    input  transform_t  transform,
    input  triangle_t   triangle,
    input  logic        in_valid,
    output logic        in_ready,

    output triangle_t   out_triangle,
    output logic        out_valid,
    input  logic        out_ready,
    output logic        busy
);

    // -------------------------------------
    // Internal pipeline registers
    // -------------------------------------
    vertex_t load_v, compute_v, world_v;
    vertex_t rot_v;
    logic [1:0] vert_ctr_in;     // which vertex is currently loading
    logic [1:0] vert_ctr_out;    // which vertex is being written out
    logic [2:0] valid_pipe;      // shift register for valid bits (LOAD→COMPUTE→OUTPUT)
    logic [2:0] load_vert;
    logic [1:0] vert_ready_ctr;

    // Rotation parameters
    q16_16_t cos_x, sin_x, cos_y, sin_y, cos_z, sin_z;
    assign sin_x = transform.rot_sin.x;
    assign cos_x = transform.rot_cos.x;
    assign sin_y = transform.rot_sin.y;
    assign cos_y = transform.rot_cos.y;
    assign sin_z = transform.rot_sin.z;
    assign cos_z = transform.rot_cos.z;

    assign busy = |valid_pipe;  // busy if any stage is active
    assign vert_ready[0] = in_ready;
    assign in_ready = (vert_ctr_in < 3) && (valid_pipe != 3'b111 ) ? 1 : 0;  // ready at start of triangle


    // Pipeline stage 0: LOAD vertex
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            vert_ctr_in  <= 0;
            valid_pipe   <= 3'b000;
        end else begin
            // Hold input 3 cycles
            if(in_valid && in_ready) begin
                load_vert_ctr <= load_vert_ctr +1;
                load_vert <= 1;
            end else if(load_vert)
                load_vert_ctr <= load_vert_ctr +1;
                if(load_vert_ctr == 2) begin
                    load_vert_ctr <= 0;
                    load_vert <= 0; 
                end

            // shift pipline state
            valid_pipe <= {valid_pipe[1:0], (in_valid || load_vert) && in_ready}; 

            // load next vertex when input valid
            if ((in_valid || load_vert) && in_ready) begin
                unique case (vert_ctr_in)
                    2'd0: load_v <= triangle.v0;
                    2'd1: load_v <= triangle.v1;
                    2'd2: load_v <= triangle.v2;
                endcase
                vert_ctr_in <= vert_ctr_in + 1;
            end

            if (vert_ctr_out == 2) begin
                vert_ctr_in   <= 0;
                valid_pipe[0] <= 0;
            end
        end
    end

    // Pipeline stage 1: rotation + translation
    always_ff @(posedge clk) begin
        if (valid_pipe[1]) begin
            rot_v.x <= (cos_z*cos_y)*load_v.x
                     + (cos_z*sin_y*sin_x - sin_z*cos_x)*load_v.y
                     + (cos_z*sin_y*cos_x + sin_z*sin_x)*load_v.z;

            rot_v.y <= (sin_z*cos_y)*load_v.x
                     + (sin_z*sin_y*sin_x + cos_z*cos_x)*load_v.y
                     + (sin_z*sin_y*cos_x - cos_z*sin_x)*load_v.z;

            rot_v.z <= (-sin_y)*load_v.x
                     + (cos_y*sin_x)*load_v.y
                     + (cos_y*cos_x)*load_v.z;

            // Translate to world coordinates
            world_v.x <= rot_v.x + transform.pos.x;
            world_v.y <= rot_v.y + transform.pos.y;
            world_v.z <= rot_v.z + transform.pos.z;
        end
    end

    // Pipeline stage 2: OUTPUT
    always_ff @(posedge clk or posedge rst) begin
        out_valid <= 0; 
        if (valid_pipe[2]) begin
            unique case (vert_ctr_out)
                2'd0: out_triangle.v0 <= world_v;
                2'd1: out_triangle.v1 <= world_v;
                2'd2: out_triangle.v2 <= world_v;
            endcase
        end

        if (vert_ctr_out == 2 && out_ready) begin
            out_valid <= 1;
            vert_ctr_out <= 0;
        end else if (valid_pipe[2] && vert_ctr_out < 2) begin
            vert_ctr_out <= vert_ctr_out +1;
        end
    end

endmodule
