`timescale 1ns / 1ps

// 보레이트 틱 생성기
//   rx_tick : 1비트 시간 동안 16번 발생 (16x 오버샘플링, 수신기가 사용)
//   tx_tick : 1비트 시간마다 1번 발생   (송신기가 사용)
// 두 틱 모두 1클럭 폭의 펄스이다.
module baud_gen #(
    parameter CLK_FREQ  = 50_000_000,
    parameter BAUD_RATE = 115200
) (
    input  wire clk,
    input  wire rst_n,
    output wire tx_tick,
    output wire rx_tick
);

    // 클럭을 몇 번 세면 rx_tick 1번인가?  (50MHz / (115200*16) = 27)
    localparam integer DIV   = CLK_FREQ / (BAUD_RATE * 16);
    localparam integer CNT_W = $clog2(DIV);

    reg [CNT_W-1:0] clk_cnt;  // 0 ~ DIV-1 을 반복해서 센다
    reg [3:0]       tick_cnt; // rx_tick 을 0 ~ 15 까지 센다

    // rx_tick : clk_cnt 가 마지막 값일 때 1
    assign rx_tick = (clk_cnt == DIV - 1);

    // tx_tick : 16번째 rx_tick 일 때 1 (즉 rx_tick 16개당 1개)
    assign tx_tick = rx_tick && (tick_cnt == 4'd15);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clk_cnt  <= 0;
            tick_cnt <= 4'd0;
        end else begin
            if (rx_tick) begin
                clk_cnt  <= 0;
                tick_cnt <= tick_cnt + 1'b1; // 4비트라서 15 다음은 자동으로 0
            end else begin
                clk_cnt <= clk_cnt + 1'b1;
            end
        end
    end

endmodule
