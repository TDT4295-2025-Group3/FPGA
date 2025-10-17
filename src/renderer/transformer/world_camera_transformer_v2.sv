`timescale 1ns / 1ps
`default_nettype wire
import math_pkg::*;
import vertex_pkg::*;
import transform_pkg::*;

// p_cam = R^T * (p_world - C), scale is ignored (camera scale = 1)
module world_camera_transformer(
    input  clk,
    input  rst,
 
    input  transform_t transform,     // camera pose: pos + rot_sin/rot_cos (ZYX)
    input  triangle_t  triangle,      // world-space triangle
    input  logic       in_valid,
    output logic       ready,

    output triangle_t  out_triangle,  // camera-space triangle
    output logic       out_valid,
    input  logic       out_ready,
    output logic       busy
);

    // Q16.16 multiply with 64-bit intermediate
    function automatic q16_16_t m(input q16_16_t a, input q16_16_t b);
        logic signed [63:0] t;
        begin t = a * b; m = q16_16_t'(t >>> 16); end
    endfunction

    // Dot product row·vec, row & vec in Q16.16; accumulate wide, single >>>16
    function automatic q16_16_t dot3_q16(
        input q16_16_t ax, input q16_16_t ay, input q16_16_t az,
        input q16_16_t bx, input q16_16_t by, input q16_16_t bz
    );
        logic signed [63:0] p0, p1, p2;
        logic signed [95:0] acc;
        begin
            p0  = ax * bx; // Q32.32
            p1  = ay * by; // Q32.32
            p2  = az * bz; // Q32.32
            acc = $signed({32'sd0,p0}) + $signed({32'sd0,p1}) + $signed({32'sd0,p2});
            dot3_q16 = q16_16_t'(acc >>> 16);
        end
    endfunction

    // pipeline registers
    vertex_t load_v, temp_v, cam_v, compute_v;
    logic [1:0] vert_ctr_in;     // which vertex is currently loading
    logic [1:0] vert_ctr_out;    // which vertex is being written out
    logic [2:0] valid_pipe;      // shift register for pipeline stages  
    logic [2:0] load_vert;
    logic [1:0] load_vert_ctr;

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
        R11 = m(cz, cy);
        R12 = m(m(cz, sy), sx) - m(sz, cx);
        R13 = m(m(cz, sy), cx) + m(sz, sx);
        R21 = m(sz, cy);
        R22 = m(m(sz, sy), sx) + m(cz, cx);
        R23 = m(m(sz, sy), cx) - m(cz, sx);
        R31 = -sy;
        R32 = m(cy, sx);
        R33 = m(cy, cx);
    end

    assign busy = |valid_pipe;  // busy if any stage is active
    assign ready = (vert_ctr_in < 3) && (vert_ctr_out != 2 && out_ready) ? 1 : 0;  // ready at start of triangle

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
            if(in_valid && ready) begin
                load_vert_ctr <= load_vert_ctr +1;
                load_vert <= 1;
            end else if(load_vert)
                load_vert_ctr <= load_vert_ctr +1;
                if(load_vert_ctr == 2) begin
                    load_vert_ctr <= 0;
                    load_vert <= 0; 
                end

            // shift pipline state
            valid_pipe <= {valid_pipe[1:0], (in_valid || load_vert) && ready};
            
            // load next vertex when input valid, stage -1
            if ((in_valid || load_vert) && ready) begin
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
                temp_v.pos.x <= load_v.pos.x - transform.pos.x;
                temp_v.pos.y <= load_v.pos.y - transform.pos.y;
                temp_v.pos.z <= load_v.pos.z - transform.pos.z;
                temp_v.color <= load_v.color;
            end 

            // Rotation, stage 1
            if (valid_pipe[1]) begin
                // Translate to world coordinates, stage 1
                cam_v.pos.x <= dot3_q16(R11, R21, R31, temp_v.pos.x, temp_v.pos.y, temp_v.pos.z);
                cam_v.pos.y <= dot3_q16(R12, R22, R32, temp_v.pos.x, temp_v.pos.y, temp_v.pos.z);
                cam_v.pos.z <= dot3_q16(R13, R23, R33, temp_v.pos.x, temp_v.pos.y, temp_v.pos.z);
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
