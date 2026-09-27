`timescale 1ns / 1ps

// Loopback test: uart_tx's serial output is wired directly into uart_rx's
// serial input, both driven by the same baud_gen. Sends several bytes and
// checks that uart_rx recovers them correctly with no framing errors.
module tb_uart_loopback;

    localparam CLK_FREQ   = 1_000_000;
    localparam BAUD_RATE  = 9600;
    localparam OVERSAMPLE = 16;

    reg clk;
    reg rst_n;

    wire tx_tick, rx_tick;
    wire tx_line;

    reg        tx_start;
    reg [7:0]  tx_data;
    wire       tx_busy, tx_done;

    wire [7:0] rx_data;
    wire       rx_done, framing_error;

    baud_gen #(
        .CLK_FREQ  (CLK_FREQ),
        .BAUD_RATE (BAUD_RATE),
        .OVERSAMPLE(OVERSAMPLE)
    ) u_baud_gen (
        .clk    (clk),
        .rst_n  (rst_n),
        .tx_tick(tx_tick),
        .rx_tick(rx_tick)
    );

    uart_tx u_tx (
        .clk     (clk),
        .rst_n   (rst_n),
        .tx_tick (tx_tick),
        .tx_start(tx_start),
        .tx_data (tx_data),
        .tx      (tx_line),
        .tx_busy (tx_busy),
        .tx_done (tx_done)
    );

    uart_rx #(
        .OVERSAMPLE(OVERSAMPLE)
    ) u_rx (
        .clk          (clk),
        .rst_n        (rst_n),
        .rx_tick      (rx_tick),
        .rx           (tx_line),
        .rx_data      (rx_data),
        .rx_done      (rx_done),
        .framing_error(framing_error)
    );

    always #500 clk = ~clk; // 1 MHz

    integer errors;
    integer sent;

    // simple scoreboard: remember what we sent, in order
    reg [7:0] expected_q [0:31];
    integer   wr_ptr, rd_ptr;

    task send_byte(input [7:0] b);
        begin
            @(posedge clk);
            wait (!tx_busy);
            tx_data  = b;
            tx_start = 1'b1;
            expected_q[wr_ptr] = b;
            wr_ptr = wr_ptr + 1;
            @(posedge clk);
            tx_start = 1'b0;
        end
    endtask

    initial begin
        clk = 0; rst_n = 0;
        tx_start = 0; tx_data = 8'h00;
        errors = 0; sent = 0; wr_ptr = 0; rd_ptr = 0;

        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (5) @(posedge clk);

        send_byte(8'h55); // 0101_0101
        send_byte(8'hA5);
        send_byte(8'h00);
        send_byte(8'hFF);
        send_byte(8'h3C);

        // wait for all 5 bytes to be received, with a generous timeout
        wait (rd_ptr == 5);

        $display("--------------------------------------------------");
        $display("uart loopback tb summary: sent=%0d received=%0d errors=%0d",
                  wr_ptr, rd_ptr, errors);
        if (errors == 0)
            $display("  RESULT: PASS");
        else
            $display("  RESULT: FAIL");
        $display("--------------------------------------------------");
        $finish;
    end

    // watchdog in case rx_done never arrives
    initial begin
        #200_000_000; // 200 ms of sim time
        $display("ERROR: TIMEOUT waiting for loopback bytes");
        $finish;
    end

    always @(posedge clk) begin
        if (rx_done) begin
            sent = sent + 1;
            if (framing_error) begin
                errors = errors + 1;
                $display("[%0t] ERROR: framing_error on received byte 0x%02h", $time, rx_data);
            end
            if (rx_data !== expected_q[rd_ptr]) begin
                errors = errors + 1;
                $display("[%0t] ERROR: got 0x%02h, expected 0x%02h",
                          $time, rx_data, expected_q[rd_ptr]);
            end else begin
                $display("[%0t] OK: received 0x%02h", $time, rx_data);
            end
            rd_ptr = rd_ptr + 1;
        end
    end

endmodule
