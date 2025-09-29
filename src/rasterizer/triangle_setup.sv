`timescale 1ns / 1ps
`default_nettype none

import rasterizer_pkg::*;
import vertex_pkg::*;

module triangle_setup #(
    parameter int WIDTH  = 320,
    parameter int HEIGHT = 240
) (
    input  wire logic clk,
    input  wire logic rst,

    input  wire vertex_t v0,
    input  wire vertex_t v1,
    input  wire vertex_t v2,

    input  wire logic    in_valid,
    output logic         in_ready,

    output triangle_state_t out_state,
    output logic            out_valid,
    input  wire logic       out_ready,
    output logic            busy
);

    // FSM
    typedef enum logic [1:0] {IDLE, DIV_START, DIV_WAIT, OUTPUT} state_t;
    state_t state, next_state;

    // Registers for geometry
    triangle_state_t tri_reg;
    logic signed [75:0] denom_reg;   // Q64.12
    logic [63:0] div_divisor_reg; 
    logic denom_neg_reg;

    // Divider interface signals
    logic        div_valid;
    logic        div_ready;
    logic [63:0] div_divisor, div_dividend;
    logic        div_out_valid;
    logic [86:0] div_out_data;
    logic div_divisor_ready, div_dividend_ready;

    div_rasterizer div_inst (
        .aclk                    (clk),
        .aresetn                 (!rst),

        .s_axis_divisor_tdata    (div_divisor),
        .s_axis_divisor_tvalid   (div_valid),
        .s_axis_divisor_tready   (div_divisor_ready),

        .s_axis_dividend_tdata   (div_dividend),
        .s_axis_dividend_tvalid  (div_valid),
        .s_axis_dividend_tready  (div_dividend_ready),

        .m_axis_dout_tdata       (div_out_data),
        .m_axis_dout_tvalid      (div_out_valid),
        
        .m_axis_dout_tuser       (),

        .m_axis_dout_tready      (1'b1) // Always ready to accept result
    );

    // Combine ready signals
    assign div_ready = div_divisor_ready & div_dividend_ready;

    // Output / status signals
    assign out_state = tri_reg;
    assign out_valid = (state == OUTPUT);
    assign in_ready  = (state == IDLE);
    assign busy      = (state != IDLE);

    // Divider inputs
    assign div_valid = (state == DIV_START);
    assign div_divisor  = div_divisor_reg;
    assign div_dividend = 1 << 16;

    // FSM
    always_ff @(posedge clk or posedge rst) begin
        if (rst) state <= IDLE;
        else     state <= next_state;
    end

    always_comb begin
        next_state = state;
        unique case (state)
            IDLE: begin
                if (in_valid && in_ready)
                    next_state = DIV_START;
            end
            DIV_START: begin
                if (div_ready)
                    next_state = DIV_WAIT;
            end
            DIV_WAIT: begin
                if (div_out_valid)
                    next_state = OUTPUT;
            end
            OUTPUT: begin
                if (out_valid && out_ready)
                    next_state = IDLE;
            end
            default: next_state = IDLE;
        endcase
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            tri_reg      <= '0;
            denom_reg    <= '0;
            div_divisor_reg  <= '0;
            denom_neg_reg    <= 1'b0;
        end else begin
            if (state == IDLE && in_valid && in_ready) begin
                logic signed [18:0] v0x = v0.pos.x[31:13]; // Q16.3
                logic signed [18:0] v0y = v0.pos.y[31:13];
                logic signed [18:0] v1x = v1.pos.x[31:13];
                logic signed [18:0] v1y = v1.pos.y[31:13];
                logic signed [18:0] v2x = v2.pos.x[31:13];
                logic signed [18:0] v2y = v2.pos.y[31:13];

                logic signed [18:0] e0x = v1x - v0x; // Q16.3
                logic signed [18:0] e0y = v1y - v0y;
                logic signed [18:0] e1x = v2x - v0x;
                logic signed [18:0] e1y = v2y - v0y;

                logic signed [37:0] d00 = e0x*e0x + e0y*e0y; // Q32.6
                logic signed [37:0] d01 = e0x*e1x + e0y*e1y; 
                logic signed [37:0] d11 = e1x*e1x + e1y*e1y;

                logic signed [75:0] denom = d00*d11 - d01*d01; // Q64.12
                logic [75:0] denom_abs = denom[75] ? (~denom + 1) : denom;

                denom_reg  <= denom;
                div_divisor_reg <= denom_abs[75:12]; // Q64.0
                denom_neg_reg   <= denom[75]; // sign of full Q64.12

                // Triangle state
                tri_reg.v0x <= v0x;
                tri_reg.v0y <= v0y;
                tri_reg.e0x <= e0x;
                tri_reg.e0y <= e0y;
                tri_reg.e1x <= e1x;
                tri_reg.e1y <= e1y;

                tri_reg.d00 <= d00;
                tri_reg.d01 <= d01;
                tri_reg.d11 <= d11;

                tri_reg.v0_color   <= v0.color;
                tri_reg.v1_color   <= v1.color;
                tri_reg.v2_color   <= v2.color;
                tri_reg.v0_depth   <= v0.pos.z;
                tri_reg.v1_depth   <= v1.pos.z;
                tri_reg.v2_depth   <= v2.pos.z;

                // Bounding box
                tri_reg.bbox_min_x <= clamp(min3(v0.pos.x, v1.pos.x, v2.pos.x) >>> 16, 0, WIDTH-1);
                tri_reg.bbox_max_x <= clamp((max3(v0.pos.x, v1.pos.x, v2.pos.x) + 32'hFFFF) >>> 16, 0, WIDTH-1);
                tri_reg.bbox_min_y <= clamp(min3(v0.pos.y, v1.pos.y, v2.pos.y) >>> 16, 0, HEIGHT-1);
                tri_reg.bbox_max_y <= clamp((max3(v0.pos.y, v1.pos.y, v2.pos.y) + 32'hFFFF) >>> 16, 0, HEIGHT-1);
            end

            if (state == DIV_WAIT && div_out_valid) begin
                tri_reg.denom_inv <= div_out_data[15:0]; // Q0.16
                tri_reg.denom_neg <= denom_neg_reg;
            end
        end
    end
endmodule
