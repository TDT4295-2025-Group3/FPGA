`timescale 1ns / 1ps
`default_nettype wire
import vertex_pkg::*;
import math_pkg::*;

module vertex_projector(
    input  logic clk,
    input  logic rst,

    input  vertex_t   vertex,
    input  logic      in_valid,
    output logic      in_ready,

    input  q16_16_t   focal_length,

    output vertex_t   out_vertex,
    output logic      out_valid,
    input  logic      out_ready,
    output logic      busy
);

    // pipeline and vertex control
    vertex_t load_v, div_v, proj_v;
    q16_16_t z_inv_reg;
    
    // pipeline flags
    logic load_done;     // stage 0
    logic load_div_done; // stage 1, after we have the selected vertex we load z_abs for dividing
    logic latch_done;
    logic proj_done;
    logic output_pending;

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
    
    assign busy = load_done || load_div_done || div_done || div_busy || latch_done || proj_done || output_pending;
    assign in_ready = !busy ? 1 : 0;
    
    logic load_vert;
    logic [2:0] load_vert_ctr;
    
    // Load vert
    always_ff @(posedge clk) begin
        if (rst) begin
            load_done  <= 0;
            load_done  <= 0;
        end else begin
            if (in_valid && in_ready) begin
                load_v <= vertex;
                load_done <= 1;
            end else 
                load_done <= 0;
        end
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

    always_ff @(posedge clk) begin
        if (rst) begin
            out_valid <= 0;
            output_pending <= 0;
        end else begin
            if (proj_done) begin
                out_vertex <= proj_v;
                out_valid <= 1;
                output_pending <= 1;
            end else if (out_ready && out_valid) begin
                out_valid <= 0;
                output_pending <= 0;
            end
        end
end
endmodule
