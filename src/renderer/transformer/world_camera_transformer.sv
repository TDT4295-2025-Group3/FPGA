`timescale 1ns / 1ps
import math_pkg::*;
import vertex_pkg::*;
`default_nettype wire

// p_cam = R^T * (p_world - C), scale is ignored (camera scale = 1)
module world_camera_transformer(
    input  clk,
    input  rst,
 
    input  transform_t transform,     // camera pose: pos + rot_sin/rot_cos (ZYX)
    input  triangle_t  triangle,      // world-space triangle
    input  logic       in_valid,
    output logic       in_ready,

    output triangle_t  out_triangle,  // camera-space triangle
    output logic       out_valid,
    input  logic       out_ready,
    output logic       busy
);
    // ------------ helpers (Q16.16 safe) ------------
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

    // ------------ camera rotation coeffs (ZYX), then use R^T ------------
    q16_16_t cz, sz, cy, sy, cx, sx;
    assign cz = transform.rot_cos.z;  assign sz = transform.rot_sin.z;
    assign cy = transform.rot_cos.y;  assign sy = transform.rot_sin.y;
    assign cx = transform.rot_cos.x;  assign sx = transform.rot_sin.x;

    // R for ZYX
    q16_16_t R11, R12, R13, R21, R22, R23, R31, R32, R33;
    always @* begin
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

    // We use R^T rows = columns of R:
    // RT0 = (R11, R21, R31)
    // RT1 = (R12, R22, R32)
    // RT2 = (R13, R23, R33)

    // ------------ handshake & storage ------------
    triangle_t tri_in_reg, tri_out_reg;
    logic [1:0] vert_ctr;
    logic       have_work;
    
    q16_16_t dx, cam_x;
    q16_16_t dy, cam_y;
    q16_16_t dz, cam_z;

    assign in_ready  = !have_work;            // accept when idle
    assign out_valid = have_work && (vert_ctr == 2'd3);  // valid after 3 vertices processed
    assign out_triangle = tri_out_reg;
    assign busy = have_work;

    // Latch input triangle when accepted
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            have_work   <= 1'b0;
            tri_in_reg  <= '0;
            tri_out_reg <= '0;
            vert_ctr    <= 2'd0;
        end else begin
            // Accept new triangle
            if (in_valid && in_ready) begin
                tri_in_reg <= triangle;
                vert_ctr   <= 2'd0;
                have_work  <= 1'b1;
            end

            // Produce/consume handshake
            if (out_valid && out_ready) begin
                have_work <= 1'b0;
            end

            if (have_work && (vert_ctr != 2'd3)) begin
                // ------------ per-vertex processing ------------
                // Do one vertex per cycle while have_work && vert_ctr<3
                vertex_t vin, vout;

                unique case (vert_ctr)
                    2'd0: vin = tri_in_reg.v0;
                    2'd1: vin = tri_in_reg.v1;
                    2'd2: vin = tri_in_reg.v2;
                    default: vin = '0;
                endcase

                // p_world - C
                dx = vin.pos.x - transform.pos.x;
                dy = vin.pos.y - transform.pos.y;
                dz = vin.pos.z - transform.pos.z;

                // p_cam = R^T * (p - C)
                cam_x = dot3_q16(R11, R21, R31, dx, dy, dz);
                cam_y = dot3_q16(R12, R22, R32, dx, dy, dz);
                cam_z = dot3_q16(R13, R23, R33, dx, dy, dz);

                vout.pos.x = cam_x;
                vout.pos.y = cam_y;
                vout.pos.z = cam_z;
                vout.color = vin.color;

                unique case (vert_ctr)
                    2'd0: tri_out_reg.v0 <= vout;
                    2'd1: tri_out_reg.v1 <= vout;
                    2'd2: tri_out_reg.v2 <= vout;
                endcase

                // advance; 3 -> "done" sentinel (2'd3)
                vert_ctr <= (vert_ctr == 2'd2) ? 2'd3 : (vert_ctr + 2'd1);
            end
        end
    end

endmodule
