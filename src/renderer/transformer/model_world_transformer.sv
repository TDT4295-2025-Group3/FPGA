`timescale 1ns / 1ps
`default_nettype wire
import math_pkg::*;
import vertex_pkg::*;
import transform_pkg::*;

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
    vertex_t load_v, compute_v, world_v;
    vertex_t rot_v;
    logic [1:0] vert_ctr_in;     // which vertex is currently loading
    logic [1:0] vert_ctr_out;    // which vertex is being written out
    logic [2:0] valid_pipe;      // shift register for pipeline stages  
    logic [2:0] load_vert;
    logic [1:0] load_vert_ctr;

    // Rotation parameters
    q16_16_t cx, sx, cy, sy, cz, sz;
    assign sx = transform.sin_rot.x;    assign cy = transform.cos_rot.y;
    assign cx = transform.cos_rot.x;    assign sz = transform.sin_rot.z;
    assign sy = transform.sin_rot.y;    assign cz = transform.cos_rot.z;

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
    assign in_ready = (vert_ctr_in < 3) && (valid_pipe != 3'b111 ) ? 1 : 0;  // ready at start of triangle

    // Using a pipeline to maxemise thoughput with valid_pipe controll signal
    // Load vertex
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            vert_ctr_in   <= 0;
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

    // Rotation + translation
    always_ff @(posedge clk) begin
        if (valid_pipe[1] && !rst) begin
            // use dot product for rotation
            rot_v.pos.x <= dot3_q16(R11, R12, R13, x, y, z);
            rot_v.pos.y <= dot3_q16(R21, R22, R23, x, y, z);
            rot_v.pos.z <= dot3_q16(R31, R32, R33, x, y, z);
            rot_v.color <= load_v.color;

            // Translate to world coordinates
            world_v.pos.x <= m(rot_v.pos.x * transform.scale.x) + transform.pos.x;
            world_v.pos.y <= m(rot_v.pos.y * transform.scale.y) + transform.pos.y;
            world_v.pos.z <= m(rot_v.pos.z * transform.scale.z) + transform.pos.z;
            world_v.color   <= rot_v.color;
        end
    end

    // output
    always_ff @(posedge clk) begin
        if(!rst) begin
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
    end

endmodule
