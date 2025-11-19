`timescale 1ns / 1ps 
`default_nettype wire
import vertex_pkg::*;
import math_pkg::*;

module vertex_projector #(
    parameter int FOCAL_LENGTH = 256
) (
    input  logic clk,
    input  logic rst,

    input  vertex_t   vertex,
    input  logic      in_valid,
    output logic      in_ready,

    output vertex_t   out_vertex,
    output logic      out_valid,
    input  logic      out_ready,
    output logic      busy
);
    localparam q16_16_t FOCAL_Q16_16 = q16_16_t'(FOCAL_LENGTH <<< 16);

    // pipeline and vertex control
    vertex_t load_v, div_v, proj_v;
    q16_16_t z_inv_reg;
    
    // pipeline flags
    logic load_done;     // stage 0
    logic load_div_done; // stage 1, divider start
    logic latch_done;
    logic proj_done;
    logic output_pending;

    // Divider interface
    logic    div_busy, div_done, div_valid;
    q16_16_t div_b;
    q16_16_t div_val;
    q16_16_t z_inv;

    inv #(
        .IN_BITS   (32),
        .IN_FBITS  (16),
        .OUT_BITS  (32),
        .OUT_FBITS (16)
    ) u_inv (
        .clk   (clk),
        .rst   (rst),
        .start (load_div_done),
        .x     (div_b),
        .busy  (div_busy),
        .done  (div_done),
        .valid (div_valid),
        .dbz   (),
        .ovf   (),
        .y     (div_val)
    );

    assign z_inv = q16_16_t'(div_val);
    
    assign busy    = load_done || load_div_done || div_done || div_busy || latch_done || proj_done || output_pending;
    assign in_ready = !busy ? 1 : 0;
    
    logic load_vert;
    logic [2:0] load_vert_ctr;

    
    // Load vert
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            load_done  <= 1'b0;
        end else begin
            if (in_valid && in_ready) begin
                load_v    <= vertex;
                load_done <= 1'b1;
            end else begin
                load_done <= 1'b0;
            end
        end
    end

    // Stage 1: Divider start (feed signed z directly; guard z==0)
    always_ff @(posedge clk) begin
        if (load_done) begin
            div_b         <= (load_v.pos.z == 32'd0) ? 32'd1 : load_v.pos.z;
            load_div_done <= 1'b1;
            div_v         <= load_v;
        end else begin
            load_div_done <= 1'b0;
        end
    end

    // Stage 2: Divider result latch
    always_ff @(posedge clk) begin
        if (div_done) begin
            z_inv_reg  <= z_inv;
            latch_done <= 1'b1;
        end else begin
            latch_done <= 1'b0;
        end
    end

    // Stage 3: Projection (no sign branch needed; z_inv is signed 1/z)
    always_ff @(posedge clk) begin
        if (latch_done) begin
            proj_v.pos.x <= project_q16_16(FOCAL_Q16_16, div_v.pos.x, z_inv_reg);
            proj_v.pos.y <= project_q16_16(FOCAL_Q16_16, div_v.pos.y, z_inv_reg);
            proj_v.pos.z <= div_v.pos.z;
            proj_v.color <= div_v.color;
            proj_done    <= 1'b1;
        end else begin
            proj_done    <= 1'b0;
        end
    end

    // Output stage
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            out_valid       <= 1'b0;
            output_pending  <= 1'b0;
        end else begin
            if (proj_done) begin
                out_vertex      <= proj_v;
                out_valid       <= 1'b1;
                output_pending  <= 1'b1;
            end else if (out_ready && out_valid) begin
                out_valid       <= 1'b0;
                output_pending  <= 1'b0;
            end
        end
    end

endmodule
