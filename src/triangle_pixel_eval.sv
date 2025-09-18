`default_nettype none
`timescale 1ns / 1ps

module triangle_pixel_eval (
    input  logic signed [31:0] ax, ay, az,
    input  logic signed [31:0] bx, by, bz,
    input  logic signed [31:0] cx, cy, cz,
    input  logic [11:0] a_color, b_color, c_color,
    input  logic signed [31:0] px, py,
    output logic signed [31:0] pz,
    output logic p_inside,
    output logic [11:0] p_color
);
    logic signed [31:0] v0x = bx - ax;
    logic signed [31:0] v0y = by - ay;
    logic signed [31:0] v1x = cx - ax;
    logic signed [31:0] v1y = cy - ay;
    logic signed [31:0] v2x = px - ax;
    logic signed [31:0] v2y = py - ay;

    logic signed [63:0] d00, d01, d11, d20, d21;
    dot2d dot00_inst (.p0x(v0x), .p0y(v0y), .p1x(v0x), .p1y(v0y), .dot(d00));
    dot2d dot01_inst (.p0x(v0x), .p0y(v0y), .p1x(v1x), .p1y(v1y), .dot(d01));
    dot2d dot11_inst (.p0x(v1x), .p0y(v1y), .p1x(v1x), .p1y(v1y), .dot(d11));
    dot2d dot20_inst (.p0x(v2x), .p0y(v2y), .p1x(v0x), .p1y(v0y), .dot(d20));
    dot2d dot21_inst (.p0x(v2x), .p0y(v2y), .p1x(v1x), .p1y(v1y), .dot(d21));

    logic signed [127:0] denom = d00 * d11 - d01 * d01;
    logic signed [127:0] v_num = d11 * d20 - d01 * d21;
    logic signed [127:0] w_num = d00 * d21 - d01 * d20;
    logic signed [127:0] u_num = denom - v_num - w_num;

    logic signed [31:0] u, v, w;
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

            pz = (u * az + v * bz + w * cz) >>> 16;
        end else begin
            p_color = 12'b0;
            pz = 32'b0;
        end
    end

endmodule
