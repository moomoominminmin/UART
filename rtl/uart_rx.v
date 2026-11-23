`timescale 1ns / 1ps

// UART 수신기 (8N1: start 1 + data 8 + stop 1)
//   100MHz 클럭을 그대로 쓰고, 1비트 = 5클럭으로 받는다. (100MHz / 5 = 20Mbps)
//   cnt 가 0 -> 1 -> 2 -> 3 -> 4 를 돌고, 각 비트의 3번째 클럭(cnt == 2)에서 값을 읽는다.
//   rx 가 0으로 떨어진 것을 본 클럭을 start bit 의 1번째 클럭(cnt = 0)으로 친다.
//
//   상태 흐름:  IDLE -> START -> DATA(8번) -> STOP -> IDLE
//
//   면적을 줄이기 위해
//     - rx_done 은 레지스터 없이 (STOP && sample) 로 바로 만든다.
//     - 리셋이 꼭 필요한 state 만 리셋하고, 나머지는 리셋 없는 DFF 를 쓴다.
module uart_rx #(
    parameter CLKS_PER_BIT = 5,         // 1비트 = 클럭 5개
    parameter SAMPLE_POINT = 2          // cnt 가 이 값일 때 읽는다 (2 = 3번째 클럭)
) (
    input  wire       clk,
    input  wire       rst_n,

    input  wire       rx,            // 시리얼 입력 (쉬는 동안 1), clk 와 비동기

    output reg  [7:0] rx_data,       // 수신한 데이터 (rx_done 일 때 유효)
    output wire       rx_done        // 1클럭 펄스: 1바이트 수신 완료
);

    localparam [1:0] IDLE  = 2'd0,
                     START = 2'd1,
                     DATA  = 2'd2,
                     STOP  = 2'd3;

    localparam integer CNT_W = $clog2(CLKS_PER_BIT);

    // ---- 입력 동기화 ----
    // rx 는 clk 와 상관없이 변하는 외부 신호라서 플립플롭 2개를 거쳐서 사용한다.
    reg rx_sync0, rx_sync1;
    always @(posedge clk) begin
        rx_sync0 <= rx;
        rx_sync1 <= rx_sync0;
    end
    // 이후로는 rx 대신 항상 rx_sync1 만 사용한다.

    reg [1:0]       state;
    reg [CNT_W-1:0] cnt;      // 1비트 안에서 클럭을 세는 카운터 (0 ~ 4)
    reg [2:0]       bit_idx;  // 지금 받는 데이터 비트 번호 (0 ~ 7)

    wire sample   = (cnt == SAMPLE_POINT);      // 3번째 클럭: 값을 읽는다
    wire bit_done = (cnt == CLKS_PER_BIT - 1);  // 5번째 클럭: 1비트 시간이 끝났다

    assign rx_done = (state == STOP) && sample;

    // ---- 상태 ----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
        end else begin
            case (state)
                // 대기: rx 가 0으로 떨어지면 start bit 가 시작된 것 (이 클럭이 1번째)
                IDLE:  if (rx_sync1 == 1'b0) state <= START;

                // start bit 의 3번째 클럭에서 다시 확인한다.
                // 1이면 잡음이므로 무시하고, 0이면 이 비트가 끝날 때 DATA 로 넘어간다.
                START: begin
                    if (sample && rx_sync1) state <= IDLE;
                    else if (bit_done)      state <= DATA;
                end

                // 각 비트의 3번째 클럭에서 읽고, 8번째 비트가 끝나면 STOP 으로
                DATA:  if (bit_done && bit_idx == 3'd7) state <= STOP;

                // stop bit 의 3번째 클럭까지 기다린다. (stop bit 값은 검사하지 않는다)
                // 이 클럭이 곧 rx_done 이다. 남은 stop bit 는 IDLE 에서 1로 보인다.
                STOP:  if (sample) state <= IDLE;
            endcase
        end
    end

    // ---- 5 카운터 ----
    // IDLE 에서 1을 넣어 둔다. rx 가 0인 걸 본 클럭이 이미 0번째이기 때문이다.
    // IDLE 에서 매 클럭 덮어쓰므로 리셋이 필요 없다.
    always @(posedge clk) begin
        if (state == IDLE)  cnt <= 1;
        else if (bit_done)  cnt <= 0;
        else                cnt <= cnt + 1'b1;
    end

    // ---- 데이터, 비트 번호 ----
    always @(posedge clk) begin
        if (state == START) begin
            bit_idx <= 3'd0;
        end else if (state == DATA) begin
            if (sample)   rx_data[bit_idx] <= rx_sync1;
            if (bit_done) bit_idx          <= bit_idx + 1'b1;
        end
    end

endmodule
