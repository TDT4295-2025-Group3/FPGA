`timescale 1ns / 1ps
`default_nettype wire
import math_pkg::*;
import vertex_pkg::*;

module world_camera_transformer(
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

    // ---------------- helpers ----------------
    function automatic q16_16_t m(input q16_16_t a, input q16_16_t b);
        logic signed [63:0] t;
        begin
            t = a * b;
            m = q16_16_t'(t >>> 16);
        end
    endfunction

    function automatic q16_16_t dot3_q16(
        input q16_16_t ax, input q16_16_t ay, input q16_16_t az,
        input q16_16_t bx, input q16_16_t by, input q16_16_t bz
    );
        logic signed [63:0] p0, p1, p2;
        logic signed [95:0] acc;
        begin
            p0  = ax * bx;
            p1  = ay * by;
            p2  = az * bz;
            acc = $signed({32'sd0,p0}) + $signed({32'sd0,p1}) + $signed({32'sd0,p2});
            dot3_q16 = q16_16_t'(acc >>> 16);
        end
    endfunction

    // ---------------- rotation matrix (ZYX) ----------------
    q16_16_t cz, sz, cy, sy, cx, sx;
    assign cz = transform.rot_cos.z; assign sz = transform.rot_sin.z;
    assign cy = transform.rot_cos.y; assign sy = transform.rot_sin.y;
    assign cx = transform.rot_cos.x; assign sx = transform.rot_sin.x;

    q16_16_t R11, R12, R13, R21, R22, R23, R31, R32, R33;
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

    // ---------------- pipeline registers ----------------
    typedef struct packed {
        vertex_t v0, v1, v2;
    } triangle_stage_t;

    triangle_stage_t tri_in_reg, tri_out_reg;
    logic [1:0] vert_ctr;
    logic       have_work;

    // temp vertex pipeline stage
    vertex_t vin, vout, cam_v, temp_v;

    // ready/busy signals
    assign in_ready  = !have_work;
    assign out_valid = have_work && (vert_ctr == 2'd3);
    assign out_triangle = tri_out_reg;
    assign busy = have_work;

    // ---------------- input latch ----------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            vert_ctr    <= 2'd0;
            have_work   <= 1'b0;
            tri_in_reg  <= '0;
            tri_out_reg <= '0;
        end else begin
            // Accept new triangle
            if (in_valid && in_ready) begin
                tri_in_reg <= triangle;
                vert_ctr   <= 2'd0;
                have_work  <= 1'b1;
            end
    
            if (have_work && vert_ctr < 3) begin
                // Select vertex
                unique case (vert_ctr)
                    2'd0: vin <= tri_in_reg.v0;
                    2'd1: vin <= tri_in_reg.v1;
                    2'd2: vin <= tri_in_reg.v2;
                    default: vin = '0;
                endcase
    
                // Compute
                temp_v.pos.x <= vin.pos.x - transform.pos.x;
                temp_v.pos.y <= vin.pos.y - transform.pos.y;
                temp_v.pos.z <= vin.pos.z - transform.pos.z;
    
                cam_v.pos.x <= dot3_q16(R11, R21, R31, temp_v.pos.x, temp_v.pos.y, temp_v.pos.z);
                cam_v.pos.y <= dot3_q16(R12, R22, R32, temp_v.pos.x, temp_v.pos.y, temp_v.pos.z);
                cam_v.pos.z <= dot3_q16(R13, R23, R33, temp_v.pos.x, temp_v.pos.y, temp_v.pos.z);
    
                // Write output once
                unique case (vert_ctr)
                    2'd0: tri_out_reg.v0 <= vout;
                    2'd1: tri_out_reg.v1 <= vout;
                    2'd2: tri_out_reg.v2 <= vout;
                endcase
    
                // Advance counter
                vert_ctr <= vert_ctr + 2'd1;
            end
    
            // Done
            if (vert_ctr == 3 && out_valid && out_ready) begin
                have_work <= 1'b0;
                vert_ctr <= 2'd0;
            end
        end
    end
endmodule
