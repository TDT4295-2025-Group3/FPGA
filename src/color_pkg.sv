`default_nettype none
`timescale 1ns / 1ps

package color_pkg;

  typedef struct packed {
      logic [3:0] r;
      logic [3:0] g;
      logic [3:0] b;
  } color12_t;

  typedef struct packed {
      logic [4:0] r;
      logic [5:0] g;
      logic [4:0] b;
  } color16_t;

endpackage
