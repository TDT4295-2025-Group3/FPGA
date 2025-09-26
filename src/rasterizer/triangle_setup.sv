module triangle_setup #(
    parameter int WIDTH  = 320,
    parameter int HEIGHT = 240
) (
    input  wire logic clk,
    input  wire logic rst,

    input  wire vertex_t v0,
    input  wire vertex_t v1,
    input  wire vertex_t v2,

    input  wire logic    in_valid,
    output logic         in_ready,

    output triangle_state_t out_state,
    output logic            out_valid,
    input  wire logic       out_ready,
    output logic            busy
);

    // FSM states
    typedef enum logic [1:0] {S_IDLE, S_DIV_START, S_DIV_WAIT, S_OUTPUT} state_t;
    state_t state, next_state;

    // Registers for geometry
    triangle_state_t tri_reg;
    logic signed [75:0] denom_comb;
    logic signed [63:0] denom_trunc, denom_abs;
    logic denom_neg;

    // Divider interface signals
    logic        div_s_valid, div_s_ready;
    logic [63:0] div_divisor, div_dividend;
    logic        div_m_valid;
    logic [87:0] div_m_data; // check width: yours said [87:0]
    logic        div_m_ready;
    logic        div_dbz;

    // Instance of divider IP
    div_rasterizer u_div (
        .aclk                   (clk),
        .aresetn                (~rst),

        .s_axis_divisor_tvalid  (div_s_valid),
        .s_axis_divisor_tready  (div_s_ready),
        .s_axis_divisor_tdata   (div_divisor),

        .s_axis_dividend_tvalid (div_s_valid),
        .s_axis_dividend_tready (),
        .s_axis_dividend_tdata  (div_dividend),

        .m_axis_dout_tvalid     (div_m_valid),
        .m_axis_dout_tready     (1'b1), // always ready
        .m_axis_dout_tdata      (div_m_data),
        .m_axis_dout_tuser      (div_dbz)
    );

    // Handshake outputs
    assign busy     = (state != S_IDLE);
    assign in_ready = (state == S_IDLE);
    assign out_valid= (state == S_OUTPUT);

    // Divider inputs
    assign div_divisor  = denom_abs;
    assign div_dividend = 64'd65536; // 1.0 in Q0.16

    // FSM
    always_ff @(posedge clk or posedge rst) begin
        if (rst) state <= S_IDLE;
        else     state <= next_state;
    end

    always_comb begin
        next_state = state;
        case (state)
            S_IDLE: if (in_valid && in_ready) next_state = S_DIV_START;
            S_DIV_START: if (div_s_ready)     next_state = S_DIV_WAIT;
            S_DIV_WAIT: if (div_m_valid)      next_state = S_OUTPUT;
            S_OUTPUT: if (out_valid && out_ready) next_state = S_IDLE;
        endcase
    end

    // Drive div_s_valid in S_DIV_START
    assign div_s_valid = (state == S_DIV_START);

    // Work registers
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            tri_reg <= '0;
            denom_trunc <= '0;
            denom_abs   <= '0;
            denom_neg   <= 1'b0;
        end else begin
            if (state == S_IDLE && in_valid && in_ready) begin
                // Compute geometry
                tri_reg.v0x <= v0.pos.x[31:13];
                tri_reg.v0y <= v0.pos.y[31:13];
                tri_reg.e0x <= v1.pos.x[31:13] - v0.pos.x[31:13];
                tri_reg.e0y <= v1.pos.y[31:13] - v0.pos.y[31:13];
                tri_reg.e1x <= v2.pos.x[31:13] - v0.pos.x[31:13];
                tri_reg.e1y <= v2.pos.y[31:13] - v0.pos.y[31:13];

                tri_reg.d00 <= tri_reg.e0x*tri_reg.e0x + tri_reg.e0y*tri_reg.e0y;
                tri_reg.d01 <= tri_reg.e0x*tri_reg.e1x + tri_reg.e0y*tri_reg.e1y;
                tri_reg.d11 <= tri_reg.e1x*tri_reg.e1x + tri_reg.e1y*tri_reg.e1y;

                denom_comb  = tri_reg.d00*tri_reg.d11 - tri_reg.d01*tri_reg.d01;
                denom_trunc = denom_comb[75 -: 64];
                denom_neg   = denom_trunc[63];
                denom_abs   = denom_neg ? (~denom_trunc + 1) : denom_trunc;

                // Fill bbox/colors/depths
                tri_reg.bbox_min_x <= clamp(min3(v0.pos.x, v1.pos.x, v2.pos.x) >>> 16, 0, WIDTH-1);
                tri_reg.bbox_max_x <= clamp((max3(v0.pos.x, v1.pos.x, v2.pos.x) + 32'hFFFF) >>> 16, 0, WIDTH-1);
                tri_reg.bbox_min_y <= clamp(min3(v0.pos.y, v1.pos.y, v2.pos.y) >>> 16, 0, HEIGHT-1);
                tri_reg.bbox_max_y <= clamp((max3(v0.pos.y, v1.pos.y, v2.pos.y) + 32'hFFFF) >>> 16, 0, HEIGHT-1);
                tri_reg.v0_color   <= v0.color;
                tri_reg.v1_color   <= v1.color;
                tri_reg.v2_color   <= v2.color;
                tri_reg.v0_depth   <= v0.pos.z;
                tri_reg.v1_depth   <= v1.pos.z;
                tri_reg.v2_depth   <= v2.pos.z;
            end

            if (state == S_DIV_WAIT && div_m_valid) begin
                // Grab reciprocal result
                tri_reg.denom_inv <= {div_m_data[15:0], 1'b0}; // convert Q1.15 -> Q0.16
                tri_reg.denom_neg <= denom_neg;
            end
        end
    end

    // Output state register
    assign out_state = tri_reg;

endmodule
