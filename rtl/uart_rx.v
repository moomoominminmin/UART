`timescale 1ns / 1ps

// UART 수신기 (8N1: start 1 + data 8 + stop 1)
//   start bit 의 하강 엣지에서 카운터를 시작해서,
//   각 비트의 "가운데"에서 값을 읽는다. (가장자리는 신호가 흔들리기 때문)
//
//   상태 흐름:  IDLE -> START -> DATA(8번) -> STOP -> IDLE
//
//   면적(DFF 수)을 줄이기 위해
//     - 비트 번호(bit_idx) 대신 시프트 레지스터 안의 "마커" 비트로 8비트를 셌다.
//     - rx_done 은 레지스터 없이 (STOP && bit_done) 로 바로 만든다.
//     - 비교기는 bit_done 하나만 쓴다. (START 에서는 카운터를 중간값부터 시작)
module uart_rx #(
    parameter CLK_FREQ  = 50_000_000,
    parameter BAUD_RATE = 115200
) (
    input  wire       clk,
    input  wire       rst_n,

    input  wire       rx,            // 시리얼 입력 (쉬는 동안 1), clk 와 비동기

    output wire [7:0] rx_data,       // 수신한 데이터 (rx_done 일 때 유효)
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
    reg rx_sync0, rx_sync1;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_sync0 <= 1'b1;
            rx_sync1 <= 1'b1;
        end else begin
            rx_sync0 <= rx;
            rx_sync1 <= rx_sync0;
        end
    end
    // 이후로는 rx 대신 항상 rx_sync1 만 사용한다.

    reg [1:0]       state;
    reg [CNT_W-1:0] cnt;    // clk 를 세는 카운터
    reg [8:0]       shreg;  // { 받은 데이터 8비트, 마커 } : 위에서 밀어 넣는다

    wire bit_done = (cnt == CLKS_PER_BIT - 1);  // 1비트 시간이 지났다

    assign rx_data = shreg[8:1];
    assign rx_done = (state == STOP) && bit_done;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            cnt   <= 0;
        end else begin
            case (state)
                // 대기: rx 가 0으로 떨어지면 start bit 가 시작된 것
                IDLE: begin
                    cnt <= HALF_START;
                    if (rx_sync1 == 1'b0)
                        state <= START;
                end

                // start bit 의 가운데에서 다시 확인한다.
                // 아직 0이면 진짜 start bit, 1이면 잡음이므로 무시한다.
                START: begin
                    if (bit_done) begin
                        cnt   <= 0;
                        state <= (rx_sync1 == 1'b0) ? DATA : IDLE;
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                // 1비트 시간마다 한 번씩 읽는다. 그러면 항상 비트의 가운데이다.
                // 마커가 shreg[1] 에 있으면 지금 읽는 것이 마지막(8번째) 비트이다.
                DATA: begin
                    if (bit_done) begin
                        cnt <= 0;
                        if (shreg[1]) state <= STOP;
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                // stop bit 의 가운데까지 기다린다. (stop bit 값은 검사하지 않는다)
                // 이 상태에서 bit_done 인 클럭이 곧 rx_done 이다.
                STOP: begin
                    if (bit_done) state <= IDLE;
                    else          cnt   <= cnt + 1'b1;
                end
            endcase
        end
    end

    // ---- 데이터 시프트 레지스터 ----
    // 데이터만 담는 레지스터라서 리셋이 필요 없다. (리셋 없는 DFF 가 더 작다)
    // START 끝에서 마커를 맨 위에 넣고, 데이터가 하나 들어올 때마다 한 칸씩 내려간다.
    // 8개를 받으면 마커가 shreg[0] 에 도착하고 데이터는 shreg[8:1] 에 LSB 순서대로 놓인다.
    always @(posedge clk) begin
        if (bit_done) begin
            if (state == START)
                shreg <= 9'b1_0000_0000;
            else if (state == DATA)
                shreg <= {rx_sync1, shreg[8:1]};
        end
    end

endmodule
