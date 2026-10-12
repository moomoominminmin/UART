`timescale 1ns / 1ps

// 진단용 테스트벤치: DUT 의 tx 핀 파형을 그대로 찍어서 보레이트 / 프레임 길이 / 패리티를 알아낸다.
// 합격/불합격 판정은 없다. "uart_top dut (" 의 모듈 이름만 바꿔서 쓴다.
// tx_empty / rx_empty / parity_error 는 쓰지 않는다.
module tb_uart_diag;
    reg        clk = 0, rst_n = 0, wr_en = 0, rd_en = 0, rx = 1;
    reg  [7:0] wr_data = 0;
    wire       tx_full, rx_overrun, framing_error, tx;
    wire [7:0] rd_data;

    uart_top dut (
        .clk(clk), .rst_n(rst_n),
        .wr_en(wr_en), .wr_data(wr_data), .tx_full(tx_full),
        .rd_en(rd_en), .rd_data(rd_data),
        .rx_overrun(rx_overrun), .framing_error(framing_error),
        .tx(tx), .rx(rx)
    );

    always #10 clk = ~clk;

    // tx 가 바뀔 때마다 시각과 직전 값이 유지된 시간을 출력
    time t_last = 0;
    reg  tx_prev = 1;
    always @(tx) begin
        $display("  tx %b -> %b  at %0d ns   (prev level lasted %0d ns)", tx_prev, tx, $time, ($time - t_last));
        t_last  = $time;
        tx_prev = tx;
    end

    task send(input [7:0] d);
        begin
            $display("--- write 0x%02h  ---", d);
            @(negedge clk); wr_data = d; wr_en = 1;
            @(negedge clk); wr_en = 0;
            #(150_000);   // 프레임 하나가 충분히 끝날 때까지
        end
    endtask

    initial begin
        repeat (5) @(negedge clk);
        rst_n = 1;
        repeat (5) @(negedge clk);
        send(8'h55);
        send(8'h01);
        send(8'h00);
        $display("DONE");
        $finish;
    end
endmodule
