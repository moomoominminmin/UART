`timescale 1ns / 1ps

// UART transmitter, 8N1 (8 data bits, no parity, 1 stop bit)
// Drives one bit per tx_tick pulse (tx_tick comes from baud_gen, 1x baud rate)
module uart_tx (
    input  wire       clk,
    input  wire       rst_n,

    input  wire       tx_tick,     // 1 pulse per bit period
    input  wire       tx_start,    // pulse: latch tx_data and begin sending
    input  wire [7:0] tx_data,

    output reg         tx,         // serial line (idle = 1)
    output reg         tx_busy,    // high while a frame is in flight
    output reg         tx_done     // 1-cycle pulse when the frame finishes
);

    localparam [1:0] IDLE  = 2'd0,
                      START = 2'd1,
                      DATA  = 2'd2,
                      STOP  = 2'd3;

    reg [1:0] state;
    reg [2:0] bit_idx;
    reg [7:0] data_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= IDLE;
            tx       <= 1'b1;
            tx_busy  <= 1'b0;
            tx_done  <= 1'b0;
            bit_idx  <= 3'd0;
            data_reg <= 8'd0;
        end else begin
            tx_done <= 1'b0;

            case (state)
                IDLE: begin
                    tx <= 1'b1;
                    if (tx_start) begin
                        data_reg <= tx_data;
                        tx_busy  <= 1'b1;
                        state    <= START;
                    end
                end

                // wait for the next bit-period boundary, then drive the start bit
                START: begin
                    if (tx_tick) begin
                        tx      <= 1'b0;
                        bit_idx <= 3'd0;
                        state   <= DATA;
                    end
                end

                DATA: begin
                    if (tx_tick) begin
                        tx <= data_reg[bit_idx];
                        if (bit_idx == 3'd7) begin
                            state <= STOP;
                        end else begin
                            bit_idx <= bit_idx + 1'b1;
                        end
                    end
                end

                STOP: begin
                    if (tx_tick) begin
                        tx      <= 1'b1;
                        tx_busy <= 1'b0;
                        tx_done <= 1'b1;
                        state   <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
