`timescale 1ns / 1ps
`default_nettype wire
import opcode_defs::*;

module spi_driver #(
    parameter MAX_VERT  = 8192,     // 2^13 bit = 8192,
    parameter MAX_TRI   = 8192,     // 2^13 bit = 8192,
    parameter MAX_INST  = 256,      // Also used max vert and tri buffers
    parameter MAX_VERT_BUF = 256,   // maximum distinct vertex buffers
    parameter MAX_TRI_BUF  = 256,   // maximum distinct triangle buffers
    
    parameter MAX_VERT_CNT = 256,             // max vertices per buffer
    parameter MAX_TRI_CNT = 256,              // max triangles per buffer
    parameter VTX_W     = 108,                // 3*32 + 3*4 bits (spec)
    parameter VIDX_W    = $clog2(MAX_VERT_CNT), 
    parameter TIDX_W    = $clog2(MAX_TRI_CNT),   
    parameter TRI_W     = 3*VIDX_W,           // 3*8 bits. Might want to increase for safety 3*12 bits
    parameter DATA_W    = 32,
    parameter TRANS_W   = DATA_W * 9          // 9 floats
    )(
    
    // SPI interface pins
    input  logic sck,       // Serial clock
    input  logic rst,
    input  logic mosi_0,    // Maser out, slave in 1 through 4
    input  logic mosi_1,
    input  logic mosi_2,
    input  logic mosi_3,
    output logic miso,      // Master in, slave out
    input  logic CS_n,      // Chip select, active low
    
    // SPI packet interface (already de-serialized by SPI front-end)
    output logic        opcode_valid,
    output logic [3:0]  opcode,

    output logic  vert_hdr_valid,    // Opcode: Create vert chosen
    output logic  vert_valid,        // next vertex ready for buffer
    output logic [VTX_W-1:0] vert_out,
    output logic [$clog2(MAX_VERT)-1:0]   vert_base,
    output logic [VIDX_W-1:0]             vert_count,

    output logic  tri_hdr_valid,
    output logic  tri_valid,
    output logic [TRI_W-1:0] tri_out,
    output logic [$clog2(MAX_TRI)-1:0]    tri_base,
    output logic [TIDX_W-1:0]             tri_count,

    // SPI link --> raster memory
    output logic  inst_valid, inst_id_valid,
    output logic [VIDX_W-1:0]  vert_id_out,
    output logic [TIDX_W-1:0]  tri_id_out,
    output logic [TRANS_W-1:0] transform_out,
    output logic [7:0] inst_id_out,
    
    // Memory → SPI driver
    input  logic [3:0]  status
    );
    
    // SPI buffer resources
    logic [3:0] bit_ctr;                            // need to count up to staus (4) or IDs (8)
    (*keep="true"*) logic [7:0] next_inst_id, next_vert_id, next_tri_id;  // force keep due to synth optimization
    logic miso_r;
        
    logic [3:0] nybble;
    logic [$clog2(TRANS_W/4):0] nbl_ctr;   // Nybble counter, need to be able to count to 288 bit
    logic [$clog2(MAX_VERT)-1:0] vert_ctr;
    logic [$clog2(MAX_TRI)-1:0]  tri_ctr;
    logic mosi_flag;
    
    enum logic [3:0] {
    IDLE, LOAD_OP, WIPE_ALL, STATUS_OUT,
    LOAD_VERT_COUNT, CREATE_VERT, CREATE_VERT_RESULT,
    LOAD_TRI_COUNT, CREATE_TRI, CREATE_TRI_RESULT,
    LOAD_INST_DATA, CREATE_INST, CREATE_INST_RESULT,
    LOAD_UPDATE_INST, UPDATE_INST} spi_state;
    
    always_ff @(posedge sck) begin
        opcode_valid <= 0;
        if(rst) begin
            vert_ctr      <= 0;
            tri_ctr       <= 0;
            nbl_ctr       <= 0;
            next_inst_id  <= 1; // 0 reserved for camera
            next_vert_id  <= 0;
            next_tri_id   <= 0;
            vert_base     <= 0;
            tri_base      <= 0;
            spi_state <= LOAD_OP;
        end else begin 
            if(!CS_n) begin
                case(spi_state)
                    LOAD_OP: begin
                        vert_valid <= 0;
                        tri_valid  <= 0;
                        vert_hdr_valid <= 0;
                        tri_hdr_valid  <= 0;
                        inst_valid   <= 0;
                        inst_id_valid <= 0;
                        nbl_ctr  <= 0;
                        opcode <= {mosi_3, mosi_2, mosi_1, mosi_0};
                        opcode_valid <= 1;
                        if(OP_CREATE_VERT == {mosi_3, mosi_2, mosi_1, mosi_0}) spi_state <= LOAD_VERT_COUNT;
                        else if(OP_CREATE_TRI  == {mosi_3, mosi_2, mosi_1, mosi_0}) spi_state <= LOAD_TRI_COUNT;
                        else if(OP_CREATE_INST == {mosi_3, mosi_2, mosi_1, mosi_0}) spi_state <= LOAD_INST_DATA;
                        else if(OP_UPDATE_INST == {mosi_3, mosi_2, mosi_1, mosi_0}) spi_state <= LOAD_UPDATE_INST;
                        else begin
                            opcode_valid <= 0;
                        end
                    end
                    
                    LOAD_VERT_COUNT: begin
                        if(nbl_ctr < VIDX_W/4-1) begin
                            vert_count <= {vert_count[VIDX_W-5:0], mosi_3, mosi_2, mosi_1, mosi_0};
                            nbl_ctr   <= nbl_ctr +1;
                        end else if (nbl_ctr == VIDX_W/4-1) begin
                            vert_count <= {vert_count[VIDX_W-5:0], mosi_3, mosi_2, mosi_1, mosi_0};
                            vert_base  <= vert_base + {vert_count[VIDX_W-5:0], mosi_3, mosi_2, mosi_1, mosi_0};
                            vert_hdr_valid <= 1;
                            nbl_ctr    <= 0;
                            spi_state  <= CREATE_VERT;
                        end
                    end
                    
                    CREATE_VERT: begin
                        // Check if all nybbles are loaded
                        if(nbl_ctr == (VTX_W/4)-1) begin
                            vert_out  <= {vert_out[VTX_W-5:0], mosi_3, mosi_2, mosi_1, mosi_0};
                            vert_valid <= 1; // Next vertex ready for loading
                            nbl_ctr   <= 0;
                            
                            // Check if we have all vetice for the buffer
                            if(vert_ctr ==  vert_count-1) begin
                                spi_state <= CREATE_VERT_RESULT;
                                vert_ctr <= 0;      
                                vert_id_out <= next_vert_id;
                                next_vert_id <= next_vert_id + 1;
                            end else begin
                                vert_ctr <= vert_ctr +1;
                            end
                            
                        // Sift vertex and increment counter
                        end else begin
                            nbl_ctr <= nbl_ctr +1;
                            vert_valid <= 0;
                            vert_out <= {vert_out[VTX_W-5:0], mosi_3, mosi_2, mosi_1, mosi_0};
                        end
                    end
                    
                    
                    LOAD_TRI_COUNT: begin
                        if(nbl_ctr < TIDX_W/4-1) begin
                            tri_count <= {tri_count[TIDX_W-5:0], mosi_3, mosi_2, mosi_1, mosi_0};
                            nbl_ctr   <= nbl_ctr +1;
                        end else if (nbl_ctr == TIDX_W/4-1) begin
                            tri_count <= {tri_count[TIDX_W-5:0], mosi_3, mosi_2, mosi_1, mosi_0};
                            tri_base  <= tri_base + {tri_count[TIDX_W-5:0], mosi_3, mosi_2, mosi_1, mosi_0};
                            tri_hdr_valid <= 1;
                            nbl_ctr    <= 0;
                            spi_state  <= CREATE_TRI;
                        end
                    end
                    
                    
                    CREATE_TRI: begin
                        if (nbl_ctr == (TRI_W/4)-1) begin
                            tri_out <= {tri_out[TRI_W-5:0], mosi_3, mosi_2, mosi_1, mosi_0};
                            tri_valid <= 1;
                            nbl_ctr <= 0;
                    
                            if (tri_ctr == tri_count-1) begin 
                                spi_state <= CREATE_TRI_RESULT;
                                tri_ctr <= 0;                            
                                tri_id_out <= next_tri_id;
                                next_tri_id <= next_tri_id + 1;
                            end else begin
                                tri_ctr <= tri_ctr + 1;
                            end
                            
                        end else begin
                            nbl_ctr <= nbl_ctr + 1;
                            tri_valid <= 0;
                            tri_out <= {tri_out[TRI_W-5:0], mosi_3, mosi_2, mosi_1, mosi_0};
                        end
                    end
                    
                    // Each ID is 8 bit so first two is loeaded into vert_id and last to into tri_id
                    LOAD_INST_DATA: begin
                        if (nbl_ctr < 2) begin
                            vert_id_out <= {vert_id_out[3:0], mosi_3, mosi_2, mosi_1, mosi_0};
                            nbl_ctr <= nbl_ctr +1;
                        end else if(nbl_ctr == 3) begin
                            tri_id_out <= {tri_id_out[3:0], mosi_3, mosi_2, mosi_1, mosi_0};
                            nbl_ctr <= nbl_ctr +1;
                        end else begin
                            tri_id_out <= {tri_id_out[3:0], mosi_3, mosi_2, mosi_1, mosi_0};
                            nbl_ctr    <= 0;
                            spi_state <= CREATE_INST;
                        end
                    end
                    CREATE_INST: begin
                        if (nbl_ctr == (TRANS_W/4)-1) begin
                            transform_out <= {transform_out[TRANS_W-5:0], mosi_3, mosi_2, mosi_1, mosi_0};
                            inst_valid <= 1;
                            inst_id_out <= next_inst_id;
                            next_inst_id <= next_inst_id + 1;
                            nbl_ctr <= 0;
                            spi_state  <= CREATE_INST_RESULT;
                        end else begin
                            nbl_ctr <= nbl_ctr +1;
                            transform_out <= {transform_out[TRANS_W-5:0], mosi_3, mosi_2, mosi_1, mosi_0};
                        end
                    end
                    LOAD_UPDATE_INST: begin
                        if (nbl_ctr < 2) begin
                            inst_id_out <= {inst_id_out[3:0], mosi_3, mosi_2, mosi_1, mosi_0};
                        end else begin
                            inst_id_out <= {inst_id_out[3:0], mosi_3, mosi_2, mosi_1, mosi_0};
                            nbl_ctr    <= 0;
                            inst_id_valid <= 1;
                            spi_state <= UPDATE_INST;
                        end
                    end
                    UPDATE_INST: begin
                        if (nbl_ctr == (TRANS_W/4)-1) begin
                            transform_out <= {transform_out[TRANS_W-5:0], mosi_3, mosi_2, mosi_1, mosi_0};
                            inst_valid <= 1;
                            nbl_ctr <= 0;
                            spi_state  <= STATUS_OUT;
                        end else begin
                            nbl_ctr <= nbl_ctr +1;
                            transform_out <= {transform_out[TRANS_W-5:0], mosi_3, mosi_2, mosi_1, mosi_0};
                        end
                    end

                    CREATE_VERT_RESULT,
                    CREATE_TRI_RESULT,
                    CREATE_INST_RESULT: begin
                        vert_valid <= 0;
                        tri_valid  <= 0;
                        inst_valid <= 0;
                        if(mosi_flag)
                            spi_state <= STATUS_OUT;
                    end

                    STATUS_OUT: begin
                        if(mosi_flag)  
                            spi_state <= LOAD_OP;
                    end
                endcase
            end
        end
    end
        
    always_ff @(negedge sck) begin
        if (rst) begin
            miso_r  <= 0;
            bit_ctr <= 0;
            mosi_flag <= 0;
        end else if (!CS_n) begin
            mosi_flag <= 0; // default

            case (spi_state)
                CREATE_VERT_RESULT: begin
                    miso_r <= vert_id_out[bit_ctr];
                    if (bit_ctr == 7) begin
                        bit_ctr <= 0;
                        mosi_flag <= 1; // signal done to posedge FSM
                    end else bit_ctr <= bit_ctr + 1;
                end

                CREATE_TRI_RESULT: begin
                    miso_r <= tri_id_out[bit_ctr];
                    if (bit_ctr == 7) begin
                        bit_ctr <= 0;
                        mosi_flag <= 1;
                    end else bit_ctr <= bit_ctr + 1;
                end

                CREATE_INST_RESULT: begin
                    miso_r <= inst_id_out[bit_ctr];
                    if (bit_ctr == 7) begin
                        bit_ctr <= 0;
                        mosi_flag <= 1;
                    end else bit_ctr <= bit_ctr + 1;
                end

                STATUS_OUT: begin
                    miso_r <= status[bit_ctr];
                    if (bit_ctr == 3) begin
                        bit_ctr <= 0;
                        mosi_flag <= 1;
                    end else bit_ctr <= bit_ctr + 1;
                end
            endcase
        end
    end

    assign miso = miso_r;
    
endmodule
