`timescale 1ns / 1ps

// UART receiver, 8-N-1 by default, or 8-P-1 when PARITY_EN=1
// (8 data bits, optional parity bit, 1 stop bit)
// Uses rx_tick from baud_gen (16x oversampling) to find the mid-point of each
// bit and sample there, which rejects edge jitter/noise on the line.
module uart_rx #(
    parameter OVERSAMPLE = 16,
    parameter PARITY_EN  = 0,  // 0: no parity bit (legacy 8N1), 1: expect/check a parity bit
    parameter PARITY_ODD = 0   // 0: even parity, 1: odd parity (only used if PARITY_EN=1)
) (
    input  wire       clk,
    input  wire       rst_n,

    input  wire       rx_tick,     // 16 pulses per bit period
    input  wire       rx,          // serial line (idle = 1), async to clk

    output reg [7:0]  rx_data,
    output reg        rx_done,       // 1-cycle pulse: rx_data is valid
    output reg        framing_error, // 1-cycle pulse: stop bit was not '1'
    output reg        parity_error   // 1-cycle pulse: received parity bit didn't match data_reg (PARITY_EN=1 only)
);

    localparam [2:0] IDLE   = 3'd0,
                      START  = 3'd1,
                      DATA   = 3'd2,
                      PARITY = 3'd3,
                      STOP   = 3'd4;

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

    reg [2:0]          state;
    reg [OS_CNT_W-1:0]  os_cnt;
    reg [2:0]           bit_idx;
    reg [7:0]            data_reg;
    reg                  parity_reg;   // received parity bit (PARITY_EN=1 only)

    // expected parity of data_reg, flipped to odd parity if PARITY_ODD is set
    wire expected_parity = PARITY_ODD ? ~(^data_reg) : (^data_reg);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= IDLE;
            os_cnt        <= 0;
            bit_idx       <= 3'd0;
            data_reg      <= 8'd0;
            parity_reg    <= 1'b0;
            rx_data       <= 8'd0;
            rx_done       <= 1'b0;
            framing_error <= 1'b0;
            parity_error  <= 1'b0;
        end else begin
            rx_done       <= 1'b0;
            framing_error <= 1'b0;
            parity_error  <= 1'b0;

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
                                state <= PARITY_EN ? PARITY : STOP;
                            end else begin
                                bit_idx <= bit_idx + 1'b1;
                            end
                        end else begin
                            os_cnt <= os_cnt + 1'b1;
                        end
                    end
                end

                // only entered when PARITY_EN=1; os_cnt was reset at bit7's own
                // midpoint (see DATA above), so reaching this bit's midpoint
                // takes a FULL period, same as the bit-to-bit spacing in DATA
                PARITY: begin
                    if (rx_tick) begin
                        if (os_cnt == (OVERSAMPLE - 1)) begin
                            os_cnt     <= 0;
                            parity_reg <= rx_sync1;
                            state      <= STOP;
                        end else begin
                            os_cnt <= os_cnt + 1'b1;
                        end
                    end
                end

                // os_cnt was reset at the previous bit's midpoint (bit7 in DATA,
                // or the parity bit in PARITY), so reaching the stop bit's
                // midpoint takes a FULL period (like the bit-to-bit spacing in
                // DATA), not the half-period used in START.
                STOP: begin
                    if (rx_tick) begin
                        if (os_cnt == (OVERSAMPLE - 1)) begin
                            rx_data       <= data_reg;
                            rx_done       <= 1'b1;
                            framing_error <= (rx_sync1 != 1'b1);
                            parity_error  <= PARITY_EN && (parity_reg != expected_parity);
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
