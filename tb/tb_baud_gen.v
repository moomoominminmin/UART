`timescale 1ns / 1ps

// Testbench for baud_gen
// - Measures the actual period (in clk cycles) of tx_tick and rx_tick
// - Compares against the expected TX_DIV / RX_DIV computed the same way the DUT does
// - Also checks that rx_tick fires exactly OVERSAMPLE times per tx_tick period
module tb_baud_gen;

    // Use small-ish numbers so the sim finishes fast, but keep a non-trivial divide ratio
    localparam CLK_FREQ   = 1_000_000;   // 1 MHz
    localparam BAUD_RATE  = 9600;
    localparam OVERSAMPLE = 16;

    localparam integer RX_DIV_EXP = CLK_FREQ / (BAUD_RATE * OVERSAMPLE);
    // tx_tick is derived from rx_tick (every OVERSAMPLE-th rx_tick), so its
    // period is exactly RX_DIV_EXP * OVERSAMPLE cycles, not CLK_FREQ/BAUD_RATE.
    localparam integer TX_DIV_EXP = RX_DIV_EXP * OVERSAMPLE;

    reg clk;
    reg rst_n;
    wire tx_tick;
    wire rx_tick;

    baud_gen #(
        .CLK_FREQ  (CLK_FREQ),
        .BAUD_RATE (BAUD_RATE),
        .OVERSAMPLE(OVERSAMPLE)
    ) dut (
        .clk    (clk),
        .rst_n  (rst_n),
        .tx_tick(tx_tick),
        .rx_tick(rx_tick)
    );

    // 1 MHz clock -> 1000 ns period
    always #500 clk = ~clk;

    // --- measurement state ---
    integer tx_cycle_cnt;
    integer rx_cycle_cnt;
    integer tx_period_last;
    integer rx_period_last;
    integer rx_per_tx_cnt;

    integer tx_checks;
    integer rx_checks;
    integer ratio_checks;
    integer errors;

    initial begin
        clk   = 0;
        rst_n = 0;
        tx_cycle_cnt    = 0;
        rx_cycle_cnt    = 0;
        tx_period_last  = -1;
        rx_period_last  = -1;
        rx_per_tx_cnt   = 0;
        tx_checks       = 0;
        rx_checks       = 0;
        ratio_checks    = 0;
        errors          = 0;

        repeat (5) @(posedge clk);
        rst_n = 1;

        // let it run long enough to see several tx_tick periods
        // (each tx_tick period = TX_DIV cycles, run ~6 periods)
        repeat (TX_DIV_EXP * 6 + 20) @(posedge clk);

        $display("--------------------------------------------------");
        $display("baud_gen tb summary");
        $display("  TX_DIV expected = %0d, RX_DIV expected = %0d", TX_DIV_EXP, RX_DIV_EXP);
        $display("  tx_tick periods checked = %0d", tx_checks);
        $display("  rx_tick periods checked = %0d", rx_checks);
        $display("  rx_tick-per-tx_tick ratio checks = %0d", ratio_checks);
        if (errors == 0)
            $display("  RESULT: PASS");
        else
            $display("  RESULT: FAIL (%0d error(s))", errors);
        $display("--------------------------------------------------");
        $finish;
    end

    // count clk cycles since reset deasserted, always incrementing
    always @(posedge clk) begin
        if (!rst_n) begin
            tx_cycle_cnt <= 0;
            rx_cycle_cnt <= 0;
        end else begin
            tx_cycle_cnt <= tx_cycle_cnt + 1;
            rx_cycle_cnt <= rx_cycle_cnt + 1;
        end
    end

    // measure tx_tick period
    always @(posedge clk) begin
        if (rst_n && tx_tick) begin
            if (tx_period_last != -1) begin
                tx_checks = tx_checks + 1;
                if (tx_cycle_cnt - tx_period_last !== TX_DIV_EXP) begin
                    errors = errors + 1;
                    $display("[%0t] ERROR: tx_tick period = %0d, expected %0d",
                              $time, tx_cycle_cnt - tx_period_last, TX_DIV_EXP);
                end
            end
            tx_period_last = tx_cycle_cnt;

            // check how many rx_tick pulses occurred during this tx period, then reset counter
            if (ratio_checks >= 0 && tx_checks > 0) begin
                ratio_checks = ratio_checks + 1;
                if (rx_per_tx_cnt !== OVERSAMPLE) begin
                    errors = errors + 1;
                    $display("[%0t] ERROR: rx_tick count within tx period = %0d, expected %0d",
                              $time, rx_per_tx_cnt, OVERSAMPLE);
                end
            end
            rx_per_tx_cnt = 0;
        end
    end

    // measure rx_tick period, and count pulses per tx period
    always @(posedge clk) begin
        if (rst_n && rx_tick) begin
            if (rx_period_last != -1) begin
                rx_checks = rx_checks + 1;
                if (rx_cycle_cnt - rx_period_last !== RX_DIV_EXP) begin
                    errors = errors + 1;
                    $display("[%0t] ERROR: rx_tick period = %0d, expected %0d",
                              $time, rx_cycle_cnt - rx_period_last, RX_DIV_EXP);
                end
            end
            rx_period_last = rx_cycle_cnt;
            rx_per_tx_cnt  = rx_per_tx_cnt + 1;
        end
    end

endmodule
