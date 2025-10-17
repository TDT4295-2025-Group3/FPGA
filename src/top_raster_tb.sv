`timescale 1ns / 1ps
`default_nettype none
import opcode_defs::*;
import buffer_id_pkg::*;
import vertex_pkg::*;
import transform_pkg::*;

module top_raster_tb;

    // Parameters
    localparam MAX_VERT  = 256;
    localparam MAX_TRI   = 256;
    localparam MAX_INST  = 256;
    localparam MAX_VERT_BUF = 256;
    localparam MAX_TRI_BUF  = 256;
    localparam MAX_VERT_CNT = 256;
    localparam MAX_TRI_CNT = 256;
    localparam VTX_W     = 108;
    localparam VIDX_W    = $clog2(MAX_VERT_CNT);
    localparam TIDX_W    = $clog2(MAX_TRI_CNT);
    localparam TRI_W     = 3*VIDX_W;
    localparam DATA_W    = 32;
    localparam TRANS_W   = DATA_W * 12;

    // Clock / reset
    logic clk;
    logic sck;
    logic rst;

    // SPI signals
    logic CS_n;
    wire  [3:0] spi_io;
    logic [3:0] spi_drive;
    logic       spi_de;
    assign spi_io = spi_de ? spi_drive : 4'bz;

    logic initial_load_done;
    triangle_t camera_triangle;

    // Instantiate DUT
    top_raster_system #(
        .MAX_VERT(MAX_VERT),
        .MAX_TRI(MAX_TRI),
        .MAX_INST(MAX_INST),
        .MAX_VERT_BUF(MAX_VERT_BUF),
        .MAX_TRI_BUF(MAX_TRI_BUF),
        .MAX_VERT_CNT(MAX_VERT_CNT),
        .MAX_TRI_CNT(MAX_TRI_CNT),
        .VTX_W(VTX_W),
        .VIDX_W(VIDX_W),
        .TIDX_W(TIDX_W),
        .TRI_W(TRI_W),
        .DATA_W(DATA_W),
        .TRANS_W(TRANS_W)
    ) dut (
        .clk(clk),
        .sck(sck),
        .rst(rst),
        .CS_n(CS_n),
        .spi_io(spi_io),
        
        .initial_load_done(initial_load_done),
        .camera_triangle(camera_triangle)
    );

    // Clock generation
    initial clk = 0;
    always #5 clk = ~clk;  // 100 MHz

    initial sck = 0;
    always #50 sck = ~sck; // 10 MHz SPI clock

    
    // === Reset ===
    initial begin
        initial_load_done = '0;
        rst    = 1;
        CS_n   = 1;
        spi_de = 0;
        spi_drive = 0;
        #100;
        rst = 0;
        #20;
        run_sequence();
        #2000;
        $finish;
    end

    // === SPI helpers ===
    task spi_send_nybble(input [3:0] val);
        begin
            @(negedge sck);
            CS_n = 0;
            spi_de = 1;
            spi_drive = val;
            @(posedge sck);
            spi_de = 0;
        end
    endtask

    task spi_send_opcode(input [3:0] opcode);
        begin
            repeat (8) spi_send_nybble(4'b0);
            spi_send_nybble(opcode);
        end
    endtask
    
    task spi_return_result();
        repeat (4) @(posedge sck);
        CS_n = 1;
    endtask

    // === Example SPI sequence ===
    task run_sequence();
        begin
            // CREATE_VERT test
            spi_send_opcode(OP_CREATE_VERT);
            // Send vertex count = 3 
            spi_send_nybble(4'h0);
            spi_send_nybble(4'h3);

            // Send dummy vertex data (just 108 bits = 27 nybbles)
            repeat (27) spi_send_nybble(4'hA); // Vert 0
            repeat (27) spi_send_nybble(4'hB); // Vert 1
            repeat (27) spi_send_nybble(4'hC); // Vert 2
            spi_return_result();

            // CREATE_TRI test
            // count = 1
            spi_send_opcode(OP_CREATE_TRI);
            spi_send_nybble(4'h0);
            spi_send_nybble(4'h1);  
            
            // send triangle data
            spi_send_nybble(4'h0);
            spi_send_nybble(4'h0);
            
            spi_send_nybble(4'h0);
            spi_send_nybble(4'h1);
            
            spi_send_nybble(4'h0);
            spi_send_nybble(4'h2);
            
            // finish Sending tri data
            spi_return_result();            
            
            // Update camera transform to no rotation
            // pos = (0, 0, 0)
            // sin = (0, 0, 0)
            // cos = (1, 1, 1)
            spi_send_opcode(OP_UPDATE_INST);
            repeat (2) spi_send_nybble(4'h0);   // inst 0 = camera
            // Pos 32*3/4 = 24
            repeat (24) spi_send_nybble(4'h0); 
            // sin = 24
            repeat (24) spi_send_nybble(4'h0); 
            // cos_x 32/4 = 8
            repeat (3) spi_send_nybble(4'h0); 
            repeat (1) spi_send_nybble(4'h1);
            repeat (4) spi_send_nybble(4'h0); 
            // cos_y
            repeat (3) spi_send_nybble(4'h0); 
            repeat (1) spi_send_nybble(4'h1);
            repeat (4) spi_send_nybble(4'h0); 
            // cos_z
            repeat (3) spi_send_nybble(4'h0); 
            repeat (1) spi_send_nybble(4'h1);
            repeat (4) spi_send_nybble(4'h0); 
            // scale = 24
            repeat (24) spi_send_nybble(4'h0);
            spi_return_result();   
            
            // CREATE_INST test
            spi_send_opcode(OP_CREATE_INST);
            repeat (2) spi_send_nybble(4'h0);   // Vert id
            repeat (2) spi_send_nybble(4'h0);   // tri id
            // Transform 96*4 = 384
            repeat (1) spi_send_nybble(4'hA); 
            repeat (94) spi_send_nybble(4'hB); 
            repeat (1) spi_send_nybble(4'hA);  
            
            spi_return_result();
            
            initial_load_done = 1'b1;
            repeat (20) @(posedge sck);
            initial_load_done = 1'b0;
            
            repeat (30) @(posedge clk);
        end
    endtask

endmodule
