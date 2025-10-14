`timescale 1ns / 1ps
import vertex_pkg::*;
import transform_pkg::*;

module world_transform(
    input  clk,
    input  rst,

    // Handshake
    input  logic tri_in_valid,
    input  logic tri_in_ready,
    input  triangle_t tri_in,

    output logic tri_out_valid,
    output logic tri_out_ready,
    output triangle_t tri_out,

    input  transform_t inst_transform
    );
    
    vertex_t rot_x;
    vertex_t rot_y;
    vertex_t rot_z;
    
    logic signed [31:0] cos_x, sin_x, cos_y, sin_y, cos_z, sin_z;

    sincos_lut sincos_inst_x(.angle(angle_x), .sine(sin_x), .cosine(cos_x));
    sincos_lut sincos_inst_y(.angle(angle_y), .sine(sin_y), .cosine(cos_y));
    sincos_lut sincos_inst_z(.angle(angle_z), .sine(sin_z), .cosine(cos_z));
    
    always_ff @(posedge clk or posedge rst)begin
        if(tri_in_valid && tri_in_valid) begin
            tri_out.v0 <= {rot_x.pos.x + inst_transform.x, 
                           rot_x.pos.y + inst_transform.y, 
                           rot_x.pos.z + inst_transform.z};
            tri_out.v1 <= {rot_y.pos.x + inst_transform.x, 
                           rot_y.pos.y + inst_transform.y, 
                           rot_y.pos.z + inst_transform.z};
            tri_out.v2 <= {rot_z.pos.x + inst_transform.x, 
                           rot_z.pos.y + inst_transform.y, 
                           rot_z.pos.z + inst_transform.z};
        end
    end

endmodule
