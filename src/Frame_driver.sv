`timescale 1ns / 1ps
import transform_pkg::*;
import buffer_id_pkg::*;
import vertex_pkg::*;
`default_nettype wire

module frame_driver#(
    localparam MAX_VERT  = 256,      // 2^13 bit = 8192
    localparam MAX_TRI   = 256,      // 2^13 bit = 8192
    localparam MAX_INST  = 256,      // Also used max vert and tri buffers
    localparam MAX_VERT_BUF = 256,   // maximum distinct vertex buffers
    localparam MAX_TRI_BUF  = 256,   // maximum distinct triangle buffers
    
    localparam MAX_VERT_CNT = 256,             // max vertices per buffer
    localparam MAX_TRI_CNT = 256,              // max triangles per buffer
    localparam VTX_W     = 108,                // 3*32 + 3*4 bits (spec)
    localparam VIDX_W = $clog2(MAX_VERT_CNT), 
    localparam TIDX_W = $clog2(MAX_TRI_CNT),   
    localparam TRI_W     = 3*VIDX_W,           // 3*8 bits. Might want to increase for safety 3*12 bits
    localparam DATA_W    = 32,
    localparam TRANS_W   = DATA_W * 9   // 9 floats
    )(
    
    // General inputs
    input logic clk, rst,
    
    // Memory ← Frame driver
    output logic [$clog2(MAX_VERT)-1:0] vert_addr,
    output logic [$clog2(MAX_TRI)-1:0] tri_addr,
    output logic [7:0] rd_inst_id,
    
    // Memory → Frame driver
    input inst_t inst_in,
    input vertex_t vert_in,
    input logic [TRI_W-1:0] idx_tri,
    
    
    // Frame driver → Transform
    input  logic draw_ready, 
    output logic draw_valid,
    output triangle_t tri_out,
    output transform_t transform_out
    );
    
    // FSM resources (current vertex/triagnle and counters)
    logic [$clog2(MAX_VERT)-1:0] curr_vert_base;
    logic [VIDX_W-1:0] curr_vert_count;
    logic [VIDX_W-1:0] vert_ctr;
    
    logic [$clog2(MAX_TRI)-1:0] curr_tri_base;
    logic [TIDX_W-1:0] curr_tri_count;
    logic [TIDX_W-1:0] tri_ctr;
    
    enum logic [2:0] {RC_IDLE, RC_FETCH_DESC, RC_STREAM_VERT, RC_STREAM_TRI} rc_state; // Rasterdizer controller state
    
    always_ff @(posedge clk or posedge rst) begin
        if(rst) begin
            rc_state <= RC_IDLE;
            tri_ctr    <= '0;
            draw_valid <= '0;
            vert_ctr   <= '0;
        end else begin
            case(rc_state)
                RC_IDLE: if(draw_ready) begin
                    rc_state <= RC_FETCH_DESC;
                end
                
                RC_FETCH_DESC: begin
                    curr_tri_base     <= tri_table[inst_ram[rd_inst_id].tri_id].base;
                    curr_tri_count    <= tri_table[inst_ram[rd_inst_id].tri_id].count;
                    curr_vert_base    <= vert_table[inst_ram[rd_inst_id].vert_id].base;
                    curr_vert_count   <= vert_table[inst_ram[rd_inst_id].vert_id].count;
                    tri_ctr <= 0;
                    rc_state <= RC_STREAM_TRI;
                    
                    cord_out <= {inst_ram[rd_inst_id].posx,  
                                inst_ram[rd_inst_id].posy,  
                                inst_ram[rd_inst_id].posz};
                                                            
                    agl_out  <= {inst_ram[rd_inst_id].rotx,  
                                inst_ram[rd_inst_id].roty,  
                                inst_ram[rd_inst_id].rotz};
                                                            
                    scale_out <= {inst_ram[rd_inst_id].scalex,
                                inst_ram[rd_inst_id].scaley,
                                inst_ram[rd_inst_id].scalez};
                end
                
                RC_STREAM_TRI: if(tri_ctr < curr_tri_count)begin
                    draw_valid <= '0;
                    vert_ctr   <= '0;
                    tri_addr   <= curr_tri_base + tri_ctr;
                    tri_ctr <= tri_ctr +1;
                    rc_state <= RC_STREAM_VERT;
                end else
                    rc_state <= RC_IDLE;
                    
                RC_STREAM_VERT: begin
                    draw_valid <= 1;
                
                    case (vert_ctr)
                        0: vert_addr <= curr_vert_base + idx_tri[VIDX_W-1:0];           // first vertex
                        1: vert_addr <= curr_vert_base + idx_tri[2*VIDX_W-1:VIDX_W];   // second vertex
                        2: vert_addr <= curr_vert_base + idx_tri[3*VIDX_W-1:2*VIDX_W]; // third vertex
                    endcase
                
                    if (vert_ctr < 2)
                        vert_ctr <= vert_ctr + 1;
                    else begin
                        vert_ctr <= '0;
                        rc_state <= RC_STREAM_TRI;
                    end
                end
            endcase
        end   
    end
    
    
endmodule
