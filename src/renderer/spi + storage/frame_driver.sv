`timescale 1ns / 1ps
import transform_pkg::*;
import buffer_id_pkg::*;
import vertex_pkg::*;
`default_nettype wire

module frame_driver #(
    parameter MAX_VERT      = 8192, // 2^13 = 8192
    parameter MAX_TRI       = 8192,
    parameter MAX_VERT_CNT  = 256,
    parameter MAX_TRI_CNT   = 256,
    parameter VTX_W         = 108,
    parameter VIDX_W        = $clog2(MAX_VERT_CNT),
    parameter TIDX_W        = $clog2(MAX_TRI_CNT),
    parameter TRI_W         = 3*VIDX_W
)(
    input  logic clk, rst,
    
    // spi driver ↔ frame driver
    input  logic [7:0] max_inst,

    // Memory control
    output logic [$clog2(MAX_VERT)-1:0] vert_addr,
    output logic [$clog2(MAX_TRI)-1:0]  tri_addr,
    output logic [7:0] inst_id_rd,

    // Memory inputs
    input  vertex_t      vert_in,
    input  logic [TRI_W-1:0] idx_tri,

    // Instance descriptor
    input  logic [$clog2(MAX_VERT)-1:0]  curr_vert_base,
    input  logic [$clog2(MAX_TRI)-1:0]   curr_tri_base,
    input  logic [TIDX_W-1:0]            curr_tri_count,

    // Frame driver → Transform
    input  logic draw_ready,  // transform ready
    input  logic world_busy,  // don't start new frame while busy
    input  transform_t transform_in,
    output logic draw_done,   // All instances done
    output logic draw_valid,  // valid triangle in output
    output logic camera_transform_valid,
    output transform_t transform_out,
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
    enum logic [3:0] {
        IDLE,
        LOAD_BASE,
        REQUEST_TRI,
        WAIT_TRI,
        LOAD_TRI,
        WAIT_VERT,
        CAPTURE_V0,
        CAPTURE_V1,
        CAPTURE_V2,
        OUTPUT_TRI,
        DONE
    } frame_state;
    
    // 8 cycles per triangle
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            frame_state   <= IDLE;
            tri_ctr       <= '0;
            idx_tri_reg   <= '0;
            tri_reg       <= '0;
            v_collect[0]  <= '0;
            v_collect[1]  <= '0;
            v_collect[2]  <= '0;
            transform_reg <= '0;
            camera_transform_valid  <= '0;
            draw_valid    <= 1'b0;
            tri_addr      <= '0;
            vert_addr     <= '0;
            next_inst_id  <= '0;
            inst_id_rd    <= '0;
            draw_done     <= '0;
        end else begin
            // Default outputs per cycle
            draw_valid <= '0;
            vert_addr  <= '0;
            tri_addr   <= '0;
            camera_transform_valid <= '0;

            // NP: need to wait +2 cycles: +1 load_addr +1 ram_out, to acces ram data
            case (frame_state)
                IDLE: begin
                    if (draw_ready) begin
                        next_inst_id <= next_inst_id +1;
                        inst_id_rd   <= next_inst_id;
                        frame_state <= LOAD_BASE;
                    end
                    draw_done <= 0;
                end
                
                // curr_tri_base <= tri_table[inst_table[inst_id].base];
                // tansform <= transform_ram[inst_id];
                LOAD_BASE: begin
                    frame_state <= REQUEST_TRI;
                    if(inst_id_rd == 0) 
                        frame_state <= OUTPUT_TRI;
                end

                REQUEST_TRI: begin
                    tri_addr <= curr_tri_base + tri_ctr;
                    frame_state <= LOAD_TRI;
                end
                
                // idx_tri <= tri_ram[tri_addr];
                LOAD_TRI: begin
                    frame_state <= WAIT_TRI;
                end
                
                WAIT_TRI: begin
                    idx_tri_reg <= idx_tri;
                    vert_addr <= curr_vert_base + idx_tri[3*VIDX_W-1:2*VIDX_W]; // request v0
                    frame_state <= WAIT_VERT;
                end
                
                // vert_in <= vert_ram[vert_addr];
                WAIT_VERT: begin
                    frame_state <= CAPTURE_V0;
                    vert_addr <= curr_vert_base + idx_tri_reg[2*VIDX_W-1:VIDX_W]; // request v1
                end

                CAPTURE_V0: begin
                    v_collect[0] <= vert_in;
                    frame_state <= CAPTURE_V1;
                    vert_addr <= curr_vert_base + idx_tri_reg[VIDX_W-1:0]; // request v2
                end

                CAPTURE_V1: begin
                    v_collect[1] <= vert_in;
                    frame_state <= CAPTURE_V2;
                end

                CAPTURE_V2: begin
                    v_collect[2] <= vert_in;
                    frame_state <= OUTPUT_TRI;
                end

                OUTPUT_TRI: begin
                    if (inst_id_rd == 0 && !world_busy) begin 
                        transform_reg <= transform_in;
                        camera_transform_valid  <= 1;
                        frame_state <= IDLE;
                        if(max_inst == 0)
                            next_inst_id <= 0;
                    end else if (inst_id_rd != 0) begin
                        if (draw_ready) begin
                            tri_reg.v0 <= v_collect[0];
                            tri_reg.v1 <= v_collect[1];
                            tri_reg.v2 <= v_collect[2];
                            transform_reg <= transform_in;
                            draw_valid <= 1'b1;
                            
                            if (tri_ctr < curr_tri_count - 1) begin
                                tri_ctr <= tri_ctr + 1;
                                frame_state <= REQUEST_TRI;
                            end else begin
                                tri_ctr <= 0;
                                frame_state <= IDLE;
                                // If all instances are done stop output
                                if(inst_id_rd == max_inst) begin
                                    draw_done <= 1;
                                    next_inst_id <= 0;
                                    frame_state <= DONE;
                                end
                            end
                        end
                    end
                end
                
                DONE: if(draw_ready) begin
                        frame_state <= IDLE;
                end

                default: frame_state <= IDLE;
            endcase
        end
    end

    assign tri_out = tri_reg;
    assign transform_out = transform_reg;

endmodule
