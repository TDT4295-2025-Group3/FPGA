`timescale 1ns / 1ps
`default_nettype none
import opcode_defs::*;
import buffer_id_pkg::*;
import vertex_pkg::*;

module tb_top_raster_system;
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
    logic clk_100m;
    logic sck;
    logic rst_n;

    // SPI signals
    logic CS_n;
    wire  [3:0] spi_io;
    logic [3:0] spi_drive;
    logic       spi_de;
    assign spi_io = spi_de ? spi_drive : 4'bz;
    
    // test ports
    logic [7:0] vert_id;
    logic [3:0] spi_status_test;
    logic [3:0] error_status_test;
    logic output_bit;

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
        .clk_100m(clk_100m),
        .sck(sck),
        .rst_n(rst_n),
        .CS_n(CS_n),
        .spi_io(spi_io),
        
        .vert_id(vert_id),
        .spi_status_test(spi_status_test),
        .error_status_test(error_status_test),
        .output_bit(output_bit)
    );

    // Clock generation
    initial clk_100m = 0;
    always #5 clk_100m = ~clk_100m;  // 100 MHz

    initial sck = 0;
    always #50 sck = ~sck; // 10 MHz SPI clock

    
    // === Reset ===
    initial begin
        rst_n  = 0;
        CS_n   = 1;
        spi_de = 0;
        spi_drive = 0;
        #20; 
        rst_n = 1;
        #6200; // wait for clock lock
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
    
    task spi_return_status();
        repeat (2) @(posedge sck);
        CS_n = 1;
    endtask

    // === Example SPI sequence ===
    task run_sequence();
        begin
            // CREATE_VERT test
            spi_send_opcode(OP_CREATE_VERT);
            // Send vertex count
            spi_send_nybble(4'h0);
            spi_send_nybble(4'h3);

            // Send dummy vertex data (just 108 bits = 27 nybbles, 8*3 points + 3 colour)
            // vert 0 pos (0,0,0)
            repeat (8) spi_send_nybble(0);
            repeat (8) spi_send_nybble(0);
            repeat (8) spi_send_nybble(0);
            repeat (3) spi_send_nybble(4'hA);
            // vert 1 pos (0,2,0)
            repeat (8) spi_send_nybble(0);
            repeat (3) spi_send_nybble(0);
            repeat (1) spi_send_nybble(2);
            repeat (4) spi_send_nybble(0);
            repeat (8) spi_send_nybble(0);
            repeat (3) spi_send_nybble(4'hB);
            // vert 2 pos (0,0,2)
            repeat (8) spi_send_nybble(0);
            repeat (8) spi_send_nybble(0);
            repeat (3) spi_send_nybble(0);
            repeat (1) spi_send_nybble(2);
            repeat (4) spi_send_nybble(0);
            repeat (3) spi_send_nybble(4'hC);
//            // vert 3 pos (a,0,0)
//            repeat (3) spi_send_nybble(0);
//            repeat (1) spi_send_nybble(4'hA);
//            repeat (4) spi_send_nybble(0);
//            repeat (8) spi_send_nybble(0);
//            repeat (8) spi_send_nybble(0);
//            repeat (3) spi_send_nybble(4'hD);
//            // vert 4 pos (1,1,1)
//            repeat (3) spi_send_nybble(0);
//            repeat (1) spi_send_nybble(4'h1);
//            repeat (4) spi_send_nybble(0);
//            repeat (3) spi_send_nybble(0);
//            repeat (1) spi_send_nybble(4'h1);
//            repeat (4) spi_send_nybble(0);
//            repeat (3) spi_send_nybble(0);
//            repeat (1) spi_send_nybble(4'h1);
//            repeat (4) spi_send_nybble(0);
//            repeat (3) spi_send_nybble(4'hE);
            
            spi_return_result();

            // CREATE_TRI test
            // send tri count
            spi_send_opcode(OP_CREATE_TRI);
            spi_send_nybble(4'h0);
            spi_send_nybble(4'h1);  
            
            // send triangle data
            // Tri 0
            spi_send_nybble(4'h0);
            spi_send_nybble(4'h0); // vert 0
            spi_send_nybble(4'h0);
            spi_send_nybble(4'h1); // vert 1
            spi_send_nybble(4'h0);
            spi_send_nybble(4'h2); // vert 2
//            // Tri 1
//            spi_send_nybble(4'h0);
//            spi_send_nybble(4'h3); // vert 3
//            spi_send_nybble(4'h0);
//            spi_send_nybble(4'h1); // vert 1
//            spi_send_nybble(4'h0);
//            spi_send_nybble(4'h2); // vert 2
//            // Tri 2
//            spi_send_nybble(4'h0);
//            spi_send_nybble(4'h0); // vert 0
//            spi_send_nybble(4'h0);
//            spi_send_nybble(4'h2); // vert 2
//            spi_send_nybble(4'h0);
//            spi_send_nybble(4'h4); // vert 4
            
            // finish Sending tri data
            spi_return_result();            
            
            // Update camera transform to no rotation 
            // q16_16 numbers
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
            // update inst doesn't really need this long of a wait
            spi_return_status();   
            
            // CREATE_INST test
            spi_send_opcode(OP_CREATE_INST);
            repeat (2) spi_send_nybble(4'h0);   // Vert id
            repeat (2) spi_send_nybble(4'h0);   // tri id
            // Transform 32*3*4 = 384 (32 bit: pos, sin, cos, scale)
            // no rotation transform
            // Pos 32*3/4 = 24
            repeat (24) spi_send_nybble(4'h0); 
            // sin (0,0,0)
            repeat (8) spi_send_nybble(4'h0); 
            repeat (8) spi_send_nybble(4'h0); 
            repeat (8) spi_send_nybble(4'h0); 
            // cos(1,1,1)
            // cos_x 
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
            // scale (1,1,1)
            repeat (3) spi_send_nybble(4'h0); 
            repeat (1) spi_send_nybble(4'h1);
            repeat (4) spi_send_nybble(4'h0); 
            repeat (3) spi_send_nybble(4'h0); 
            repeat (1) spi_send_nybble(4'h2);
            repeat (4) spi_send_nybble(4'h0); 
            repeat (3) spi_send_nybble(4'h0); 
            repeat (1) spi_send_nybble(4'h3);
            repeat (4) spi_send_nybble(4'h0); 
            spi_return_result();

            // wait 60 cycles to monitor further pipeline
            repeat (60) @(posedge sck);
        end
    endtask

endmodule
