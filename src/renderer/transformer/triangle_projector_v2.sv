`timescale 1ns / 1ps
`default_nettype wire
import vertex_pkg::*;
import math_pkg::*;

module triangle_projector_v2(
    input  logic clk,
    input  logic rst,

    input  triangle_t triangle,
    input  logic      in_valid,
    output logic      in_ready,

    input  q16_16_t   focal_length,

    output triangle_t out_triangle,
    output logic      out_valid,
    input  logic      out_ready,
    output logic      busy
);

    // pipeline and vertex control
    logic [1:0] vert_ctr_in, vert_ctr_out;
    vertex_t load_v, div_v, proj_v;
    q16_16_t z_inv_reg;
    
    // pipeline flags
    logic load_done;     // stage 0
    logic load_div_done; // stage 1, after we have the selected vertex we load z_abs for dividing
    logic latch_done;
    logic proj_done;

    // Divider interface
    logic    div_busy, div_done, div_valid;
    q16_16_t div_b;
    q16_16_t div_val;
    q16_16_t z_inv;

    divu #(.WIDTH(32), .FBITS(16)) u_divu (
        .clk   (clk),
        .rst   (rst),
        .start (load_div_done),
        .busy  (div_busy),
        .done  (div_done),
        .valid (div_valid),
        .dbz   (),
        .ovf   (),
        .a     (32'd1 << 16),
        .b     (div_b),
        .val   (div_val)
    );

    assign z_inv = q16_16_t'(div_val);
    
    assign busy = load_done || load_div_done || latch_done || proj_done;
    assign in_ready = (vert_ctr_in < 3) && (vert_ctr_out != 2 && out_ready) ? 1 : 0;
    
    logic load_vert;
    logic [2:0] load_vert_ctr;
    
    // pipeline control
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            vert_ctr_in  <= 0;
            vert_ctr_out <= 0;
        end else begin
             if(in_valid && in_ready) begin
                load_vert_ctr <= load_vert_ctr +1;
                load_vert <= 1;
            end else if(load_vert && in_ready) begin
                load_vert_ctr <= load_vert_ctr +1;
                if(load_vert_ctr == 2 && in_ready) begin
                    load_vert_ctr <= 0;
                    load_vert <= 0; 
                end
            end
            if ((in_valid || load_vert) && in_ready) begin
                vert_ctr_in <= (vert_ctr_in == 2) ? 0 : vert_ctr_in + 1;
            end

            if (proj_done && out_ready) begin
                vert_ctr_out <= (vert_ctr_out == 2) ? 0 : vert_ctr_out + 1;
            end
        end
    end

    // Stage 0: Load vertex
    always_ff @(posedge clk) begin
        if (in_valid && in_ready) begin
            unique case (vert_ctr_in)
                2'd0: load_v <= triangle.v0;
                2'd1: load_v <= triangle.v1;
                2'd2: load_v <= triangle.v2;
            endcase
            load_done <= 1;
        end else 
            load_done <= 0;
    end

    // Stage 1: Divider start and |z|
    q16_16_t z_signed;
    logic [31:0] z_abs;
    always_ff @(posedge clk) begin
        if (load_done) begin
            z_signed = load_v.pos.z;
            z_abs = z_signed[31] ? -z_signed : z_signed;
            div_b <= (z_abs == 0) ? 32'd1 : z_abs;
            load_div_done <= 1'b1;
            div_v <= load_v;
        end else begin
            load_div_done <= 1'b0;
        end
    end

    // Stage 2: Divider result latch
    always_ff @(posedge clk) begin
        if (div_done) begin
            z_inv_reg <= z_inv;
            latch_done <= 1;
        end else 
            latch_done <= 0;
    end

    // Stage 3: Projection
    always_ff @(posedge clk) begin
        if (latch_done) begin
            if (div_v.pos.z[31]) begin
                proj_v.pos.x <= -project_q16_16(focal_length, div_v.pos.x, z_inv_reg);
                proj_v.pos.y <= -project_q16_16(focal_length, div_v.pos.y, z_inv_reg);
            end else begin
                proj_v.pos.x <= project_q16_16(focal_length, div_v.pos.x, z_inv_reg);
                proj_v.pos.y <= project_q16_16(focal_length, div_v.pos.y, z_inv_reg);
            end

            proj_v.pos.z <= div_v.pos.z;
            proj_v.color <= div_v.color;
            proj_done <= 1;
        end else
            proj_done <= 0;
    end

    // Stage 4: Output triangle
    always_ff @(posedge clk) begin
        if (rst) begin
            out_valid <= 0;
        end else begin
            out_valid <= 0;
            if (proj_done) begin
                unique case (vert_ctr_out)
                    2'd0: out_triangle.v0 <= proj_v;
                    2'd1: out_triangle.v1 <= proj_v;
                    2'd2: out_triangle.v2 <= proj_v;
                endcase

                if (vert_ctr_out == 2)
                    out_valid <= 1;
            end
        end
    end
endmodule
