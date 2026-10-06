`timescale 1ns / 1ps

// UART 수신기
//   기본은 8N1, PARITY_EN=1 이면 패리티 비트도 검사한다 (8P1).
//   rx_tick(1비트 시간에 16번) 을 세어서 각 비트의 "가운데"에서 값을 읽는다.
//   가운데에서 읽으면 신호가 흔들리는 가장자리를 피할 수 있다.
//
//   상태 흐름:  IDLE -> START -> DATA(8번) -> [PARITY] -> STOP -> IDLE
module uart_rx #(
    parameter PARITY_EN  = 0,  // 0: 패리티 없음, 1: 패리티 검사
    parameter PARITY_ODD = 0   // 0: 짝수(even) 패리티, 1: 홀수(odd) 패리티
) (
    input  wire       clk,
    input  wire       rst_n,

    input  wire       rx_tick,       // 1비트 시간에 16번 발생하는 펄스
    input  wire       rx,            // 시리얼 입력 (쉬는 동안 1), clk 와 비동기

    output reg  [7:0] rx_data,       // 수신한 데이터
    output reg        rx_done,       // 1클럭 펄스: rx_data 가 유효함
    output reg        framing_error, // 1클럭 펄스: stop bit 가 1이 아니었음
    output reg        parity_error   // 1클럭 펄스: 패리티가 맞지 않았음
);

    localparam [2:0] IDLE   = 3'd0,
                     START  = 3'd1,
                     DATA   = 3'd2,
                     PARITY = 3'd3,
                     STOP   = 3'd4;

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

    reg [2:0] state;
    reg [3:0] cnt;         // rx_tick 개수를 세는 카운터
    reg [2:0] bit_idx;     // 지금 받는 데이터 비트 번호 (0 ~ 7)
    reg [7:0] data_reg;    // 받은 데이터를 모으는 레지스터
    reg       parity_reg;  // 받은 패리티 비트

    // 받은 데이터로 계산한 "기대하는 패리티" (송신기와 같은 방식)
    wire expected_parity = PARITY_ODD ? ~(^data_reg) : (^data_reg);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= IDLE;
            cnt           <= 4'd0;
            bit_idx       <= 3'd0;
            data_reg      <= 8'd0;
            parity_reg    <= 1'b0;
            rx_data       <= 8'd0;
            rx_done       <= 1'b0;
            framing_error <= 1'b0;
            parity_error  <= 1'b0;
        end else begin
            // 펄스 출력은 기본적으로 0, 아래에서 필요할 때만 1로 만든다
            rx_done       <= 1'b0;
            framing_error <= 1'b0;
            parity_error  <= 1'b0;

            case (state)
                // 대기: rx 가 0으로 떨어지면 start bit 가 시작된 것
                IDLE: begin
                    cnt <= 4'd0;
                    if (rx_sync1 == 1'b0)
                        state <= START;
                end

                // start bit 의 가운데(rx_tick 8개 후)에서 다시 확인한다.
                // 아직 0이면 진짜 start bit, 1이면 잡음이므로 무시한다.
                START: begin
                    if (rx_tick) begin
                        if (cnt == 4'd7) begin
                            cnt <= 4'd0;
                            if (rx_sync1 == 1'b0) begin
                                bit_idx <= 3'd0;
                                state   <= DATA;
                            end else begin
                                state <= IDLE;
                            end
                        end else begin
                            cnt <= cnt + 1'b1;
                        end
                    end
                end

                // 16 tick(= 1비트)마다 한 번씩 읽는다. 그러면 항상 비트의 가운데이다.
                DATA: begin
                    if (rx_tick) begin
                        if (cnt == 4'd15) begin
                            cnt              <= 4'd0;
                            data_reg[bit_idx] <= rx_sync1;
                            if (bit_idx == 3'd7) begin
                                if (PARITY_EN) state <= PARITY;
                                else           state <= STOP;
                            end else begin
                                bit_idx <= bit_idx + 1'b1;
                            end
                        end else begin
                            cnt <= cnt + 1'b1;
                        end
                    end
                end

                // 패리티 비트 읽기 (PARITY_EN=1 일 때만 거쳐감)
                PARITY: begin
                    if (rx_tick) begin
                        if (cnt == 4'd15) begin
                            cnt        <= 4'd0;
                            parity_reg <= rx_sync1;
                            state      <= STOP;
                        end else begin
                            cnt <= cnt + 1'b1;
                        end
                    end
                end

                // stop bit 의 가운데에서 읽는다. 1이어야 정상.
                // 수신 완료를 알리고 IDLE 로 돌아간다.
                STOP: begin
                    if (rx_tick) begin
                        if (cnt == 4'd15) begin
                            rx_data       <= data_reg;
                            rx_done       <= 1'b1;
                            framing_error <= (rx_sync1 != 1'b1);
                            parity_error  <= PARITY_EN && (parity_reg != expected_parity);
                            state         <= IDLE;
                        end else begin
                            cnt <= cnt + 1'b1;
                        end
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
