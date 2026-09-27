`timescale 1ns / 1ps

// Top-level UART: baud_gen + uart_tx + uart_rx, each wrapped with a 16-byte
// sync FIFO so a connecting module only ever deals with simple
// wr_en/rd_en/full/empty handshakes instead of per-byte tx_start/rx_done timing.
module uart_top #(
    parameter CLK_FREQ   = 50_000_000,
    parameter BAUD_RATE  = 115200,
    parameter FIFO_DEPTH = 16
) (
    input  wire       clk,
    input  wire       rst_n,

    // write side: push a byte to transmit into the TX FIFO
    input  wire       wr_en,
    input  wire [7:0] wr_data,
    output wire       tx_full,
    output wire       tx_empty,   // TX FIFO empty (i.e. nothing left to send)

    // read side: pop a received byte from the RX FIFO
    input  wire       rd_en,
    output wire [7:0] rd_data,
    output wire       rx_empty,

    // status (1-cycle pulses)
    output wire       rx_overrun,     // RX FIFO was full when a new byte arrived (byte dropped)
    output wire       framing_error,  // stop bit was not '1' on the last received byte

    // serial pins
    output wire       tx,
    input  wire       rx
);

    wire tx_tick, rx_tick;

    baud_gen #(
        .CLK_FREQ (CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) u_baud_gen (
        .clk    (clk),
        .rst_n  (rst_n),
        .tx_tick(tx_tick),
        .rx_tick(rx_tick)
    );

    // ---------------- TX path: wr_data -> tx_fifo -> uart_tx -> tx ----------------
    wire       tx_fifo_empty;
    wire [7:0] tx_fifo_rd_data;
    wire       tx_busy, tx_done;

    // pop the next byte the instant tx is free; the FIFO's combinational
    // read means tx_fifo_rd_data is already valid for the byte being popped
    wire pop_tx = !tx_busy && !tx_fifo_empty;

    sync_fifo #(
        .DATA_WIDTH(8),
        .DEPTH     (FIFO_DEPTH)
    ) u_tx_fifo (
        .clk    (clk),
        .rst_n  (rst_n),
        .wr_en  (wr_en),
        .wr_data(wr_data),
        .full   (tx_full),
        .rd_en  (pop_tx),
        .rd_data(tx_fifo_rd_data),
        .empty  (tx_fifo_empty)
    );

    assign tx_empty = tx_fifo_empty;

    uart_tx u_tx (
        .clk     (clk),
        .rst_n   (rst_n),
        .tx_tick (tx_tick),
        .tx_start(pop_tx),
        .tx_data (tx_fifo_rd_data),
        .tx      (tx),
        .tx_busy (tx_busy),
        .tx_done (tx_done)
    );

    // ---------------- RX path: rx -> uart_rx -> rx_fifo -> rd_data ----------------
    wire [7:0] rx_data_w;
    wire       rx_done_w;
    wire       rx_fifo_full;

    uart_rx #(
        .OVERSAMPLE(16)
    ) u_rx (
        .clk          (clk),
        .rst_n        (rst_n),
        .rx_tick      (rx_tick),
        .rx           (rx),
        .rx_data      (rx_data_w),
        .rx_done      (rx_done_w),
        .framing_error(framing_error)
    );

    sync_fifo #(
        .DATA_WIDTH(8),
        .DEPTH     (FIFO_DEPTH)
    ) u_rx_fifo (
        .clk    (clk),
        .rst_n  (rst_n),
        .wr_en  (rx_done_w),
        .wr_data(rx_data_w),
        .full   (rx_fifo_full),
        .rd_en  (rd_en),
        .rd_data(rd_data),
        .empty  (rx_empty)
    );

    // a byte finished on the wire but the FIFO had no room -> dropped, flag it
    assign rx_overrun = rx_done_w && rx_fifo_full;

endmodule
