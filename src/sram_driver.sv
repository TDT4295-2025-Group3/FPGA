`default_nettype none
`timescale 1ns / 1ps

module sram_driver (
    input wire logic clk,
    input wire logic rst,
    input wire logic req,           
    input wire logic write_enable,
    input wire logic [20:0] address,
    input wire logic [15:0] write_data,
    output logic [15:0] read_data,
    output logic ready,

    // SRAM pins
    output logic [20:0] sram_addr,
    inout  wire  [15:0] sram_dq,
    output logic        sram_cs_n,
    output logic        sram_we_n,
    output logic        sram_oe_n,
    output logic        sram_ub_n,
    output logic        sram_lb_n
);
    // FSM states
    typedef enum logic [1:0] { IDLE, ACCESS } state_t;

    state_t state, next_state;

    // Latched request info
    logic [20:0] addr_reg;
    logic [15:0] wdata_reg;
    logic we_reg;

    // Bidirectional bus handling
    logic [15:0] dq_out;
    logic dq_oe;  // output enable (1 = drive bus)

    assign sram_dq = dq_oe ? dq_out : 16'hZZZZ;
    wire [15:0] dq_in = sram_dq;

    // Byte enables: always full 16-bit word
    always_comb begin
        sram_ub_n = 1'b0; // active low
        sram_lb_n = 1'b0; // active low
    end

    // Sequential part: state + latching request + capturing read data
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state     <= IDLE;
            addr_reg  <= '0;
            wdata_reg <= '0;
            we_reg    <= 1'b0;
            read_data <= '0;
        end else begin
            state <= next_state;

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

    // Combinational part: next state and SRAM control signals
    always_comb begin
        // Defaults
        next_state  = state;
        ready       = 1'b0;

        // Default SRAM signals (inactive)
        sram_addr   = addr_reg;
        sram_cs_n   = 1'b1;
        sram_we_n   = 1'b1;
        sram_oe_n   = 1'b1;
        dq_out      = wdata_reg;
        dq_oe       = 1'b0;

        unique case (state)
            IDLE: begin
                ready = 1'b1;    // ready for new request
                if (req) begin
                    // Latch happens in sequential block
                    next_state = ACCESS;
                end
            end

            ACCESS: begin
                // Drive address and control lines
                sram_addr = addr_reg;
                sram_cs_n = 1'b0;    // select chip

                if (we_reg) begin
                    // WRITE cycle
                    sram_we_n = 1'b0;    // assert write
                    sram_oe_n = 1'b1;    // disable output
                    dq_out    = wdata_reg;
                    dq_oe     = 1'b1;    // drive data to SRAM

                    // One clock of ACCESS is enough if clk period >= tWC/tPWE
                    next_state = IDLE;
                end else begin
                    // READ cycle
                    sram_we_n = 1'b1;    // not writing
                    sram_oe_n = 1'b0;    // enable output
                    dq_oe     = 1'b0;    // don't drive bus

                    // At the end of this cycle, we capture dq_in -> rdata
                    next_state = IDLE;
                end
            end

            default: begin
                next_state = IDLE;
            end
        endcase
    end

endmodule
