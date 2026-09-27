`timescale 1ns / 1ps

// Testbench for uart_rx (standalone, no baud_gen/uart_tx involved)
// - Drives rx_tick as a simple free-running pulse every TICK_PERIOD clk cycles
//   (the 16x-oversample tick uart_rx expects from baud_gen)
// - Manually bit-bangs the "rx" serial line, holding each bit for exactly
//   OVERSAMPLE rx_tick pulses (one full bit period), the same way a real
//   transmitter's line would look
// - Checks normal frames (rx_done/rx_data), a bad stop bit (framing_error),
//   and that a short glitch on the line is rejected without producing a
//   spurious rx_done
module tb_uart_rx;

    localparam integer OVERSAMPLE  = 16;
    // clk cycles per rx_tick (arbitrary, just needs several clk cycles so the
    // 2-flop input synchronizer's latency is negligible next to a bit period)
    localparam integer TICK_PERIOD = 10;

    reg clk;
    reg rst_n;
    reg rx_tick;
    reg rx;

    wire [7:0] rx_data;
    wire       rx_done;
    wire       framing_error;

    uart_rx #(
        .OVERSAMPLE(OVERSAMPLE)
    ) dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .rx_tick      (rx_tick),
        .rx           (rx),
        .rx_data      (rx_data),
        .rx_done      (rx_done),
        .framing_error(framing_error)
    );

    // 10 MHz clock -> 100 ns period
    always #50 clk = ~clk;

    // free-running rx_tick, one clk-wide pulse every TICK_PERIOD cycles
    integer tick_cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tick_cnt <= 0;
            rx_tick  <= 1'b0;
        end else if (tick_cnt == TICK_PERIOD - 1) begin
            tick_cnt <= 0;
            rx_tick  <= 1'b1;
        end else begin
            tick_cnt <= tick_cnt + 1;
            rx_tick  <= 1'b0;
        end
    end

    integer errors;
    integer frames_ok;

    // scoreboard: rx_done is a 1-cycle pulse that fires at the MIDPOINT of
    // the stop bit (i.e. while send_frame is still driving the last half of
    // the stop bit), not after the frame is fully done being driven. So we
    // can't just call a blocking "wait for rx_done" task after send_frame
    // returns -- by then the pulse has already come and gone, and we'd wait
    // forever. Instead, record what we expect up front and let a background
    // always block catch every rx_done pulse as it happens.
    reg [7:0] expected_data_q [0:31];
    reg       expected_ferr_q [0:31];
    integer   wr_ptr, rd_ptr;

    // wait for a clk edge where rx_tick currently reads 1, then let this
    // edge's NBA updates settle (same race-avoidance pattern used in
    // tb_uart_tx.v's wait_tick)
    task wait_rx_tick;
        begin
            @(posedge clk);
            while (!rx_tick) @(posedge clk);
            #1;
        end
    endtask

    // hold rx at bit_val for exactly one full bit period (OVERSAMPLE rx_ticks)
    task send_bit(input bit_val);
        integer i;
        begin
            rx = bit_val;
            for (i = 0; i < OVERSAMPLE; i = i + 1) wait_rx_tick;
        end
    endtask

    // send a full 8N1 frame; stop_val lets us deliberately corrupt the stop
    // bit to exercise framing_error. Also records what we expect to see on
    // rx_done into the scoreboard queue.
    //
    // uart_rx samples (and transitions STOP->IDLE) at the MIDPOINT of the
    // stop bit, not at its end. If we held a bad stop bit low for the full
    // OVERSAMPLE ticks, the DUT would return to IDLE while our line is
    // *still* low for the second half of that same period -- and IDLE
    // re-arms on any low level, misreading that leftover low half as a
    // brand-new start bit (a phantom frame that then eats everything sent
    // afterwards). So for a bad stop bit we only hold it low past the
    // sample point, then release high for the remainder of the bit period.
    task send_frame(input [7:0] b, input stop_val);
        integer i;
        begin
            expected_data_q[wr_ptr] = b;
            expected_ferr_q[wr_ptr] = (stop_val !== 1'b1);
            wr_ptr = wr_ptr + 1;

            send_bit(1'b0);           // start bit
            for (i = 0; i < 8; i = i + 1) send_bit(b[i]);  // data, LSB first

            if (stop_val === 1'b1) begin
                send_bit(1'b1);        // normal stop bit
            end else begin
                rx = 1'b0;
                repeat (OVERSAMPLE / 2 + 2) wait_rx_tick;  // past the sample point
                rx = 1'b1;
                repeat (OVERSAMPLE / 2 - 2) wait_rx_tick;  // finish out the bit period high
            end
        end
    endtask

    initial begin
        clk       = 0;
        rst_n     = 0;
        rx        = 1'b1; // idle
        errors    = 0;
        frames_ok = 0;
        wr_ptr    = 0;
        rd_ptr    = 0;

        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (5) @(posedge clk);

        // --- normal frames ---
        send_frame(8'h55, 1'b1);
        send_frame(8'hA5, 1'b1);
        send_frame(8'h00, 1'b1);
        send_frame(8'hFF, 1'b1);
        send_frame(8'h3C, 1'b1);

        // --- bad stop bit -> framing_error expected, data still recovered ---
        send_frame(8'h81, 1'b0);

        // let the line sit at a genuinely stable idle level for a full bit
        // period before the glitch test below -- send_frame() ends with
        // rx = 1'b1, but that's a single blocking assignment with zero
        // duration; without this wait, the glitch pulse would butt directly
        // up against the previous frame's (deliberately low) stop bit and
        // the two would merge into one long low pulse instead of looking
        // like "stable idle, then a brief glitch"
        repeat (OVERSAMPLE * TICK_PERIOD) @(posedge clk);

        // --- glitch rejection: a low pulse much shorter than half a bit
        // period should NOT be mistaken for a start bit ---
        rx = 1'b0;
        repeat (3) @(posedge clk); // << half a bit period (8*TICK_PERIOD cycles)
        rx = 1'b1;
        repeat (OVERSAMPLE * TICK_PERIOD) @(posedge clk); // wait a full bit period
        if (rd_ptr != wr_ptr) begin
            errors = errors + 1;
            $display("[%0t] ERROR: rx_done fired after a glitch, should have been rejected", $time);
        end else begin
            $display("[%0t] OK: glitch correctly rejected, no rx_done", $time);
        end

        // FSM should have cleanly returned to IDLE: a normal frame right
        // after the glitch must still be received correctly
        send_frame(8'h5A, 1'b1);

        // wait for every sent frame to be scored, with a generous timeout
        wait (rd_ptr == wr_ptr);
        repeat (5) @(posedge clk);

        $display("--------------------------------------------------");
        $display("uart_rx tb summary: sent=%0d frames_ok=%0d errors=%0d", wr_ptr, frames_ok, errors);
        if (errors == 0)
            $display("  RESULT: PASS");
        else
            $display("  RESULT: FAIL");
        $display("--------------------------------------------------");
        $finish;
    end

    // background scoreboard: catch every rx_done pulse as it happens and
    // check it against the next expected entry in FIFO order
    always @(posedge clk) begin
        if (rx_done) begin
            if (rx_data !== expected_data_q[rd_ptr]) begin
                errors = errors + 1;
                $display("[%0t] ERROR: rx_data = 0x%02h, expected 0x%02h",
                          $time, rx_data, expected_data_q[rd_ptr]);
            end else if (framing_error !== expected_ferr_q[rd_ptr]) begin
                errors = errors + 1;
                $display("[%0t] ERROR: framing_error = %b, expected %b (byte 0x%02h)",
                          $time, framing_error, expected_ferr_q[rd_ptr], rx_data);
            end else begin
                $display("[%0t] OK: rx_data=0x%02h framing_error=%b", $time, rx_data, framing_error);
                frames_ok = frames_ok + 1;
            end
            rd_ptr = rd_ptr + 1;
        end
    end

    // watchdog
    initial begin
        #2_000_000;
        $display("ERROR: TIMEOUT");
        $finish;
    end

endmodule
