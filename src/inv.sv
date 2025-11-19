module inv #(
    parameter int IN_BITS   = 64,
    parameter int IN_FBITS  = 0,
    parameter int OUT_BITS  = 41,
    parameter int OUT_FBITS = 35
)(
    input  wire  logic                       clk, rst, start,
    input  wire  logic signed [IN_BITS-1:0]  x,   // Q(*).IN_FBITS
    output       logic                       busy, done, valid, dbz, ovf,
    output       logic signed [OUT_BITS-1:0] y    // Q(OUT_BITS-OUT_FBITS-1).OUT_FBITS
);
    // sign-preserving truncation of x to divider width
    logic signed [OUT_BITS-1:0] b_in;
    assign b_in = x;

    // pre-scale dividend to account for IN_FBITS
    logic signed [OUT_BITS-1:0] a_in = $signed(1) <<< IN_FBITS;

    div #(
        .WIDTH (OUT_BITS),
        .FBITS (OUT_FBITS)
    ) u_div (
        .clk(clk), .rst(rst), .start(start),
        .busy(busy), .done(done), .valid(valid), .dbz(dbz), .ovf(ovf),
        .a(a_in), .b(b_in), .val(y)
    );
endmodule
