`timescale 1ns / 1ps

// loopback 테스트: tx 를 rx 에 연결하고 여러 바이트를 보내서 그대로 돌아오는지 확인
//   합성 후 netlist 에도 그대로 쓸 수 있게 DUT 의 포트만 사용하고 파라미터는 덮어쓰지 않는다.
//   (기본값 50MHz / 115200bps 기준) 합성 후에는 아래 "uart_top dut (" 의 모듈 이름만 바꾸면 된다.
module tb_uart_top;

    reg      clk = 0;
    reg        rst_n = 0;
    reg        tx_start = 0;
    reg  [7:0] tx_data = 0;
    wire       tx_busy;
    wire [7:0] rx_data;
    wire       rx_done;
    wire       line;   // tx -> rx loopback

    uart_top dut (
        .clk(clk), .rst_n(rst_n),
        .tx_start(tx_start), .tx_data(tx_data), .tx_busy(tx_busy),
        .rx_data(rx_data), .rx_done(rx_done),
        .tx(line), .rx(line)
    );

    always #10 clk = ~clk;  // 50MHz (uart_top 기본 CLK_FREQ 와 일치해야 함)

    reg [7:0] expected [0:3];
    integer   rx_cnt = 0;
    integer   errors = 0;

    always @(posedge clk) begin
        if (rx_done) begin
            if (rx_data !== expected[rx_cnt]) begin
                $display("FAIL: #%0d expected %h got %h", rx_cnt, expected[rx_cnt], rx_data);
                errors = errors + 1;
            end else begin
                $display("PASS: #%0d %h", rx_cnt, rx_data);
            end
            rx_cnt = rx_cnt + 1;
        end
    end

    task send(input [7:0] d);
        begin
            @(posedge clk);
            while (tx_busy) @(posedge clk);
            tx_data  <= d;
            tx_start <= 1'b1;
            @(posedge clk);
            tx_start <= 1'b0;
        end
    endtask

    integer i;
    initial begin
        expected[0] = 8'h55; expected[1] = 8'hA3; expected[2] = 8'h00; expected[3] = 8'hFF;
        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (5) @(posedge clk);

        for (i = 0; i < 4; i = i + 1) send(expected[i]);

        wait (rx_cnt == 4);
        repeat (100) @(posedge clk);
        if (errors == 0) $display("ALL PASS");
        else             $display("%0d ERRORS", errors);
        $finish;
    end

    // 안전장치
    initial begin
        #5_000_000;
        $display("TIMEOUT");
        $finish;
    end

endmodule
