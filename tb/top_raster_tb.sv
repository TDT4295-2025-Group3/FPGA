`timescale 1ns / 1ps
`default_nettype none
import opcode_defs::*;
import buffer_id_pkg::*;
import vertex_pkg::*;

// Due to the fact i only get a sck from the mcu when recieving data i will have to time 
// most of the tests in accordance with how the quad spi work in stm32.
// Due to this CS_n is always asserted when there is a clock edge and thus will never
// be deserted in this test bench.
module tb_top_raster_system;
    // Parameters
    localparam MAX_VERT  = 256;
    localparam MAX_TRI   = 256;
    localparam MAX_INST  = 256;
//    localparam MAX_VERT_BUF = 256;
//    localparam MAX_TRI_BUF  = 256;
//    localparam MAX_VERT_CNT = 4096;  // max vertices per buffer  
//    localparam MAX_TRI_CNT  = 4096;  // max triangles per buffer 
//    localparam VTX_W     = 108;
//    localparam VIDX_W    = $clog2(MAX_VERT_CNT);
//    localparam TIDX_W    = $clog2(MAX_TRI_CNT);
//    localparam TRI_W     = 3*VIDX_W;
//    localparam DATA_W    = 32;
//    localparam TRANS_W   = DATA_W * 12;

    // Clock / reset
    logic clk_100m;
    logic sck;
    logic sck_en;
    logic rst_n;

    // SPI signals
    logic CS_n;
    wire  [3:0] spi_io;
    logic [3:0] spi_drive;
    logic       spi_de;
    assign spi_io = spi_de ? spi_drive : 4'bz;
    
    // test ports
    logic [7:0] red_1_2;
    logic [3:0] wait_ctr_out;
    logic [7:0] tri_id_out;
    logic [3:0] spi_status_test;
    logic [3:0] error_status_test;
    logic output_bit;

    // Instantiate DUT
    top_raster_system #(
        .MAX_VERT(MAX_VERT),
        .MAX_TRI(MAX_TRI),
        .MAX_INST(MAX_INST)
    ) dut (
        .clk_100m(clk_100m),
        .sck(sck),
        .rst_n(rst_n),
        .CS_n(CS_n),
        .spi_io(spi_io),
        
        .red_1_2(red_1_2),
//        .wait_ctr_out(wait_ctr_out),
//        .tri_id_out(tri_id_out),
        .spi_status_test(spi_status_test),
        .error_status_test(error_status_test),
        .output_bit(output_bit)
    );

    // Clock generation
    initial clk_100m = 0;
    always #5 clk_100m = ~clk_100m;  // 100 MHz

    initial sck = 0;
    initial sck_en = 0;
    always begin
        if (sck_en) begin
            #250; // 10MHz:100ns, 2MHz: 500ns 
            if (sck_en)
                sck = ~sck;
        end else begin
            @(posedge sck_en);
        end
    end
        
    // === Reset ===
    initial begin
        rst_n  = 1;
        CS_n   = 1;
        sck_en = 0;
        spi_de = 0;
        spi_drive = 0;
        #20; 
        rst_n = 0;
        #20;
        rst_n = 1;
        #8000; // wait for clock lock
        sck = 0;
        run_sequence();
        #2000;
        $finish;
    end

    // === SPI helpers ===
    task spi_send_nybble(input [3:0] val);
        begin
            @(negedge sck);
//            CS_n = 0;
//            spi_de = 1;
            spi_drive = val;
            @(posedge sck);
//            spi_de = 0;
        end
    endtask

    task spi_send_opcode(input [3:0] opcode);
        begin
            // Junk data will be sent (as if it were sending data to memory)
            // ready_ctr in count to 8 before CS_ready is asserted
            CS_n = 0;
            #100
            sck_en = 1;
            spi_de = 1;
            repeat (7) spi_send_nybble(4'b1010);
            spi_send_nybble(opcode);
        end
    endtask
    
    task spi_return_result();
        // wait for post junk data after read
        // here i will wait with wait_ctr
        repeat (1) @(negedge sck);
        spi_de = 0;
        repeat (3) @(posedge sck);
        #50
        sck_en = 0;
        sck    = 0;
        #100 // is this waiting included in  @(posedge sck_en);?
        CS_n = 1;
        // mcu is now finished with writing to the FPGA
        #500 // the time break between the mcu being ready to recieve data
        
        // start the proccess of sending back data
        CS_n = 0;
        #100
        sck_en = 1;
        spi_de = 1;
        // Junk data (ready_ctr incrementing here)
        repeat (7) spi_send_nybble(4'b1100);
        // Two padding nybbles for the spi pins to stabalise (idc just works better)
        repeat (2) spi_send_nybble(4'b0000);
        spi_de = 0;
        // id +2, status output +1: 3 cycles output
        repeat (3) @(posedge sck);
        // post junk data after writeback
        repeat (3) @(posedge sck);
        sck_en = 0;
        #50
        sck    = 0;
        #100
        CS_n = 1;
    endtask
    
    task spi_return_status();
        repeat (1) @(negedge sck);
        spi_de = 0;
        repeat (3) @(posedge sck);
        #50
        sck_en = 0;
        sck    = 0;
        #100 // is this waiting included in  @(posedge sck_en);?
        CS_n = 1;
        // mcu is now finished with writing to the FPGA
        #500 // the time break between the mcu being ready to recieve data
        
        // start the proccess of sending back data
        CS_n = 0;
        #100
        sck_en = 1;
        // Junk data (ready_ctr incrementing here)
        repeat (7) spi_send_nybble(4'b110);
        // status output +1: 1 cycle output
        repeat (1) @(posedge sck);
        // post junk data after writeback
        repeat (3) @(posedge sck);
        sck_en = 0;
        #50
        sck    = 0;
        #100
        CS_n = 1;
    endtask

    // === Example SPI sequence ===
    task run_sequence();
        begin
            // CREATE_VERT 1
            spi_send_opcode(OP_CREATE_VERT);
            // Send vertex count
            spi_send_nybble(4'h0);
            spi_send_nybble(4'h0);
            spi_send_nybble(4'h4);

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
            // vert 3 pos (a,0,0)
            repeat (3) spi_send_nybble(0);
            repeat (1) spi_send_nybble(4'hA);
            repeat (4) spi_send_nybble(0);
            repeat (8) spi_send_nybble(0);
            repeat (8) spi_send_nybble(0);
            repeat (3) spi_send_nybble(4'hD);
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
            
            // CREATE_VERT 2
            spi_send_opcode(OP_CREATE_VERT);
            // Send vertex count
            spi_send_nybble(4'h0);
            spi_send_nybble(4'h0);
            spi_send_nybble(4'h3);
            // vert 0 pos (0,0,0)
            repeat (8) spi_send_nybble(0);
            repeat (8) spi_send_nybble(4'hA);
            repeat (8) spi_send_nybble(0);
            repeat (3) spi_send_nybble(4'h1);
            // vert 1 pos (0,2,0)
            repeat (8) spi_send_nybble(0);
            repeat (3) spi_send_nybble(0);
            repeat (1) spi_send_nybble(4'hB);
            repeat (4) spi_send_nybble(0);
            repeat (8) spi_send_nybble(0);
            repeat (3) spi_send_nybble(4'h2);
            // vert 2 pos (0,0,2)
            repeat (8) spi_send_nybble(0);
            repeat (8) spi_send_nybble(0);
            repeat (3) spi_send_nybble(0);
            repeat (1) spi_send_nybble(4'hC);
            repeat (4) spi_send_nybble(0);
            repeat (3) spi_send_nybble(4'h3);
            spi_return_result();     
            
            // CREATE_VERT 3
            spi_send_opcode(OP_CREATE_VERT);
            // Send vertex count
            spi_send_nybble(4'h0);
            spi_send_nybble(4'h0);
            spi_send_nybble(4'h3);
            // vert 0 pos (0,0,0)
            repeat (8) spi_send_nybble(0);
            repeat (8) spi_send_nybble(4'hA);
            repeat (8) spi_send_nybble(0);
            repeat (3) spi_send_nybble(4'h1);
            // vert 1 pos (0,2,0)
            repeat (8) spi_send_nybble(0);
            repeat (3) spi_send_nybble(0);
            repeat (1) spi_send_nybble(4'hB);
            repeat (4) spi_send_nybble(0);
            repeat (8) spi_send_nybble(0);
            repeat (3) spi_send_nybble(4'h2);
            // vert 2 pos (0,0,2)
            repeat (8) spi_send_nybble(0);
            repeat (8) spi_send_nybble(0);
            repeat (3) spi_send_nybble(0);
            repeat (1) spi_send_nybble(4'hC);
            repeat (4) spi_send_nybble(0);
            repeat (3) spi_send_nybble(4'h3);
            spi_return_result();   
            
//            // CREATE_VERT 4
//            spi_send_opcode(OP_CREATE_VERT);
//            // Send vertex count
//            spi_send_nybble(4'h0);
//            spi_send_nybble(4'h0);
//            spi_send_nybble(4'h3);
//            // vert 0 pos (0,0,0)
//            repeat (8) spi_send_nybble(0);
//            repeat (8) spi_send_nybble(4'hA);
//            repeat (8) spi_send_nybble(0);
//            repeat (3) spi_send_nybble(4'h1);
//            // vert 1 pos (0,2,0)
//            repeat (8) spi_send_nybble(0);
//            repeat (3) spi_send_nybble(0);
//            repeat (1) spi_send_nybble(4'hB);
//            repeat (4) spi_send_nybble(0);
//            repeat (8) spi_send_nybble(0);
//            repeat (3) spi_send_nybble(4'h2);
//            // vert 2 pos (0,0,2)
//            repeat (8) spi_send_nybble(0);
//            repeat (8) spi_send_nybble(0);
//            repeat (3) spi_send_nybble(0);
//            repeat (1) spi_send_nybble(4'hC);
//            repeat (4) spi_send_nybble(0);
//            repeat (3) spi_send_nybble(4'h3);
//            spi_return_result();   
            
//            // CREATE_VERT 5
//            spi_send_opcode(OP_CREATE_VERT);
//            // Send vertex count
//            spi_send_nybble(4'h0);
//            spi_send_nybble(4'h0);
//            spi_send_nybble(4'h3);
//            // vert 0 pos (0,0,0)
//            repeat (8) spi_send_nybble(0);
//            repeat (8) spi_send_nybble(4'hA);
//            repeat (8) spi_send_nybble(0);
//            repeat (3) spi_send_nybble(4'h1);
//            // vert 1 pos (0,2,0)
//            repeat (8) spi_send_nybble(0);
//            repeat (3) spi_send_nybble(0);
//            repeat (1) spi_send_nybble(4'hB);
//            repeat (4) spi_send_nybble(0);
//            repeat (8) spi_send_nybble(0);
//            repeat (3) spi_send_nybble(4'h2);
//            // vert 2 pos (0,0,2)
//            repeat (8) spi_send_nybble(0);
//            repeat (8) spi_send_nybble(0);
//            repeat (3) spi_send_nybble(0);
//            repeat (1) spi_send_nybble(4'hC);
//            repeat (4) spi_send_nybble(0);
//            repeat (3) spi_send_nybble(4'h3);
//            spi_return_result();   
            
//            // CREATE_VERT 6
//            spi_send_opcode(OP_CREATE_VERT);
//            // Send vertex count
//            spi_send_nybble(4'h0);
//            spi_send_nybble(4'h0);
//            spi_send_nybble(4'h3);
//            // vert 0 pos (0,0,0)
//            repeat (8) spi_send_nybble(0);
//            repeat (8) spi_send_nybble(4'hA);
//            repeat (8) spi_send_nybble(0);
//            repeat (3) spi_send_nybble(4'h1);
//            // vert 1 pos (0,2,0)
//            repeat (8) spi_send_nybble(0);
//            repeat (3) spi_send_nybble(0);
//            repeat (1) spi_send_nybble(4'hB);
//            repeat (4) spi_send_nybble(0);
//            repeat (8) spi_send_nybble(0);
//            repeat (3) spi_send_nybble(4'h2);
//            // vert 2 pos (0,0,2)
//            repeat (8) spi_send_nybble(0);
//            repeat (8) spi_send_nybble(0);
//            repeat (3) spi_send_nybble(0);
//            repeat (1) spi_send_nybble(4'hC);
//            repeat (4) spi_send_nybble(0);
//            repeat (3) spi_send_nybble(4'h3);
//            spi_return_result();   
            
//            // CREATE_VERT 7
//            spi_send_opcode(OP_CREATE_VERT);
//            // Send vertex count
//            spi_send_nybble(4'h0);
//            spi_send_nybble(4'h0);
//            spi_send_nybble(4'h3);
//            // vert 0 pos (0,0,0)
//            repeat (8) spi_send_nybble(0);
//            repeat (8) spi_send_nybble(4'hA);
//            repeat (8) spi_send_nybble(0);
//            repeat (3) spi_send_nybble(4'h1);
//            // vert 1 pos (0,2,0)
//            repeat (8) spi_send_nybble(0);
//            repeat (3) spi_send_nybble(0);
//            repeat (1) spi_send_nybble(4'hB);
//            repeat (4) spi_send_nybble(0);
//            repeat (8) spi_send_nybble(0);
//            repeat (3) spi_send_nybble(4'h2);
//            // vert 2 pos (0,0,2)
//            repeat (8) spi_send_nybble(0);
//            repeat (8) spi_send_nybble(0);
//            repeat (3) spi_send_nybble(0);
//            repeat (1) spi_send_nybble(4'hC);
//            repeat (4) spi_send_nybble(0);
//            repeat (3) spi_send_nybble(4'h3);
//            spi_return_result();   
            
//            // CREATE_VERT 8
//            spi_send_opcode(OP_CREATE_VERT);
//            // Send vertex count
//            spi_send_nybble(4'h0);
//            spi_send_nybble(4'h0);
//            spi_send_nybble(4'h3);
//            // vert 0 pos (0,0,0)
//            repeat (8) spi_send_nybble(0);
//            repeat (8) spi_send_nybble(4'hA);
//            repeat (8) spi_send_nybble(0);
//            repeat (3) spi_send_nybble(4'h1);
//            // vert 1 pos (0,2,0)
//            repeat (8) spi_send_nybble(0);
//            repeat (3) spi_send_nybble(0);
//            repeat (1) spi_send_nybble(4'hB);
//            repeat (4) spi_send_nybble(0);
//            repeat (8) spi_send_nybble(0);
//            repeat (3) spi_send_nybble(4'h2);
//            // vert 2 pos (0,0,2)
//            repeat (8) spi_send_nybble(0);
//            repeat (8) spi_send_nybble(0);
//            repeat (3) spi_send_nybble(0);
//            repeat (1) spi_send_nybble(4'hC);
//            repeat (4) spi_send_nybble(0);
//            repeat (3) spi_send_nybble(4'h3);
//            spi_return_result();       
            
//            // CREATE_VERT 9
//            spi_send_opcode(OP_CREATE_VERT);
//            // Send vertex count
//            spi_send_nybble(4'h0);
//            spi_send_nybble(4'h0);
//            spi_send_nybble(4'h3);
//            // vert 0 pos (0,0,0)
//            repeat (8) spi_send_nybble(0);
//            repeat (8) spi_send_nybble(4'hA);
//            repeat (8) spi_send_nybble(0);
//            repeat (3) spi_send_nybble(4'h1);
//            // vert 1 pos (0,2,0)
//            repeat (8) spi_send_nybble(0);
//            repeat (3) spi_send_nybble(0);
//            repeat (1) spi_send_nybble(4'hB);
//            repeat (4) spi_send_nybble(0);
//            repeat (8) spi_send_nybble(0);
//            repeat (3) spi_send_nybble(4'h2);
//            // vert 2 pos (0,0,2)
//            repeat (8) spi_send_nybble(0);
//            repeat (8) spi_send_nybble(0);
//            repeat (3) spi_send_nybble(0);
//            repeat (1) spi_send_nybble(4'hC);
//            repeat (4) spi_send_nybble(0);
//            repeat (3) spi_send_nybble(4'h3);
//            spi_return_result();           
            
//            // CREATE_VERT 10
//            spi_send_opcode(OP_CREATE_VERT);
//            // Send vertex count
//            spi_send_nybble(4'h0);
//            spi_send_nybble(4'h0);
//            spi_send_nybble(4'h3);
//            // vert 0 pos (0,0,0)
//            repeat (8) spi_send_nybble(0);
//            repeat (8) spi_send_nybble(4'hA);
//            repeat (8) spi_send_nybble(0);
//            repeat (3) spi_send_nybble(4'h1);
//            // vert 1 pos (0,2,0)
//            repeat (8) spi_send_nybble(0);
//            repeat (3) spi_send_nybble(0);
//            repeat (1) spi_send_nybble(4'hB);
//            repeat (4) spi_send_nybble(0);
//            repeat (8) spi_send_nybble(0);
//            repeat (3) spi_send_nybble(4'h2);
//            // vert 2 pos (0,0,2)
//            repeat (8) spi_send_nybble(0);
//            repeat (8) spi_send_nybble(0);
//            repeat (3) spi_send_nybble(0);
//            repeat (1) spi_send_nybble(4'hC);
//            repeat (4) spi_send_nybble(0);
//            repeat (3) spi_send_nybble(4'h3);
//            spi_return_result();        
            
//            // CREATE_VERT 11
//            spi_send_opcode(OP_CREATE_VERT);
//            // Send vertex count
//            spi_send_nybble(4'h0);
//            spi_send_nybble(4'h0);
//            spi_send_nybble(4'h3);
//            // vert 0 pos (0,0,0)
//            repeat (8) spi_send_nybble(0);
//            repeat (8) spi_send_nybble(4'hA);
//            repeat (8) spi_send_nybble(0);
//            repeat (3) spi_send_nybble(4'h1);
//            // vert 1 pos (0,2,0)
//            repeat (8) spi_send_nybble(0);
//            repeat (3) spi_send_nybble(0);
//            repeat (1) spi_send_nybble(4'hB);
//            repeat (4) spi_send_nybble(0);
//            repeat (8) spi_send_nybble(0);
//            repeat (3) spi_send_nybble(4'h2);
//            // vert 2 pos (0,0,2)
//            repeat (8) spi_send_nybble(0);
//            repeat (8) spi_send_nybble(0);
//            repeat (3) spi_send_nybble(0);
//            repeat (1) spi_send_nybble(4'hC);
//            repeat (4) spi_send_nybble(0);
//            repeat (3) spi_send_nybble(4'h3);
//            spi_return_result();        
            
//            // CREATE_VERT 12
//            spi_send_opcode(OP_CREATE_VERT);
//            // Send vertex count
//            spi_send_nybble(4'h0);
//            spi_send_nybble(4'h0);
//            spi_send_nybble(4'h3);
//            // vert 0 pos (0,0,0)
//            repeat (8) spi_send_nybble(0);
//            repeat (8) spi_send_nybble(4'hA);
//            repeat (8) spi_send_nybble(0);
//            repeat (3) spi_send_nybble(4'h1);
//            // vert 1 pos (0,2,0)
//            repeat (8) spi_send_nybble(0);
//            repeat (3) spi_send_nybble(0);
//            repeat (1) spi_send_nybble(4'hB);
//            repeat (4) spi_send_nybble(0);
//            repeat (8) spi_send_nybble(0);
//            repeat (3) spi_send_nybble(4'h2);
//            // vert 2 pos (0,0,2)
//            repeat (8) spi_send_nybble(0);
//            repeat (8) spi_send_nybble(0);
//            repeat (3) spi_send_nybble(0);
//            repeat (1) spi_send_nybble(4'hC);
//            repeat (4) spi_send_nybble(0);
//            repeat (3) spi_send_nybble(4'h3);
//            spi_return_result();        
            
//            // CREATE_VERT 13
//            spi_send_opcode(OP_CREATE_VERT);
//            // Send vertex count
//            spi_send_nybble(4'h0);
//            spi_send_nybble(4'h0);
//            spi_send_nybble(4'h3);
//            // vert 0 pos (0,0,0)
//            repeat (8) spi_send_nybble(0);
//            repeat (8) spi_send_nybble(4'hA);
//            repeat (8) spi_send_nybble(0);
//            repeat (3) spi_send_nybble(4'h1);
//            // vert 1 pos (0,2,0)
//            repeat (8) spi_send_nybble(0);
//            repeat (3) spi_send_nybble(0);
//            repeat (1) spi_send_nybble(4'hB);
//            repeat (4) spi_send_nybble(0);
//            repeat (8) spi_send_nybble(0);
//            repeat (3) spi_send_nybble(4'h2);
//            // vert 2 pos (0,0,2)
//            repeat (8) spi_send_nybble(0);
//            repeat (8) spi_send_nybble(0);
//            repeat (3) spi_send_nybble(0);
//            repeat (1) spi_send_nybble(4'hC);
//            repeat (4) spi_send_nybble(0);
//            repeat (3) spi_send_nybble(4'h3);
//            spi_return_result();        
            
//            // CREATE_VERT 14
//            spi_send_opcode(OP_CREATE_VERT);
//            // Send vertex count
//            spi_send_nybble(4'h0);
//            spi_send_nybble(4'h0);
//            spi_send_nybble(4'h3);
//            // vert 0 pos (0,0,0)
//            repeat (8) spi_send_nybble(0);
//            repeat (8) spi_send_nybble(4'hA);
//            repeat (8) spi_send_nybble(0);
//            repeat (3) spi_send_nybble(4'h1);
//            // vert 1 pos (0,2,0)
//            repeat (8) spi_send_nybble(0);
//            repeat (3) spi_send_nybble(0);
//            repeat (1) spi_send_nybble(4'hB);
//            repeat (4) spi_send_nybble(0);
//            repeat (8) spi_send_nybble(0);
//            repeat (3) spi_send_nybble(4'h2);
//            // vert 2 pos (0,0,2)
//            repeat (8) spi_send_nybble(0);
//            repeat (8) spi_send_nybble(0);
//            repeat (3) spi_send_nybble(0);
//            repeat (1) spi_send_nybble(4'hC);
//            repeat (4) spi_send_nybble(0);
//            repeat (3) spi_send_nybble(4'h3);
//            spi_return_result();        
            
//            // CREATE_VERT 15
//            spi_send_opcode(OP_CREATE_VERT);
//            // Send vertex count
//            spi_send_nybble(4'h0);
//            spi_send_nybble(4'h0);
//            spi_send_nybble(4'h3);
//            // vert 0 pos (0,0,0)
//            repeat (8) spi_send_nybble(0);
//            repeat (8) spi_send_nybble(4'hA);
//            repeat (8) spi_send_nybble(0);
//            repeat (3) spi_send_nybble(4'h1);
//            // vert 1 pos (0,2,0)
//            repeat (8) spi_send_nybble(0);
//            repeat (3) spi_send_nybble(0);
//            repeat (1) spi_send_nybble(4'hB);
//            repeat (4) spi_send_nybble(0);
//            repeat (8) spi_send_nybble(0);
//            repeat (3) spi_send_nybble(4'h2);
//            // vert 2 pos (0,0,2)
//            repeat (8) spi_send_nybble(0);
//            repeat (8) spi_send_nybble(0);
//            repeat (3) spi_send_nybble(0);
//            repeat (1) spi_send_nybble(4'hC);
//            repeat (4) spi_send_nybble(0);
//            repeat (3) spi_send_nybble(4'h3);
//            spi_return_result();        
            
//            // CREATE_VERT 16
//            spi_send_opcode(OP_CREATE_VERT);
//            // Send vertex count
//            spi_send_nybble(4'h0);
//            spi_send_nybble(4'h0);
//            spi_send_nybble(4'h3);
//            // vert 0 pos (0,0,0)
//            repeat (8) spi_send_nybble(0);
//            repeat (8) spi_send_nybble(4'hA);
//            repeat (8) spi_send_nybble(0);
//            repeat (3) spi_send_nybble(4'h1);
//            // vert 1 pos (0,2,0)
//            repeat (8) spi_send_nybble(0);
//            repeat (3) spi_send_nybble(0);
//            repeat (1) spi_send_nybble(4'hB);
//            repeat (4) spi_send_nybble(0);
//            repeat (8) spi_send_nybble(0);
//            repeat (3) spi_send_nybble(4'h2);
//            // vert 2 pos (0,0,2)
//            repeat (8) spi_send_nybble(0);
//            repeat (8) spi_send_nybble(0);
//            repeat (3) spi_send_nybble(0);
//            repeat (1) spi_send_nybble(4'hC);
//            repeat (4) spi_send_nybble(0);
//            repeat (3) spi_send_nybble(4'h3);
//            spi_return_result();        
            
//            // CREATE_VERT 17
//            spi_send_opcode(OP_CREATE_VERT);
//            // Send vertex count
//            spi_send_nybble(4'h0);
//            spi_send_nybble(4'h0);
//            spi_send_nybble(4'h3);
//            // vert 0 pos (0,0,0)
//            repeat (8) spi_send_nybble(0);
//            repeat (8) spi_send_nybble(4'hA);
//            repeat (8) spi_send_nybble(0);
//            repeat (3) spi_send_nybble(4'h1);
//            // vert 1 pos (0,2,0)
//            repeat (8) spi_send_nybble(0);
//            repeat (3) spi_send_nybble(0);
//            repeat (1) spi_send_nybble(4'hB);
//            repeat (4) spi_send_nybble(0);
//            repeat (8) spi_send_nybble(0);
//            repeat (3) spi_send_nybble(4'h2);
//            // vert 2 pos (0,0,2)
//            repeat (8) spi_send_nybble(0);
//            repeat (8) spi_send_nybble(0);
//            repeat (3) spi_send_nybble(0);
//            repeat (1) spi_send_nybble(4'hC);
//            repeat (4) spi_send_nybble(0);
//            repeat (3) spi_send_nybble(4'h3);
//            spi_return_result();  

            // CREATE_TRI 1
            // send tri count
            spi_send_opcode(OP_CREATE_TRI);
            spi_send_nybble(4'h0);
            spi_send_nybble(4'h0);
            spi_send_nybble(4'h1);  
            // Tri 0
            spi_send_nybble(4'h0);
            spi_send_nybble(4'h0);
            spi_send_nybble(4'h0); // vert 0
            spi_send_nybble(4'h0);
            spi_send_nybble(4'h0);
            spi_send_nybble(4'h1); // vert 1
            spi_send_nybble(4'h0);
            spi_send_nybble(4'h0);
            spi_send_nybble(4'h2); // vert 2
//            // Tri 1
//            spi_send_nybble(4'h0);
//            spi_send_nybble(4'h0);
//            spi_send_nybble(4'h3); // vert 3
//            spi_send_nybble(4'h0);
//            spi_send_nybble(4'h0);
//            spi_send_nybble(4'h1); // vert 1
//            spi_send_nybble(4'h0);
//            spi_send_nybble(4'h0);
//            spi_send_nybble(4'h2); // vert 2
//            // Tri 2
//            spi_send_nybble(4'h0);
//            spi_send_nybble(4'h0);
//            spi_send_nybble(4'h0); // vert 0
//            spi_send_nybble(4'h0);
//            spi_send_nybble(4'h0);
//            spi_send_nybble(4'h2); // vert 2
//            spi_send_nybble(4'h0);
//            spi_send_nybble(4'h0);
//            spi_send_nybble(4'h4); // vert 4
            // finish Sending tri data
            spi_return_result();           
            
            // CREATE_TRI 2
            // send tri count
            spi_send_opcode(OP_CREATE_TRI);
            spi_send_nybble(4'h0);
            spi_send_nybble(4'h0);
            spi_send_nybble(4'h1);  
            // Tri 0
            spi_send_nybble(4'h0);
            spi_send_nybble(4'h0);
            spi_send_nybble(4'h2); // vert 0
            spi_send_nybble(4'h0);
            spi_send_nybble(4'h0);
            spi_send_nybble(4'h1); // vert 1
            spi_send_nybble(4'h0);
            spi_send_nybble(4'h0);
            spi_send_nybble(4'h0); // vert 2   
            spi_return_result();            
            
            // CREATE_INST 1 test
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
            
            
           // CREATE_INST 2
            spi_send_opcode(OP_CREATE_INST);
            repeat (1) spi_send_nybble(4'h0);   // Vert id
            repeat (1) spi_send_nybble(4'h1);   // Vert id
            repeat (1) spi_send_nybble(4'h0);   // tri id
            repeat (1) spi_send_nybble(4'h1);   // tri id
            
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
            
            // wait for frame driver send data down the pipeline
            #6000
            
            // Terminate the system
            spi_send_opcode(OP_WIPE_ALL);
            spi_return_status();
            
        end
    endtask

endmodule
