`timescale 1ns / 1ps
`default_nettype wire
import math_pkg::*;
import vertex_pkg::*;
import transformer_pkg::*;

// p_cam = R^T * (p_world - C), scale is ignored (camera scale = 1)
module world_camera_transformer(
    input  clk,
    input  rst,
 
    input  triangle_t  triangle,      // world-space triangle
    input  logic       in_valid,
    output logic       in_ready,

    output triangle_t  out_triangle,  // camera-space triangle
    output logic       out_valid,
    input  logic       out_ready,
    output logic       busy,
    
    // import Rotation matrix from model to world transformer
    input  q16_16_t R11, R12, R13,
    input  q16_16_t R21, R22, R23,
    input  q16_16_t R31, R32, R33,
    
    input q16_16_t cam_x, cam_y, cam_z
);
    // pipeline registers
    vertex_t load_v, temp_v, cam_v, compute_v;
    logic [1:0] vert_ctr_in;     // which vertex is currently loading
    logic [1:0] vert_ctr_out;    // which vertex is being written out
    logic [2:0] valid_pipe;      // shift register for pipeline stages  
    logic [2:0] load_vert;
    logic [1:0] load_vert_ctr;

    assign busy = |valid_pipe;  // busy if any stage is active
    assign in_ready = (vert_ctr_in < 3) && (vert_ctr_out != 2 && out_ready) ? 1 : 0;  // ready at start of triangle

    // Using a pipeline to maxemise thoughput with valid_pipe controll signal
    // Load vertex
    always_ff @(posedge clk) begin
        if (rst) begin
            vert_ctr_in   <= 0;
            vert_ctr_out  <= 0;
            load_vert_ctr <= 0;
            load_vert     <= 0;
            load_v        <= 0;
            valid_pipe    <= 3'b000;
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
            
            // load next vertex when input valid, stage -1
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
        
            // Translation, stage 0
            if (valid_pipe[0]) begin
                temp_v.pos.x <= load_v.pos.x - cam_x;
                temp_v.pos.y <= load_v.pos.y - cam_y;
                temp_v.pos.z <= load_v.pos.z - cam_z;
                temp_v.color <= load_v.color;
            end 

            // Rotation, stage 1
            if (valid_pipe[1]) begin
                // Translate to world coordinates, stage 1
                cam_v.pos.x <= dot3_transform(R11, R21, R31, temp_v.pos.x, temp_v.pos.y, temp_v.pos.z);
                cam_v.pos.y <= dot3_transform(R12, R22, R32, temp_v.pos.x, temp_v.pos.y, temp_v.pos.z);
                cam_v.pos.z <= dot3_transform(R13, R23, R33, temp_v.pos.x, temp_v.pos.y, temp_v.pos.z);
                cam_v.color   <= temp_v.color;
            end

            // Output, stage 2
            out_valid <= 0; 
            if (valid_pipe[2]) begin
                unique case (vert_ctr_out)
                    2'd0: out_triangle.v0 <= cam_v;
                    2'd1: out_triangle.v1 <= cam_v;
                    2'd2: out_triangle.v2 <= cam_v;
                endcase
            end

            if (vert_ctr_out == 2 && out_ready) begin
                out_valid <= 1;
                vert_ctr_out <= 0;
            end else if (valid_pipe[2] && vert_ctr_out < 2) begin
                vert_ctr_out <= vert_ctr_out +1;
            end
        end
    end
endmodule
