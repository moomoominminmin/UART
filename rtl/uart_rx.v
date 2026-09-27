`timescale 1ns / 1ps

// UART receiver, 8N1 (8 data bits, no parity, 1 stop bit)
// Uses rx_tick from baud_gen (16x oversampling) to find the mid-point of each
// bit and sample there, which rejects edge jitter/noise on the line.
module uart_rx #(
    parameter OVERSAMPLE = 16
) (
    input  wire       clk,
    input  wire       rst_n,

    input  wire       rx_tick,     // 16 pulses per bit period
    input  wire       rx,          // serial line (idle = 1), async to clk

    output reg [7:0]  rx_data,
    output reg        rx_done,       // 1-cycle pulse: rx_data is valid
    output reg        framing_error  // 1-cycle pulse: stop bit was not '1'
);

    localparam [1:0] IDLE  = 2'd0,
                      START = 2'd1,
                      DATA  = 2'd2,
                      STOP  = 2'd3;

    localparam integer OS_CNT_W = $clog2(OVERSAMPLE);
    localparam integer MID      = OVERSAMPLE / 2 - 1; // sample point within a bit period

    // 2-flop synchronizer: rx is an external async signal
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

    reg [1:0]          state;
    reg [OS_CNT_W-1:0]  os_cnt;
    reg [2:0]           bit_idx;
    reg [7:0]            data_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= IDLE;
            os_cnt        <= 0;
            bit_idx       <= 3'd0;
            data_reg      <= 8'd0;
            rx_data       <= 8'd0;
            rx_done       <= 1'b0;
            framing_error <= 1'b0;
        end else begin
            rx_done       <= 1'b0;
            framing_error <= 1'b0;

            case (state)
                IDLE: begin
                    os_cnt <= 0;
                    if (rx_sync1 == 1'b0) begin
                        // possible start bit, verify at its mid-point
                        state <= START;
                    end
                end

                // confirm the line is still low half a bit period after the
                // falling edge was seen; a glitch shorter than that is rejected
                START: begin
                    if (rx_tick) begin
                        if (os_cnt == MID[OS_CNT_W-1:0]) begin
                            if (rx_sync1 == 1'b0) begin
                                os_cnt  <= 0;
                                bit_idx <= 3'd0;
                                state   <= DATA;
                            end else begin
                                state <= IDLE; // glitch, not a real start bit
                            end
                        end else begin
                            os_cnt <= os_cnt + 1'b1;
                        end
                    end
                end

                DATA: begin
                    if (rx_tick) begin
                        if (os_cnt == (OVERSAMPLE - 1)) begin
                            os_cnt          <= 0;
                            data_reg[bit_idx] <= rx_sync1;
                            if (bit_idx == 3'd7) begin
                                state <= STOP;
                            end else begin
                                bit_idx <= bit_idx + 1'b1;
                            end
                        end else begin
                            os_cnt <= os_cnt + 1'b1;
                        end
                    end
                end

                // os_cnt was reset at bit7's own midpoint (see DATA above), so
                // reaching the stop bit's midpoint takes a FULL period (like the
                // bit-to-bit spacing in DATA), not the half-period used in START.
                STOP: begin
                    if (rx_tick) begin
                        if (os_cnt == (OVERSAMPLE - 1)) begin
                            rx_data       <= data_reg;
                            rx_done       <= 1'b1;
                            framing_error <= (rx_sync1 != 1'b1);
                            state         <= IDLE;
                        end else begin
                            os_cnt <= os_cnt + 1'b1;
                        end
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
