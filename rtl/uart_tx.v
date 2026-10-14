`timescale 1ns / 1ps

// UART 송신기 (8N1: start 1 + data 8 + stop 1)
//   시스템 clk 를 CLKS_PER_BIT 번 세어서 1비트 시간을 만든다.
//
//   상태 흐름:  IDLE -> START -> DATA(8번) -> STOP -> IDLE
module uart_tx #(
    parameter CLK_FREQ  = 50_000_000,
    parameter BAUD_RATE = 115200
) (
    input  wire       clk,
    input  wire       rst_n,

    input  wire       tx_start,  // 1클럭 펄스: tx_data 를 받아서 전송 시작 (tx_busy=0 일 때만)
    input  wire [7:0] tx_data,

    output reg        tx,        // 시리얼 출력 (쉬는 동안 1)
    output reg        tx_busy    // 전송 중이면 1
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
    reg [7:0]       data_reg;  // 보낼 데이터를 저장해 두는 레지스터

    wire bit_done = (cnt == CLKS_PER_BIT - 1);  // 1비트 시간이 끝났다

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= IDLE;
            tx       <= 1'b1;
            tx_busy  <= 1'b0;
            cnt      <= 0;
            bit_idx  <= 3'd0;
            data_reg <= 8'd0;
        end else begin
            case (state)
                // 대기: tx_start 가 오면 데이터를 저장하고 start bit(0) 출력
                IDLE: begin
                    tx <= 1'b1;
                    if (tx_start) begin
                        data_reg <= tx_data;
                        tx_busy  <= 1'b1;
                        tx       <= 1'b0;
                        cnt      <= 0;
                        state    <= START;
                    end
                end

                // start bit 를 1비트 시간 동안 유지한 뒤 data bit0 출력
                START: begin
                    if (bit_done) begin
                        cnt     <= 0;
                        tx      <= data_reg[0];
                        bit_idx <= 3'd0;
                        state   <= DATA;
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                // 1비트 시간마다 다음 데이터 비트 출력 (LSB 먼저), 마지막 뒤에는 stop bit(1)
                DATA: begin
                    if (bit_done) begin
                        cnt <= 0;
                        if (bit_idx == 3'd7) begin
                            tx    <= 1'b1;
                            state <= STOP;
                        end else begin
                            bit_idx <= bit_idx + 1'b1;
                            tx      <= data_reg[bit_idx + 1'b1];
                        end
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                // stop bit 를 1비트 시간 동안 유지한 뒤 종료
                STOP: begin
                    if (bit_done) begin
                        tx_busy <= 1'b0;
                        state   <= IDLE;
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
