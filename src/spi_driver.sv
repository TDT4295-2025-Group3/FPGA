`timescale 1ns / 1ps
import opcode_defs::*;

module spi_driver #(
    localparam MAX_VERT  = 5000,
    localparam MAX_TRI   = 5000,
    localparam MAX_INST  = 256,      // Also used max vert and tri buffers
    localparam MAX_VERT_BUF = 256,   // maximum distinct vertex buffers
    localparam MAX_TRI_BUF  = 256,   // maximum distinct triangle buffers
    
    localparam MAX_VERT_CNT = 256,             // max vertices per buffer
    localparam MAX_TRI_CNT = 256,              // max triangles per buffer
    localparam VTX_W     = 108,                // 3*32 + 3*4 bits (spec)
    localparam VIDX_W    = $clog2(MAX_VERT_CNT), 
    localparam TIDX_W    = $clog2(MAX_TRI_CNT),   
    localparam TRI_W     = 3*VIDX_W,           // 3*8 bits. Might want to increase for safety 3*12 bits
    localparam DATA_W    = 32,
    localparam TRANS_W   = DATA_W * 9          // 9 floats
    )(
    
    // SPI interface pins
    input  logic sck,       // Serial clock
    input  logic rst,
    input  logic mosi_0,    // Maser out, slave in 1 through 4
    input  logic mosi_1,
    input  logic mosi_2,
    input  logic mosi_3,
    input  logic miso,      // Master in, slave out
    input  logic CS_n,      // Chip select, active low
    
    // SPI packet interface (already de-serialized by SPI front-end)
    output logic        opcode_valid,
    output logic [3:0]  opcode,

    output logic [11:0] num_verts,
    output logic [11:0] num_tris,

    output logic  vert_valid,             // Opcode: Create vert chosen
    output logic  next_vert_valid,        // next vertex ready for buffer
    output logic [VTX_W-1:0] vert_out,
    output logic [$clog2(MAX_VERT)-1:0]   vert_base,
    output logic [VIDX_W-1:0]             vert_count,

    output logic  tri_valid,
    output logic  next_tri_valid,
    output logic [TRI_W-1:0] tri_out,
    output logic [$clog2(MAX_TRI)-1:0]    tri_base,
    output logic [TIDX_W-1:0]             tri_count,

    // SPI link --> raster memory
    output logic  inst_valid,
    output logic [VIDX_W-1:0]  vert_id_out,
    output logic [TIDX_W-1:0]  tri_id_out,
    output logic [TRANS_W-1:0] transform_out,
    output logic [7:0]  inst_id_out,
    
    // FPGA memory → MCU
    input  logic [3:0]  status,
    input  logic [VIDX_W-1:0]  vert_id_in,
    input  logic [TIDX_W-1:0]  tri_id_in,
    input  logic [7:0]  inst_id_in
    );
    
    // SPI buffer resources
    logic [$clog2(MAX_VERT)-1:0] vert_base_ctr;
    logic [$clog2(MAX_TRI)-1:0]  tri_base_ctr;
    
    enum logic [3:0] {
    IDLE, LOAD_OP, WIPE_ALL, 
    LOAD_VERT_COUNT, CREATE_VERT, 
    LOAD_TRI_COUNT, CREATE_TRI, 
    LOAD_INST_DATA, CREATE_INST, 
    UPDATE_INST} spi_state;
    
    logic [3:0] nybble;
    logic [$clog2(VTX_W/4):0] nbl_ctr;            // Nybble counter, need to be able to count to 108 bit
    logic [$clog2(VTX_W)-1:0] vert_bit_ctr;
    logic [$clog2(TRI_W)-1:0] tri_bit_ctr;
    logic [$clog2(MAX_VERT)-1:0] vert_ctr;
    logic [$clog2(MAX_TRI)-1:0]  tri_ctr;
    
    always_ff @(posedge sck) begin
        opcode_valid <= 0;
        if(rst) begin
            vert_base_ctr <= 0;
            tri_base_ctr  <= 0;
            nbl_ctr       <= 0;
            spi_state <= LOAD_OP;
        end else begin 
            case(spi_state)
                LOAD_OP: if (!CS_n) begin
                    vert_bit_ctr <= 0;
                    tri_bit_ctr  <= 0;
                    next_vert_valid <= 0;
                    nbl_ctr  <= 0;
                    opcode <= {mosi_3, mosi_2, mosi_1, mosi_0};
                    opcode_valid <= 1;
                    if(OP_CREATE_VERT == {mosi_3, mosi_2, mosi_1, mosi_0}) spi_state <= LOAD_VERT_COUNT;
                    else if(OP_CREATE_TRI  == {mosi_3, mosi_2, mosi_1, mosi_0}) spi_state <= LOAD_TRI_COUNT;
                    else if(OP_CREATE_INST == {mosi_3, mosi_2, mosi_1, mosi_0}) spi_state <= CREATE_INST;
                    else if(OP_UPDATE_INST == {mosi_3, mosi_2, mosi_1, mosi_0}) spi_state <= UPDATE_INST;
                    else begin
                        opcode_valid <= 0;
                    end
                end
                
                LOAD_VERT_COUNT: begin
                    if(nbl_ctr < VIDX_W/4-1) begin
                        vert_count <= {vert_count[VIDX_W-1:4], mosi_3, mosi_2, mosi_1, mosi_0};
                        nbl_ctr   <= nbl_ctr +1;
                    end else if (nbl_ctr == VIDX_W/4-1) begin
                        vert_count <= {vert_count[VIDX_W-1:4], mosi_3, mosi_2, mosi_1, mosi_0};
                        vert_base  <= vert_base + vert_ctr;
                        spi_state  <= CREATE_VERT;
                        nbl_ctr    <= 0;
                    end
                end
                
                CREATE_VERT: begin
                    // Check if all nybbles are loaded
                    if(nbl_ctr == (VTX_W/4)-1) begin
                        vert_out  <= {vert_out[VTX_W-1:4], mosi_3, mosi_2, mosi_1, mosi_0};
                        next_vert_valid <= 1; // Next vertex ready for loading
                        nbl_ctr   <= 0;
                        
                        // Check if we have all vetice for the buffer
                        if(vert_ctr ==  vert_count) begin
                            spi_state <= LOAD_OP;
                        end else begin
                            vert_ctr <= vert_ctr +1;
                        end
                        
                    // Sift vertex and increment counter
                    end else begin
                        nbl_ctr <= nbl_ctr +1;
                        next_vert_valid <= 0;
                        vert_out <= {vert_out[VTX_W-1:4], mosi_3, mosi_2, mosi_1, mosi_0};
                    end
                end
                
                LOAD_TRI_COUNT: begin
                    if(nbl_ctr < TIDX_W/4-1) begin
                        tri_count <= {tri_count[TIDX_W-1:4], mosi_3, mosi_2, mosi_1, mosi_0};
                        nbl_ctr   <= nbl_ctr +1;
                    end else if (nbl_ctr == TIDX_W/4-1) begin
                        tri_count <= {tri_count[TIDX_W-1:4], mosi_3, mosi_2, mosi_1, mosi_0};
                        tri_base  <= tri_base + tri_ctr;
                        spi_state  <= CREATE_TRI;
                        nbl_ctr    <= 0;
                    end
                end
                
                
                CREATE_TRI: begin
                    if (nbl_ctr == (TRI_W/4)-1) begin
                        tri_out <= {tri_out[TRI_W-1:4], mosi_3, mosi_2, mosi_1, mosi_0};
                        next_tri_valid <= 1;
                        nbl_ctr <= 0;
                
                        if (tri_ctr == tri_count-1) begin 
                            spi_state <= LOAD_OP;
                        end else begin
                            tri_ctr <= tri_ctr + 1;
                        end
                        
                    end else begin
                        nbl_ctr <= nbl_ctr + 1;
                        next_tri_valid <= 1;
                        tri_out <= {tri_out[TRI_W-1:4], mosi_3, mosi_2, mosi_1, mosi_0};
                    end
                end
                
                // Each ID is 8 bit so first two is loeaded into vert_id and last to into tri_id
                LOAD_INST_DATA: begin
                    if (nbl_ctr < 2) begin
                        vert_id_out <= {vert_id_out[7:4], mosi_3, mosi_2, mosi_1, mosi_0};
                    end else if(nbl_ctr == 3) begin
                        tri_id_out <= {tri_id_out[7:4], mosi_3, mosi_2, mosi_1, mosi_0};
                    end else begin
                        tri_id_out <= {tri_id_out[7:4], mosi_3, mosi_2, mosi_1, mosi_0};
                        nbl_ctr    <= 0;
                        spi_state <= CREATE_INST;
                    end
                end
                CREATE_INST: begin
                    if (nbl_ctr == (TRANS_W/4)-1) begin
                        transform_out <= {transform_out[TRANS_W-1:4], mosi_3, mosi_2, mosi_1, mosi_0};
                        next_tri_valid <= 1;
                        nbl_ctr <= 0;
                        spi_state  <= CREATE_INST;
                    end
                end
            endcase
        end
    end
    
endmodule
