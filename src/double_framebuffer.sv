`default_nettype none
`timescale 1ns / 1ps

import color_pkg::color12_t;

module double_framebuffer #(
    parameter int FB_WIDTH  = 160,
    parameter int FB_HEIGHT = 120
) (
    input  wire logic        clk_write,   // clock for writing (renderer)
    input  wire logic        clk_read,    // clock for reading (VGA)
    input  wire logic        swap,        // signal to swap buffers
    input  wire logic        rst,

    // write side (render)
    input  wire logic        write_enable,
    input  wire logic [$clog2(FB_WIDTH)-1:0]  write_x,
    input  wire logic [$clog2(FB_HEIGHT)-1:0] write_y,
    input  wire color12_t    write_data,

    // read side (VGA)
    input  wire logic [$clog2(FB_WIDTH)-1:0]  read_x,
    input  wire logic [$clog2(FB_HEIGHT)-1:0] read_y,
    output      logic [11:0]                  read_data,

    // SRAM Left (buffer A)
    output logic [20:0] sram_l_addr,
    inout  wire  [15:0] sram_l_dq,
    output logic        sram_l_cs_n,
    output logic        sram_l_we_n,
    output logic        sram_l_oe_n,
    output logic        sram_l_ub_n,
    output logic        sram_l_lb_n,

    // SRAM Right (buffer B)
    output logic [20:0] sram_r_addr,
    inout  wire  [15:0] sram_r_dq,
    output logic        sram_r_cs_n,
    output logic        sram_r_we_n,
    output logic        sram_r_oe_n,
    output logic        sram_r_ub_n,
    output logic        sram_r_lb_n
);

    // ----------------------------------------------------------------
    // Common address math
    // ----------------------------------------------------------------
    localparam int FB_DEPTH   = FB_WIDTH * FB_HEIGHT;   // 160*120 = 19200
    localparam int ADDR_WIDTH = $clog2(FB_DEPTH);       // 15 bits

    logic [ADDR_WIDTH-1:0] write_addr, read_addr;
    assign write_addr = write_y * FB_WIDTH + write_x;
    assign read_addr  = read_y  * FB_WIDTH + read_x;

    // Extend to full 21-bit SRAM address (only low bits used)
    wire [20:0] write_addr_ext = {{(21-ADDR_WIDTH){1'b0}}, write_addr};
    wire [20:0] read_addr_ext  = {{(21-ADDR_WIDTH){1'b0}}, read_addr};

    // Byte lanes always enabled (16-bit words)
    assign sram_l_ub_n = 1'b0;
    assign sram_l_lb_n = 1'b0;
    assign sram_r_ub_n = 1'b0;
    assign sram_r_lb_n = 1'b0;

    // ----------------------------------------------------------------
    // Buffer selection (same scheme as old BRAM version)
    // ----------------------------------------------------------------
    typedef enum logic { FB_A, FB_B } fb_select_t;

    // Which buffer we are WRITING to in clk_write domain
    fb_select_t fb_write_select;

    // One-bit toggle telling the read domain which buffer to READ
    logic fb_read_sel_wr;   // 0 => read A, 1 => read B (write-domain view)
    logic fb_read_sel_rd;   // synchronized version in read domain

    // Synchronizer flops
    logic sync_ff1, sync_ff2;

    // Write clock domain: handle swaps
    always_ff @(posedge clk_write or posedge rst) begin
        if (rst) begin
            fb_read_sel_wr  <= 1'b0;
            fb_write_select <= FB_B;  // start by writing B, reading A
        end else if (swap) begin
            fb_read_sel_wr  <= ~fb_read_sel_wr;
            fb_write_select <= (fb_write_select == FB_A) ? FB_B : FB_A;
        end
    end

    // Sync fb_read_sel_wr into clk_read domain
    always_ff @(posedge clk_read or posedge rst) begin
        if (rst) begin
            sync_ff1 <= 1'b0;
            sync_ff2 <= 1'b0;
        end else begin
            sync_ff1 <= fb_read_sel_wr;
            sync_ff2 <= sync_ff1;
        end
    end
    assign fb_read_sel_rd = sync_ff2;

    // Enum-style front-buffer select in read domain
    fb_select_t fb_read_select;
    always_ff @(posedge clk_read or posedge rst) begin
        if (rst)
            fb_read_select <= FB_A;      // read A at reset (contents will be garbage)
        else
            fb_read_select <= (fb_read_sel_rd ? FB_B : FB_A);
    end

    // ----------------------------------------------------------------
    // SRAM control signals split by domain
    //
    // For each chip we have:
    //   *_wr: driven in clk_write (when that chip is back buffer)
    //   *_rd: driven in clk_read  (when that chip is front buffer)
    //
    // At the bottom we mux them based on fb_write_select, so a chip
    // is *either* written *or* read in a given frame, never both.
    // ----------------------------------------------------------------

    // Left chip (A) write-domain signals
    logic [20:0] sram_l_addr_wr;
    logic [15:0] sram_l_dq_out_wr;
    logic        sram_l_dq_oe_wr;
    logic        sram_l_cs_n_wr;
    logic        sram_l_we_n_wr;
    logic        sram_l_oe_n_wr;

    // Left chip (A) read-domain signals
    logic [20:0] sram_l_addr_rd;
    logic        sram_l_cs_n_rd;
    logic        sram_l_we_n_rd;
    logic        sram_l_oe_n_rd;

    // Right chip (B) write-domain signals
    logic [20:0] sram_r_addr_wr;
    logic [15:0] sram_r_dq_out_wr;
    logic        sram_r_dq_oe_wr;
    logic        sram_r_cs_n_wr;
    logic        sram_r_we_n_wr;
    logic        sram_r_oe_n_wr;

    // Right chip (B) read-domain signals
    logic [20:0] sram_r_addr_rd;
    logic        sram_r_cs_n_rd;
    logic        sram_r_we_n_rd;
    logic        sram_r_oe_n_rd;

    // Data busses driven only by write-domain
    assign sram_l_dq = sram_l_dq_oe_wr ? sram_l_dq_out_wr : 16'hZZZZ;
    assign sram_r_dq = sram_r_dq_oe_wr ? sram_r_dq_out_wr : 16'hZZZZ;

    // ----------------------------------------------------------------
    // WRITE DOMAIN (clk_write)
    //   - Write one pixel per cycle to the "back buffer" chip
    //   - No handshakes, no dropped writes
    // ----------------------------------------------------------------
    always_ff @(posedge clk_write or posedge rst) begin
        if (rst) begin
            // Left A defaults
            sram_l_addr_wr   <= 21'd0;
            sram_l_dq_out_wr <= 16'd0;
            sram_l_dq_oe_wr  <= 1'b0;
            sram_l_cs_n_wr   <= 1'b1;
            sram_l_we_n_wr   <= 1'b1;
            sram_l_oe_n_wr   <= 1'b1;
            // Right B defaults
            sram_r_addr_wr   <= 21'd0;
            sram_r_dq_out_wr <= 16'd0;
            sram_r_dq_oe_wr  <= 1'b0;
            sram_r_cs_n_wr   <= 1'b1;
            sram_r_we_n_wr   <= 1'b1;
            sram_r_oe_n_wr   <= 1'b1;
        end else begin
            // Default: no write this cycle
            sram_l_cs_n_wr  <= 1'b1;
            sram_l_we_n_wr  <= 1'b1;
            sram_l_oe_n_wr  <= 1'b1;
            sram_l_dq_oe_wr <= 1'b0;

            sram_r_cs_n_wr  <= 1'b1;
            sram_r_we_n_wr  <= 1'b1;
            sram_r_oe_n_wr  <= 1'b1;
            sram_r_dq_oe_wr <= 1'b0;

            if (write_enable) begin
                case (fb_write_select)
                    FB_A: begin
                        // write to left chip A
                        sram_l_addr_wr   <= write_addr_ext;
                        sram_l_dq_out_wr <= {4'h0, write_data};
                        sram_l_dq_oe_wr  <= 1'b1;

                        sram_l_cs_n_wr   <= 1'b0;
                        sram_l_we_n_wr   <= 1'b0;  // write
                        sram_l_oe_n_wr   <= 1'b1;  // disable SRAM output
                    end
                    FB_B: begin
                        // write to right chip B
                        sram_r_addr_wr   <= write_addr_ext;
                        sram_r_dq_out_wr <= {4'h0, write_data};
                        sram_r_dq_oe_wr  <= 1'b1;

                        sram_r_cs_n_wr   <= 1'b0;
                        sram_r_we_n_wr   <= 1'b0;  // write
                        sram_r_oe_n_wr   <= 1'b1;  // disable SRAM output
                    end
                endcase
            end
        end
    end

    // ----------------------------------------------------------------
    // READ DOMAIN (clk_read)
    //   Treat the front buffer chip as a simple async ROM,
    //   and sample its dq each pixel.
    //
    //   This gives a *fixed* 1-pixel latency between read_addr
    //   and read_data, similar to your old BRAM framebuffer.
    // ----------------------------------------------------------------
    logic [11:0] read_data_A, read_data_B;

    always_ff @(posedge clk_read or posedge rst) begin
        if (rst) begin
            // A
            sram_l_addr_rd <= 21'd0;
            sram_l_cs_n_rd <= 1'b1;
            sram_l_we_n_rd <= 1'b1;
            sram_l_oe_n_rd <= 1'b1;
            read_data_A    <= 12'h000;

            // B
            sram_r_addr_rd <= 21'd0;
            sram_r_cs_n_rd <= 1'b1;
            sram_r_we_n_rd <= 1'b1;
            sram_r_oe_n_rd <= 1'b1;
            read_data_B    <= 12'h000;
        end else begin
            // Default: neither chip selected from read side
            sram_l_cs_n_rd <= 1'b1;
            sram_l_we_n_rd <= 1'b1;
            sram_l_oe_n_rd <= 1'b1;

            sram_r_cs_n_rd <= 1'b1;
            sram_r_we_n_rd <= 1'b1;
            sram_r_oe_n_rd <= 1'b1;

            // Front-buffer read
            case (fb_read_select)
                FB_A: begin
                    // Drive address for A and sample its data for *previous* address
                    sram_l_addr_rd <= read_addr_ext;
                    sram_l_cs_n_rd <= 1'b0;
                    sram_l_we_n_rd <= 1'b1; // read-only
                    sram_l_oe_n_rd <= 1'b0;

                    read_data_A <= sram_l_dq[11:0];
                end
                FB_B: begin
                    sram_r_addr_rd <= read_addr_ext;
                    sram_r_cs_n_rd <= 1'b0;
                    sram_r_we_n_rd <= 1'b1; // read-only
                    sram_r_oe_n_rd <= 1'b0;

                    read_data_B <= sram_r_dq[11:0];
                end
            endcase
        end
    end

    // Final mux of A/B into read_data (still clk_read domain)
    always_ff @(posedge clk_read or posedge rst) begin
        if (rst)
            read_data <= 12'h000;
        else begin
            case (fb_read_select)
                FB_A: read_data <= read_data_A;
                FB_B: read_data <= read_data_B;
            endcase
        end
    end

    // ----------------------------------------------------------------
    // Top-level pin muxing
    //
    // Only one domain actively controls each chip at a time:
    //   - If fb_write_select == FB_A, chip A is back-buffer (write-only)
    //     so we use *_wr for A, *_rd for B.
    //   - If fb_write_select == FB_B, chip B is back-buffer (write-only)
    //     so we use *_wr for B, *_rd for A.
    // ----------------------------------------------------------------
    always_comb begin
        if (fb_write_select == FB_A) begin
            // A is back buffer (write), B is front buffer (read)
            sram_l_addr = sram_l_addr_wr;
            sram_l_cs_n = sram_l_cs_n_wr;
            sram_l_we_n = sram_l_we_n_wr;
            sram_l_oe_n = sram_l_oe_n_wr;

            sram_r_addr = sram_r_addr_rd;
            sram_r_cs_n = sram_r_cs_n_rd;
            sram_r_we_n = sram_r_we_n_rd;
            sram_r_oe_n = sram_r_oe_n_rd;
        end else begin
            // B is back buffer (write), A is front buffer (read)
            sram_l_addr = sram_l_addr_rd;
            sram_l_cs_n = sram_l_cs_n_rd;
            sram_l_we_n = sram_l_we_n_rd;
            sram_l_oe_n = sram_l_oe_n_rd;

            sram_r_addr = sram_r_addr_wr;
            sram_r_cs_n = sram_r_cs_n_wr;
            sram_r_we_n = sram_r_we_n_wr;
            sram_r_oe_n = sram_r_oe_n_wr;
        end
    end

endmodule
