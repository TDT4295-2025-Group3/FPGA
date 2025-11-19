`default_nettype none
`timescale 1ns / 1ps

import color_pkg::color16_t;

module double_framebuffer #(
    parameter int FB_WIDTH  = 160,
    parameter int FB_HEIGHT = 120
) (
    // write side (render)
    input  wire logic        clk_write,
    input  wire logic        clk_read,
    input  wire logic        swap,
    input  wire logic        rst,

    input  wire logic        write_enable,
    input  wire logic [$clog2(FB_WIDTH)-1:0]  write_x,
    input  wire logic [$clog2(FB_HEIGHT)-1:0] write_y,
    input  wire color16_t    write_data,

    // read side (VGA)
    input  wire logic [$clog2(FB_WIDTH)-1:0]  read_x,
    input  wire logic [$clog2(FB_HEIGHT)-1:0] read_y,
    output       color16_t                    read_data,

    // SRAM Left  (buffer A)
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
    // Address math (same as old BRAM version)
    // ----------------------------------------------------------------
    localparam int FB_DEPTH   = FB_WIDTH * FB_HEIGHT;
    localparam int ADDR_WIDTH = $clog2(FB_DEPTH);

    logic [ADDR_WIDTH-1:0] write_addr, read_addr;
    assign write_addr = write_y * FB_WIDTH + write_x;
    assign read_addr  = read_y  * FB_WIDTH + read_x;

    wire [20:0] write_addr_ext = {{(21-ADDR_WIDTH){1'b0}}, write_addr};
    wire [20:0] read_addr_ext  = {{(21-ADDR_WIDTH){1'b0}}, read_addr};

    // full 16-bit word access
    assign sram_l_ub_n = 1'b0;
    assign sram_l_lb_n = 1'b0;
    assign sram_r_ub_n = 1'b0;
    assign sram_r_lb_n = 1'b0;

    // ----------------------------------------------------------------
    // Buffer selection (copied from working BRAM version)
    // ----------------------------------------------------------------
    typedef enum logic { FB_A, FB_B } fb_select_t;

    // write-domain: which buffer we are writing to
    fb_select_t fb_write_select;

    // 1-bit toggle to tell read-domain which buffer to read
    logic fb_read_sel_wr;   // in write clock domain
    logic fb_read_sel_rd;   // synchronized into read clock domain

    // synchronizer flops (read domain)
    logic sync_ff1, sync_ff2;

    // WRITE DOMAIN: handle swap + toggle for read side
    always_ff @(posedge clk_write or posedge rst) begin
        if (rst) begin
            fb_read_sel_wr  <= 1'b0;
            fb_write_select <= FB_B;   // start writing B, reading A
        end else if (swap) begin
            fb_read_sel_wr  <= ~fb_read_sel_wr;
            fb_write_select <= (fb_write_select == FB_A) ? FB_B : FB_A;
        end
    end

    // READ DOMAIN: sync toggle and decode to FB_A/FB_B
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

    fb_select_t fb_read_select;
    always_ff @(posedge clk_read or posedge rst) begin
        if (rst)
            fb_read_select <= FB_A;              // read A at reset
        else
            fb_read_select <= (fb_read_sel_rd ? FB_B : FB_A);
    end

    // ----------------------------------------------------------------
    // SRAM signals per domain
    // ----------------------------------------------------------------

    // Left chip (A) write domain
    logic [20:0] sram_l_addr_wr;
    logic [15:0] sram_l_dq_out_wr;
    logic        sram_l_dq_oe_wr;
    logic        sram_l_cs_n_wr;
    logic        sram_l_we_n_wr;
    logic        sram_l_oe_n_wr;

    // Left chip (A) read domain
    logic [20:0] sram_l_addr_rd;
    logic        sram_l_cs_n_rd;
    logic        sram_l_we_n_rd;
    logic        sram_l_oe_n_rd;

    // Right chip (B) write domain
    logic [20:0] sram_r_addr_wr;
    logic [15:0] sram_r_dq_out_wr;
    logic        sram_r_dq_oe_wr;
    logic        sram_r_cs_n_wr;
    logic        sram_r_we_n_wr;
    logic        sram_r_oe_n_wr;

    // Right chip (B) read domain
    logic [20:0] sram_r_addr_rd;
    logic        sram_r_cs_n_rd;
    logic        sram_r_we_n_rd;
    logic        sram_r_oe_n_rd;

    // write-side drives the FPGA->SRAM data bus
    assign sram_l_dq = sram_l_dq_oe_wr ? sram_l_dq_out_wr : 16'hZZZZ;
    assign sram_r_dq = sram_r_dq_oe_wr ? sram_r_dq_out_wr : 16'hZZZZ;

    // ----------------------------------------------------------------
    // WRITE DOMAIN (clk_write): write back buffer only
    // ----------------------------------------------------------------
    always_ff @(posedge clk_write or posedge rst) begin
        if (rst) begin
            // A
            sram_l_addr_wr   <= 21'd0;
            sram_l_dq_out_wr <= 16'd0;
            sram_l_dq_oe_wr  <= 1'b0;
            sram_l_cs_n_wr   <= 1'b1;
            sram_l_we_n_wr   <= 1'b1;
            sram_l_oe_n_wr   <= 1'b1;
            // B
            sram_r_addr_wr   <= 21'd0;
            sram_r_dq_out_wr <= 16'd0;
            sram_r_dq_oe_wr  <= 1'b0;
            sram_r_cs_n_wr   <= 1'b1;
            sram_r_we_n_wr   <= 1'b1;
            sram_r_oe_n_wr   <= 1'b1;
        end else begin
            // defaults: no write
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
                        sram_l_addr_wr   <= write_addr_ext;
                        sram_l_dq_out_wr <= write_data;
                        sram_l_dq_oe_wr  <= 1'b1;
                        sram_l_cs_n_wr   <= 1'b0;
                        sram_l_we_n_wr   <= 1'b0; // write
                        sram_l_oe_n_wr   <= 1'b1;
                    end
                    FB_B: begin
                        sram_r_addr_wr   <= write_addr_ext;
                        sram_r_dq_out_wr <= write_data;
                        sram_r_dq_oe_wr  <= 1'b1;
                        sram_r_cs_n_wr   <= 1'b0;
                        sram_r_we_n_wr   <= 1'b0; // write
                        sram_r_oe_n_wr   <= 1'b1;
                    end
                endcase
            end
        end
    end

    // ----------------------------------------------------------------
    // READ DOMAIN (clk_read)
    //
    // Contract to the rest of the design:
    //   - color for (read_x, read_y) used in cycle N
    //   - appears on read_data in cycle N+1
    //
    // Implementation:
    //   - each cycle we:
    //       1) sample data from the *previous* front buffer (fb_front_prev)
    //       2) issue a new read to the *current* front buffer (fb_read_select)
    // ----------------------------------------------------------------
    fb_select_t fb_front_prev;   // buffer we sampled this cycle (was front last cycle)
    color16_t   read_data_reg;

    always_ff @(posedge clk_read or posedge rst) begin
        if (rst) begin
            // initial: no reads
            sram_l_addr_rd <= 21'd0;
            sram_l_cs_n_rd <= 1'b1;
            sram_l_we_n_rd <= 1'b1;
            sram_l_oe_n_rd <= 1'b1;

            sram_r_addr_rd <= 21'd0;
            sram_r_cs_n_rd <= 1'b1;
            sram_r_we_n_rd <= 1'b1;
            sram_r_oe_n_rd <= 1'b1;

            fb_front_prev  <= FB_A;        // arbitrary
            read_data_reg  <= '{default:0};
        end else begin
            // 1) sample data from the buffer that was front in the *previous* cycle
            case (fb_front_prev)
                FB_A: read_data_reg <= sram_l_dq;
                FB_B: read_data_reg <= sram_r_dq;
            endcase

            // 2) default: deselect both chips in read domain
            sram_l_cs_n_rd <= 1'b1;
            sram_l_we_n_rd <= 1'b1;
            sram_l_oe_n_rd <= 1'b1;

            sram_r_cs_n_rd <= 1'b1;
            sram_r_we_n_rd <= 1'b1;
            sram_r_oe_n_rd <= 1'b1;

            // 3) issue a new read for the *current* front buffer
            fb_front_prev <= fb_read_select;       // next cycle we'll sample from this one

            case (fb_read_select)
                FB_A: begin
                    sram_l_addr_rd <= read_addr_ext;
                    sram_l_cs_n_rd <= 1'b0;
                    sram_l_we_n_rd <= 1'b1;        // read
                    sram_l_oe_n_rd <= 1'b0;
                end
                FB_B: begin
                    sram_r_addr_rd <= read_addr_ext;
                    sram_r_cs_n_rd <= 1'b0;
                    sram_r_we_n_rd <= 1'b1;        // read
                    sram_r_oe_n_rd <= 1'b0;
                end
            endcase
        end
    end

    assign read_data = read_data_reg;

    // ----------------------------------------------------------------
    // Top-level mux for pins: each chip is *either* in write mode
    // (back buffer) or read mode (front buffer), never both.
    // ----------------------------------------------------------------
    always_comb begin
        if (fb_write_select == FB_A) begin
            // A = back buffer (write), B = front buffer (read)
            sram_l_addr = sram_l_addr_wr;
            sram_l_cs_n = sram_l_cs_n_wr;
            sram_l_we_n = sram_l_we_n_wr;
            sram_l_oe_n = sram_l_oe_n_wr;

            sram_r_addr = sram_r_addr_rd;
            sram_r_cs_n = sram_r_cs_n_rd;
            sram_r_we_n = sram_r_we_n_rd;
            sram_r_oe_n = sram_r_oe_n_rd;
        end else begin
            // B = back buffer (write), A = front buffer (read)
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
