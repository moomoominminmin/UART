`timescale 1ns / 1ps

// UART 최상위 모듈
//   baud_gen + uart_tx + uart_rx 에 FIFO 를 하나씩 붙였다.
//   사용하는 쪽은 복잡한 타이밍 없이 wr_en / rd_en / full / empty 만 쓰면 된다.
//
//   보내기 : wr_data -> [TX FIFO] -> uart_tx -> tx
//   받기   : rx -> uart_rx -> [RX FIFO] -> rd_data
module uart_top #(
    parameter CLK_FREQ   = 50_000_000,
    parameter BAUD_RATE  = 115200,
    parameter TX_FIFO_DEPTH = 2,   // TX FIFO 깊이 (2의 거듭제곱)
    parameter RX_FIFO_DEPTH = 8    // RX FIFO 깊이 (2의 거듭제곱)
) (
    input  wire       clk,
    input  wire       rst_n,        // 비동기 리셋, 0 이면 리셋

    // 보내기: 1바이트를 TX FIFO 에 넣는다
    input  wire       wr_en,        // 1 이면 wr_data 를 FIFO 에 저장 (tx_full=1 이면 무시)
    input  wire [7:0] wr_data,
    output wire       tx_full,      // TX FIFO 가득 참
    output wire       tx_empty,     // TX FIFO 비어 있음

    // 받기: RX FIFO 에서 1바이트를 꺼낸다
    input  wire       rd_en,        // 1 이면 FIFO 맨 앞 데이터를 꺼냄 (rx_empty=1 이면 무시)
    output wire [7:0] rd_data,      // FIFO 맨 앞 데이터 (rx_empty=0 일 때 유효)
    output wire       rx_empty,     // RX FIFO 비어 있음

    // 상태 표시 (1클럭 펄스)
    output wire       rx_overrun,    // RX FIFO 가 가득 찬 상태에서 새 데이터가 와서 버려짐

    // 시리얼 핀
    output wire       tx,
    input  wire       rx
);

    // ---------------- 보레이트 틱 ----------------
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

    // ---------------- 송신 경로 ----------------
    wire [7:0] tx_fifo_data;
    wire       tx_busy;

    // 송신기가 쉬고 있고 FIFO 에 데이터가 있으면 하나 꺼내서 바로 전송 시작
    wire tx_start = !tx_busy && !tx_empty;

    sync_fifo #(
        .DATA_WIDTH(8),
        .DEPTH     (TX_FIFO_DEPTH)
    ) u_tx_fifo (
        .clk    (clk),
        .rst_n  (rst_n),
        .wr_en  (wr_en),
        .wr_data(wr_data),
        .full   (tx_full),
        .rd_en  (tx_start),
        .rd_data(tx_fifo_data),
        .empty  (tx_empty)
    );

    uart_tx u_tx (
        .clk     (clk),
        .rst_n   (rst_n),
        .tx_tick (tx_tick),
        .tx_start(tx_start),
        .tx_data (tx_fifo_data),
        .tx      (tx),
        .tx_busy (tx_busy)
    );

    // ---------------- 수신 경로 ----------------
    wire [7:0] rx_data;
    wire       rx_done;
    wire       rx_full;

    uart_rx u_rx (
        .clk          (clk),
        .rst_n        (rst_n),
        .rx_tick      (rx_tick),
        .rx           (rx),
        .rx_data      (rx_data),
        .rx_done      (rx_done)
    );

    // 1바이트를 다 받으면(rx_done) 자동으로 RX FIFO 에 저장
    sync_fifo #(
        .DATA_WIDTH(8),
        .DEPTH     (RX_FIFO_DEPTH)
    ) u_rx_fifo (
        .clk    (clk),
        .rst_n  (rst_n),
        .wr_en  (rx_done),
        .wr_data(rx_data),
        .full   (rx_full),
        .rd_en  (rd_en),
        .rd_data(rd_data),
        .empty  (rx_empty)
    );

    // 데이터가 도착했는데 FIFO 가 가득 차 있으면 버려진다 -> overrun
    assign rx_overrun = rx_done && rx_full;

endmodule
