// `default_nettype none
// `timescale 1ns / 1ps

// module top_pcb #(
//     parameter MAX_VERT  = 8192,
//     parameter MAX_TRI   = 8192,
//     parameter MAX_INST  = 256,
//     parameter SCK_FILTER = 50,
//     localparam MAX_VERT_BUF = 256,
//     localparam MAX_TRI_BUF  = 256,
//     localparam MAX_VERT_CNT = 4096,
//     localparam MAX_TRI_CNT  = 4096,
//     localparam VTX_W     = 108,
//     localparam VIDX_W    = $clog2(MAX_VERT_CNT),
//     localparam TIDX_W    = $clog2(MAX_TRI_CNT),
//     localparam TRI_W     = 3*VIDX_W,
//     localparam ID_W      = 8,
//     localparam DATA_W    = 32,
//     localparam TRANS_W   = DATA_W * 12
// )(
//     input  wire logic clk_pix,       // 25.175 MHz input clock

//     // VGA
//     output      logic [4:0] vga_r,
//     output      logic [5:0] vga_g,
//     output      logic [4:0] vga_b,
//     output      logic       vga_hsync,
//     output      logic       vga_vsync,

//     // SPI (unused in this test)
//     inout  wire logic [3:0] spi_io,
//     input  wire logic       spi_clk,
//     input  wire logic       spi_cs_n,

//     // General Purpose I/O – status
//     inout  wire logic [5:0] gp_io,

//     // SRAM Left
//     inout  wire  [15:0]     sram_l_dq,
//     output      logic [20:0] sram_l_addr,
//     output      logic        sram_l_cs_n,
//     output      logic        sram_l_we_n,
//     output      logic        sram_l_oe_n,
//     output      logic        sram_l_ub_n,
//     output      logic        sram_l_lb_n,

//     // SRAM Right
//     inout  wire  [15:0]     sram_r_dq,
//     output      logic [20:0] sram_r_addr,
//     output      logic        sram_r_cs_n,
//     output      logic        sram_r_we_n,
//     output      logic        sram_r_oe_n,
//     output      logic        sram_r_ub_n,
//     output      logic        sram_r_lb_n
// );

//     // ================================================================
//     // Clocks: use clk_sram (50 MHz) for tests, clk_pix for VGA
//     // ================================================================
//     logic clk_100m;
//     logic clk_render;
//     logic clk_sram;
//     logic clk_locked;

//     logic rst_100m;
//     logic rst_render;
//     logic rst_sram;

//     // No external reset; rely on MMCM lock
//     logic rst_n = 1'b1;
//     logic rst   = ~rst_n;

//     gfx_clocks clocks_inst (
//         .clk_pix    (clk_pix),
//         .rst        (rst),
//         .clk_render (clk_render), // unused here
//         .clk_sram   (clk_sram),
//         .clk_100m   (clk_100m),   // unused
//         .clk_locked (clk_locked),
//         .rst_render (rst_render), // unused
//         .rst_sram   (rst_sram),
//         .rst_100m   (rst_100m)    // unused
//     );

//     // ================================================================
//     // SRAM drivers (left & right)
//     // ================================================================
//     localparam int   ADDR_WIDTH = 21;
//     localparam logic [15:0] PAT0 = 16'hAAAA;
//     localparam logic [15:0] PAT1 = 16'h5555;

//     // ---------- Left ----------
//     logic        l_drv_req;
//     logic        l_drv_we;
//     logic [20:0] l_drv_addr;
//     logic [15:0] l_drv_wdata;
//     logic [15:0] l_drv_rdata;
//     logic        l_drv_ready;

//     sram_driver u_sram_driver_left (
//         .clk          (clk_sram),
//         .rst          (rst_sram),
//         .req          (l_drv_req),
//         .write_enable (l_drv_we),
//         .address      (l_drv_addr),
//         .write_data   (l_drv_wdata),
//         .read_data    (l_drv_rdata),
//         .ready        (l_drv_ready),

//         .sram_addr    (sram_l_addr),
//         .sram_dq      (sram_l_dq),
//         .sram_cs_n    (sram_l_cs_n),
//         .sram_we_n    (sram_l_we_n),
//         .sram_oe_n    (sram_l_oe_n),
//         .sram_ub_n    (sram_l_ub_n),
//         .sram_lb_n    (sram_l_lb_n)
//     );

//     // ---------- Right ----------
//     logic        r_drv_req;
//     logic        r_drv_we;
//     logic [20:0] r_drv_addr;
//     logic [15:0] r_drv_wdata;
//     logic [15:0] r_drv_rdata;
//     logic        r_drv_ready;

//     sram_driver u_sram_driver_right (
//         .clk          (clk_sram),
//         .rst          (rst_sram),
//         .req          (r_drv_req),
//         .write_enable (r_drv_we),
//         .address      (r_drv_addr),
//         .write_data   (r_drv_wdata),
//         .read_data    (r_drv_rdata),
//         .ready        (r_drv_ready),

//         .sram_addr    (sram_r_addr),
//         .sram_dq      (sram_r_dq),
//         .sram_cs_n    (sram_r_cs_n),
//         .sram_we_n    (sram_r_we_n),
//         .sram_oe_n    (sram_r_oe_n),
//         .sram_ub_n    (sram_r_ub_n),
//         .sram_lb_n    (sram_r_lb_n)
//     );

//     // ================================================================
//     // Address-bus test FSMs (left & right)
//     //
//     // For each bit i = 0..20:
//     //   1) Write PAT0 to address 0
//     //   2) Write PAT1 to address (1 << i)
//     //   3) Read addr 0 (expect PAT0)
//     //   4) Read addr (1<<i) (expect PAT1)
//     //
//     // If both reads match, bit i is marked OK, else bit i is BAD.
//     // ================================================================
//     typedef enum logic [3:0] {
//         L_IDLE,
//         L_W0_ISSUE, L_W0_WAIT,
//         L_W1_ISSUE, L_W1_WAIT,
//         L_R0_ISSUE, L_R0_WAIT,
//         L_R1_ISSUE, L_R1_WAIT,
//         L_NEXT_BIT,
//         L_DONE
//     } l_state_t;

//     typedef enum logic [3:0] {
//         R_IDLE,
//         R_W0_ISSUE, R_W0_WAIT,
//         R_W1_ISSUE, R_W1_WAIT,
//         R_R0_ISSUE, R_R0_WAIT,
//         R_R1_ISSUE, R_R1_WAIT,
//         R_NEXT_BIT,
//         R_DONE
//     } r_state_t;

//     // Left side
//     l_state_t    l_state, l_next_state;
//     logic [4:0]  l_bit_idx;        // 0..20
//     logic        l_r0_ok;
//     logic [20:0] l_bit_ok;         // 1 = this address bit passed
//     logic        l_all_done_l;

//     // Right side
//     r_state_t    r_state, r_next_state;
//     logic [4:0]  r_bit_idx;        // 0..20
//     logic        r_r0_ok;
//     logic [20:0] r_bit_ok;
//     logic        r_all_done_r;

//     // ---------- Left FSM sequential ----------
//     always_ff @(posedge clk_sram or posedge rst_sram) begin
//         if (rst_sram) begin
//             l_state      <= L_IDLE;
//             l_bit_idx    <= 5'd0;
//             l_r0_ok      <= 1'b0;
//             l_bit_ok     <= '0;
//             l_all_done_l <= 1'b0;
//         end else begin
//             l_state <= l_next_state;

//             case (l_state)
//                 L_IDLE: begin
//                     l_bit_idx    <= 5'd0;
//                     l_bit_ok     <= '0;
//                     l_all_done_l <= 1'b0;
//                 end

//                 L_R0_WAIT: begin
//                     if (l_drv_ready) begin
//                         l_r0_ok <= (l_drv_rdata == PAT0);
//                     end
//                 end

//                 L_R1_WAIT: begin
//                     if (l_drv_ready) begin
//                         l_bit_ok[l_bit_idx] <= l_r0_ok & (l_drv_rdata == PAT1);
//                     end
//                 end

//                 L_NEXT_BIT: begin
//                     if (l_bit_idx == (ADDR_WIDTH-1)) begin
//                         l_all_done_l <= 1'b1;
//                     end else begin
//                         l_bit_idx <= l_bit_idx + 5'd1;
//                     end
//                 end

//                 default: ; // no extra work
//             endcase
//         end
//     end

//     // ---------- Left FSM combinational ----------
//     always_comb begin
//         // Defaults
//         l_drv_req    = 1'b0;
//         l_drv_we     = 1'b0;
//         l_drv_addr   = 21'd0;
//         l_drv_wdata  = PAT0;
//         l_next_state = l_state;

//         unique case (l_state)
//             L_IDLE: begin
//                 if (!l_all_done_l && l_drv_ready)
//                     l_next_state = L_W0_ISSUE;
//             end

//             // Write PAT0 to addr 0
//             L_W0_ISSUE: begin
//                 if (l_drv_ready) begin
//                     l_drv_req   = 1'b1;
//                     l_drv_we    = 1'b1;
//                     l_drv_addr  = 21'd0;
//                     l_drv_wdata = PAT0;
//                     l_next_state = L_W0_WAIT;
//                 end
//             end

//             L_W0_WAIT: begin
//                 if (l_drv_ready)
//                     l_next_state = L_W1_ISSUE;
//             end

//             // Write PAT1 to addr (1<<bit_idx)
//             L_W1_ISSUE: begin
//                 if (l_drv_ready) begin
//                     l_drv_req   = 1'b1;
//                     l_drv_we    = 1'b1;
//                     l_drv_addr  = (21'd1 << l_bit_idx);
//                     l_drv_wdata = PAT1;
//                     l_next_state = L_W1_WAIT;
//                 end
//             end

//             L_W1_WAIT: begin
//                 if (l_drv_ready)
//                     l_next_state = L_R0_ISSUE;
//             end

//             // Read back addr 0
//             L_R0_ISSUE: begin
//                 if (l_drv_ready) begin
//                     l_drv_req   = 1'b1;
//                     l_drv_we    = 1'b0;
//                     l_drv_addr  = 21'd0;
//                     l_next_state = L_R0_WAIT;
//                 end
//             end

//             L_R0_WAIT: begin
//                 if (l_drv_ready)
//                     l_next_state = L_R1_ISSUE;
//             end

//             // Read back addr (1<<bit_idx)
//             L_R1_ISSUE: begin
//                 if (l_drv_ready) begin
//                     l_drv_req   = 1'b1;
//                     l_drv_we    = 1'b0;
//                     l_drv_addr  = (21'd1 << l_bit_idx);
//                     l_next_state = L_R1_WAIT;
//                 end
//             end

//             L_R1_WAIT: begin
//                 if (l_drv_ready)
//                     l_next_state = L_NEXT_BIT;
//             end

//             L_NEXT_BIT: begin
//                 if (l_bit_idx == (ADDR_WIDTH-1))
//                     l_next_state = L_DONE;
//                 else
//                     l_next_state = L_W0_ISSUE;
//             end

//             L_DONE: begin
//                 l_next_state = L_DONE;
//             end

//             default: l_next_state = L_IDLE;
//         endcase
//     end

//     // ---------- Right FSM sequential ----------
//     always_ff @(posedge clk_sram or posedge rst_sram) begin
//         if (rst_sram) begin
//             r_state      <= R_IDLE;
//             r_bit_idx    <= 5'd0;
//             r_r0_ok      <= 1'b0;
//             r_bit_ok     <= '0;
//             r_all_done_r <= 1'b0;
//         end else begin
//             r_state <= r_next_state;

//             case (r_state)
//                 R_IDLE: begin
//                     r_bit_idx    <= 5'd0;
//                     r_bit_ok     <= '0;
//                     r_all_done_r <= 1'b0;
//                 end

//                 R_R0_WAIT: begin
//                     if (r_drv_ready) begin
//                         r_r0_ok <= (r_drv_rdata == PAT0);
//                     end
//                 end

//                 R_R1_WAIT: begin
//                     if (r_drv_ready) begin
//                         r_bit_ok[r_bit_idx] <= r_r0_ok & (r_drv_rdata == PAT1);
//                     end
//                 end

//                 R_NEXT_BIT: begin
//                     if (r_bit_idx == (ADDR_WIDTH-1)) begin
//                         r_all_done_r <= 1'b1;
//                     end else begin
//                         r_bit_idx <= r_bit_idx + 5'd1;
//                     end
//                 end

//                 default: ; // no extra work
//             endcase
//         end
//     end

//     // ---------- Right FSM combinational ----------
//     always_comb begin
//         // Defaults
//         r_drv_req    = 1'b0;
//         r_drv_we     = 1'b0;
//         r_drv_addr   = 21'd0;
//         r_drv_wdata  = PAT0;
//         r_next_state = r_state;

//         unique case (r_state)
//             R_IDLE: begin
//                 if (!r_all_done_r && r_drv_ready)
//                     r_next_state = R_W0_ISSUE;
//             end

//             // Write PAT0 to addr 0
//             R_W0_ISSUE: begin
//                 if (r_drv_ready) begin
//                     r_drv_req   = 1'b1;
//                     r_drv_we    = 1'b1;
//                     r_drv_addr  = 21'd0;
//                     r_drv_wdata = PAT0;
//                     r_next_state = R_W0_WAIT;
//                 end
//             end

//             R_W0_WAIT: begin
//                 if (r_drv_ready)
//                     r_next_state = R_W1_ISSUE;
//             end

//             // Write PAT1 to addr (1<<bit_idx)
//             R_W1_ISSUE: begin
//                 if (r_drv_ready) begin
//                     r_drv_req   = 1'b1;
//                     r_drv_we    = 1'b1;
//                     r_drv_addr  = (21'd1 << r_bit_idx);
//                     r_drv_wdata = PAT1;
//                     r_next_state = R_W1_WAIT;
//                 end
//             end

//             R_W1_WAIT: begin
//                 if (r_drv_ready)
//                     r_next_state = R_R0_ISSUE;
//             end

//             // Read back addr 0
//             R_R0_ISSUE: begin
//                 if (r_drv_ready) begin
//                     r_drv_req   = 1'b1;
//                     r_drv_we    = 1'b0;
//                     r_drv_addr  = 21'd0;
//                     r_next_state = R_R0_WAIT;
//                 end
//             end

//             R_R0_WAIT: begin
//                 if (r_drv_ready)
//                     r_next_state = R_R1_ISSUE;
//             end

//             // Read back addr (1<<bit_idx)
//             R_R1_ISSUE: begin
//                 if (r_drv_ready) begin
//                     r_drv_req   = 1'b1;
//                     r_drv_we    = 1'b0;
//                     r_drv_addr  = (21'd1 << r_bit_idx);
//                     r_next_state = R_R1_WAIT;
//                 end
//             end

//             R_R1_WAIT: begin
//                 if (r_drv_ready)
//                     r_next_state = R_NEXT_BIT;
//             end

//             R_NEXT_BIT: begin
//                 if (r_bit_idx == (ADDR_WIDTH-1))
//                     r_next_state = R_DONE;
//                 else
//                     r_next_state = R_W0_ISSUE;
//             end

//             R_DONE: begin
//                 r_next_state = R_DONE;
//             end

//             default: r_next_state = R_IDLE;
//         endcase
//     end

//     // ================================================================
//     // Summary flags & GPIO
//     // ================================================================
//     wire left_done        = l_all_done_l;
//     wire right_done       = r_all_done_r;
//     wire left_all_bits_ok = &l_bit_ok;
//     wire right_all_bits_ok= &r_bit_ok;

//     wire left_fail  = left_done  && !left_all_bits_ok;
//     wire right_fail = right_done && !right_all_bits_ok;

//     // gp_io[0] = left_done
//     // gp_io[1] = left_fail
//     // gp_io[2] = right_done
//     // gp_io[3] = right_fail
//     assign gp_io[0] = left_done;
//     assign gp_io[1] = left_fail;
//     assign gp_io[2] = right_done;
//     assign gp_io[3] = right_fail;
//     assign gp_io[4] = 1'bz;
//     assign gp_io[5] = 1'bz;

//     // ================================================================
//     // Simple 640x480 VGA timing + striped visualisation
//     // With small gaps between stripes so you can count them.
//     // ================================================================
//     localparam int H_VISIBLE = 640;
//     localparam int H_FRONT   = 16;
//     localparam int H_SYNC    = 96;
//     localparam int H_BACK    = 48;
//     localparam int H_TOTAL   = H_VISIBLE + H_FRONT + H_SYNC + H_BACK; // 800

//     localparam int V_VISIBLE = 480;
//     localparam int V_FRONT   = 10;
//     localparam int V_SYNC    = 2;
//     localparam int V_BACK    = 33;
//     localparam int V_TOTAL   = V_VISIBLE + V_FRONT + V_SYNC + V_BACK; // 525

//     logic [9:0] h_cnt;
//     logic [9:0] v_cnt;
//     logic       de;

//     wire pix_rst = ~clk_locked;

//     always_ff @(posedge clk_pix or posedge pix_rst) begin
//         if (pix_rst) begin
//             h_cnt <= 10'd0;
//             v_cnt <= 10'd0;
//         end else begin
//             if (h_cnt == H_TOTAL-1) begin
//                 h_cnt <= 10'd0;
//                 if (v_cnt == V_TOTAL-1)
//                     v_cnt <= 10'd0;
//                 else
//                     v_cnt <= v_cnt + 10'd1;
//             end else begin
//                 h_cnt <= h_cnt + 10'd1;
//             end
//         end
//     end

//     assign de = (h_cnt < H_VISIBLE) && (v_cnt < V_VISIBLE);

//     // Active-low sync pulses
//     assign vga_hsync = ~((h_cnt >= (H_VISIBLE + H_FRONT)) &&
//                          (h_cnt <  (H_VISIBLE + H_FRONT + H_SYNC)));
//     assign vga_vsync = ~((v_cnt >= (V_VISIBLE + V_FRONT)) &&
//                          (v_cnt <  (V_VISIBLE + V_FRONT + V_SYNC)));

//     // Stripe mapping with gaps
//     localparam int N_BITS    = 21;
//     localparam int SLOT_W    = H_VISIBLE / N_BITS; // width of one bit "slot"
//     localparam int GAP_W     = 2;                  // horizontal gap between stripes
//     localparam int STRIPE_W  = SLOT_W - GAP_W;     // actual colored width

//     logic [4:0] bit_idx;
//     logic [9:0] slot_x;

//     always_comb begin
//         if (h_cnt < (N_BITS * SLOT_W)) begin
//             bit_idx = h_cnt / SLOT_W;                  // which bit (0..20)
//             slot_x  = h_cnt % SLOT_W;                  // position within that slot
//         end else begin
//             bit_idx = 5'd31;                           // out of range
//             slot_x  = 10'd0;
//         end
//     end

//     // VGA color: top half = left bits, bottom half = right bits
//     always_comb begin
//         // Default: black
//         vga_r = 5'h00;
//         vga_g = 6'h00;
//         vga_b = 5'h00;

//         if (!de) begin
//             // off-screen
//         end else if (!(left_done && right_done)) begin
//             // While tests running: dark blue
//             vga_r = 5'h00;
//             vga_g = 6'h00;
//             vga_b = 5'h0F;
//         end else if (bit_idx < N_BITS) begin
//             // Inside one of the bit slots
//             if (slot_x >= STRIPE_W) begin
//                 // This is the GAP area: keep black so you can visually separate stripes
//                 vga_r = 5'h00;
//                 vga_g = 6'h00;
//                 vga_b = 5'h00;
//             end else if (v_cnt < (V_VISIBLE/2)) begin
//                 // TOP HALF: LEFT SRAM
//                 if (l_bit_ok[bit_idx]) begin
//                     // Green = this address bit seems OK
//                     vga_r = 5'h00;
//                     vga_g = 6'h3F;
//                     vga_b = 5'h00;
//                 end else begin
//                     // Red = this address bit failed
//                     vga_r = 5'h1F;
//                     vga_g = 6'h00;
//                     vga_b = 5'h00;
//                 end
//             end else begin
//                 // BOTTOM HALF: RIGHT SRAM
//                 if (r_bit_ok[bit_idx]) begin
//                     vga_r = 5'h00;
//                     vga_g = 6'h3F;
//                     vga_b = 5'h00;
//                 end else begin
//                     vga_r = 5'h1F;
//                     vga_g = 6'h00;
//                     vga_b = 5'h00;
//                 end
//             end
//         end else begin
//             // Right margin: grey
//             vga_r = 5'h08;
//             vga_g = 6'h10;
//             vga_b = 5'h08;
//         end
//     end

//     // ================================================================
//     // SPI pins unused: tri-state them
//     // ================================================================
//     assign spi_io = 4'bzzzz;
//     // spi_clk and spi_cs_n are inputs; ignored

// endmodule


`default_nettype none
`timescale 1ns / 1ps

module top_pcb #(
    parameter MAX_VERT   = 8192,
    parameter MAX_TRI    = 8192,
    parameter MAX_INST   = 256,
    parameter SCK_FILTER = 50,
    localparam MAX_VERT_BUF = 256,
    localparam MAX_TRI_BUF  = 256,
    localparam MAX_VERT_CNT = 4096,
    localparam MAX_TRI_CNT  = 4096,
    localparam VTX_W     = 108,
    localparam VIDX_W    = $clog2(MAX_VERT_CNT),
    localparam TIDX_W    = $clog2(MAX_TRI_CNT),
    localparam TRI_W     = 3*VIDX_W,
    localparam ID_W      = 8,
    localparam DATA_W    = 32,
    localparam TRANS_W   = DATA_W * 12
)(
    input  wire logic clk_pix,
    output      logic [4:0] vga_r,
    output      logic [5:0] vga_g,
    output      logic [4:0] vga_b,
    output      logic       vga_hsync,
    output      logic       vga_vsync,
    inout  wire logic [3:0] spi_io,
    input  wire logic       spi_clk,
    input  wire logic       spi_cs_n,
    inout  wire logic [5:0] gp_io,
    inout  wire  [15:0]     sram_l_dq,
    output      logic [20:0] sram_l_addr,
    output      logic        sram_l_cs_n,
    output      logic        sram_l_we_n,
    output      logic        sram_l_oe_n,
    output      logic        sram_l_ub_n,
    output      logic        sram_l_lb_n,
    inout  wire  [15:0]     sram_r_dq,
    output      logic [20:0] sram_r_addr,
    output      logic        sram_r_cs_n,
    output      logic        sram_r_we_n,
    output      logic        sram_r_oe_n,
    output      logic        sram_r_ub_n,
    output      logic        sram_r_lb_n
);

    logic clk_100m, clk_render, clk_sram, clk_locked;
    logic rst_100m, rst_render, rst_sram;
    logic rst_n = 1'b1;
    logic rst   = ~rst_n;

    gfx_clocks clocks_inst (
        .clk_pix    (clk_pix),
        .rst        (rst),
        .clk_render (clk_render),
        .clk_sram   (clk_sram),
        .clk_100m   (clk_100m),
        .clk_locked (clk_locked),
        .rst_render (rst_render),
        .rst_sram   (rst_sram),
        .rst_100m   (rst_100m)
    );

    localparam int   ADDR_BITS = 21;
    localparam logic [15:0] PAT0 = 16'hAAAA;
    localparam logic [15:0] PAT1 = 16'h5555;

    logic        l_drv_req,  l_drv_we;
    logic [20:0] l_drv_addr;
    logic [15:0] l_drv_wdata, l_drv_rdata;
    logic        l_drv_ready;

    sram_driver u_sram_driver_left (
        .clk          (clk_sram),
        .rst          (rst_sram),
        .req          (l_drv_req),
        .write_enable (l_drv_we),
        .address      (l_drv_addr),
        .write_data   (l_drv_wdata),
        .read_data    (l_drv_rdata),
        .ready        (l_drv_ready),
        .sram_addr    (sram_l_addr),
        .sram_dq      (sram_l_dq),
        .sram_cs_n    (sram_l_cs_n),
        .sram_we_n    (sram_l_we_n),
        .sram_oe_n    (sram_l_oe_n),
        .sram_ub_n    (sram_l_ub_n),
        .sram_lb_n    (sram_l_lb_n)
    );

    logic        r_drv_req,  r_drv_we;
    logic [20:0] r_drv_addr;
    logic [15:0] r_drv_wdata, r_drv_rdata;
    logic        r_drv_ready;

    sram_driver u_sram_driver_right (
        .clk          (clk_sram),
        .rst          (rst_sram),
        .req          (r_drv_req),
        .write_enable (r_drv_we),
        .address      (r_drv_addr),
        .write_data   (r_drv_wdata),
        .read_data    (r_drv_rdata),
        .ready        (r_drv_ready),
        .sram_addr    (sram_r_addr),
        .sram_dq      (sram_r_dq),
        .sram_cs_n    (sram_r_cs_n),
        .sram_we_n    (sram_r_we_n),
        .sram_oe_n    (sram_r_oe_n),
        .sram_ub_n    (sram_r_ub_n),
        .sram_lb_n    (sram_r_lb_n)
    );

    typedef enum logic [3:0] {
        L_IDLE,
        L_W0_ISSUE, L_W0_WAIT,
        L_W1_ISSUE, L_W1_WAIT,
        L_R0_ISSUE, L_R0_WAIT,
        L_R1_ISSUE, L_R1_WAIT,
        L_NEXT_BIT,
        L_DONE
    } l_state_t;

    typedef enum logic [3:0] {
        R_IDLE,
        R_W0_ISSUE, R_W0_WAIT,
        R_W1_ISSUE, R_W1_WAIT,
        R_R0_ISSUE, R_R0_WAIT,
        R_R1_ISSUE, R_R1_WAIT,
        R_NEXT_BIT,
        R_DONE
    } r_state_t;

    l_state_t    l_state, l_next_state;
    logic [4:0]  l_bit_idx;
    logic        l_r0_ok;
    logic [20:0] l_bit_ok;
    logic        l_addr_done;

    r_state_t    r_state, r_next_state;
    logic [4:0]  r_bit_idx;
    logic        r_r0_ok;
    logic [20:0] r_bit_ok;
    logic        r_addr_done;

    logic        l_a_req, l_a_we;
    logic [20:0] l_a_addr;
    logic [15:0] l_a_wdata;

    logic        r_a_req, r_a_we;
    logic [20:0] r_a_addr;
    logic [15:0] r_a_wdata;

    always_ff @(posedge clk_sram or posedge rst_sram) begin
        if (rst_sram) begin
            l_state     <= L_IDLE;
            l_bit_idx   <= 5'd0;
            l_r0_ok     <= 1'b0;
            l_bit_ok    <= '0;
            l_addr_done <= 1'b0;
        end else begin
            l_state <= l_next_state;
            case (l_state)
                L_IDLE: begin
                    l_bit_idx   <= 5'd0;
                    l_bit_ok    <= '0;
                    l_addr_done <= 1'b0;
                end
                L_R0_WAIT: if (l_drv_ready) l_r0_ok <= (l_drv_rdata == PAT0);
                L_R1_WAIT: if (l_drv_ready) l_bit_ok[l_bit_idx] <= l_r0_ok & (l_drv_rdata == PAT1);
                L_NEXT_BIT: begin
                    if (l_bit_idx == (ADDR_BITS-1)) l_addr_done <= 1'b1;
                    else                              l_bit_idx   <= l_bit_idx + 5'd1;
                end
                default: ;
            endcase
        end
    end

    always_comb begin
        l_a_req = 1'b0; l_a_we = 1'b0; l_a_addr = 21'd0; l_a_wdata = PAT0;
        l_next_state = l_state;
        unique case (l_state)
            L_IDLE:     if (!l_addr_done && l_drv_ready) l_next_state = L_W0_ISSUE;
            L_W0_ISSUE: if (l_drv_ready) begin l_a_req=1; l_a_we=1; l_a_addr=21'd0;         l_a_wdata=PAT0; l_next_state=L_W0_WAIT; end
            L_W0_WAIT:  if (l_drv_ready) l_next_state = L_W1_ISSUE;
            L_W1_ISSUE: if (l_drv_ready) begin l_a_req=1; l_a_we=1; l_a_addr=(21'd1<<l_bit_idx); l_a_wdata=PAT1; l_next_state=L_W1_WAIT; end
            L_W1_WAIT:  if (l_drv_ready) l_next_state = L_R0_ISSUE;
            L_R0_ISSUE: if (l_drv_ready) begin l_a_req=1; l_a_we=0; l_a_addr=21'd0;         l_next_state=L_R0_WAIT; end
            L_R0_WAIT:  if (l_drv_ready) l_next_state = L_R1_ISSUE;
            L_R1_ISSUE: if (l_drv_ready) begin l_a_req=1; l_a_we=0; l_a_addr=(21'd1<<l_bit_idx); l_next_state=L_R1_WAIT; end
            L_R1_WAIT:  if (l_drv_ready) l_next_state = L_NEXT_BIT;
            L_NEXT_BIT: l_next_state = (l_bit_idx==(ADDR_BITS-1)) ? L_DONE : L_W0_ISSUE;
            L_DONE:     l_next_state = L_DONE;
            default:    l_next_state = L_IDLE;
        endcase
    end

    always_ff @(posedge clk_sram or posedge rst_sram) begin
        if (rst_sram) begin
            r_state     <= R_IDLE;
            r_bit_idx   <= 5'd0;
            r_r0_ok     <= 1'b0;
            r_bit_ok    <= '0;
            r_addr_done <= 1'b0;
        end else begin
            r_state <= r_next_state;
            case (r_state)
                R_IDLE: begin
                    r_bit_idx   <= 5'd0;
                    r_bit_ok    <= '0;
                    r_addr_done <= 1'b0;
                end
                R_R0_WAIT: if (r_drv_ready) r_r0_ok <= (r_drv_rdata == PAT0);
                R_R1_WAIT: if (r_drv_ready) r_bit_ok[r_bit_idx] <= r_r0_ok & (r_drv_rdata == PAT1);
                R_NEXT_BIT: begin
                    if (r_bit_idx == (ADDR_BITS-1)) r_addr_done <= 1'b1;
                    else                              r_bit_idx   <= r_bit_idx + 5'd1;
                end
                default: ;
            endcase
        end
    end

    always_comb begin
        r_a_req = 1'b0; r_a_we = 1'b0; r_a_addr = 21'd0; r_a_wdata = PAT0;
        r_next_state = r_state;
        unique case (r_state)
            R_IDLE:     if (!r_addr_done && r_drv_ready) r_next_state = R_W0_ISSUE;
            R_W0_ISSUE: if (r_drv_ready) begin r_a_req=1; r_a_we=1; r_a_addr=21'd0;         r_a_wdata=PAT0; r_next_state=R_W0_WAIT; end
            R_W0_WAIT:  if (r_drv_ready) r_next_state = R_W1_ISSUE;
            R_W1_ISSUE: if (r_drv_ready) begin r_a_req=1; r_a_we=1; r_a_addr=(21'd1<<r_bit_idx); r_a_wdata=PAT1; r_next_state=R_W1_WAIT; end
            R_W1_WAIT:  if (r_drv_ready) r_next_state = R_R0_ISSUE;
            R_R0_ISSUE: if (r_drv_ready) begin r_a_req=1; r_a_we=0; r_a_addr=21'd0;         r_next_state=R_R0_WAIT; end
            R_R0_WAIT:  if (r_drv_ready) r_next_state = R_R1_ISSUE;
            R_R1_ISSUE: if (r_drv_ready) begin r_a_req=1; r_a_we=0; r_a_addr=(21'd1<<r_bit_idx); r_next_state=R_R1_WAIT; end
            R_R1_WAIT:  if (r_drv_ready) r_next_state = R_NEXT_BIT;
            R_NEXT_BIT: r_next_state = (r_bit_idx==(ADDR_BITS-1)) ? R_DONE : R_W0_ISSUE;
            R_DONE:     r_next_state = R_DONE;
            default:    r_next_state = R_IDLE;
        endcase
    end

    localparam [20:0] DQ_TEST_ADDR = 21'h00100;

    typedef enum logic [3:0] {
        D_IDLE, D_W1_ISSUE, D_W1_WAIT, D_R1_ISSUE, D_R1_WAIT,
        D_W0_ISSUE, D_W0_WAIT, D_R0_ISSUE, D_R0_WAIT, D_NEXT, D_DONE
    } d_state_t;

    d_state_t    l_dstate, l_dnext;
    logic  [4:0] l_dq_idx;
    logic [15:0] l_dq_ok_bits;
    logic        l_data_done;
    d_state_t    r_dstate, r_dnext;
    logic  [4:0] r_dq_idx;
    logic [15:0] r_dq_ok_bits;
    logic        r_data_done;

    logic l_cs_seen, l_we_seen, l_oe_seen;
    logic r_cs_seen, r_we_seen, r_oe_seen;

    logic        l_d_req, l_d_we;
    logic [20:0] l_d_addr;
    logic [15:0] l_d_wdata;

    logic        r_d_req, r_d_we;
    logic [20:0] r_d_addr;
    logic [15:0] r_d_wdata;

    always_ff @(posedge clk_sram or posedge rst_sram) begin
        if (rst_sram) begin
            l_dstate    <= D_IDLE;
            l_dq_idx    <= 5'd0;
            l_dq_ok_bits<= 16'h0000;
            l_data_done <= 1'b0;
            l_cs_seen   <= 1'b0;
            l_we_seen   <= 1'b0;
            l_oe_seen   <= 1'b0;
        end else begin
            l_dstate <= l_dnext;
            if (!sram_l_cs_n) l_cs_seen <= 1'b1;
            if (!sram_l_we_n) l_we_seen <= 1'b1;
            if (!sram_l_oe_n) l_oe_seen <= 1'b1;
            case (l_dstate)
                D_IDLE: begin
                    l_dq_idx     <= 5'd0;
                    l_dq_ok_bits <= 16'hFFFF;
                    l_data_done  <= 1'b0;
                end
                D_R1_WAIT: if (l_drv_ready) begin
                    logic [15:0] exp1 = (16'h0001 << l_dq_idx);
                    if (l_drv_rdata != exp1) l_dq_ok_bits[l_dq_idx] <= 1'b0;
                end
                D_R0_WAIT: if (l_drv_ready) begin
                    logic [15:0] exp0 = ~(16'h0001 << l_dq_idx);
                    if (l_drv_rdata != exp0) l_dq_ok_bits[l_dq_idx] <= 1'b0;
                end
                D_NEXT: begin
                    if (l_dq_idx == 5'd15) l_data_done <= 1'b1;
                    else                    l_dq_idx    <= l_dq_idx + 5'd1;
                end
                default: ;
            endcase
        end
    end

    always_comb begin
        l_dnext = l_dstate;
        l_d_req = 1'b0; l_d_we = 1'b0; l_d_addr = DQ_TEST_ADDR; l_d_wdata = 16'h0000;
        case (l_dstate)
            D_IDLE: if (l_addr_done && l_drv_ready) l_dnext = D_W1_ISSUE;
            D_W1_ISSUE: if (l_drv_ready) begin
                l_d_req=1; l_d_we=1; l_d_addr=DQ_TEST_ADDR; l_d_wdata=(16'h0001<<l_dq_idx); l_dnext=D_W1_WAIT;
            end
            D_W1_WAIT:  if (l_drv_ready) l_dnext = D_R1_ISSUE;
            D_R1_ISSUE: if (l_drv_ready) begin
                l_d_req=1; l_d_we=0; l_d_addr=DQ_TEST_ADDR; l_dnext=D_R1_WAIT;
            end
            D_R1_WAIT:  if (l_drv_ready) l_dnext = D_W0_ISSUE;
            D_W0_ISSUE: if (l_drv_ready) begin
                l_d_req=1; l_d_we=1; l_d_addr=DQ_TEST_ADDR; l_d_wdata=~(16'h0001<<l_dq_idx); l_dnext=D_W0_WAIT;
            end
            D_W0_WAIT:  if (l_drv_ready) l_dnext = D_R0_ISSUE;
            D_R0_ISSUE: if (l_drv_ready) begin
                l_d_req=1; l_d_we=0; l_d_addr=DQ_TEST_ADDR; l_dnext=D_R0_WAIT;
            end
            D_R0_WAIT:  if (l_drv_ready) l_dnext = D_NEXT;
            D_NEXT:     l_dnext = (l_dq_idx==5'd15) ? D_DONE : D_W1_ISSUE;
            D_DONE:     l_dnext = D_DONE;
            default:    l_dnext = D_IDLE;
        endcase
    end

    always_ff @(posedge clk_sram or posedge rst_sram) begin
        if (rst_sram) begin
            r_dstate    <= D_IDLE;
            r_dq_idx    <= 5'd0;
            r_dq_ok_bits<= 16'h0000;
            r_data_done <= 1'b0;
            r_cs_seen   <= 1'b0;
            r_we_seen   <= 1'b0;
            r_oe_seen   <= 1'b0;
        end else begin
            r_dstate <= r_dnext;
            if (!sram_r_cs_n) r_cs_seen <= 1'b1;
            if (!sram_r_we_n) r_we_seen <= 1'b1;
            if (!sram_r_oe_n) r_oe_seen <= 1'b1;
            case (r_dstate)
                D_IDLE: begin
                    r_dq_idx     <= 5'd0;
                    r_dq_ok_bits <= 16'hFFFF;
                    r_data_done  <= 1'b0;
                end
                D_R1_WAIT: if (r_drv_ready) begin
                    logic [15:0] exp1 = (16'h0001 << r_dq_idx);
                    if (r_drv_rdata != exp1) r_dq_ok_bits[r_dq_idx] <= 1'b0;
                end
                D_R0_WAIT: if (r_drv_ready) begin
                    logic [15:0] exp0 = ~(16'h0001 << r_dq_idx);
                    if (r_drv_rdata != exp0) r_dq_ok_bits[r_dq_idx] <= 1'b0;
                end
                D_NEXT: begin
                    if (r_dq_idx == 5'd15) r_data_done <= 1'b1;
                    else                    r_dq_idx    <= r_dq_idx + 5'd1;
                end
                default: ;
            endcase
        end
    end

    always_comb begin
        r_dnext = r_dstate;
        r_d_req = 1'b0; r_d_we = 1'b0; r_d_addr = DQ_TEST_ADDR; r_d_wdata = 16'h0000;
        case (r_dstate)
            D_IDLE: if (r_addr_done && r_drv_ready) r_dnext = D_W1_ISSUE;
            D_W1_ISSUE: if (r_drv_ready) begin
                r_d_req=1; r_d_we=1; r_d_addr=DQ_TEST_ADDR; r_d_wdata=(16'h0001<<r_dq_idx); r_dnext=D_W1_WAIT;
            end
            D_W1_WAIT:  if (r_drv_ready) r_dnext = D_R1_ISSUE;
            D_R1_ISSUE: if (r_drv_ready) begin
                r_d_req=1; r_d_we=0; r_d_addr=DQ_TEST_ADDR; r_dnext=D_R1_WAIT;
            end
            D_R1_WAIT:  if (r_drv_ready) r_dnext = D_W0_ISSUE;
            D_W0_ISSUE: if (r_drv_ready) begin
                r_d_req=1; r_d_we=1; r_d_addr=DQ_TEST_ADDR; r_d_wdata=~(16'h0001<<r_dq_idx); r_dnext=D_W0_WAIT;
            end
            D_W0_WAIT:  if (r_drv_ready) r_dnext = D_R0_ISSUE;
            D_R0_ISSUE: if (r_drv_ready) begin
                r_d_req=1; r_d_we=0; r_d_addr=DQ_TEST_ADDR; r_dnext=D_R0_WAIT;
            end
            D_R0_WAIT:  if (r_drv_ready) r_dnext = D_NEXT;
            D_NEXT:     r_dnext = (r_dq_idx==5'd15) ? D_DONE : D_W1_ISSUE;
            D_DONE:     r_dnext = D_DONE;
            default:    r_dnext = D_IDLE;
        endcase
    end

    always_comb begin
        if (!l_addr_done) begin
            l_drv_req   = l_a_req;
            l_drv_we    = l_a_we;
            l_drv_addr  = l_a_addr;
            l_drv_wdata = l_a_wdata;
        end else begin
            l_drv_req   = l_d_req;
            l_drv_we    = l_d_we;
            l_drv_addr  = l_d_addr;
            l_drv_wdata = l_d_wdata;
        end
    end

    always_comb begin
        if (!r_addr_done) begin
            r_drv_req   = r_a_req;
            r_drv_we    = r_a_we;
            r_drv_addr  = r_a_addr;
            r_drv_wdata = r_a_wdata;
        end else begin
            r_drv_req   = r_d_req;
            r_drv_we    = r_d_we;
            r_drv_addr  = r_d_addr;
            r_drv_wdata = r_d_wdata;
        end
    end

    wire left_all_done  = l_addr_done && l_data_done;
    wire right_all_done = r_addr_done && r_data_done;

    localparam int H_VISIBLE = 640;
    localparam int H_FRONT   = 16;
    localparam int H_SYNC    = 96;
    localparam int H_BACK    = 48;
    localparam int H_TOTAL   = H_VISIBLE + H_FRONT + H_SYNC + H_BACK;
    localparam int V_VISIBLE = 480;
    localparam int V_FRONT   = 10;
    localparam int V_SYNC    = 2;
    localparam int V_BACK    = 33;
    localparam int V_TOTAL   = V_VISIBLE + V_FRONT + V_SYNC + V_BACK;

    logic [9:0] h_cnt, v_cnt;
    logic       de;
    wire pix_rst = ~clk_locked;

    always_ff @(posedge clk_pix or posedge pix_rst) begin
        if (pix_rst) begin
            h_cnt <= 10'd0; v_cnt <= 10'd0;
        end else begin
            if (h_cnt == H_TOTAL-1) begin
                h_cnt <= 10'd0;
                v_cnt <= (v_cnt == V_TOTAL-1) ? 10'd0 : v_cnt + 10'd1;
            end else begin
                h_cnt <= h_cnt + 10'd1;
            end
        end
    end

    assign de = (h_cnt < H_VISIBLE) && (v_cnt < V_VISIBLE);
    assign vga_hsync = ~((h_cnt >= (H_VISIBLE + H_FRONT)) && (h_cnt <  (H_VISIBLE + H_FRONT + H_SYNC)));
    assign vga_vsync = ~((v_cnt >= (V_VISIBLE + V_FRONT)) && (v_cnt <  (V_VISIBLE + V_FRONT + V_SYNC)));

    localparam int N_ADDR   = 21;
    localparam int GAP_W    = 2;
    localparam int ADDR_SLOT_W  = 24;
    localparam int ADDR_STRIPE  = ADDR_SLOT_W - GAP_W;
    localparam int ADDR_PANEL_W = N_ADDR * ADDR_SLOT_W;
    localparam int N_DQ         = 16;
    localparam int DQ_SLOT_W    = 6;
    localparam int DQ_STRIPE    = DQ_SLOT_W - GAP_W;
    localparam int DQ_PANEL_W   = N_DQ * DQ_SLOT_W;
    localparam int N_CTRL       = 3;
    localparam int CTRL_SLOT_W  = 8;
    localparam int CTRL_STRIPE  = CTRL_SLOT_W - GAP_W;
    localparam int CTRL_PANEL_W = N_CTRL * CTRL_SLOT_W;
    localparam int PANEL_TOTAL  = ADDR_PANEL_W + DQ_PANEL_W + CTRL_PANEL_W;

    logic [9:0] x_in_panel;
    logic [4:0] addr_idx;
    logic [4:0] dq_idx;
    logic [1:0] ctrl_idx;
    logic [9:0] slot_x;

    always_comb begin
        x_in_panel = h_cnt;
        addr_idx = 5'd31;
        dq_idx   = 5'd31;
        ctrl_idx = 2'd3;
        slot_x   = 10'd0;
        if (x_in_panel < ADDR_PANEL_W) begin
            addr_idx = x_in_panel / ADDR_SLOT_W;
            slot_x   = x_in_panel % ADDR_SLOT_W;
        end else if (x_in_panel < ADDR_PANEL_W + DQ_PANEL_W) begin
            logic [9:0] rel = x_in_panel - ADDR_PANEL_W;
            dq_idx = rel / DQ_SLOT_W;
            slot_x = rel % DQ_SLOT_W;
        end else if (x_in_panel < ADDR_PANEL_W + DQ_PANEL_W + CTRL_PANEL_W) begin
            logic [9:0] rel = x_in_panel - ADDR_PANEL_W - DQ_PANEL_W;
            ctrl_idx = rel / CTRL_SLOT_W;
            slot_x   = rel % CTRL_SLOT_W;
        end
    end

    function automatic void set_rgb_green(output logic [4:0] r, output logic [5:0] g, output logic [4:0] b);
        r=5'h00; g=6'h3F; b=5'h00;
    endfunction
    function automatic void set_rgb_red(output logic [4:0] r, output logic [5:0] g, output logic [4:0] b);
        r=5'h1F; g=6'h00; b=5'h00;
    endfunction
    function automatic void set_rgb_blue_dim(output logic [4:0] r, output logic [5:0] g, output logic [4:0] b);
        r=5'h00; g=6'h00; b=5'h0F;
    endfunction
    function automatic void set_rgb_grey(output logic [4:0] r, output logic [5:0] g, output logic [4:0] b);
        r=5'h08; g=6'h10; b=5'h08;
    endfunction
    function automatic void set_rgb_black(output logic [4:0] r, output logic [5:0] g, output logic [4:0] b);
        r=5'h00; g=6'h00; b=5'h00;
    endfunction

    wire left_done_addr         = l_addr_done;
    wire right_done_addr        = r_addr_done;
    wire left_all_bits_ok_addr  = &l_bit_ok;
    wire right_all_bits_ok_addr = &r_bit_ok;
    wire left_fail_addr  = left_done_addr  && !left_all_bits_ok_addr;
    wire right_fail_addr = right_done_addr && !right_all_bits_ok_addr;

    assign gp_io[0] = left_done_addr;
    assign gp_io[1] = left_fail_addr;
    assign gp_io[2] = right_done_addr;
    assign gp_io[3] = right_fail_addr;
    assign gp_io[4] = 1'bz;
    assign gp_io[5] = 1'bz;

    always_comb begin
        set_rgb_black(vga_r, vga_g, vga_b);
        if (!de) begin
        end else if (!(left_all_done && right_all_done)) begin
            set_rgb_blue_dim(vga_r, vga_g, vga_b);
        end else if (x_in_panel < ADDR_PANEL_W) begin
            if (slot_x >= ADDR_STRIPE) begin
                set_rgb_black(vga_r, vga_g, vga_b);
            end else if (v_cnt < (V_VISIBLE/2)) begin
                if (l_bit_ok[addr_idx]) set_rgb_green(vga_r, vga_g, vga_b);
                else                    set_rgb_red  (vga_r, vga_g, vga_b);
            end else begin
                if (r_bit_ok[addr_idx]) set_rgb_green(vga_r, vga_g, vga_b);
                else                    set_rgb_red  (vga_r, vga_g, vga_b);
            end
        end else if (x_in_panel < ADDR_PANEL_W + DQ_PANEL_W) begin
            if (slot_x >= DQ_STRIPE) begin
                set_rgb_black(vga_r, vga_g, vga_b);
            end else if (v_cnt < (V_VISIBLE/2)) begin
                if (l_dq_ok_bits[dq_idx]) set_rgb_green(vga_r, vga_g, vga_b);
                else                      set_rgb_red  (vga_r, vga_g, vga_b);
            end else begin
                if (r_dq_ok_bits[dq_idx]) set_rgb_green(vga_r, vga_g, vga_b);
                else                      set_rgb_red  (vga_r, vga_g, vga_b);
            end
        end else if (x_in_panel < ADDR_PANEL_W + DQ_PANEL_W + CTRL_PANEL_W) begin
            if (slot_x >= CTRL_STRIPE) begin
                set_rgb_black(vga_r, vga_g, vga_b);
            end else if (v_cnt < (V_VISIBLE/2)) begin
                logic ok;
                case (ctrl_idx)
                    2'd0: ok = l_cs_seen;
                    2'd1: ok = l_we_seen;
                    default: ok = l_oe_seen;
                endcase
                if (ok) set_rgb_green(vga_r, vga_g, vga_b); else set_rgb_red(vga_r, vga_g, vga_b);
            end else begin
                logic ok;
                case (ctrl_idx)
                    2'd0: ok = r_cs_seen;
                    2'd1: ok = r_we_seen;
                    default: ok = r_oe_seen;
                endcase
                if (ok) set_rgb_green(vga_r, vga_g, vga_b); else set_rgb_red(vga_r, vga_g, vga_b);
            end
        end else begin
            set_rgb_grey(vga_r, vga_g, vga_b);
        end
    end

    assign spi_io = 4'bzzzz;

endmodule
