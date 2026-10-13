`timescale 1ns / 1ps

// UART 송신기 (8N1: start 1 + data 8 + stop 1)
//   tx_tick(1비트 시간마다 1번) 마다 비트를 하나씩 내보낸다.
//
//   상태 흐름:  IDLE -> START -> DATA(8번) -> STOP -> IDLE
module uart_tx (
    input  wire       clk,
    input  wire       rst_n,

    input  wire       tx_tick,   // 1비트 시간마다 1클럭 펄스
    input  wire       tx_start,  // 1클럭 펄스: tx_data 를 받아서 전송 시작
    input  wire [7:0] tx_data,

    output reg        tx,        // 시리얼 출력 (쉬는 동안 1)
    output reg        tx_busy    // 전송 중이면 1
);

    localparam [1:0] IDLE  = 2'd0,
                     START = 2'd1,
                     DATA  = 2'd2,
                     STOP  = 2'd3;

    reg [1:0] state;
    reg [2:0] bit_idx;   // 지금 보내는 데이터 비트 번호 (0 ~ 7)
    reg [7:0] data_reg;  // 보낼 데이터를 저장해 두는 레지스터

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= IDLE;
            tx       <= 1'b1;
            tx_busy  <= 1'b0;
            bit_idx  <= 3'd0;
            data_reg <= 8'd0;
        end else begin
            case (state)
                // 대기: tx_start 가 오면 데이터를 저장하고 시작
                IDLE: begin
                    tx <= 1'b1;
                    if (tx_start) begin
                        data_reg <= tx_data;
                        tx_busy  <= 1'b1;
                        state    <= START;
                    end
                end

                // 다음 tx_tick 에서 start bit(0) 출력
                START: begin
                    if (tx_tick) begin
                        tx      <= 1'b0;
                        bit_idx <= 3'd0;
                        state   <= DATA;
                    end
                end

                // tx_tick 마다 데이터를 LSB(bit0)부터 한 비트씩 출력
                DATA: begin
                    if (tx_tick) begin
                        tx <= data_reg[bit_idx];
                        if (bit_idx == 3'd7) state <= STOP;
                        else                 bit_idx <= bit_idx + 1'b1;
                    end
                end

                // stop bit(1) 출력 후 종료
                STOP: begin
                    if (tx_tick) begin
                        tx      <= 1'b1;
                        tx_busy <= 1'b0;
                        state   <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
