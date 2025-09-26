`timescale 1ns / 1ps

module tb_top;

  logic clk_100m;
  logic btn_rst_n;

  // Clock generation
  initial begin
    clk_100m = 0;
    forever #5 clk_100m = ~clk_100m; // 100 MHz
  end

  // Reset
  initial begin
    btn_rst_n = 0;
    #100;
    btn_rst_n = 1;
  end

  // Instantiate your top
  top dut (
    .clk_100m(clk_100m),
    .btn_rst_n(btn_rst_n)
  );

  // Simulation runtime
  initial begin
    #100_000_000;
    $finish;
  end

endmodule
