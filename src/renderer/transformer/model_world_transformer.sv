`timescale 1ns / 1ps
import math_pkg::*;
import vertex_pkg::*;
default nettype wire;

module model_world_transformer(
    input  clk,
    input  rst,
 
    input  transform_t transform,
    input  triangle_t triangle,
    input  logic in_valid,
    output logic in_ready,

    output triangle_t out_triangle,
    output logic out_valid,
    input  logic out_ready,
    output logic busy
    );
    
    vertex_t rot_x, rot_y, rot_z;
    vertex_t world_x, world_y, world_z;
    logic [1:0] vert_ctr;
    logic [1:0] load_ctr;
    logic vert_loaded;

    q16_16_t vert_x, vert_y, vert_z;
    q16_16_t cos_x, sin_x, cos_y, sin_y, cos_z, sin_z;

    assign sin_x = transform.rot_sin.x;
    assign cos_x = transform.rot_cos.x;
    assign sin_y = transform.rot_sin.y;
    assign cos_y = transform.rot_cos.y;
    assign sin_z = transform.rot_sin.z;
    assign cos_z = transform.rot_cos.z;
    
always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        vert_ctr    <= 0;
        vert_loaded <= 0;
    end else if (in_valid && in_ready) begin
        case (vert_ctr)
            2'd0: begin
                vert_x <= triangle.v0.x;
                vert_y <= triangle.v0.y;
                vert_z <= triangle.v0.z;
            end
            2'd1: begin
                vert_x <= triangle.v1.x;
                vert_y <= triangle.v1.y;
                vert_z <= triangle.v1.z;
            end
            2'd2: begin
                vert_x <= triangle.v2.x;
                vert_y <= triangle.v2.y;
                vert_z <= triangle.v2.z;
            end
        endcase

        // Rotation (Z-Y-X order)
        rot_x <= (cos_z*cos_y)*vert_x  // FIXME: this gonna break because of fixed point (q16.16 * q16.16 = q32.32 and multiplication result needs to be shifted back)
               + (cos_z*sin_y*sin_x - sin_z*cos_x)*vert_y 
               + (cos_z*sin_y*cos_x + sin_z*sin_x)*vert_z;

        rot_y <= (sin_z*cos_y)*vert_x // FIXME: this gonna break because of fixed point
               + (sin_z*sin_y*sin_x + cos_z*cos_x)*vert_y 
               + (sin_z*sin_y*cos_x - cos_z*sin_x)*vert_z;

        rot_z <= (-sin_y)*vert_x // FIXME: this gonna break because of fixed point
               + (cos_y*sin_x)*vert_y 
               + (cos_y*cos_x)*vert_z;

        // Translation to world
        world_x <= rot_x + transform.pos.x;
        world_y <= rot_y + transform.pos.y;
        world_z <= rot_z + transform.pos.z;

        // Next vertex
        if(load_ctr < 3) begin
            Case (vert_ctr)
                2'd0: begin
                    out_traingle.v0.x <= world_x;
                    out_traingle.v0.y <= world_y;
                    out_traingle.v0.z <= world_z;
                    load_ctr <= load_ctr +1;
                end
                2'd1: begin
                    out_traingle.v1.x <= world_x;
                    out_traingle.v1.y <= world_y;
                    out_traingle.v1.z <= world_z;
                    load_ctr <= load_ctr +1;
                end
                2'd2: begin
                    out_traingle.v2.x <= world_x;
                    out_traingle.v2.y <= world_y;
                    out_traingle.v2.z <= world_z;
                end
            endcase
            load_ctr <= load_ctr +1;
        end else begin 
            load_ctr <= 0;
            out_valid <= 1;
            out_traingle.v0.x <= world_x;
            out_traingle.v0.y <= world_y;
            out_traingle.v0.z <= world_z;
        end
        vert_ctr <= (vert_ctr == 2) ? 0 : vert_ctr + 1;
    end
end

endmodule
