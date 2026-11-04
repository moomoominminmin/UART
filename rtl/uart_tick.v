`timescale 1ns / 1ps

// UART 공용 프리스케일러
//   clk 를 PRE_DIV 번 셀 때마다 tick 을 1클럭 낸다.
//   1비트 = tick 16개 가 되도록 PRE_DIV 를 정한다. (10MHz / 9600bps 이면 PRE_DIV = 65)
//   uart_tx 와 uart_rx 가 같이 쓴다.
module uart_tick #(
    parameter CLK_FREQ  = 10_000_000,
    parameter BAUD_RATE = 9600
) (
    input  wire clk,
    input  wire rst_n,
    output wire tick       // 1클럭 펄스: PRE_DIV 클럭마다 한 번
);

    localparam integer PRE_DIV = CLK_FREQ / (BAUD_RATE * 16);
    localparam integer PRE_W   = $clog2(PRE_DIV);

    reg [PRE_W-1:0] pre;   // clk 를 세는 카운터 (0 ~ PRE_DIV-1)

    assign tick = (pre == PRE_DIV - 1);

    // 리셋 DFF 대신 리셋 없는 DFF 를 쓰고, 리셋이 걸려 있는 동안 0으로 지운다.
    // (리셋 중에도 클럭이 돌아야 한다)
    always @(posedge clk) begin
        if (!rst_n || tick) pre <= 0;
        else                pre <= pre + 1'b1;
    end

endmodule
