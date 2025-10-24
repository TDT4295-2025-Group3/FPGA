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
    triangle_t out_triangle_r;
    logic [1:0] load_vert_ctr;
    logic [1:0] vert_ctr_out;    // which vertex is being written out
    logic [2:0] valid_pipe;      // shift register for pipeline stages 
    logic       load_vert;
    logic       pipe_en;
    logic       triangle_ready;
    logic       triangle_ready_d;
    logic       out_valid_r;

    assign busy = |valid_pipe || out_valid_r;  // busy if any stage is active
    assign pipe_en  = out_ready || !valid_pipe[2]; 
    assign in_ready = pipe_en;
    assign triangle_ready = valid_pipe[2] && (vert_ctr_out == 2);
    // Using a pipeline to maxemise thoughput with valid_pipe controll signal
    // Load vertex
    always_ff @(posedge clk) begin
        if (rst) begin
            vert_ctr_out  <= 0;
            load_vert_ctr <= 0;
            load_vert     <= 0;
            out_valid_r   <= 0;
            load_v        <= 0;
            temp_v        <= 0;
            cam_v         <= 0;
            out_triangle  <= 0;
            valid_pipe    <= 3'b000;
        end else begin
            triangle_ready_d <= triangle_ready;
            // Hold input 3 cycles
            if(in_valid && in_ready && load_vert_ctr == 0) begin
                load_vert_ctr <= load_vert_ctr +1;
                load_vert <= 1;
            end else if(load_vert && in_ready) begin
                if(load_vert_ctr == 2) begin
                    load_vert_ctr <= 0;
                    load_vert <= 0; 
                end else 
                    load_vert_ctr <= load_vert_ctr +1;
            end

            // shift pipline state
            if(pipe_en) begin
                valid_pipe <= {valid_pipe[1:0], (in_valid || load_vert) && in_ready};
                    
                // load next vertex when input valid, stage -1
                if ((in_valid || load_vert) && in_ready) begin
                    unique case (load_vert_ctr)
                        2'd0: load_v <= triangle.v0;
                        2'd1: load_v <= triangle.v1;
                        2'd2: load_v <= triangle.v2;
                    endcase
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
                if (valid_pipe[2]) begin
                    unique case (vert_ctr_out)
                        2'd0: out_triangle_r.v0 <= cam_v;
                        2'd1: out_triangle_r.v1 <= cam_v;
                        2'd2: out_triangle_r.v2 <= cam_v;
                    endcase
                end                
                if (vert_ctr_out == 2 && out_ready) begin
                    vert_ctr_out <= 0;
                end else if (valid_pipe[2] && vert_ctr_out < 2) begin
                    vert_ctr_out <= vert_ctr_out +1;
                end
            end 
            
            if (triangle_ready_d && !out_valid_r) begin
                out_valid_r <= 1; // triangle assembled this cycle
                out_triangle <= out_triangle_r;
            end else if (out_ready && out_valid_r) begin
                out_valid_r <= 0;
            end
        end
    end
    assign out_valid = out_valid_r;
endmodule
