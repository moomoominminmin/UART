`timescale 1ns / 1ps

// Two uart_top instances, cross-wired tx<->rx, exercising real device-to-device
// communication (as opposed to tb_uart_top's single-instance self-loopback):
//   dut_a.tx -> dut_b.rx      dut_b.tx -> dut_a.rx
// Both instances have PARITY_EN=1, so this also exercises the parity-check
// logic added to uart_rx.
//
// Checks:
//   1) A->B and B->A byte streams arrive correctly, in order, with no
//      framing_error/parity_error, when the link is clean
//   2) a single-bit corruption injected onto the A->B wire is caught by
//      dut_b's parity_error (without a matching framing_error), and that the
//      link recovers cleanly for the frame right after
module tb_uart_top_pair;

    localparam CLK_FREQ   = 1_000_000;
    localparam BAUD_RATE  = 9600;
    localparam FIFO_DEPTH = 16;

    reg clk, rst_n;

    // ---- side A ----
    reg        wr_en_a;
    reg [7:0]  wr_data_a;
    wire       tx_full_a, tx_empty_a;
    reg        rd_en_a;
    wire [7:0] rd_data_a;
    wire       rx_empty_a;
    wire       rx_overrun_a, framing_error_a, parity_error_a;
    wire       tx_a;

    // ---- side B ----
    reg        wr_en_b;
    reg [7:0]  wr_data_b;
    wire       tx_full_b, tx_empty_b;
    reg        rd_en_b;
    wire [7:0] rd_data_b;
    wire       rx_empty_b;
    wire       rx_overrun_b, framing_error_b, parity_error_b;
    wire       tx_b;

    // A->B link can be corrupted (single bit flip) on demand; B->A stays clean
    reg  corrupt_ab;
    wire link_ab = corrupt_ab ? ~tx_a : tx_a;
    wire link_ba = tx_b;

    uart_top #(
        .CLK_FREQ  (CLK_FREQ),
        .BAUD_RATE (BAUD_RATE),
        .FIFO_DEPTH(FIFO_DEPTH),
        .PARITY_EN (1),
        .PARITY_ODD(0)
    ) dut_a (
        .clk          (clk),
        .rst_n        (rst_n),
        .wr_en        (wr_en_a),
        .wr_data      (wr_data_a),
        .tx_full      (tx_full_a),
        .tx_empty     (tx_empty_a),
        .rd_en        (rd_en_a),
        .rd_data      (rd_data_a),
        .rx_empty     (rx_empty_a),
        .rx_overrun   (rx_overrun_a),
        .framing_error(framing_error_a),
        .parity_error (parity_error_a),
        .tx           (tx_a),
        .rx           (link_ba)
    );

    uart_top #(
        .CLK_FREQ  (CLK_FREQ),
        .BAUD_RATE (BAUD_RATE),
        .FIFO_DEPTH(FIFO_DEPTH),
        .PARITY_EN (1),
        .PARITY_ODD(0)
    ) dut_b (
        .clk          (clk),
        .rst_n        (rst_n),
        .wr_en        (wr_en_b),
        .wr_data      (wr_data_b),
        .tx_full      (tx_full_b),
        .tx_empty     (tx_empty_b),
        .rd_en        (rd_en_b),
        .rd_data      (rd_data_b),
        .rx_empty     (rx_empty_b),
        .rx_overrun   (rx_overrun_b),
        .framing_error(framing_error_b),
        .parity_error (parity_error_b),
        .tx           (tx_b),
        .rx           (link_ab)
    );

    always #500 clk = ~clk; // 1 MHz

    integer errors;
    reg     allow_errors; // suppress the background error check during test 4's deliberate corruption

    // parity_error/framing_error are 1-cycle pulses that fire the moment
    // rx_done does -- well before test 4 gets around to draining the FIFO and
    // checking them, so latch them instead of reading the live signal late
    reg saw_parity_error_b, saw_framing_error_b;
    always @(posedge clk) begin
        if (parity_error_b)  saw_parity_error_b  <= 1'b1;
        if (framing_error_b) saw_framing_error_b <= 1'b1;
    end

    // ---- generic push/pop tasks, parameterized by which side ----
    task push_a(input [7:0] b);
        begin
            @(posedge clk);
            wr_data_a = b;
            wr_en_a   = 1'b1;
            @(posedge clk);
            wr_en_a   = 1'b0;
        end
    endtask

    task push_b(input [7:0] b);
        begin
            @(posedge clk);
            wr_data_b = b;
            wr_en_b   = 1'b1;
            @(posedge clk);
            wr_en_b   = 1'b0;
        end
    endtask

    reg [7:0] expected_b_q [0:63]; // bytes A sent, to be checked against what B receives
    reg [7:0] expected_a_q [0:63]; // bytes B sent, to be checked against what A receives
    integer   exp_b_wr, exp_b_rd;
    integer   exp_a_wr, exp_a_rd;

    // sample *_empty at negedge, safely after the FIFO's posedge NBA updates
    // have settled (same race avoided in tb_uart_top.v)
    task wait_b_ready; begin @(negedge clk); while (rx_empty_b) @(negedge clk); end endtask
    task wait_a_ready; begin @(negedge clk); while (rx_empty_a) @(negedge clk); end endtask

    task pop_and_check_b;
        reg [7:0] captured;
        begin
            @(posedge clk);
            rd_en_b = 1'b1;
            captured = rd_data_b;
            @(posedge clk);
            rd_en_b = 1'b0;
            if (captured !== expected_b_q[exp_b_rd]) begin
                errors = errors + 1;
                $display("[%0t] ERROR: B popped 0x%02h, expected 0x%02h", $time, captured, expected_b_q[exp_b_rd]);
            end else begin
                $display("[%0t] OK: B popped 0x%02h", $time, captured);
            end
            exp_b_rd = exp_b_rd + 1;
        end
    endtask

    task pop_and_check_a;
        reg [7:0] captured;
        begin
            @(posedge clk);
            rd_en_a = 1'b1;
            captured = rd_data_a;
            @(posedge clk);
            rd_en_a = 1'b0;
            if (captured !== expected_a_q[exp_a_rd]) begin
                errors = errors + 1;
                $display("[%0t] ERROR: A popped 0x%02h, expected 0x%02h", $time, captured, expected_a_q[exp_a_rd]);
            end else begin
                $display("[%0t] OK: A popped 0x%02h", $time, captured);
            end
            exp_a_rd = exp_a_rd + 1;
        end
    endtask

    // Corrupt exactly one bit period on the A->B link: waits for tx_a to be
    // busy sending a frame, lets TARGET_TICK internal tx_tick pulses go by
    // (tick 1 drives the start bit, tick 2 drives data bit0, tick 3 data
    // bit1, ...), then flips whatever value is on the wire for the following
    // bit period only. Flipping a data bit (not the stop bit) guarantees a
    // parity mismatch without also tripping framing_error.
    // waits for a posedge clk where dut_a.tx_tick reads 1 -- @(posedge
    // dut_a.tx_tick) directly on that internal comb wire double-triggers in
    // this simulator (a delta-cycle artifact around the NBA update of the
    // rx_cnt/os_cnt registers it's derived from), so qualify by clk instead
    task wait_tx_a_tick;
        begin
            @(posedge clk);
            while (!dut_a.tx_tick) @(posedge clk);
        end
    endtask

    task corrupt_one_bit(input integer target_tick);
        integer tick_count;
        begin
            corrupt_ab = 1'b0;
            wait (dut_a.tx_busy);
            tick_count = 0;
            while (tick_count < target_tick) begin
                wait_tx_a_tick;
                tick_count = tick_count + 1;
            end
            corrupt_ab = 1'b1;
            wait_tx_a_tick;
            corrupt_ab = 1'b0;
        end
    endtask

    integer i;

    initial begin
        clk = 0; rst_n = 0;
        wr_en_a = 0; wr_data_a = 0; rd_en_a = 0;
        wr_en_b = 0; wr_data_b = 0; rd_en_b = 0;
        corrupt_ab = 0;
        allow_errors = 1'b0;
        errors = 0;
        exp_a_wr = 0; exp_a_rd = 0;
        exp_b_wr = 0; exp_b_rd = 0;

        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (5) @(posedge clk);

        // ---- test 1: A -> B ----
        $display("---- test 1: A -> B ----");
        for (i = 0; i < 5; i = i + 1) begin
            expected_b_q[exp_b_wr] = 8'hA0 + i;
            exp_b_wr = exp_b_wr + 1;
            push_a(8'hA0 + i);
        end
        for (i = 0; i < 5; i = i + 1) begin
            wait_b_ready;
            pop_and_check_b;
        end

        // ---- test 2: B -> A ----
        $display("---- test 2: B -> A ----");
        for (i = 0; i < 5; i = i + 1) begin
            expected_a_q[exp_a_wr] = 8'h50 + i;
            exp_a_wr = exp_a_wr + 1;
            push_b(8'h50 + i);
        end
        for (i = 0; i < 5; i = i + 1) begin
            wait_a_ready;
            pop_and_check_a;
        end

        // ---- test 3: simultaneous bidirectional exchange ----
        $display("---- test 3: simultaneous A<->B exchange ----");
        for (i = 0; i < 6; i = i + 1) begin
            expected_b_q[exp_b_wr] = 8'hC0 + i;
            exp_b_wr = exp_b_wr + 1;
            expected_a_q[exp_a_wr] = 8'h20 + i;
            exp_a_wr = exp_a_wr + 1;
            fork
                push_a(8'hC0 + i);
                push_b(8'h20 + i);
            join
        end
        for (i = 0; i < 6; i = i + 1) begin
            wait_b_ready; pop_and_check_b;
            wait_a_ready; pop_and_check_a;
        end

        // ---- test 4: inject a single-bit error on A->B, expect parity_error ----
        $display("---- test 4: single-bit corruption -> parity_error on B ----");
        allow_errors        = 1'b1;
        saw_parity_error_b  = 1'b0;
        saw_framing_error_b = 1'b0;
        fork
            begin
                expected_b_q[exp_b_wr] = 8'h96; // 1001_0110, arbitrary
                exp_b_wr = exp_b_wr + 1;
                push_a(8'h96);
            end
            corrupt_one_bit(4); // flip data bit1's period
        join
        wait_b_ready;
        // this byte is expected to be WRONG (that's the point) -- consume it
        // without scoring it against the scoreboard, then check the error flag
        begin : consume_bad_byte
            reg [7:0] captured;
            @(posedge clk);
            rd_en_b = 1'b1;
            captured = rd_data_b;
            @(posedge clk);
            rd_en_b = 1'b0;
            $display("[%0t] INFO: B received 0x%02h under injected corruption", $time, captured);
            exp_b_rd = exp_b_rd + 1;
        end

        if (!saw_parity_error_b) begin
            errors = errors + 1;
            $display("[%0t] ERROR: parity_error_b did not assert for the corrupted frame", $time);
        end else begin
            $display("[%0t] OK: parity_error_b asserted as expected", $time);
        end
        if (saw_framing_error_b) begin
            errors = errors + 1;
            $display("[%0t] ERROR: framing_error_b unexpectedly asserted (corruption should have hit a data bit, not the stop bit)", $time);
        end

        allow_errors = 1'b0;

        // ---- test 5: link recovers cleanly right after the corrupted frame ----
        $display("---- test 5: link recovers after corruption ----");
        for (i = 0; i < 3; i = i + 1) begin
            expected_b_q[exp_b_wr] = 8'hD0 + i;
            exp_b_wr = exp_b_wr + 1;
            push_a(8'hD0 + i);
        end
        for (i = 0; i < 3; i = i + 1) begin
            wait_b_ready;
            pop_and_check_b;
        end

        $display("--------------------------------------------------");
        $display("uart_top_pair tb summary: errors=%0d", errors);
        if (errors == 0)
            $display("  RESULT: PASS");
        else
            $display("  RESULT: FAIL");
        $display("--------------------------------------------------");
        $finish;
    end

    initial begin
        #1_000_000_000; // 1 s watchdog
        $display("ERROR: TIMEOUT");
        $finish;
    end

    // background checks: no framing/parity errors should occur outside test 4
    always @(posedge clk) begin
        if (!allow_errors) begin
            if (framing_error_a || parity_error_a) begin
                errors = errors + 1;
                $display("[%0t] ERROR: unexpected error flag on A (framing=%b parity=%b)", $time, framing_error_a, parity_error_a);
            end
            if (framing_error_b || parity_error_b) begin
                errors = errors + 1;
                $display("[%0t] ERROR: unexpected error flag on B (framing=%b parity=%b)", $time, framing_error_b, parity_error_b);
            end
        end
    end

endmodule
