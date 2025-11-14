`default_nettype none
`timescale 1ns / 1ps

module sram_driver (
    input  wire logic        clk,
    input  wire logic        rst,

    input  wire logic        req,
    input  wire logic        write_enable,
    input  wire logic [20:0] address,
    input  wire logic [15:0] write_data,
    output      logic [15:0] read_data,
    output      logic        ready,

    // SRAM pins
    output      logic [20:0] sram_addr,
    inout  wire [15:0]       sram_dq,
    output      logic        sram_cs_n,
    output      logic        sram_we_n,
    output      logic        sram_oe_n,
    output      logic        sram_ub_n,
    output      logic        sram_lb_n
);

    // FSM states
    typedef enum logic [1:0] { IDLE, SETUP, ACCESS } state_t;
    state_t state, next_state;

    logic [20:0] addr_reg;
    logic [15:0] wdata_reg;
    logic        we_reg;

    // Bidirectional bus handling
    logic [15:0] dq_out;
    logic        dq_oe;   // output enable

    assign sram_dq = dq_oe ? dq_out : 16'hZZZZ;
    wire [15:0] dq_in = sram_dq;

    // Always use full 16-bit word
    assign sram_ub_n = 1'b0;
    assign sram_lb_n = 1'b0;

    // Sequential: state + request latching + read_data capture
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state     <= IDLE;
            addr_reg  <= '0;
            wdata_reg <= '0;
            we_reg    <= 1'b0;
            read_data <= '0;
        end else begin
            state <= next_state;

            // Latch request when we leave IDLE
            if (state == IDLE && req) begin
                addr_reg  <= address;
                wdata_reg <= write_data;
                we_reg    <= write_enable;
            end

            // Capture read data at the end of ACCESS state
            if (state == ACCESS && !we_reg) begin
                read_data <= dq_in;
            end
        end
    end

    // Combinational: next state + SRAM drive
    always_comb begin
        // defaults
        next_state = state;
        ready      = 1'b0;

        sram_addr  = addr_reg;
        sram_cs_n  = 1'b1;
        sram_we_n  = 1'b1;
        sram_oe_n  = 1'b1;

        dq_out     = wdata_reg;
        dq_oe      = 1'b0;

        unique case (state)
            IDLE: begin
                ready = 1'b1;
                if (req) begin
                    // latch happens in sequential block
                    next_state = SETUP;
                end
            end

            // Drive address and control, allow signals to settle
            SETUP: begin
                sram_addr = addr_reg;
                sram_cs_n = 1'b0;

                if (we_reg) begin
                    // WRITE: still 1-cycle
                    sram_we_n = 1'b0;
                    sram_oe_n = 1'b1;
                    dq_out    = wdata_reg;
                    dq_oe     = 1'b1;
                    next_state = IDLE;
                end else begin
                    // READ: enable outputs, but don't sample yet
                    sram_we_n = 1'b1;
                    sram_oe_n = 1'b0;
                    dq_oe     = 1'b0;
                    next_state = ACCESS;
                end
            end

            // Extra cycle for read access time, sample at end
            ACCESS: begin
                sram_addr = addr_reg;
                sram_cs_n = 1'b0;
                sram_we_n = 1'b1;
                sram_oe_n = 1'b0;
                dq_oe     = 1'b0;

                next_state = IDLE;
            end

            default: begin
                next_state = IDLE;
            end
        endcase
    end

endmodule
