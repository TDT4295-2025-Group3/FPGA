`timescale 1ns / 1ps
`default_nettype wire
import math_pkg::*;
import vertex_pkg::*;
import transformer_pkg::*;

module model_world_transformer(
    input  logic        clk,
    input  logic        rst,
    input  logic        camera_transform_valid,

    input  transform_t  transform,
    input  triangle_t   triangle,
    input  logic        in_valid,
    output logic        in_ready,

    output triangle_t   out_triangle,
    output logic        out_valid,
    input  logic        out_ready,
    output logic        busy,
    
    output q16_16_t out_R11, out_R12, out_R13,
    output q16_16_t out_R21, out_R22, out_R23,
    output q16_16_t out_R31, out_R32, out_R33,
    
    output q16_16_t cam_x, cam_y, cam_z
);

    // pipeline registers
    vertex_t load_v, rot_v, world_v;
    triangle_t out_triangle_r;
    logic [1:0] load_vert_ctr;
    logic [1:0] vert_ctr_out;    // which vertex is being written out
    logic [2:0] valid_pipe;      // shift register for pipeline stages  
    logic       load_vert;
    logic       pipe_en;
    logic       triangle_ready;
    logic       triangle_ready_d;
    logic       out_valid_r;

    // Rotation parameters
    q16_16_t cx, sx, cy, sy, cz, sz;
    assign sx = transform.rot_sin.x;    assign cy = transform.rot_cos.y;
    assign cx = transform.rot_cos.x;    assign sz = transform.rot_sin.z;
    assign sy = transform.rot_sin.y;    assign cz = transform.rot_cos.z;

    // Compute rotation matrix R (ZYX)
    q16_16_t R11, R12, R13;
    q16_16_t R21, R22, R23;
    q16_16_t R31, R32, R33;
    always_comb begin
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

    assign busy = |valid_pipe || out_valid_r;  // busy if any stage is active
    assign pipe_en  = out_ready || !valid_pipe[2]; 
    assign in_ready = pipe_en && !camera_transform_valid ? 1 : 0;
    assign triangle_ready = valid_pipe[2] && (vert_ctr_out == 2);
    
    // Using a pipeline to maxemise thoughput with valid_pipe controll signal
    // Load vertex
    always_ff @(posedge clk) begin
        if (rst) begin
            vert_ctr_out  <= 0;
            load_vert_ctr <= 0;
            load_vert     <= 0;
            load_v        <= 0;
            out_valid_r   <= 0;
            rot_v         <= 0;
            world_v       <= 0;
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
            
            if(load_vert && in_ready) begin
                if(load_vert_ctr == 2) begin
                    load_vert_ctr <= 0;
                    load_vert <= 0;
                end else begin
                    load_vert_ctr <= load_vert_ctr + 1;
                end
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
                        default: load_v <= triangle.v0;
                    endcase
                end
            
                // Rotation, use dot product for rotation, stage 0
                if (valid_pipe[0]) begin
                    rot_v.pos.x <= dot3_transform(R11, R12, R13, load_v.pos.x, load_v.pos.y, load_v.pos.z);
                    rot_v.pos.y <= dot3_transform(R21, R22, R23, load_v.pos.x, load_v.pos.y, load_v.pos.z);
                    rot_v.pos.z <= dot3_transform(R31, R32, R33, load_v.pos.x, load_v.pos.y, load_v.pos.z);
                    rot_v.color <= load_v.color;
                end 
                
                // Translation, stage 1
                if (valid_pipe[1]) begin
                    // Translate to world coordinates, stage 1
                    world_v.pos.x <= mul_transform(rot_v.pos.x, transform.scale.x) + transform.pos.x;
                    world_v.pos.y <= mul_transform(rot_v.pos.y, transform.scale.y) + transform.pos.y;
                    world_v.pos.z <= mul_transform(rot_v.pos.z, transform.scale.z) + transform.pos.z;
                    world_v.color   <= rot_v.color;
                end

                // load output triangle, stage 2
                if (valid_pipe[2]) begin
                    unique case (vert_ctr_out)
                        2'd0: out_triangle_r.v0 <= world_v;
                        2'd1: out_triangle_r.v1 <= world_v;
                        2'd2: out_triangle_r.v2 <= world_v;
                        default: out_triangle_r.v0 <= world_v;
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

    // latch matrix values for camera transform to save DSPs
    always_ff @(posedge clk) begin
        if (rst) begin
            out_R11 <= 0;
            out_R12 <= 0;
            out_R13 <= 0;
            out_R21 <= 0;
            out_R22 <= 0;
            out_R23 <= 0;
            out_R31 <= 0;
            out_R32 <= 0;
            out_R33 <= 0;
            cam_x <= 0;
            cam_y <= 0;
            cam_z <= 0;
        end else if(camera_transform_valid) begin
            out_R11 <= R11;
            out_R12 <= R12;
            out_R13 <= R13;
            out_R21 <= R21;
            out_R22 <= R22;
            out_R23 <= R23;
            out_R31 <= R31;
            out_R32 <= R32;
            out_R33 <= R33;
            cam_x <= transform.pos.x;
            cam_y <= transform.pos.y;
            cam_z <= transform.pos.z;
        end
    end

    assign out_valid = out_valid_r;

endmodule
