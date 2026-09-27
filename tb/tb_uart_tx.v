`timescale 1ns / 1ps

// Testbench for uart_tx (standalone, no baud_gen/uart_rx involved)
// - Drives tx_tick as a simple free-running pulse every TICK_PERIOD clk cycles
// - Samples the serial "tx" line once per tx_tick and decodes start/data/stop
//   bits, comparing the recovered byte against what was sent
// - Checks tx_busy is asserted for the whole frame and deasserts with tx_done
// - Checks tx_start is ignored while tx_busy is high
module tb_uart_tx;

    // clk cycles per bit period (arbitrary, just needs to be >= a few cycles
    // so tx_tick and the DUT's internal logic are clearly separated in time)
    localparam integer TICK_PERIOD = 20;

    reg clk;
    reg rst_n;
    reg tx_tick;

    reg        tx_start;
    reg [7:0]  tx_data;
    wire       tx;
    wire       tx_busy;
    wire       tx_done;

    uart_tx dut (
        .clk     (clk),
        .rst_n   (rst_n),
        .tx_tick (tx_tick),
        .tx_start(tx_start),
        .tx_data (tx_data),
        .tx      (tx),
        .tx_busy (tx_busy),
        .tx_done (tx_done)
    );

    // 10 MHz clock -> 100 ns period
    always #50 clk = ~clk;

    // free-running tx_tick, one clk-wide pulse every TICK_PERIOD cycles
    integer tick_cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tick_cnt <= 0;
            tx_tick  <= 1'b0;
        end else if (tick_cnt == TICK_PERIOD - 1) begin
            tick_cnt <= 0;
            tx_tick  <= 1'b1;
        end else begin
            tick_cnt <= tick_cnt + 1;
            tx_tick  <= 1'b0;
        end
    end

    integer errors;
    integer sent;

    // tx_tick is a registered pulse: the DUT's synchronous logic reacts to it
    // on the clk edge where tx_tick currently reads 1 (the same edge that
    // will clear it back to 0). Wait for that edge, then let this edge's
    // NBA updates (both the DUT's and tx_tick's own) settle with #1 before
    // sampling anything, to avoid racing the always blocks.
    task wait_tick;
        begin
            @(posedge clk);
            while (!tx_tick) @(posedge clk);
            #1;
        end
    endtask

    task send_and_check(input [7:0] b);
        integer i;
        reg [7:0] rx_shift;
        begin
            @(posedge clk);
            wait (!tx_busy);
            tx_data  = b;
            tx_start = 1'b1;
            @(posedge clk);
            tx_start = 1'b0;
            #1; // let this edge's NBA (tx_busy <= 1) settle before checking

            // tx_busy should go high no later than the cycle after tx_start
            if (!tx_busy) begin
                errors = errors + 1;
                $display("[%0t] ERROR: tx_busy did not assert after tx_start (byte 0x%02h)", $time, b);
            end

            // wait for, and check, the start bit
            wait_tick;
            if (tx !== 1'b0) begin
                errors = errors + 1;
                $display("[%0t] ERROR: start bit = %b, expected 0", $time, tx);
            end

            // sample 8 data bits, LSB first
            rx_shift = 8'h00;
            for (i = 0; i < 8; i = i + 1) begin
                wait_tick;
                rx_shift[i] = tx;
            end

            // stop bit
            wait_tick;
            if (tx !== 1'b1) begin
                errors = errors + 1;
                $display("[%0t] ERROR: stop bit = %b, expected 1", $time, tx);
            end

            if (rx_shift !== b) begin
                errors = errors + 1;
                $display("[%0t] ERROR: decoded byte = 0x%02h, expected 0x%02h", $time, rx_shift, b);
            end else begin
                $display("[%0t] OK: sent/decoded 0x%02h", $time, b);
            end

            // tx_done should pulse and tx_busy should drop, both on the same
            // edge the stop bit was sampled (tx_done is already asserted by
            // now since wait_tick settled past that edge's NBA updates)
            if (!tx_done) begin
                errors = errors + 1;
                $display("[%0t] ERROR: tx_done did not pulse for byte 0x%02h", $time, b);
            end
            if (tx_busy) begin
                errors = errors + 1;
                $display("[%0t] ERROR: tx_busy still high after tx_done for byte 0x%02h", $time, b);
            end

            sent = sent + 1;
        end
    endtask

    initial begin
        clk      = 0;
        rst_n    = 0;
        tx_start = 0;
        tx_data  = 8'h00;
        errors   = 0;
        sent     = 0;

        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (5) @(posedge clk);

        // idle line should be high before any transmission
        if (tx !== 1'b1) begin
            errors = errors + 1;
            $display("[%0t] ERROR: idle tx = %b, expected 1", $time, tx);
        end

        send_and_check(8'h55); // 0101_0101
        send_and_check(8'hA5);
        send_and_check(8'h00);
        send_and_check(8'hFF);
        send_and_check(8'h3C);

        // back-to-back: kick off a new byte immediately after the previous
        // one finishes, with no idle gap
        send_and_check(8'h81);
        send_and_check(8'h7E);

        $display("--------------------------------------------------");
        $display("uart_tx tb summary: sent=%0d errors=%0d", sent, errors);
        if (errors == 0)
            $display("  RESULT: PASS");
        else
            $display("  RESULT: FAIL");
        $display("--------------------------------------------------");
        $finish;
    end

    // watchdog
    initial begin
        #200_000;
        $display("ERROR: TIMEOUT");
        $finish;
    end

endmodule
