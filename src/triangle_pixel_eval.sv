`default_nettype none
`timescale 1ns / 1ps

import math_pkg::point2d_t;
import math_pkg::point3d_t;
import math_pkg::q16_16_t;
import math_pkg::q32_32_t;
import math_pkg::q64_64_t;
import color_pkg::color12_t;

module triangle_pixel_eval (
    input  point3d_t a,
    input  point3d_t b,
    input  point3d_t c,
    input  color12_t a_color, b_color, c_color,
    input  point2d_t p,
    output q16_16_t p_z,
    output logic p_inside,
    output color12_t p_color
);
    q16_16_t v0x, v0y, v1x, v1y, v2x, v2y;

    assign v0x = b.x - a.x;
    assign v0y = b.y - a.y;
    assign v1x = c.x - a.x;
    assign v1y = c.y - a.y;
    assign v2x = p.x - a.x;
    assign v2y = p.y - a.y;


    q32_32_t d00, d01, d11, d20, d21;
    dot2d dot00_inst (.p0('{v0x, v0y}), .p1('{v0x, v0y}), .dot(d00));
    dot2d dot01_inst (.p0('{v0x, v0y}), .p1('{v1x, v1y}), .dot(d01));
    dot2d dot11_inst (.p0('{v1x, v1y}), .p1('{v1x, v1y}), .dot(d11));
    dot2d dot20_inst (.p0('{v2x, v2y}), .p1('{v0x, v0y}), .dot(d20));
    dot2d dot21_inst (.p0('{v2x, v2y}), .p1('{v1x, v1y}), .dot(d21));

    q64_64_t denom, v_num, w_num, u_num;
    
    assign denom = d00 * d11 - d01 * d01;
    assign v_num = d11 * d20 - d01 * d21;
    assign w_num = d00 * d21 - d01 * d20;
    assign u_num = denom - v_num - w_num;

    q16_16_t u, v, w;
    always_comb begin
        if (denom != 0) begin
            v = (v_num <<< 16) / denom;
            w = (w_num <<< 16) / denom;
            u = (u_num <<< 16) / denom;
        end
        else begin
            u = 0; v = 0; w = 0;
        end
    end

    always_comb begin
        p_inside = (u >= 0) && (v >= 0) && (w >= 0);
        if (p_inside) begin
            // Color channels are 4-bit, so u/v/w in Q16.16 -> shift down
            p_color[11:8] = (u * a_color[11:8] + v * b_color[11:8] + w * c_color[11:8]) >>> 16;
            p_color[7:4]  = (u * a_color[7:4]  + v * b_color[7:4]  + w * c_color[7:4])  >>> 16;
            p_color[3:0]  = (u * a_color[3:0]  + v * b_color[3:0]  + w * c_color[3:0])  >>> 16;

            p_z = (u * a.z + v * b.z + w * c.z) >>> 16;
        end else begin
            p_color = 12'b0;
            p_z = 32'b0;
        end
    end

endmodule
