`timescale 1ns/1ps
module raster_mem #(
    localparam MAX_VERT  = 5000,
    localparam MAX_TRI   = 5000,
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
    input  logic        clk,
    input  logic        rst,
    input  logic        sck,

    // SPI packet interface (already de-serialized by SPI front-end)
    input  logic        opcode_valid,
    input  logic [3:0]  opcode,

    input  logic [11:0] num_verts,
    input  logic [11:0] num_tris,

    input  logic  vert_valid,             // Opcode: Create vert chosen
    input  logic  next_vert_valid,        // next vertex ready for buffer
    input  logic [VTX_W-1:0] vert_in,
    input  logic [$clog2(MAX_VERT)-1:0]   vert_base,
    input  logic [VIDX_W-1:0]             vert_count,

    input  logic  tri_valid,
    input  logic  next_tri_valid,
    input  logic [TRI_W-1:0] tri_in,
    input  logic [$clog2(MAX_TRI)-1:0]    tri_base,
    input  logic [TIDX_W-1:0]             tri_count,

    // Create/Update instance
    input  logic  inst_valid,
    input  logic [VIDX_W-1:0]  vert_id_in,
    input  logic [TIDX_W-1:0]  tri_id_in,
    input  logic [TRANS_W-1:0] transform_in,
    input  logic [7:0]  inst_id_in,

    // FPGA → MCU
    output logic [3:0]  status,
    output logic [VIDX_W-1:0]  vert_id_out,
    output logic [TIDX_W-1:0]  tri_id_out,
    output logic [7:0]  inst_id_out,
    
    // Memory → Transform
    input  logic rd_en, 
    input  logic [7:0] rd_inst_id,
    output logic draw_valid,
    output logic [VTX_W-1:0] vert_out,
    output logic [DATA_W*3-1:0] cord_out,
    output logic [DATA_W*3-1:0] agl_out,
    output logic [DATA_W*3-1:0] scale_out
);

    // ---- ID counters ----
    logic [$clog2(MAX_INST)-1:0] next_vert_id, next_tri_id, next_inst_id;

    // ---- Memories ----
    logic [VTX_W-1:0] vertex_ram [MAX_VERT-1:0];
    logic [2:0][VIDX_W-1:0] tri_ram   [MAX_TRI-1:0];

    typedef struct packed {
        logic [DATA_W-1:0] posx,posy,posz;
        logic [DATA_W-1:0] rotx,roty,rotz;
        logic [DATA_W-1:0] scalex,scaley,scalez;
        logic [$clog2(MAX_VERT_BUF)-1:0] vert_id;
        logic [$clog2(MAX_VERT_BUF)-1:0] tri_id;
    } transform_t;
    
    typedef struct packed {
        logic [$clog2(MAX_VERT)-1:0]  base;
        logic [VIDX_W-1:0]            count;
    } vert_desc_t;
    
    typedef struct packed {
        logic [$clog2(MAX_TRI)-1:0]   base;
        logic [TIDX_W-1:0]            count;
    } tri_desc_t;
    
    vert_desc_t vert_table [MAX_INST];      // Descriptor table for each instance ID
    tri_desc_t  tri_table  [MAX_VERT_BUF];  // Descriptor tables 
    transform_t inst_ram   [MAX_TRI_BUF];   // used for each model  
    
    // FSM resources (current vertex/triagnle and counters)
    logic [$clog2(MAX_VERT)-1:0] curr_vert_base;
    logic [VIDX_W-1:0] curr_vert_count;
    logic [VIDX_W-1:0] vert_ctr;
    logic [$clog2(MAX_VERT)-1:0] vert_ram_addr;
    logic [VTX_W-1:0] vert_out_r;
    
    logic [$clog2(MAX_TRI)-1:0] curr_tri_base;
    logic [TIDX_W-1:0] curr_tri_count;
    logic [TIDX_W-1:0] tri_ctr;

    // ---- FSM ----
    enum logic [2:0] {IDLE, 
    CREATE_VERT_HDR, CREATE_VERT_DATA, 
    CREATE_TRI_HDR,  CREATE_TRI_DATA, 
    CREATE_INST, UPDATE_INST} 
    state;

    always_ff @(posedge sck or posedge rst) begin
        if (rst) begin
            next_vert_id <= 0;
            next_tri_id  <= 0;
            next_inst_id <= 1; // 0 reserved for camera
            vert_ctr     <= 0;
            tri_ctr      <= 0;
            state <= IDLE;
            status <= 4'b0000;
        end else begin
            if (opcode_valid) begin
                unique case(opcode)
                    4'b0000: begin // WIPE ALL
                        next_vert_id <= 0;
                        next_tri_id  <= 0;
                        next_inst_id <= 1;
                        status <= 4'b0000;
                    end
                    4'b0001: state <= CREATE_VERT_HDR;
                    4'b0010: state <= CREATE_TRI_HDR;
                    4'b0011: state <= CREATE_INST;
                    4'b0100: state <= UPDATE_INST;
                    default: status <= 4'b0011; // Invalid Opcode
                endcase
            end

            case(state)
                CREATE_VERT_HDR: if (vert_valid) begin
                    vert_table[next_vert_id].base  <= vert_base;
                    vert_table[next_vert_id].count <= vert_count;
                    curr_vert_base  <= vert_base;
                    curr_vert_count <= vert_count;
                    vert_id_out <= next_vert_id;
                    next_vert_id <= next_vert_id + 1;
                    vert_ctr <= 0;
                    state <= CREATE_VERT_DATA;
                end
                
                CREATE_VERT_DATA: begin
                    if (next_vert_valid && vert_ctr < curr_vert_count) begin
                        vertex_ram[curr_vert_base + vert_ctr] <= vert_in;
                        vert_ctr <= vert_ctr + 1;

                    end else if (vert_ctr == curr_vert_count) begin
                        status <= 4'b0000; // OK
                        state  <= IDLE;
                    end else if (vert_ctr > curr_vert_count) begin
                        status <= 4'b0010; // Invalid id
                        state  <= IDLE;
                    end
                end
                CREATE_TRI_HDR: if (vert_valid) begin
                    tri_table[next_tri_id].base <= tri_base;
                    tri_table[next_tri_id].count <= tri_count;
                    curr_tri_base  <= tri_base;
                    curr_tri_count <= tri_count;
                    tri_id_out  <= next_tri_id;
                    next_tri_id <= next_tri_id + 1;
                    tri_ctr <= 0;
                    state   <= CREATE_TRI_DATA;
                end
                
                CREATE_TRI_DATA: begin
                    if (next_tri_valid && tri_ctr < curr_tri_count) begin
                        tri_ram[curr_tri_base + tri_ctr][2] <= tri_in[3*VIDX_W-1:2*VIDX_W];
                        tri_ram[curr_tri_base + tri_ctr][1] <= tri_in[2*VIDX_W-1:VIDX_W];
                        tri_ram[curr_tri_base + tri_ctr][0] <= tri_in[VIDX_W-1:0];
                        tri_ctr <= tri_ctr + 1;
                    end else if (tri_ctr == curr_tri_count) begin
                        status <= 4'b0000; // OK
                        state  <= IDLE;
                    end else if (tri_ctr >= curr_tri_count) begin
                        status <= 4'b0010; // Invalid id
                        state  <= IDLE;
                    end
                end
                CREATE_INST: if(inst_valid) begin
                    inst_ram[next_inst_id] <= transform_in;
                    inst_ram[next_inst_id].vert_id <= vert_id_in;
                    inst_ram[next_inst_id].tri_id <= tri_id_in;
                    inst_id_out <= next_inst_id;
                    next_inst_id <= next_inst_id + 1;
                    status <= 4'b0000;
                    state  <= IDLE;
                end
                UPDATE_INST: if(inst_valid) begin
                    inst_ram[inst_id_in] <= transform_in;
                    status <= 4'b0000;
                    state  <= IDLE;
                end
            endcase
        end
    end
    
    enum logic [2:0] {RC_IDLE, RC_FETCH_DESC, RC_STREAM_VERT, RC_STREAM_TRI} rc_state; // Rasterdizer controller state
    logic [2:0][VIDX_W-1:0] curr_tri; 
    
    always_ff @(posedge sck or posedge rst) begin
        if(rst) begin
            rc_state <= RC_IDLE;
            tri_ctr    <= '0;
            draw_valid <= '0;
            curr_tri   <= '0;
            vert_ctr   <= '0;
        end else begin
            case(rc_state)
                RC_IDLE: if(rd_en) begin
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
                    curr_tri <= tri_ram[curr_tri_base + tri_ctr];
                    draw_valid <= '0;
                    vert_ctr  <= '0;
                    tri_ctr <= tri_ctr +1;
                    rc_state <= RC_STREAM_VERT;
                    vert_ram_addr <= vert_base + tri_ram[curr_tri_base + tri_ctr];
                end else
                    rc_state <= RC_IDLE;
                    
                RC_STREAM_VERT: begin
                    draw_valid <= 1;
                    vert_out_r <= vertex_ram[vert_ram_addr];

                    if(vert_ctr < 2)begin
                        vert_ram_addr <= vert_base + curr_tri[vert_ctr +1];
                        vert_ctr <= vert_ctr +1;
                    end else if(vert_ctr == 2) begin
                        vert_ctr <= '0;
                        rc_state <= RC_STREAM_TRI;
                    end
                end
            endcase
        end   
    end
    assign vert_out = vert_out_r;

endmodule