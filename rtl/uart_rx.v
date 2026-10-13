`timescale 1ns / 1ps

// UART 수신기
//   8N1 (start 1 + data 8 + stop 1).
//   rx_tick(1비트 시간에 16번) 을 세어서 각 비트의 "가운데"에서 값을 읽는다.
//   가운데에서 읽으면 신호가 흔들리는 가장자리를 피할 수 있다.
//
//   상태 흐름:  IDLE -> START -> DATA(8번) -> STOP -> IDLE
module uart_rx (
    input  wire       clk,
    input  wire       rst_n,

    input  wire       rx_tick,       // 1비트 시간에 16번 발생하는 펄스
    input  wire       rx,            // 시리얼 입력 (쉬는 동안 1), clk 와 비동기

    output reg  [7:0] rx_data,       // 수신한 데이터
    output reg        rx_done        // 1클럭 펄스: rx_data 가 유효함
);

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

    reg [1:0] state;
    reg [3:0] cnt;         // rx_tick 개수를 세는 카운터
    reg [2:0] bit_idx;     // 지금 받는 데이터 비트 번호 (0 ~ 7)
    reg [7:0] data_reg;    // 받은 데이터를 모으는 레지스터


    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= IDLE;
            cnt           <= 4'd0;
            bit_idx       <= 3'd0;
            data_reg      <= 8'd0;
            rx_data       <= 8'd0;
            rx_done       <= 1'b0;
        end else begin
            // 펄스 출력은 기본적으로 0, 아래에서 필요할 때만 1로 만든다
            rx_done       <= 1'b0;

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
                                state <= STOP;
                            end else begin
                                bit_idx <= bit_idx + 1'b1;
                            end
                        end else begin
                            cnt <= cnt + 1'b1;
                        end
                    end
                end

                // stop bit 의 가운데까지 기다린다. (stop bit 값은 검사하지 않는다)
                // 수신 완료를 알리고 IDLE 로 돌아간다.
                STOP: begin
                    if (rx_tick) begin
                        if (cnt == 4'd15) begin
                            rx_data       <= data_reg;
                            rx_done       <= 1'b1;
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
