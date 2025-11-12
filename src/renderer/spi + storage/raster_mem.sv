// raster_mem_inferred_ram.sv
`timescale 1ns/1ps
`default_nettype wire
import buffer_id_pkg::*;
import vertex_pkg::*;

module raster_mem #(
    parameter MAX_VERT  = 8192,     // 2^13 bit = 8192, 
    parameter MAX_TRI   = 8192,     // 2^13 bit = 8192,
    parameter MAX_INST  = 256,      // maximum instences
    parameter MAX_VERT_BUF = 256,   // maximum distinct vertex buffers
    parameter MAX_TRI_BUF  = 256,   // maximum distinct triangle buffers
    parameter MAX_VERT_CNT = 4096,  // max vertices per buffer
    parameter MAX_TRI_CNT  = 4096,  // max triangles per buffer
    parameter VTX_W   = 108,
    parameter VIDX_W  = $clog2(MAX_VERT_CNT), 
    parameter TIDX_W  = $clog2(MAX_TRI_CNT),   
    parameter TRI_W   = 3*VIDX_W,
    parameter ID_W    = 8,
    parameter DATA_W  = 32,
    parameter TRANS_W = DATA_W * 12,
    parameter INST_W  = DATA_W * 12 + $clog2(MAX_VERT_BUF) + $clog2(MAX_TRI_BUF)
)(
    input  logic clk,
    input  logic rst_sck, rst_raster,
    input  logic sck,
    input  logic create_done,
    
    // Smooth clock flancs
    input  logic sck_rise_pulse,
    input  logic sck_fall_pulse,

    // SPI interface
    input  logic        opcode_valid,
    input  logic [3:0]  opcode,

    input  logic  vert_hdr_valid,
    input  logic  vert_valid,
    input  logic [VTX_W-1:0]  vert_in,
    input  logic [ID_W-1:0] vert_id_in,
    input  logic [$clog2(MAX_VERT)-1:0] vert_base,
    input  logic [VIDX_W-1:0] vert_count,

    input  logic  tri_hdr_valid,
    input  logic  tri_valid,
    input  logic [TRI_W-1:0] tri_in,
    input  logic [ID_W-1:0]  tri_id_in,
    input  logic [$clog2(MAX_TRI)-1:0] tri_base,
    input  logic [TIDX_W-1:0] tri_count,

    // Instance management
    input  logic  inst_valid,
    input  logic [TRANS_W-1:0] transform_in,
    input  logic [ID_W-1:0]         inst_id_in,

    // Frame driver access
    input  logic [$clog2(MAX_INST)-1:0] inst_id_rd,
    input  logic [$clog2(MAX_VERT)-1:0] vert_addr_rd,
    input  logic [$clog2(MAX_TRI)-1:0]  tri_addr_rd,

    output logic [$clog2(MAX_VERT)-1:0] curr_vert_base_out,
    output logic [VIDX_W-1:0]           curr_vert_count_out,
    output logic [$clog2(MAX_TRI)-1:0]  curr_tri_base_out,
    output logic [TIDX_W-1:0]           curr_tri_count_out,

    output logic [TRI_W-1:0]  idx_tri_out,
    output vertex_t           vert_out,
    output transform_t        transform_out
);

    // Vertex and Triangle RAM (infered)
    localparam VERT_ADDR_W = $clog2(MAX_VERT);
    localparam TRI_ADDR_W  = $clog2(MAX_TRI);

    logic [VERT_ADDR_W-1:0] vert_addr_wr;
    logic [VTX_W-1:0]       vert_din, vert_out_r;
    logic                   vert_we;
    logic                   vert_rise_we;

    logic [TRI_ADDR_W-1:0] tri_addr_wr;
    logic [TRI_W-1:0]      tri_din, tri_out_r;
    logic                  tri_we;
    logic                  tri_rise_we;

    assign vert_rise_we = vert_we && sck_rise_pulse;
    assign tri_rise_we  = tri_we  && sck_rise_pulse;
    (* ram_style = "block" *) logic [VTX_W-1:0] vertex_ram [0:MAX_VERT-1];
    (* ram_style = "block" *) logic [TRI_W-1:0]  tri_ram    [0:MAX_TRI-1];

    always_ff @(posedge sck) begin
        if (vert_rise_we) vertex_ram[vert_addr_wr] <= vert_din;
        if (tri_rise_we)  tri_ram[tri_addr_wr]   <= tri_din;
    end

    always_ff @(posedge clk) begin
        vert_out_r <= vertex_ram[vert_addr_rd];
        tri_out_r  <= tri_ram[tri_addr_rd];
    end

    // Instance RAM (instantiated)
    logic inst_we;
    logic inst_edge_we;
    logic [INST_W-1:0] inst_din;
    logic [INST_W-1:0] inst_dout_r;
    logic [INST_W-1:0] inst_dout_a;
    
    assign inst_edge_we = inst_we && sck_rise_pulse;

    xpm_memory_tdpram #(
        .MEMORY_SIZE        (MAX_INST * INST_W),
        .MEMORY_PRIMITIVE   ("block"),
        .CLOCKING_MODE      ("independent_clock"),
        .WRITE_DATA_WIDTH_A (INST_W),
        .READ_DATA_WIDTH_A  (INST_W),
        .WRITE_DATA_WIDTH_B (INST_W),
        .READ_DATA_WIDTH_B  (INST_W),
        .ADDR_WIDTH_A       ($clog2(MAX_INST)),
        .ADDR_WIDTH_B       ($clog2(MAX_INST)),
        .BYTE_WRITE_WIDTH_A (INST_W),
        .READ_LATENCY_A     (1),
        .READ_LATENCY_B     (1),
        .WRITE_MODE_A       ("write_first"),
        .WRITE_MODE_B       ("read_first")
    ) inst_ram (
        .clka   (sck),
        .rsta   (rst_sck),
        .ena    (1'b1),
        .wea    (inst_edge_we),
        .addra  (inst_id_in),
        .dina   (inst_din),
        .douta  (inst_dout_a),
        .clkb   (clk),
        .rstb   (rst_raster),
        .enb    (1'b1),
        .web    (1'b0),
        .addrb  (inst_id_rd),
        .dinb   ({INST_W{1'b0}}),
        .doutb  (inst_dout_r)
    );

    // Descriptor tables memroy
    logic [VERT_ADDR_W-1:0] vert_table_rd_addr;
    logic [TRI_ADDR_W-1:0]  tri_table_rd_addr;

    (* ram_style = "block" *) logic [VERT_ADDR_W+VIDX_W-1:0] vert_table_ram [0:MAX_VERT_BUF-1];
    (* ram_style = "block" *) logic [TRI_ADDR_W+TIDX_W-1:0]  tri_table_ram [0:MAX_TRI_BUF-1];

    // Write descriptors on sck
    always_ff @(posedge sck) begin
        if (vert_hdr_valid) vert_table_ram[vert_id_in] <= {vert_base, vert_count};
        if (tri_hdr_valid)  tri_table_ram[tri_id_in]   <= {tri_base, tri_count};
    end

    // Read descriptors in clk domain
    always_ff @(posedge clk) begin
        {curr_vert_base_out, curr_vert_count_out} <= vert_table_ram[vert_table_rd_addr];
        {curr_tri_base_out, curr_tri_count_out}   <= tri_table_ram[tri_table_rd_addr];
    end

    // Memory FSM
    logic [$clog2(MAX_VERT)-1:0] curr_vert_base;
    logic [VIDX_W-1:0]           curr_vert_count, vert_ctr;
    logic [$clog2(MAX_TRI)-1:0]  curr_tri_base;
    logic [TIDX_W-1:0]           curr_tri_count, tri_ctr;

    enum logic [2:0] {IDLE, 
    CREATE_VERT_HDR, CREATE_VERT_DATA, 
    CREATE_TRI_HDR, CREATE_TRI_DATA, 
    CREATE_INST, UPDATE_INST} mem_state;

    always_ff @(posedge sck or posedge rst_sck) begin
        if (rst_sck) begin
            vert_ctr  <= 0; tri_ctr <= 0;
            vert_we   <= 0; tri_we <= 0;
            inst_we   <= 0;
            curr_vert_base <= 0; curr_vert_count <= 0;
            curr_tri_base  <= 0; curr_tri_count  <= 0;
            vert_addr_wr <= 0; tri_addr_wr <= 0;
            inst_din <= 0;
            mem_state <= IDLE;
        end else if (sck_rise_pulse) begin
            if (opcode_valid) begin
                unique case (opcode)
                    4'b0001: mem_state <= CREATE_VERT_HDR;
                    4'b0010: mem_state <= CREATE_TRI_HDR;
                    4'b0011: mem_state <= CREATE_INST;
                    4'b0100: mem_state <= UPDATE_INST;
                endcase
            end

            case (mem_state)
                IDLE: begin
                    vert_we <= 0; tri_we <= 0; inst_we <= 0;
                end
                CREATE_VERT_HDR: if (vert_hdr_valid) begin
                    curr_vert_base  <= vert_base;
                    curr_vert_count <= vert_count;
                    vert_ctr        <= 0;
                    vert_addr_wr    <= vert_base;
                    mem_state       <= CREATE_VERT_DATA;
                end
                CREATE_VERT_DATA: begin
                    vert_we <= 0;
                    if (vert_valid && vert_ctr < curr_vert_count) begin
                        vert_din     <= vert_in;
                        vert_addr_wr <= curr_vert_base + vert_ctr;
                        vert_we      <= 1;
                        vert_ctr     <= vert_ctr + 1;
                    end else if (vert_ctr == curr_vert_count) mem_state <= IDLE;
                end
                CREATE_TRI_HDR: if (tri_hdr_valid) begin
                    curr_tri_base  <= tri_base;
                    curr_tri_count <= tri_count;
                    tri_ctr        <= 0;
                    tri_addr_wr    <= tri_base;
                    mem_state      <= CREATE_TRI_DATA;
                end
                CREATE_TRI_DATA: begin
                    tri_we <= 0;
                    if (tri_valid && tri_ctr < curr_tri_count) begin
                        tri_din     <= tri_in;
                        tri_addr_wr <= curr_tri_base + tri_ctr;
                        tri_we      <= 1;
                        tri_ctr     <= tri_ctr + 1;
                    end else if (tri_ctr == curr_tri_count) mem_state <= IDLE;
                end
                CREATE_INST: if (inst_valid) begin
                    inst_din <= {transform_in, vert_id_in, tri_id_in};
                    inst_we  <= 1;
                    mem_state <= IDLE;
                end
                UPDATE_INST: if (inst_valid) begin
                    inst_din <= {transform_in, vert_id_in, tri_id_in};
                    inst_we  <= 1;
                    mem_state <= IDLE;
                end
            endcase
        end
    end

    // =============================================
    // Outputs
    // =============================================
    assign vert_out    = vertex_t'(vert_out_r);
    assign idx_tri_out = tri_out_r;

    inst_t inst_cast;
    assign inst_cast = inst_t'(inst_dout_r);
    assign transform_out = transform_t'(inst_dout_r[TRANS_W+15:16]);

    // Descriptor outputs (synchronized)
    logic done_sync_0, done_sync_1;
    always_ff @(posedge clk or posedge rst_raster) begin
        if (rst_raster) begin
            done_sync_0 <= 0;
            done_sync_1 <= 0;
        end else begin
            done_sync_0 <= create_done;
            done_sync_1 <= done_sync_0;

            if (done_sync_1) begin
                vert_table_rd_addr <= inst_cast.vert_id;
                tri_table_rd_addr  <= inst_cast.tri_id;
            end
        end
    end

endmodule
