`timescale 1ns/1ps
`default_nettype wire

module reset_controller (
    input  logic rst_n,
    
    // Clocks
    input  logic clk_100m,         // spi reference clock
    input  logic sck_rise_pulse,   // serial clock rise pulse
    input  logic clk_render,       // render domain clock
    input  logic clk_pix,          // Pixel clock

    // Reset inputs
    input  logic soft_reset,        // triggered from SPI
    input  logic clk_locked,        // PLL/MMCM lock
    input  logic rst_100m_locked,
    input  logic rst_render_locked,

    // Reset outputs 
    output logic rst_render,        // render domain reset
    output logic rst_100m,           // spi domain reset
    output logic rst_pix,
    output logic rst_protect        // protection flag
);
    logic rst;
    assign rst = !rst_n; // convert to active-high

    logic reset_render_sync_0;
    logic reset_render_sync_1;
    logic reset_pix_sync_0;
    logic reset_pix_sync_1;
    logic [2:0] rst_ctr;
    logic reset_spi_sync;
    

    // 2-stage synchronization
    always_ff @(posedge clk_render or posedge rst_render_locked) begin
        if(rst_render_locked) begin
            reset_pix_sync_0 <= 0;
            reset_pix_sync_1 <= 0;
        end else begin
            reset_pix_sync_0 <= soft_reset;
            reset_pix_sync_1 <= reset_pix_sync_0;
        end
    end


    // 2-stage synchronization
    always_ff @(posedge clk_pix or posedge rst) begin
        if(rst) begin
            reset_render_sync_0 <= 0;
            reset_render_sync_1 <= 0;
        end else begin
            reset_render_sync_0 <= soft_reset;
            reset_render_sync_1 <= reset_render_sync_0;
        end
    end

    // Sck reset pulse with protection flag needed for spi_state during WIPE_ALL opcode
    always_ff @(posedge clk_100m or posedge rst_100m_locked) begin
        if(rst_100m_locked) begin
            rst_ctr <= 0;
            rst_protect    <= 0;
            reset_spi_sync <= 0;
        end else if(sck_rise_pulse) begin 
            if (rst_ctr == 3) begin           // protect signal an extra cycle
                rst_protect    <= 0;
                rst_ctr        <= 0;
            end else if(rst_ctr == 2) begin   // deasert the reset pulse
                reset_spi_sync <= 0;
                rst_ctr        <= rst_ctr +1;
            end else if(rst_ctr == 1) begin   // system spi_driver ready to be reset
                rst_protect    <= 1;
                reset_spi_sync <= 1;
                rst_ctr        <= rst_ctr +1;
            end else if(soft_reset) begin     // if soft reset, start counting
                reset_spi_sync <= 0;
                rst_ctr        <= rst_ctr +1;
            end
        end
    end
    
    // Add soft reset from WIPE_ALL opcode and inverse clock reset to reset signals
    assign rst_100m   = rst_100m_locked   || reset_spi_sync;
    assign rst_render = rst_render_locked || reset_render_sync_1;
    assign rst_pix    = rst               || reset_pix_sync_1  || !clk_locked;
endmodule

