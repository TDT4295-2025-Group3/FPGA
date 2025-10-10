`timescale 1ns / 1ps
import transform_pkg::*;
import buffer_id_pkg::*;
import vertex_pkg::*;
`default_nettype wire

module frame_driver #(
    parameter MAX_VERT      = 8192, // 2^13 = 8192
    parameter MAX_TRI       = 8192,
    parameter INST_NR       = 2,
    parameter MAX_VERT_CNT  = 256,
    parameter MAX_TRI_CNT   = 256,
    parameter VTX_W         = 108,
    parameter VIDX_W        = $clog2(MAX_VERT_CNT),
    parameter TIDX_W        = $clog2(MAX_TRI_CNT),
    parameter TRI_W         = 3*VIDX_W
)(
    input  logic clk, rst,

    // Memory control
    output logic [$clog2(MAX_VERT)-1:0] vert_addr,
    output logic [$clog2(MAX_TRI)-1:0]  tri_addr,
    output logic [7:0] rd_inst_id,

    // Memory inputs
    input  vertex_t      vert_in,
    input  logic [TRI_W-1:0] idx_tri,

    // Instance descriptor
    input  logic [$clog2(MAX_VERT)-1:0]  curr_vert_base,
    input  logic [$clog2(MAX_TRI)-1:0]   curr_tri_base,
    input  logic [TIDX_W-1:0]            curr_tri_count,

    // Frame driver → Transform
    input  logic draw_ready,  // transform ready
    output logic draw_done,   // All instances done
    output logic draw_valid,  // valid triangle in output
    output triangle_t tri_out
);

    // Internal registers
    logic [VIDX_W-1:0] vert_ctr;
    logic [TIDX_W-1:0] tri_ctr;
    logic [7:0] next_inst_id;

    logic [TRI_W-1:0] idx_tri_reg;
    vertex_t v_collect[0:2];
    triangle_t tri_reg;
    transform_t transform_reg;

    // FSM
    typedef enum logic [2:0] {
        IDLE,
        REQUEST_TRI,
        WAIT_TRI,
        CAPTURE_V0,
        CAPTURE_V1,
        CAPTURE_V2,
        OUTPUT_TRI,
        DONE
    } state_e;

    state_e state;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state         <= IDLE;
            tri_ctr       <= '0;
            idx_tri_reg   <= '0;
            tri_reg       <= '0;
            v_collect[0]  <= '0;
            v_collect[1]  <= '0;
            v_collect[2]  <= '0;
            draw_valid    <= 1'b0;
            tri_addr      <= '0;
            vert_addr     <= '0;
            next_inst_id  <= '0;
            rd_inst_id    <= '0;
            draw_done     <= '0;
        end else begin
            // Default outputs per cycle
            draw_valid <= 1'b0;
            vert_addr  <= '0;
            tri_addr   <= '0;

            case (state)
                IDLE: begin
                    if (draw_ready) begin
                        next_inst_id <= next_inst_id +1;
                        rd_inst_id   <= next_inst_id;
                        state <= REQUEST_TRI;
                    end
                    draw_done <= 0;
                end

                REQUEST_TRI: begin
                    tri_addr <= curr_tri_base + tri_ctr;
                    state <= WAIT_TRI;
                end

                WAIT_TRI: begin
                    idx_tri_reg <= idx_tri;
                    vert_addr <= curr_vert_base + idx_tri[VIDX_W-1:0]; // request v0
                    state <= CAPTURE_V0;
                end

                CAPTURE_V0: begin
                    v_collect[0] <= vert_in;
                    vert_addr <= curr_vert_base + idx_tri_reg[2*VIDX_W-1:VIDX_W]; // request v1
                    state <= CAPTURE_V1;
                end

                CAPTURE_V1: begin
                    v_collect[1] <= vert_in;
                    vert_addr <= curr_vert_base + idx_tri_reg[3*VIDX_W-1:2*VIDX_W]; // request v2
                    state <= CAPTURE_V2;
                end

                CAPTURE_V2: begin
                    v_collect[2] <= vert_in;
                    state <= OUTPUT_TRI;
                end

                OUTPUT_TRI: begin
                    tri_reg.v0 <= v_collect[0];
                    tri_reg.v1 <= v_collect[1];
                    tri_reg.v2 <= v_collect[2];
                    draw_valid <= 1'b1;

                    if ('1) begin
                        if (tri_ctr < curr_tri_count - 1) begin
                            tri_ctr <= tri_ctr + 1;
                            state <= REQUEST_TRI;
                        end else begin
                            tri_ctr <= 0;
                            state <= IDLE;
                            if(rd_inst_id == INST_NR-1) begin
                                draw_done <= 1;
                                next_inst_id <= 0;
                                state <= DONE;
                            end
                        end
                    end
                end
                
                DONE: if(draw_ready) begin
                        state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

    assign tri_out = tri_reg;

endmodule
