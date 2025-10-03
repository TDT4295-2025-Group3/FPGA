`timescale 1ns/1ps
`default_nettype wire
import buffer_id_pkg::*;
import vertex_pkg::*;


module raster_mem #(
    localparam MAX_VERT  = 256,      // 2^13 bit = 8192
    localparam MAX_TRI   = 256,      // 2^13 bit = 8192
    localparam MAX_INST  = 256,      // maximum model instances
    localparam MAX_VERT_BUF = 256,   // maximum distinct vertex buffers
    localparam MAX_TRI_BUF  = 256,   // maximum distinct triangle buffers
    
    localparam MAX_VERT_CNT = 256,             // max vertices per buffer
    localparam MAX_TRI_CNT = 256,              // max triangles per buffer
    localparam VTX_W     = 108,                // 3*32 + 3*4 bits (spec)
    localparam VIDX_W = $clog2(MAX_VERT_CNT), 
    localparam TIDX_W = $clog2(MAX_TRI_CNT),   
    localparam TRI_W     = 3*VIDX_W,           // 3*8 bits. Might want to increase for safety 3*12 bits
    localparam DATA_W    = 32,
    localparam TRANS_W   = DATA_W * 9,         // 9 floats
    localparam INST_W    = DATA_W * 9 + $clog2(MAX_VERT_BUF) + $clog2(MAX_TRI_BUF)  // 9 floats + vert/tri id
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
    input  logic [VTX_W-1:0]   vert_in,
    input  logic [VIDX_W-1:0]  vert_id_in,
    input  logic [$clog2(MAX_VERT)-1:0]   vert_base,
    input  logic [VIDX_W-1:0]             vert_count,

    input  logic  tri_valid,
    input  logic  next_tri_valid,
    input  logic [TRI_W-1:0]   tri_in,
    input  logic [TIDX_W-1:0]  tri_id_in,
    input  logic [$clog2(MAX_TRI)-1:0]    tri_base,
    input  logic [TIDX_W-1:0]             tri_count,

    // Create/Update instance
    input  logic  inst_valid,
    input  logic [TRANS_W-1:0] transform_in,
    input  logic [INST_W-1:0]  inst_in,
    input  logic [7:0]  inst_id_in,

    // FPGA → MCU
    output logic [3:0]  status,
    
    // Memory → Frame driver
    input  logic [$clog2(MAX_INST)-1:0] inst_id_rd,    // id is for model instance addr is for specifik vertex/tri
    input  logic [$clog2(MAX_VERT)-1:0] vert_addr_rd,
    input  logic [$clog2(MAX_TRI)-1:0]  tri_addr_rd,
    
    output logic [$clog2(MAX_VERT)-1:0]  curr_vert_base_out,
    output logic [VIDX_W-1:0]            curr_vert_count_out,
    output logic [$clog2(MAX_TRI)-1:0]   curr_tri_base_out,
    output logic [TIDX_W-1:0]            curr_tri_count_out,
    
    output logic [TRI_W-1:0] idx_tri_out,
    output vertex_t vert_out,
    output inst_t inst_out
    );

    // ---- Memories ----
    localparam VERT_ADDR_W = $clog2(MAX_VERT);
    logic [$clog2(MAX_VERT)-1:0] vert_addr_wr;
    logic [VTX_W-1:0] vert_out_r;
    logic [VTX_W-1:0] vert_din;
    logic vert_we;
    
    xpm_memory_tdpram #(
        .MEMORY_SIZE        (MAX_VERT * VTX_W),   // total bits
        .MEMORY_PRIMITIVE   ("block"),            // force BRAM
        .CLOCKING_MODE      ("independent_clock"),
        .WRITE_DATA_WIDTH_A (VTX_W),
        .READ_DATA_WIDTH_A  (VTX_W),
        .WRITE_DATA_WIDTH_B (VTX_W),
        .READ_DATA_WIDTH_B  (VTX_W),
        .ADDR_WIDTH_A       (VERT_ADDR_W),
        .ADDR_WIDTH_B       (VERT_ADDR_W),
        .BYTE_WRITE_WIDTH_A (VTX_W),              // must evenly divide
        .READ_LATENCY_A     (1),
        .READ_LATENCY_B     (1),
        .WRITE_MODE_A       ("write_first"),      // A = SPI writes
        .WRITE_MODE_B       ("read_first")        // B = rasterizer reads
    ) vertex_ram (
        // Port A = SPI write
        .clka   (sck),
        .rsta   (rst),
        .ena    (1'b1),
        .wea    (vert_we),        // write enable
        .addra  (vert_addr_wr),   // SPI write address
        .dina   (vert_din),        // SPI write data
        .douta  (),               // not used
    
        // Port B = Rasterizer read
        .clkb   (clk),
        .rstb   (rst),
        .enb    (1'b1),
        .web    (1'b0),           // no writes on B
        .addrb  (vert_addr_rd),   // rasterizer read address
        .dinb   ({VTX_W{1'b0}}),  // tie off
        .doutb  (vert_out_r)      // rasterizer read data
    );

    localparam TRI_ADDR_W = $clog2(MAX_TRI);
    logic [TRI_ADDR_W-1:0] tri_addr_wr;
    logic [TRI_W-1:0]      tri_out_r;
    logic [TRI_W-1:0]      tri_din;
    logic tri_we; 
    
    xpm_memory_tdpram #(
        .MEMORY_SIZE        (MAX_TRI * TRI_W),   // total bits
        .MEMORY_PRIMITIVE   ("block"),           
        .CLOCKING_MODE      ("independent_clock"),
        .WRITE_DATA_WIDTH_A (TRI_W),
        .READ_DATA_WIDTH_A  (TRI_W),
        .WRITE_DATA_WIDTH_B (TRI_W),
        .READ_DATA_WIDTH_B  (TRI_W),
        .ADDR_WIDTH_A       (TRI_ADDR_W),
        .ADDR_WIDTH_B       (TRI_ADDR_W),
        .BYTE_WRITE_WIDTH_A (TRI_W),             // must divide evenly
        .READ_LATENCY_A     (1),
        .READ_LATENCY_B     (1),
        .WRITE_MODE_A       ("write_first"),     // SPI writes
        .WRITE_MODE_B       ("read_first")       // rasterizer reads
    ) tri_ram (
        // Port A = SPI write
        .clka   (sck),
        .rsta   (rst),
        .ena    (1'b1),
        .wea    (tri_we),        // write enable from FSM
        .addra  (tri_addr_wr),   // SPI write address
        .dina   (tri_din),        // SPI triangle input
        .douta  (),              // unused
    
        // Port B = Rasterizer read
        .clkb   (clk),
        .rstb   (rst),
        .enb    (1'b1),
        .web    (1'b0),          // no writes on read port
        .addrb  (tri_addr_rd),   // rasterizer triangle read address
        .dinb   ({TRI_W{1'b0}}), // tie off
        .doutb  (tri_out_r)       // rasterizer triangle out
    );
    
    // signals for the instance RAM
    logic inst_we;                               // write enable (assert 1 cycle with data present)
    logic [INST_W-1:0] inst_din;                 // packed data to write
    logic [INST_W-1:0] inst_dout_r;              // packed data read (registered by XPM)
    logic [INST_W-1:0] inst_daout; 
    
    // instantiate XPM dual-port RAM (A = write port on sck, B = read port on clk)
    xpm_memory_tdpram #(
        .MEMORY_SIZE        (MAX_INST * INST_W),    // total bits (informational)
        .MEMORY_PRIMITIVE   ("block"),
        .CLOCKING_MODE      ("independent_clock"),
        .WRITE_DATA_WIDTH_A (INST_W),
        .READ_DATA_WIDTH_A  (INST_W),
        .WRITE_DATA_WIDTH_B (INST_W),
        .READ_DATA_WIDTH_B  (INST_W),
        .ADDR_WIDTH_A       ($clog2(MAX_INST)),
        .ADDR_WIDTH_B       ($clog2(MAX_INST)),
        .BYTE_WRITE_WIDTH_A (INST_W),               // whole word writes
        .READ_LATENCY_A     (1),
        .READ_LATENCY_B     (1),
        .WRITE_MODE_A       ("write_first"),
        .WRITE_MODE_B       ("read_first")
    ) inst_ram (
        // Port A - write side (SPI, sck)
        .clka   (sck),
        .rsta   (rst),
        .ena    (1'b1),
        .wea    (inst_we),          // single-bit or vector, XPM expects [WRITE_DATA_WIDTH_A/...] but for full-word use 1-bit bus may be OK
        .addra  (inst_id_in),       // From SPI driver
        .dina   (inst_din),
        .douta  (inst_daout),            
    
        // Port B - read side (raster/frame, clk)
        .clkb   (clk),
        .rstb   (rst),
        .enb    (1'b1),
        .web    (1'b0),
        .addrb  (inst_id_rd),
        .dinb   ({INST_W{1'b0}}),
        .doutb  (inst_dout_r)
        // many other optional ports exist (sleep, injectecc, etc) - leave unconnected
    );
    

    vert_desc_t vert_table [MAX_INST];      // Descriptor table for each instance ID
    tri_desc_t  tri_table  [MAX_VERT_BUF];  // Descriptor tables 
    
    // FSM resources (current vertex/triagnle and counters)
    logic [$clog2(MAX_VERT)-1:0] curr_vert_base;
    logic [VIDX_W-1:0] curr_vert_count;
    logic [VIDX_W-1:0] vert_ctr;
    
    logic [$clog2(MAX_TRI)-1:0] curr_tri_base;
    logic [TIDX_W-1:0] curr_tri_count;
    logic [TIDX_W-1:0] tri_ctr;
    
    // ---- FSM ----
    enum logic [2:0] {IDLE, 
    CREATE_VERT_HDR, CREATE_VERT_DATA, 
    CREATE_TRI_HDR,  CREATE_TRI_DATA, 
    CREATE_INST, UPDATE_INST} 
    state;

    always_ff @(posedge sck) begin
        if (rst) begin
            vert_ctr  <= 0;
            tri_ctr   <= 0;
            vert_we   <= 0;
            tri_we    <= 0;
            inst_we   <= 0;
            state <= IDLE;
            status <= 4'b0000;
        end else begin
            if (opcode_valid) begin
                unique case(opcode)
                    4'b0000: begin // WIPE ALL
                        status <= 4'b0000;  // Not developed XD
                    end
                    4'b0001: state <= CREATE_VERT_HDR;
                    4'b0010: state <= CREATE_TRI_HDR;
                    4'b0011: state <= CREATE_INST;
                    4'b0100: state <= UPDATE_INST;
                    default: status <= 4'b0011; // Invalid Opcode
                endcase
            end
            case(state)
                IDLE: begin
                    vert_we <= 0;
                    tri_we  <= 0;
                    inst_we <= 0;
                end
                CREATE_VERT_HDR: if (vert_valid) begin
                    vert_table[vert_id_in].base  <= vert_base;
                    vert_table[vert_id_in].count <= vert_count;
                    curr_vert_base  <= vert_base;
                    curr_vert_count <= vert_count;
                    vert_ctr <= 0;
                    vert_addr_wr <= curr_vert_base + vert_ctr;
                    state <= CREATE_VERT_DATA;
                end
                
                CREATE_VERT_DATA: begin
                    vert_we <= 0;
                    if (next_vert_valid && vert_ctr < curr_vert_count) begin
                        vert_din <= vert_in;
                        vert_we <= 1;
                        vert_addr_wr <= curr_tri_base + vert_ctr;
                        vert_ctr <= vert_ctr + 1;

                    end else if (vert_ctr == curr_vert_count) begin
                        status <= 4'b0000; // OK
                        state  <= IDLE;
                    end else if (vert_ctr > curr_vert_count) begin
                        status <= 4'b0010; // Invalid id
                        state  <= IDLE;
                    end
                end
                CREATE_TRI_HDR: if (tri_valid) begin
                    tri_table[tri_id_in].base  <= tri_base;
                    tri_table[tri_id_in].count <= tri_count;
                    curr_tri_base  <= tri_base;
                    curr_tri_count <= tri_count;
                    tri_ctr <= 0;
                    state   <= CREATE_TRI_DATA;
                    tri_addr_wr <= curr_tri_base + tri_ctr;
                end
                
                CREATE_TRI_DATA: begin
                    tri_we <= 0;
                    if (next_tri_valid && tri_ctr < curr_tri_count) begin
                        tri_din <= tri_in;
                        tri_we  <= 1;
                        tri_addr_wr <= curr_tri_base + tri_ctr;
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
                    inst_din  <= inst_in; 
                    inst_we   <= 1;
                    status <= 4'b0000;
                    state  <= IDLE;
                end
                UPDATE_INST: begin
                    if(inst_valid) begin 
                        inst_we   <= 1;
                        inst_din <= {transform_in, inst_daout[15:0]}; // transform + ids
                        status <= 4'b0000;
                        state  <= IDLE;
                    end
                end
            endcase
        end
    end
    
    
    assign vert_out    = vertex_t'(vert_out_r);
    assign idx_tri_out = tri_out_r;
    
    inst_t inst_cast;
    assign inst_cast  = inst_t'(inst_dout_r);
    assign inst_out    = inst_cast;
    assign curr_vert_base_out  = vert_table[inst_cast.vert_id].base;  
    assign curr_vert_count_out = vert_table[inst_cast.vert_id].count; 
    assign curr_tri_base_out   = tri_table[inst_cast.tri_id].base;
    assign curr_tri_count_out  = tri_table[inst_cast.tri_id].count;

endmodule