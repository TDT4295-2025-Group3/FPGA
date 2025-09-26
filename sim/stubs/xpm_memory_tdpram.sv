`default_nettype none
`timescale 1ns/1ps

module xpm_memory_tdpram #(
    parameter int MEMORY_SIZE       = 1024,   // total bits
    parameter string MEMORY_PRIMITIVE = "auto",
    parameter string CLOCKING_MODE  = "common_clock",
    parameter int WRITE_DATA_WIDTH_A = 12,
    parameter int READ_DATA_WIDTH_B  = 12,
    parameter int ADDR_WIDTH_A       = 10,
    parameter int ADDR_WIDTH_B       = 10,
    parameter int READ_LATENCY_B     = 1,
    parameter string WRITE_MODE_B    = "read_first"
)(
    // Port A: write
    input  wire                      clka,
    input  wire                      ena,
    input  wire                      wea,
    input  wire [ADDR_WIDTH_A-1:0]   addra,
    input  wire [WRITE_DATA_WIDTH_A-1:0] dina,

    // Port B: read
    input  wire                      clkb,
    input  wire                      enb,
    input  wire [ADDR_WIDTH_B-1:0]   addrb,
    output logic [READ_DATA_WIDTH_B-1:0] doutb
);

    localparam int DEPTH_A = MEMORY_SIZE / WRITE_DATA_WIDTH_A;
    localparam int DEPTH_B = MEMORY_SIZE / READ_DATA_WIDTH_B;

    // Use the larger depth (since both ports address the same memory)
    localparam int DEPTH = (DEPTH_A > DEPTH_B) ? DEPTH_A : DEPTH_B;

    // Simple memory array
    logic [WRITE_DATA_WIDTH_A-1:0] mem [0:DEPTH-1];

    // Port A: synchronous write
    always_ff @(posedge clka) begin
        if (ena && wea) begin
            mem[addra] <= dina;
        end
    end

    // Port B: synchronous read with latency
    logic [READ_DATA_WIDTH_B-1:0] read_reg [0:READ_LATENCY_B-1];

    always_ff @(posedge clkb) begin
        if (enb) begin
            read_reg[0] <= mem[addrb];
        end
    end

    // Shift register for read latency > 1
    generate
        if (READ_LATENCY_B > 1) begin : gen_read_latency
            integer i;
            always_ff @(posedge clkb) begin
                for (i = 1; i < READ_LATENCY_B; i++) begin
                    read_reg[i] <= read_reg[i-1];
                end
            end
            assign doutb = read_reg[READ_LATENCY_B-1];
        end else begin : gen_read_latency1
            assign doutb = read_reg[0];
        end
    endgenerate

endmodule
