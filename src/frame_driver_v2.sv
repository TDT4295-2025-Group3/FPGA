`timescale 1ns / 1ps
import transform_pkg::*;
import buffer_id_pkg::*;
import vertex_pkg::*;
`default_nettype wire

module frame_drive_v2r#(
    localparam MAX_VERT  = 256,
    localparam MAX_TRI   = 256,
    localparam MAX_VERT_CNT = 256,
    localparam MAX_TRI_CNT  = 256,
    localparam VTX_W     = 108,
    localparam VIDX_W = $clog2(MAX_VERT_CNT),
    localparam TIDX_W = $clog2(MAX_TRI_CNT),
    localparam TRI_W     = 3*VIDX_W
)(
    // General inputs
    input  logic clk, rst,

    // Memory ← Frame driver (addresses we assert)
    output logic [$clog2(MAX_VERT)-1:0] vert_addr, // read address for vertex RAM (driven when requesting)
    output logic [$clog2(MAX_TRI)-1:0]  tri_addr,  // read address for tri RAM (driven to fetch triangle indices)
    output logic [7:0] rd_inst_id,                  // instance id being read (driven by frame driver)

    // Memory → Frame driver (data inputs, assumed to appear one cycle after address)
    input  transform_t   transform_in, // current instance transform (assumed valid when we start)
    input  vertex_t      vert_in,      // vertex data returned by vertex RAM (1-cycle latency)
    input  logic [TRI_W-1:0] idx_tri,  // triangle indices returned by tri RAM (1-cycle latency)

    // descriptor for instance (provided by raster_mem)
    input  logic [$clog2(MAX_VERT)-1:0]  curr_vert_base,
    input  logic [$clog2(MAX_TRI)-1:0]   curr_tri_base,
    input  logic [TIDX_W-1:0]            curr_tri_count,

    // Frame driver → Transform
    input  logic draw_ready, 
    output logic draw_valid,
    output triangle_t tri_out,
    output transform_t transform_out
);

    // FSM counters & regs
    logic [VIDX_W-1:0] vert_ctr;
    logic [TIDX_W-1:0] tri_ctr;

    // Registers to hold in-flight data
    logic [TRI_W-1:0]   idx_tri_reg;       // captured triangle index word
    vertex_t            v_collect [0:2];   // collected three vertices for current triangle
    triangle_t          tri_reg;
    transform_t         transform_reg;

    // state machine
    typedef enum logic [2:0] {
        IDLE,
        REQUEST_TRI,   // assert tri_addr
        WAIT_TRI,      // capture idx_tri, assert vert addr for v0
        CAPTURE_V0,    // capture v0 (vert_in), request v1
        CAPTURE_V1,    // capture v1, request v2
        CAPTURE_V2,    // capture v2
        OUTPUT_TRI     // pulse draw_valid, present tri + transform
    } state_e;

    state_e state, next_state;

    // ---------- Sequential: registers, captures, counters ----------
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state        <= IDLE;
            tri_ctr      <= '0;
            idx_tri_reg  <= '0;
            tri_reg      <= '0;
            transform_reg<= '0;
            rd_inst_id   <= 8'b0;
            v_collect[0] <= '0;
            v_collect[1] <= '0;
            v_collect[2] <= '0;
        end else begin
            state <= next_state;

            // when starting a new streaming session, snapshot instance & transform
            if (state == IDLE && next_state == REQUEST_TRI && draw_ready) begin
                transform_reg <= transform_in;
                rd_inst_id <= rd_inst_id + 1; // optional: advance instance id read pointer
            end

            // Capture triangle index word when we're in WAIT_TRI (tri_idx arrives one cycle after tri_addr)
            if (state == WAIT_TRI) begin
                idx_tri_reg <= idx_tri;
            end

            // Capture vertices when in the CAPTURE states (vert_in arrives one cycle after vert_addr)
            if (state == CAPTURE_V0) begin
                v_collect[0] <= vert_in;
            end else if (state == CAPTURE_V1) begin
                v_collect[1] <= vert_in;
            end else if (state == CAPTURE_V2) begin
                v_collect[2] <= vert_in;
            end

            // When in OUTPUT_TRI produce tri_reg from gathered vertices (registered values)
            if (state == OUTPUT_TRI) begin
                tri_reg.v0 <= v_collect[0];
                tri_reg.v1 <= v_collect[1];
                tri_reg.v2 <= v_collect[2];
                // transform_reg already captured earlier
            end

            // Advance tri counter when leaving OUTPUT_TRI (ready to fetch next triangle)
            if (state == OUTPUT_TRI && next_state != OUTPUT_TRI) begin
                if (tri_ctr < curr_tri_count - 1) begin
                    tri_ctr <= tri_ctr + 1;
                end else begin
                    tri_ctr <= '0; // wrap or stop depending on intended behavior
                end
            end
        end
    end

    // ---------- Combinational: next-state and outputs (single place) ----------
    // tri_addr, vert_addr, draw_valid are driven only here (prevents multi-driven nets).
    always_comb begin
        // defaults
        next_state = state;
        tri_addr   = '0;
        vert_addr  = '0;
        draw_valid = 1'b0;

        case (state)
            IDLE: begin
                if (draw_ready) begin
                    next_state = REQUEST_TRI;
                end
            end

            REQUEST_TRI: begin
                // assert tri read for current triangle
                tri_addr = curr_tri_base + tri_ctr;
                next_state = WAIT_TRI; // idx_tri will be available next cycle
            end

            WAIT_TRI: begin
                // we've captured idx_tri_reg in sequential block; now request v0 this cycle
                vert_addr = curr_vert_base + idx_tri[VIDX_W-1:0]; // idx_tri is the BRAM output this cycle
                next_state = CAPTURE_V0;
            end

            CAPTURE_V0: begin
                // We expect vert_in (v0) this cycle (captured in sequential block). Request v1 now:
                vert_addr = curr_vert_base + idx_tri_reg[2*VIDX_W-1:VIDX_W]; // request v1 (data will appear next cycle)
                next_state = CAPTURE_V1;
            end

            CAPTURE_V1: begin
                // Capture v1 this cycle; request v2 next
                vert_addr = curr_vert_base + idx_tri_reg[3*VIDX_W-1:2*VIDX_W]; // request v2
                next_state = CAPTURE_V2;
            end

            CAPTURE_V2: begin
                // Capture v2 this cycle; next output assembled triangle
                next_state = OUTPUT_TRI;
            end

            OUTPUT_TRI: begin
                // Present data for one cycle if consumer ready
                if (draw_ready) begin
                    draw_valid = 1'b1;
                    next_state = (tri_ctr < curr_tri_count - 1) ? REQUEST_TRI : IDLE;
                end else begin
                    // If consumer not ready, stay IDLE (could also stall here depending on intended behavior)
                    next_state = IDLE;
                end
            end

            default: next_state = IDLE;
        endcase
    end

    // outputs driven from registers
    assign tri_out = tri_reg;
    assign transform_out = transform_reg;

endmodule
