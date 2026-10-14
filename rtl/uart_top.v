`timescale 1ns / 1ps

// UART 최상위 모듈
//   uart_tx 와 uart_rx 를 하나로 묶었다. (FIFO 없음)
//
//   보내기 : tx_busy=0 일 때 tx_start 를 1클럭 주면서 tx_data 를 넣는다.
//   받기   : 1바이트를 다 받으면 rx_done 이 1클럭 뜨고, 그 순간 rx_data 가 유효하다.
module uart_top #(
    parameter CLK_FREQ  = 50_000_000,
    parameter BAUD_RATE = 115200
) (
    input  wire       clk,
    input  wire       rst_n,        // 비동기 리셋, 0 이면 리셋

    // 보내기
    input  wire       tx_start,     // 1클럭 펄스 (tx_busy=1 이면 사용 금지)
    input  wire [7:0] tx_data,
    output wire       tx_busy,

    // 받기
    output wire [7:0] rx_data,
    output wire       rx_done,      // 1클럭 펄스

    // 시리얼 핀
    output wire       tx,
    input  wire       rx
);

    uart_tx #(
        .CLK_FREQ (CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) u_tx (
        .clk     (clk),
        .rst_n   (rst_n),
        .tx_start(tx_start),
        .tx_data (tx_data),
        .tx      (tx),
        .tx_busy (tx_busy)
    );

    uart_rx #(
        .CLK_FREQ (CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) u_rx (
        .clk    (clk),
        .rst_n  (rst_n),
        .rx     (rx),
        .rx_data(rx_data),
        .rx_done(rx_done)
    );

endmodule
