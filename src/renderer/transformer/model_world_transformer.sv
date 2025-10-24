// `timescale 1ns / 1ps
// `default_nettype none
// import math_pkg::*;
// import vertex_pkg::*;
// import transformer_pkg::*;

// module model_world_transformer(
//     input wire logic         clk,
//     input wire logic         rst,

//     input wire model_world_t model_world,
//     input wire logic         in_valid,
//     output logic             in_ready,

//     output world_camera_t    out_world_camera,
//     output logic             out_valid,
//     input  wire logic        out_ready,
//     output logic             busy
// );

//     model_world_t model_world_r;
//     always_ff @(posedge clk or posedge rst) begin
//         if (rst) begin
//             model_world_r <= '0;
//         end else if (in_valid && in_ready) begin
//             model_world_r <= model_world;
//         end
//     end

//     // pipeline registers
//     vertex_t load_v, rot_v, world_v;
//     triangle_t out_triangle_r;
//     logic [1:0] load_vert_ctr;
//     logic [1:0] vert_ctr_out;    // which vertex is being written out
//     logic [2:0] valid_pipe;      // shift register for pipeline stages  
//     logic       load_vert;
//     logic       pipe_en;
//     logic       triangle_ready;
//     logic       triangle_ready_d;
//     logic       out_valid_r;

//     q16_16_t R11, R12, R13;
//     q16_16_t R21, R22, R23;
//     q16_16_t R31, R32, R33;
//     always_comb begin
//         R11 = model_world_r.transform.rot_mtx.R11;
//         R12 = model_world_r.transform.rot_mtx.R12;
//         R13 = model_world_r.transform.rot_mtx.R13;
//         R21 = model_world_r.transform.rot_mtx.R21;
//         R22 = model_world_r.transform.rot_mtx.R22;
//         R23 = model_world_r.transform.rot_mtx.R23;
//         R31 = model_world_r.transform.rot_mtx.R31;
//         R32 = model_world_r.transform.rot_mtx.R32;
//         R33 = model_world_r.transform.rot_mtx.R33;
//     end

//     assign busy = |valid_pipe || out_valid_r;  // busy if any stage is active
//     assign pipe_en  = out_ready || !valid_pipe[2]; 
//     assign in_ready = pipe_en;
//     assign triangle_ready = valid_pipe[2] && (vert_ctr_out == 2);
    
//     // Using a pipeline to maxemise thoughput with valid_pipe controll signal
//     // Load vertex
//     always_ff @(posedge clk) begin
//         if (rst) begin
//             vert_ctr_out  <= 0;
//             load_vert_ctr <= 0;
//             load_vert     <= 0;
//             load_v        <= 0;
//             out_valid_r   <= 0;
//             rot_v         <= 0;
//             world_v       <= 0;
//             out_triangle  <= 0;
//             valid_pipe    <= 3'b000;
//         end else begin
//             triangle_ready_d <= triangle_ready;
//             // Hold input 3 cycles
//             if(in_valid && in_ready && load_vert_ctr == 0) begin
//                 load_vert_ctr <= load_vert_ctr +1;
//                 load_vert <= 1;
//             end else if(load_vert && in_ready) begin
//                 if(load_vert_ctr == 2) begin
//                     load_vert_ctr <= 0;
//                     load_vert <= 0; 
//                 end else 
//                     load_vert_ctr <= load_vert_ctr +1;
//             end
            
//             if(load_vert && in_ready) begin
//                 if(load_vert_ctr == 2) begin
//                     load_vert_ctr <= 0;
//                     load_vert <= 0;
//                 end else begin
//                     load_vert_ctr <= load_vert_ctr + 1;
//                 end
//             end 

//             // shift pipline state
//             if(pipe_en) begin
//                 valid_pipe <= {valid_pipe[1:0], (in_valid || load_vert) && in_ready};
                
//                 // load next vertex when input valid, stage -1
//                 if ((in_valid || load_vert) && in_ready) begin
//                     unique case (load_vert_ctr)
//                         2'd0: load_v <= model_world.triangle.v0;
//                         2'd1: load_v <= model_world.triangle.v1;
//                         2'd2: load_v <= model_world.triangle.v2;
//                         default: load_v <= model_world.triangle.v0;
//                     endcase
//                 end
            
//                 // Rotation, use dot product for rotation, stage 0
//                 if (valid_pipe[0]) begin
//                     rot_v.pos.x <= mul_transform(load_v.pos.x, model_world.transform.scale.x);
//                     rot_v.pos.y <= mul_transform(load_v.pos.y, model_world.transform.scale.y);
//                     rot_v.pos.z <= mul_transform(load_v.pos.z, model_world.transform.scale.z);
//                     rot_v.color <= load_v.color;
//                 end 
                
//                 // Translation, stage 1
//                 if (valid_pipe[1]) begin
//                     // Translate to world coordinates, stage 1
//                     world_v.pos.x <= dot3_transform(R11, R12, R13, rot_v.pos.x, rot_v.pos.y, rot_v.pos.z);
//                     world_v.pos.y <= dot3_transform(R21, R22, R23, rot_v.pos.x, rot_v.pos.y, rot_v.pos.z);
//                     world_v.pos.z <= dot3_transform(R31, R32, R33, rot_v.pos.x, rot_v.pos.y, rot_v.pos.z);
//                     world_v.color   <= rot_v.color;
//                 end

//                 // load output triangle, stage 2
//                 if (valid_pipe[2]) begin
//                     unique case (vert_ctr_out)
//                         2'd0: out_triangle_r.v0    <= add_3d_transform(world_v, model_world.transform.pos);
//                         2'd1: out_triangle_r.v1    <= add_3d_transform(world_v, model_world.transform.pos);
//                         2'd2: out_triangle_r.v2    <= add_3d_transform(world_v, model_world.transform.pos);
//                         default: out_triangle_r.v0 <= add_3d_transform(world_v, model_world.transform.pos);
//                     endcase
//                 end

//                 if (vert_ctr_out == 2 && out_ready) begin
//                     vert_ctr_out <= 0;
//                 end else if (valid_pipe[2] && vert_ctr_out < 2) begin
//                     vert_ctr_out <= vert_ctr_out +1;
//                 end
//             end 
            
//             if (triangle_ready_d && !out_valid_r) begin
//                 out_valid_r <= 1; // triangle assembled this cycle
//                 out_triangle <= out_triangle_r;
//             end else if (out_ready && out_valid_r) begin
//                 out_valid_r <= 0;
//             end
//         end
//     end

//     assign out_valid = out_valid_r;

// endmodule
`default_nettype none
`timescale 1ns / 1ps
import math_pkg::*;
import vertex_pkg::*;
import transformer_pkg::*;

// Ready/valid–correct, simulation-guided fix.
// Key points:
// - Pipeline shift order is [stage0, stage1, stage2] with next = {tail, stage0, stage1}.
// - Accept a new triangle (v0) only when the pipe can advance and the v1/v2 burst is not in progress.
// - Assemble one triangle at a time in out_triangle_r, writing exactly when stage2 advances.
// - Generate exactly ONE completion pulse per triangle using an edge detector on
//   "stage2 holds vidx==2" when the pipe advances.
//
// Latency: 3 cycles per triangle once v0 is accepted (assuming continuous pipe_en).
module model_world_transformer(
    input  wire logic         clk,
    input  wire logic         rst,

    input  wire model_world_t model_world,
    input  wire logic         in_valid,
    output      logic         in_ready,

    output      world_camera_t out_world_camera,
    output      logic          out_valid,
    input  wire logic          out_ready,
    output      logic          busy
);

    // ----------------------------------------------------------------
    // State and pipeline
    // ----------------------------------------------------------------
    model_world_t model_world_r;

    // Per-stage payload regs (math is performed in the stages)
    vertex_t load_v, rot_v, world_v;

    // Pipeline valid + per-vertex index (0/1/2) tracking
    logic [2:0] valid_pipe;       // [0]=stage0, [1]=stage1, [2]=stage2
    logic [1:0] vidx_pipe [2:0];  // aligns with valid_pipe

    // v1/v2 burst loader after accepting v0
    logic load_vert;              // 1 while auto-feeding v1/v2
    logic load_vert_ctr;          // 0 -> v1 next, 1 -> v2 next

    // Output assembly & handshake
    triangle_t     out_triangle_r;
    world_camera_t out_wc_r;
    logic          out_valid_r;

    // Completion edge detector: "stage2 holds last vertex (vidx==2) when pipe advances"
    logic s2_is_last_q;
    logic s2_is_last_now;
    logic tri_done_pulse;

    // Matrix taps (from registered model)
    q16_16_t R11, R12, R13;
    q16_16_t R21, R22, R23;
    q16_16_t R31, R32, R33;

    // ----------------------------------------------------------------
    // Backpressure and readies
    // ----------------------------------------------------------------
    logic pipe_en;
    assign pipe_en  = out_ready || !valid_pipe[2];          // advance if output ready OR stage2 empty
    assign in_ready = pipe_en && !load_vert;                 // only accept a new triangle when not mid-burst

    // Busy if anything in flight or a completed triangle is waiting to be taken
    assign busy = |valid_pipe || out_valid_r;

    // Outputs
    assign out_world_camera = out_wc_r;
    assign out_valid        = out_valid_r;

    // ----------------------------------------------------------------
    // Combinational helpers
    // ----------------------------------------------------------------
    always_comb begin
        R11 = model_world_r.model.rot_mtx.R11;
        R12 = model_world_r.model.rot_mtx.R12;
        R13 = model_world_r.model.rot_mtx.R13;
        R21 = model_world_r.model.rot_mtx.R21;
        R22 = model_world_r.model.rot_mtx.R22;
        R23 = model_world_r.model.rot_mtx.R23;
        R31 = model_world_r.model.rot_mtx.R31;
        R32 = model_world_r.model.rot_mtx.R32;
        R33 = model_world_r.model.rot_mtx.R33;

        // "stage2 has the last vertex" (level) for this cycle
        s2_is_last_now = valid_pipe[2] && (vidx_pipe[2] == 2);
        // One-shot pulse exactly when the last vertex ENTERS stage2 (only when pipe advances)
        tri_done_pulse = pipe_en && s2_is_last_now && !s2_is_last_q;
    end

    // ----------------------------------------------------------------
    // Main sequential logic
    // ----------------------------------------------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            model_world_r   <= '0;

            valid_pipe      <= 3'b000;
            vidx_pipe[0]    <= 2'd0;
            vidx_pipe[1]    <= 2'd0;
            vidx_pipe[2]    <= 2'd0;

            load_vert       <= 1'b0;
            load_vert_ctr   <= 1'b0;

            load_v          <= '0;
            rot_v           <= '0;
            world_v         <= '0;

            out_triangle_r  <= '0;
            out_wc_r        <= '0;
            out_valid_r     <= 1'b0;

            s2_is_last_q    <= 1'b0;
        end else begin
            // --------------------------------------------------------
            // Accept v0 and snapshot the entire incoming model_world
            // --------------------------------------------------------
            if (in_valid && in_ready) begin
                model_world_r <= model_world;
            end

            // --------------------------------------------------------
            // Stage 2: write previous world_v into output assembly
            // (happens only when the pipe advances and stage2 was valid)
            // --------------------------------------------------------
            if (pipe_en && valid_pipe[2]) begin
                unique case (vidx_pipe[2])
                    2'd0: begin
                        out_triangle_r.v0.pos   <= add_3d_transform(world_v.pos, model_world_r.model.pos);
                        out_triangle_r.v0.color <= world_v.color;
                    end
                    2'd1: begin
                        out_triangle_r.v1.pos   <= add_3d_transform(world_v.pos, model_world_r.model.pos);
                        out_triangle_r.v1.color <= world_v.color;
                    end
                    2'd2: begin
                        out_triangle_r.v2.pos   <= add_3d_transform(world_v.pos, model_world_r.model.pos);
                        out_triangle_r.v2.color <= world_v.color;
                    end
                    default: /* no-op */;
                endcase
            end

            // --------------------------------------------------------
            // Stage 1: rotate -> world (matrix multiply)
            // --------------------------------------------------------
            if (pipe_en && valid_pipe[1]) begin
                world_v.pos.x <= dot3_transform(R11, R12, R13, rot_v.pos.x, rot_v.pos.y, rot_v.pos.z);
                world_v.pos.y <= dot3_transform(R21, R22, R23, rot_v.pos.x, rot_v.pos.y, rot_v.pos.z);
                world_v.pos.z <= dot3_transform(R31, R32, R33, rot_v.pos.x, rot_v.pos.y, rot_v.pos.z);
                world_v.color <= rot_v.color;
            end

            // --------------------------------------------------------
            // Stage 0: scale
            // --------------------------------------------------------
            if (pipe_en && valid_pipe[0]) begin
                rot_v.pos.x <= mul_transform(load_v.pos.x, model_world_r.model.scale.x);
                rot_v.pos.y <= mul_transform(load_v.pos.y, model_world_r.model.scale.y);
                rot_v.pos.z <= mul_transform(load_v.pos.z, model_world_r.model.scale.z);
                rot_v.color <= load_v.color;
            end

            // --------------------------------------------------------
            // Tail selection (decide what enters stage0 THIS cycle)
            // IMPORTANT: shift order next = {tail, stage0, stage1}
            // --------------------------------------------------------
            if (pipe_en) begin
                // Determine if we push a tail this cycle
                logic tail_valid;
                logic [1:0] tail_vidx;
                vertex_t tail_v;

                tail_valid = ((in_valid && in_ready) || load_vert);

                if (tail_valid) begin
                    if (in_valid && in_ready) begin
                        // v0 from live input
                        tail_vidx = 2'd0;
                        tail_v    = model_world.triangle.v0;
                    end else begin
                        // v1 then v2 from registered snapshot
                        if (load_vert_ctr == 1'b0) begin
                            tail_vidx = 2'd1;
                            tail_v    = model_world_r.triangle.v1;
                        end else begin
                            tail_vidx = 2'd2;
                            tail_v    = model_world_r.triangle.v2;
                        end
                    end
                end else begin
                    tail_vidx = 2'd0; // don't care when tail_valid==0
                    tail_v    = '0;
                end

                // Pipeline shift: {stage0, stage1, stage2} <= {tail, stage0, stage1}
                valid_pipe   <= {tail_valid, valid_pipe[0], valid_pipe[1]};
                vidx_pipe[2] <= vidx_pipe[1];
                vidx_pipe[1] <= vidx_pipe[0];
                vidx_pipe[0] <= tail_vidx;

                if (tail_valid) begin
                    load_v <= tail_v;
                end
            end

            // --------------------------------------------------------
            // Burst loader FSM (start after v0; feed v1 then v2)
            // --------------------------------------------------------
            if (in_valid && in_ready) begin
                load_vert     <= 1'b1;
                load_vert_ctr <= 1'b0;
            end else if (load_vert && pipe_en) begin
                if (load_vert_ctr == 1'b1) begin
                    load_vert     <= 1'b0; // done after v2
                    load_vert_ctr <= 1'b0;
                end else begin
                    load_vert_ctr <= 1'b1; // advance to v2
                end
            end

            // --------------------------------------------------------
            // Completion & output handshake
            // --------------------------------------------------------
            // Update edge-detector state ONLY when the pipe advances
            if (pipe_en) begin
                s2_is_last_q <= s2_is_last_now;
            end

            // Latch exactly once per triangle when the last vertex ENTERS stage2
            if (tri_done_pulse && !out_valid_r) begin
                out_valid_r           <= 1'b1;
                out_wc_r.triangle     <= out_triangle_r;   // assembled triangle
                out_wc_r.camera       <= model_world_r.camera;
            end else if (out_ready && out_valid_r) begin
                out_valid_r           <= 1'b0;
                // Clear assembly buffer (optional)
                out_triangle_r        <= '0;
            end
        end
    end

endmodule
`default_nettype none
