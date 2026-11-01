`timescale 1ns / 1ps

// UART 수신기 (8N1: start 1 + data 8 + stop 1)
//   start bit 의 하강 엣지에서 카운터를 시작해서,
//   각 비트의 "가운데"에서 값을 읽는다. (가장자리는 신호가 흔들리기 때문)
//
//   상태 흐름:  IDLE -> START -> DATA(8번) -> STOP -> IDLE
//
//   면적을 줄이기 위해
//     - rx_done 은 레지스터 없이 (STOP && bit_done) 로 바로 만든다.
//     - 비교기는 bit_done 하나만 쓴다. (START 에서는 카운터를 중간값부터 시작)
//     - 리셋이 꼭 필요한 state 만 리셋하고, 나머지는 리셋 없는 DFF 를 쓴다. (더 작다)
module uart_rx #(
    parameter CLK_FREQ  = 50_000_000,
    parameter BAUD_RATE = 115200
) (
    input  wire       clk,
    input  wire       rst_n,

    input  wire       rx,            // 시리얼 입력 (쉬는 동안 1), clk 와 비동기

    output reg  [7:0] rx_data,       // 수신한 데이터 (rx_done 일 때 유효)
    output wire       rx_done        // 1클럭 펄스: 1바이트 수신 완료
);

    localparam integer CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;
    localparam integer CNT_W        = $clog2(CLKS_PER_BIT);
    // START 에서 이 값부터 세면 bit_done 이 "반 비트 시간" 뒤에 뜬다
    localparam integer HALF_START   = CLKS_PER_BIT - CLKS_PER_BIT / 2;

    localparam [1:0] IDLE  = 2'd0,
                     START = 2'd1,
                     DATA  = 2'd2,
                     STOP  = 2'd3;

    // ---- 입력 동기화 ----
    // rx 는 clk 와 상관없이 변하는 외부 신호라서 플립플롭 2개를 거쳐서 사용한다.
    // (바로 쓰면 메타스테이빌리티 문제가 생길 수 있음)
    // 리셋 없는 DFF 를 쓴다. 리셋이 2클럭 이상 유지되는 동안 rx 값으로 채워진다.
    reg rx_sync0, rx_sync1;
    always @(posedge clk) begin
        rx_sync0 <= rx;
        rx_sync1 <= rx_sync0;
    end
    // 이후로는 rx 대신 항상 rx_sync1 만 사용한다.

    reg [1:0]       state;
    reg [CNT_W-1:0] cnt;      // clk 를 세는 카운터
    reg [2:0]       bit_idx;  // 지금 받는 데이터 비트 번호 (0 ~ 7)

    wire bit_done = (cnt == CLKS_PER_BIT - 1);  // 1비트 시간이 지났다

    assign rx_done = (state == STOP) && bit_done;

    // ---- 상태 ----
    // 리셋이 필요한 레지스터는 state 2비트뿐이다.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
        end else begin
            case (state)
                // 대기: rx 가 0으로 떨어지면 start bit 가 시작된 것
                IDLE:  if (rx_sync1 == 1'b0) state <= START;

                // start bit 의 가운데에서 다시 확인한다.
                // 아직 0이면 진짜 start bit, 1이면 잡음이므로 무시한다.
                START: if (bit_done) state <= (rx_sync1 == 1'b0) ? DATA : IDLE;

                // 1비트 시간마다 한 번씩 읽는다. 그러면 항상 비트의 가운데이다.
                DATA:  if (bit_done && bit_idx == 3'd7) state <= STOP;

                // stop bit 의 가운데까지 기다린다. (stop bit 값은 검사하지 않는다)
                // 이 상태에서 bit_done 인 클럭이 곧 rx_done 이다.
                STOP:  if (bit_done) state <= IDLE;
            endcase
        end
    end

    // ---- 카운터 ----
    // IDLE 에서 매 클럭 덮어쓰므로 리셋 없는 DFF 를 쓴다.
    always @(posedge clk) begin
        if (state == IDLE) cnt <= HALF_START;
        else if (bit_done) cnt <= 0;
        else               cnt <= cnt + 1'b1;
    end

    // ---- 데이터, 비트 번호 ----
    // 쓰기 전에 항상 새 값이 들어가므로 리셋이 필요 없다.
    // (리셋 직후 첫 수신 전까지 rx_data 는 X 이다. rx_done 일 때만 유효하므로 문제 없음)
    always @(posedge clk) begin
        if (state == START) begin
            bit_idx <= 3'd0;
        end else if (state == DATA && bit_done) begin
            rx_data[bit_idx] <= rx_sync1;
            bit_idx          <= bit_idx + 1'b1;
        end
    end

endmodule
