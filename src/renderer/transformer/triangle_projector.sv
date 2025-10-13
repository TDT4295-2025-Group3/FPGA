`timescale 1ns / 1ps
`default_nettype none
import vertex_pkg::*;
import math_pkg::*;  // contains project_q16_16(f, x, z_inv) doing Q16.16 * Q16.16 * Q16.16 -> Q16.16 with >>>32 total

module triangle_projector(
    input  logic clk,
    input  logic rst,

    input  triangle_t in_triangle,
    input  logic      in_valid,
    output logic      in_ready,

    input  q16_16_t   focal_length,  // e.g. 320.0 in Q16.16

    output triangle_t out_triangle,
    output logic      out_valid,
    input  logic      out_ready,

    output logic      busy
);

    // Internal registers
    triangle_t tri_in_reg;
    triangle_t tri_proj_reg;
    logic [1:0] vert_idx;

    // Divider interface (unsigned)
    logic        div_start, div_busy, div_done, div_valid;
    logic [31:0] div_b;       // |z|
    logic [31:0] div_val;     // Q16.16 reciprocal of |z|
    q16_16_t     z_inv;       // recast to signed wire (same bits)

    // FSM
    typedef enum logic [1:0] {IDLE, DIVIDE, OUTPUT} state_t;
    state_t state, next_state;

    assign busy      = (state != IDLE);
    assign in_ready  = (state == IDLE);
    assign out_valid = (state == OUTPUT);

    // --- Divider (1.0 / |z| in Q16.16) ---
    divu #(.WIDTH(32), .FBITS(16)) u_divu (
        .clk   (clk),
        .rst   (rst),
        .start (div_start),
        .busy  (div_busy),
        .done  (div_done),
        .valid (div_valid),
        .dbz   (),   // optional: expose if you want to flag degenerate triangles
        .ovf   (),
        .a     (32'd1 << 16), // 1.0 in Q16.16
        .b     (div_b),
        .val   (div_val)
    );
    assign z_inv = q16_16_t'(div_val);

    // --- FSM control & latching ---
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state    <= IDLE;
            vert_idx <= 2'd0;
        end else begin
            state <= next_state;

            if (in_valid && in_ready) begin
                tri_in_reg <= in_triangle;
                vert_idx   <= 2'd0;
            end else if (div_done) begin
                vert_idx   <= vert_idx + 2'd1;
            end
        end
    end

    always_comb begin
        next_state = state;
        div_start  = 1'b0;

        unique case (state)
            IDLE: begin
                if (in_valid)
                    next_state = DIVIDE;
            end

            DIVIDE: begin
                // pulse start when divider is idle
                if (!div_busy)
                    div_start = 1'b1;

                if (div_done && (vert_idx == 2))
                    next_state = OUTPUT;
                else if (div_done)
                    next_state = DIVIDE;
            end

            OUTPUT: begin
                if (out_ready)
                    next_state = IDLE;
            end
        endcase
    end

    // --- Divider input: |z| (unsigned), with optional epsilon clamp to avoid DBZ ---
    always_comb begin
        q16_16_t z_signed;
        unique case (vert_idx)
            2'd0: z_signed = tri_in_reg.v0.pos.z;
            2'd1: z_signed = tri_in_reg.v1.pos.z;
            2'd2: z_signed = tri_in_reg.v2.pos.z;
            default: z_signed = 32'sd1;
        endcase

        // unsigned divisor = abs(z)
        logic [31:0] z_abs = z_signed[31] ? logic'(-z_signed) : logic'(z_signed);

        // Optional: clamp zero to 1 LSB (Q16.16) to prevent DBZ behavior in divu
        // Comment out the line below if you prefer to pass 0 through and handle dbz upstream.
        div_b = (z_abs == 32'd0) ? 32'd1 : z_abs;
        // If you prefer raw behavior, just use: div_b = z_abs;
    end

    // --- Projection on divider completion ---
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            tri_proj_reg <= '0;
        end else if (div_done) begin
            // Read current vertex
            vertex_t  v_in;
            unique case (vert_idx)
                2'd0: v_in = tri_in_reg.v0;
                2'd1: v_in = tri_in_reg.v1;
                2'd2: v_in = tri_in_reg.v2;
                default: v_in = '0;
            endcase

            // Compute projection with high precision (math_pkg::project_q16_16 does Q32.32 -> Q48.48 -> >>>32)
            q16_16_t x_proj, y_proj;
            x_proj = project_q16_16(focal_length, v_in.pos.x, z_inv);
            y_proj = project_q16_16(focal_length, v_in.pos.y, z_inv);

            // Reapply sign of z because divider used |z|
            if (v_in.pos.z[31]) begin
                x_proj = -x_proj;
                y_proj = -y_proj;
            end

            // Write projected vertex
            vertex_t v_out;
            v_out.pos.x = x_proj;
            v_out.pos.y = y_proj;
            v_out.pos.z = v_in.pos.z; // preserve depth
            v_out.color = v_in.color;

            unique case (vert_idx)
                2'd0: tri_proj_reg.v0 <= v_out;
                2'd1: tri_proj_reg.v1 <= v_out;
                2'd2: tri_proj_reg.v2 <= v_out;
            endcase
        end
    end

    assign out_triangle = tri_proj_reg;

endmodule
