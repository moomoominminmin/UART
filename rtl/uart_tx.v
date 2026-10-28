`timescale 1ns / 1ps

// UART 송신기 (8N1: start 1 + data 8 + stop 1)
//   시스템 clk 를 CLKS_PER_BIT 번 세어서 1비트 시간을 만든다.
//
//   면적(DFF 수)을 줄이기 위해 FSM / 비트 번호 / tx / tx_busy 레지스터 없이
//   11비트 시프트 레지스터 하나로 프레임 전체를 표현한다.
//
//   shreg = { 마커(1), ~stop(0), ~data[7:0], ~start(1) }   ← 반전해서 저장
//     - 1비트 시간마다 오른쪽으로 한 칸 밀고, 위에서는 0이 들어온다.
//     - tx = ~shreg[0]  : 전부 밀려나 0이 되면 자연스럽게 idle(1)
//     - tx_busy = |shreg : 레지스터에 1이 하나라도 남아 있으면 전송 중
//     - 마커가 shreg[1] 에 도착하면(shreg[10:2] 가 모두 0) 지금이 stop bit 이다.
//       stop bit 가 끝나면 한 칸 미는 대신 0으로 비운다. (마커가 tx 로 나가지 않게)
module uart_tx #(
    parameter CLK_FREQ  = 50_000_000,
    parameter BAUD_RATE = 115200
) (
    input  wire       clk,
    input  wire       rst_n,

    input  wire       tx_start,  // 1클럭 펄스: tx_data 를 받아서 전송 시작 (tx_busy=0 일 때만)
    input  wire [7:0] tx_data,

    output wire       tx,        // 시리얼 출력 (쉬는 동안 1)
    output wire       tx_busy    // 전송 중이면 1
);

    localparam integer CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;
    localparam integer CNT_W        = $clog2(CLKS_PER_BIT);

    reg [CNT_W-1:0] cnt;    // 1비트 시간 안에서 clk 를 세는 카운터 (쉬는 동안은 매 클럭 0으로 지움)
    reg [10:0]      shreg;  // 보낼 프레임 (반전 저장 + 마커)

    wire bit_done  = (cnt == CLKS_PER_BIT - 1);  // 1비트 시간이 끝났다
    wire last_bit  = ~|shreg[10:2];              // 마커가 shreg[1] 에 있다 = stop bit 전송 중

    // tx 는 플립플롭 출력에 인버터 하나만 거치므로 글리치가 없다
    assign tx      = ~shreg[0];
    assign tx_busy = |shreg;

    // shreg 는 곧 상태이자 tx 출력이라 리셋이 필요하다 (리셋 중 tx=1, tx_busy=0)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shreg <= 11'd0;
        end else if (!tx_busy) begin
            // 대기: tx_start 가 오면 프레임을 통째로 넣는다. 다음 클럭부터 start bit(0) 출력
            if (tx_start)
                shreg <= {1'b1, 1'b0, ~tx_data, 1'b1};
        end else if (bit_done) begin
            // 1비트 시간마다 다음 비트로. stop bit 가 끝났으면 비워서 idle 로
            shreg <= last_bit ? 11'd0 : {1'b0, shreg[10:1]};
        end
    end

    // cnt 는 리셋 없는 DFF 를 쓴다. (리셋 DFF 보다 작다)
    // 쉬는 동안 매 클럭 0으로 지우므로, 리셋 중 shreg=0 인 동안 클럭이 돌면 0이 되어 있다.
    always @(posedge clk) begin
        if (!tx_busy || bit_done) cnt <= 0;
        else                      cnt <= cnt + 1'b1;
    end

endmodule
