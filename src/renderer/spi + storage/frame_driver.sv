`timescale 1ns / 1ps
import transformer_pkg::*;
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
    parameter TRI_W         = 3*VIDX_W,
    parameter ID_W          = 8
)(
    input  logic clk, rst,
    
    // spi driver ↔ frame driver
    input  logic [7:0] max_inst,
    input  logic       create_done,

    // Memory control
    output logic [$clog2(MAX_VERT)-1:0] vert_addr,
    output logic [$clog2(MAX_TRI)-1:0]  tri_addr,
    output logic [7:0] inst_id_rd,

    // Memory inputs
    input  transform_t       transform_in,
    input  vertex_t          vert_in,
    input  logic [TRI_W-1:0] idx_tri,

    // Instance descriptor
    input  logic [$clog2(MAX_VERT)-1:0]  curr_vert_base,
    input  logic [$clog2(MAX_TRI)-1:0]   curr_tri_base,
    input  logic [TIDX_W-1:0]            curr_tri_count,

    // Frame driver ↔ Transform
    input  logic out_ready, // transform setup ready
    output logic out_valid, // used for when the whole setup is valid 
    output transform_setup_t transform_setup,

    // Frame driver ↔ rasterdizer (when done)!!
    input  logic draw_start,
    output logic draw_done,   // All instances done
    
    output logic busy,
    
    output logic [7:0]      red_1_2,
    output logic [3:0]      red_3
    
);
    // Internal registers
    logic [TIDX_W-1:0] tri_ctr;
    logic [ID_W-1:0] next_inst_id;
    logic [1:0] wait_ctr;
    logic [ID_W-1:0] max_inst_sync_0;
    logic [ID_W-1:0] max_inst_sync;
    logic create_done_sync_0;
    logic create_done_sync;
    
    always_ff @(posedge clk or posedge rst) begin 
        if(rst) begin 
            max_inst_sync_0 <= 0;
            max_inst_sync   <= 0;
            create_done_sync_0 <= 0;
            create_done_sync   <= 0;
        end else begin 
            max_inst_sync_0 <= max_inst;
            max_inst_sync   <= max_inst_sync_0;
            create_done_sync_0 <= create_done;
            create_done_sync   <= create_done_sync_0;
        end
    end

    logic [TRI_W-1:0] idx_tri_reg;
    triangle_t t_collect;
    transform_setup_t transform_setup_r;
    
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
    
    assign busy = (frame_state != DONE);
    // 8 cycles per triangle
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            frame_state   <= IDLE;
            tri_ctr       <= '0;
            idx_tri_reg   <= '0;
            t_collect     <= '0;
            out_valid     <= '0;
            tri_addr      <= '0;
            vert_addr     <= '0;
            next_inst_id  <= '0;
            inst_id_rd    <= '0;
            draw_done     <= '0;
            wait_ctr      <= '0;
            transform_setup_r <= '0;
        end else if(create_done_sync) begin
            // Default outputs per cycle
            out_valid <= '0;
            vert_addr  <= '0;
            tri_addr   <= '0;
            transform_setup_r.model_transform_valid  <= '0;
            transform_setup_r.camera_transform_valid  <= '0;

            // NP: need to wait +2 cycles: +1 load_addr +1 ram_out, to acces ram data
            case (frame_state)
                IDLE: begin
                    if (out_ready) begin
                        next_inst_id <= next_inst_id +1;
                        inst_id_rd   <= next_inst_id;
                        frame_state <= LOAD_BASE;
                    end
                end
                
                // ctr 0: inst_dout_r   <= inst_ram[inst_id];
                // ctr 1: wait?
                // ctr 2: curr_tri_base <= tri_table_ram[inst_dout_r.base];
                LOAD_BASE: begin
                    if(wait_ctr == 2) begin
                        wait_ctr <= 0;
                        frame_state <= REQUEST_TRI;
                        if(inst_id_rd == 0)
                            frame_state <= OUTPUT_TRI;
                    end else 
                        wait_ctr <= wait_ctr+1;
                    
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
                    t_collect.v0 <= vert_in;
                    frame_state <= CAPTURE_V1;
                    vert_addr <= curr_vert_base + idx_tri_reg[VIDX_W-1:0]; // request v2
                end

                CAPTURE_V1: begin
                    t_collect.v1 <= vert_in;
                    frame_state <= CAPTURE_V2;
                end

                CAPTURE_V2: begin
                    t_collect.v2 <= vert_in;
                    frame_state <= OUTPUT_TRI;
                end

                OUTPUT_TRI: begin
                    if (inst_id_rd == 0 && out_ready) begin 
                        transform_setup_r.camera_transform <= transform_in;
                        transform_setup_r.camera_transform_valid <= 1;
                        out_valid <= 1;
                        frame_state <= IDLE;
                        if(max_inst_sync == 0)
                            next_inst_id <= 0;
                    end else if (inst_id_rd != 0 && out_ready) begin
                        transform_setup_r.triangle <= t_collect;
                        transform_setup_r.model_transform <= transform_in;
                        transform_setup_r.model_transform_valid <= 1;
                        out_valid <= 1;
                        
                        if (tri_ctr < curr_tri_count - 1) begin
                            tri_ctr <= tri_ctr + 1;
                            frame_state <= REQUEST_TRI;
                        end else begin
                            tri_ctr <= 0;
                            frame_state <= IDLE;
                            // If all instances are done stop output
                            if(inst_id_rd == max_inst_sync) begin
                                draw_done <= 1;
                                next_inst_id <= 0;
                                frame_state <= DONE;
                            end
                        end
                    end
                end
                
                DONE: if(draw_start) begin
                        frame_state <= IDLE;
                        draw_done <= 0;
                end

                default: frame_state <= IDLE;
            endcase
        end
    end

    assign transform_setup = transform_setup_r;
    // slice the red of vertex 0 and 1
    assign red_1_2 = {t_collect.v1.color[11:8], t_collect.v0.color[11:8]};
    assign red_3   =  t_collect.v2.color[11:8];
    

endmodule
