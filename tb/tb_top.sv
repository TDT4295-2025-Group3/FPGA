`timescale 1ns / 1ps

module tb_top;

  logic clk_100m;
  logic btn_rst_n;
  logic frame;
  // ... add signals for VGA if needed

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

  // Frame pulse every 10 ms
  initial begin
    frame = 0;
    forever begin
      #10_000_000; // 10 ms in 1 ns units
      frame = 1;
      #10;
      frame = 0;
    end
  end

  // Instantiate your top
  top dut (
    .clk_100m(clk_100m),
    .btn_rst_n(btn_rst_n),
    .frame(frame)
    // hook up other ports (hdmi, leds) as open/unconnected
  );

  // Simulation runtime
  initial begin
    #50_000_000; // 50 ms
    $finish;
  end

endmodule
