`timescale 1ns / 1ps

// Baud rate generator
// - tx_tick : pulses once per bit period  (1x baud rate)     -> used by uart_tx
// - rx_tick : pulses 16x per bit period   (16x oversampling) -> used by uart_rx for mid-bit sampling
module baud_gen #(
    parameter CLK_FREQ    = 50_000_000,
    parameter BAUD_RATE   = 115200,
    parameter OVERSAMPLE  = 16
) (
    input  wire clk,
    input  wire rst_n,
    output wire tx_tick,
    output wire rx_tick
);

    localparam integer TX_DIV = CLK_FREQ / BAUD_RATE;
    localparam integer RX_DIV = CLK_FREQ / (BAUD_RATE * OVERSAMPLE);

    localparam integer TX_CNT_W = $clog2(TX_DIV);
    localparam integer RX_CNT_W = $clog2(RX_DIV);

    reg [TX_CNT_W-1:0] tx_cnt;
    reg [RX_CNT_W-1:0] rx_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_cnt <= 0;
        end else if (tx_cnt == TX_DIV - 1) begin
            tx_cnt <= 0;
        end else begin
            tx_cnt <= tx_cnt + 1'b1;
        end
    end

    assign tx_tick = (tx_cnt == TX_DIV - 1);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_cnt <= 0;
        end else if (rx_cnt == RX_DIV - 1) begin
            rx_cnt <= 0;
        end else begin
            rx_cnt <= rx_cnt + 1'b1;
        end
    end

    assign rx_tick = (rx_cnt == RX_DIV - 1);

endmodule
