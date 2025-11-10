module spi_sck_sync #(
    parameter int MIN_PERIOD_CYCLES = 4  // we want a min period of n_max = T_raw/(2*T_ref)
    // 100MHz -> 10ns
    // 10MH   -> 100ns
    // 2MHz   -> 500ns, n = 25
)(
    input  wire clk_ref,          // 100MHz ?
    input  wire rst_n,
    input  wire sck_raw,
    output logic sck_level,       // stable, synchronized version of SCK
    output logic sck_rise_pulse,  // one 40MHz-cycle pulse on rising edge
    output logic sck_fall_pulse   // one 40MHz-cycle pulse on falling edge
);

    // --- Synchronize the raw clock ---
    logic sync_0, sync_1;
    always_ff @(posedge clk_ref) begin
        if (!rst_n) begin
            sync_0 <= 0;
            sync_1 <= 0;
        end else begin
            sync_0 <= sck_raw;
            sync_1 <= sync_0;
        end
    end
    assign sck_level = sync_1;

//    // --- Edge detection ---
//    logic prev;
//    always_ff @(posedge clk_ref) begin
//        if (!rst_n)
//            prev <= 0;
//        else
//            prev <= sync_1;
//    end

    wire rise_raw =  !sync_1 &  sync_0;
    wire fall_raw =   sync_1 & !sync_0;

    // --- Optional: reject glitches that come too close ---
    localparam int CNT_W = $clog2(MIN_PERIOD_CYCLES + 2);
    logic [CNT_W-1:0] cnt;
    logic accept_rise, accept_fall;

    always_ff @(posedge clk_ref) begin
        if (!rst_n) begin
            cnt <= '0;
            accept_rise <= 1'b0;
            accept_fall <= 1'b0;
        end else begin
            accept_rise <= 1'b0;
            accept_fall <= 1'b0;

            if (cnt < MIN_PERIOD_CYCLES)
                cnt <= cnt + 1'b1;

            if (rise_raw && cnt >= MIN_PERIOD_CYCLES) begin
                accept_rise <= 1'b1;
                cnt <= 0;
            end else if (fall_raw && cnt >= MIN_PERIOD_CYCLES) begin
                accept_fall <= 1'b1;
                cnt <= 0;
            end
        end
    end

    assign sck_rise_pulse = accept_rise;
    assign sck_fall_pulse = accept_fall;

endmodule
