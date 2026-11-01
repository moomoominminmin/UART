`timescale 1ns / 1ps

// UART 송신기 (8N1: start 1 + data 8 + stop 1)
//   시스템 clk 를 CLKS_PER_BIT 번 세어서 1비트 시간을 만든다.
//
//   상태 흐름:  IDLE -> START -> DATA(8번) -> STOP -> IDLE
//
//   면적을 줄이기 위해
//     - tx_busy 는 레지스터 없이 (state != IDLE) 로 바로 만든다.
//     - 리셋이 꼭 필요한 state, tx 만 리셋하고, 나머지는 리셋 없는 DFF 를 쓴다. (더 작다)
//     - 보낼 데이터를 내부에 저장하지 않고 tx_data 에서 바로 읽는다.
//       그래서 tx_start 부터 tx_busy 가 0이 될 때까지 tx_data 를 바꾸면 안 된다.
module uart_tx #(
    parameter CLK_FREQ  = 50_000_000,
    parameter BAUD_RATE = 115200
) (
    input  wire       clk,
    input  wire       rst_n,

    input  wire       tx_start,  // 1클럭 펄스: 전송 시작 (tx_busy=0 일 때만)
    input  wire [7:0] tx_data,   // 보낼 데이터. tx_start 부터 tx_busy=0 이 될 때까지 유지해야 함

    output reg        tx,        // 시리얼 출력 (쉬는 동안 1)
    output wire       tx_busy    // 전송 중이면 1
);

    localparam integer CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;
    localparam integer CNT_W        = $clog2(CLKS_PER_BIT);

    localparam [1:0] IDLE  = 2'd0,
                     START = 2'd1,
                     DATA  = 2'd2,
                     STOP  = 2'd3;

    reg [1:0]       state;
    reg [CNT_W-1:0] cnt;       // 1비트 시간 안에서 clk 를 세는 카운터
    reg [2:0]       bit_idx;   // 지금 보내는 데이터 비트 번호 (0 ~ 7)

    wire bit_done = (cnt == CLKS_PER_BIT - 1);  // 1비트 시간이 끝났다

    assign tx_busy = (state != IDLE);

    // ---- 상태, tx 출력 ----
    // 리셋 직후 tx=1(idle), state=IDLE 이어야 하므로 리셋을 쓴다.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            tx    <= 1'b1;
        end else begin
            case (state)
                // 대기: tx_start 가 오면 start bit(0) 출력
                IDLE: begin
                    if (tx_start) begin
                        tx    <= 1'b0;
                        state <= START;
                    end
                end

                // start bit 를 1비트 시간 동안 유지한 뒤 data bit0 출력
                START: begin
                    if (bit_done) begin
                        tx    <= tx_data[0];
                        state <= DATA;
                    end
                end

                // 1비트 시간마다 다음 데이터 비트 출력 (LSB 먼저), 마지막 뒤에는 stop bit(1)
                DATA: begin
                    if (bit_done) begin
                        if (bit_idx == 3'd7) begin
                            tx    <= 1'b1;
                            state <= STOP;
                        end else begin
                            tx    <= tx_data[bit_idx + 1'b1];
                        end
                    end
                end

                // stop bit 를 1비트 시간 동안 유지한 뒤 종료
                STOP: begin
                    if (bit_done)
                        state <= IDLE;
                end
            endcase
        end
    end

    // ---- 카운터 ----
    // 쉬는 동안 매 클럭 0으로 지우므로 리셋이 필요 없다.
    always @(posedge clk) begin
        if (state == IDLE || bit_done) cnt <= 0;
        else                           cnt <= cnt + 1'b1;
    end

    // ---- 비트 번호 ----
    // 쓰기 전에 항상 새 값이 들어가므로 리셋이 필요 없다.
    always @(posedge clk) begin
        if (state == START)
            bit_idx <= 3'd0;
        else if (state == DATA && bit_done)
            bit_idx <= bit_idx + 1'b1;
    end

endmodule
