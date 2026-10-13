`timescale 1ns / 1ps

// stop bit 가 깨진 프레임을 받았을 때의 동작 테스트 (framing_error 플래그를 지운 뒤의 확인용)
//
// framing_error 가 없으므로 "오류를 알려 주는지"가 아니라 아래 두 가지를 확인한다.
//   1) stop bit 가 0 인 프레임이 와도 수신기가 멈추거나 꼬이지 않고 다음 프레임을 정상 수신한다.
//   2) stop bit 가 0 이어도 데이터 바이트는 RX FIFO 에 그대로 저장된다. (버려지지 않음)
//
// 합성 후(netlist) 시뮬레이션에서도 그대로 돌도록 만들었다.
//   - uart_top 의 "포트"만 사용한다. (내부 신호, 계층 참조 없음)
//   - tx_empty / rx_empty / parity_error / framing_error 는 쓰지 않는다. (DUT 에 없어도 됨)
//   - 파라미터를 덮어쓰지 않는다. (netlist 는 파라미터가 이미 고정되어 있음)
//   - 데이터가 들어왔는지는 rx_empty 대신 "프레임 시간이 지났다"로 판단한다.
//   - "uart_top dut (" 의 모듈 이름만 netlist 의 이름으로 바꾸면 된다.
//   - 신호는 clk 의 하강 에지(negedge)에서만 바꾸고 읽는다.
//
// 사용 포트: clk, rst_n, wr_en, wr_data, tx_full, rd_en, rd_data, rx_overrun, tx, rx
module tb_uart_top_badstop;

    // ---------------- 설정 ----------------
    localparam CLK_PERIOD = 20;     // 50MHz -> 20ns
    localparam BIT_NS     = 8680;   // 115200bps 의 1비트 시간

    // ---------------- 신호 ----------------
    reg        clk   = 0;
    reg        rst_n = 0;

    reg        wr_en   = 0;
    reg  [7:0] wr_data = 0;
    wire       tx_full;

    reg        rd_en = 0;
    wire [7:0] rd_data;

    wire       rx_overrun;
    wire       tx;

    reg        rx = 1;              // 테스트벤치가 rx 핀에 직접 넣는 신호 (쉬는 동안 1)

    // ---------------- 테스트할 모듈 ----------------
    uart_top dut (                      // <-- 합성 후에는 여기 모듈 이름만 바꾼다
        .clk       (clk),
        .rst_n     (rst_n),
        .wr_en     (wr_en),
        .wr_data   (wr_data),
        .tx_full   (tx_full),
        .rd_en     (rd_en),
        .rd_data   (rd_data),
        .rx_overrun(rx_overrun),
        .tx        (tx),
        .rx        (rx)
    );

    always #(CLK_PERIOD/2) clk = ~clk;

    // rx_overrun 은 1클럭 펄스라서 한 번이라도 1 이 되면 기억해 둔다
    reg saw_overrun = 0;
    always @(posedge clk)
        if (rx_overrun) saw_overrun <= 1;

    // ---------------- 검사 도구 ----------------
    integer errors = 0;

    task check(input cond, input [8*48:1] name);
        begin
            if (cond) begin
                $display("[%0t] OK    : %0s", $time, name);
            end else begin
                $display("[%0t] ERROR : %0s", $time, name);
                errors = errors + 1;
            end
        end
    endtask

    // RX FIFO 에서 1바이트를 읽어 기대값과 비교한다 (이미 들어 있다고 보고 바로 읽음)
    task expect_byte(input [7:0] expected);
        reg [7:0] got;
        begin
            @(negedge clk);
            got   = rd_data;
            rd_en = 1;
            @(negedge clk);
            rd_en = 0;
            if (got === expected) begin
                $display("[%0t] OK    : got 0x%02h", $time, got);
            end else begin
                $display("[%0t] ERROR : got 0x%02h, expected 0x%02h", $time, got, expected);
                errors = errors + 1;
            end
        end
    endtask

    // ---------------- 시리얼 라인 동작 ----------------

    // 정상 프레임: start 0, data 8비트(LSB 먼저), stop 1
    task send_good(input [7:0] d);
        integer i;
        begin
            rx = 0;                         // start bit
            #(BIT_NS);
            for (i = 0; i < 8; i = i + 1) begin
                rx = d[i];
                #(BIT_NS);
            end
            rx = 1;                         // stop bit
            #(BIT_NS);
        end
    endtask

    // stop bit 가 깨진 프레임: stop bit 구간 앞쪽 low_16ths/16 동안만 0 이고 나머지는 1.
    // (0 을 끝까지 유지하면 수신기가 그 0 을 새 start bit 로 착각하므로 중간에 1 로 돌린다.
    //  stop bit 의 가운데(8/16)는 지나서 0 이어야 수신기가 "깨졌다"고 보는 위치를 지난다.)
    task send_bad_stop(input [7:0] d, input integer low_16ths);
        integer i;
        begin
            rx = 0;                         // start bit
            #(BIT_NS);
            for (i = 0; i < 8; i = i + 1) begin
                rx = d[i];
                #(BIT_NS);
            end
            rx = 0;                         // 깨진 stop bit
            #(BIT_NS * low_16ths / 16);
            rx = 1;
            #(BIT_NS * (16 - low_16ths) / 16);
        end
    endtask

    // 프레임 사이에 라인을 쉬게 한다 (n 비트 시간)
    task idle_bits(input integer n);
        begin
            rx = 1;
            #(BIT_NS * n);
        end
    endtask

    // 프레임을 보낸 직후 FIFO 에 쓰는 시간을 조금 준다 (rx_empty 대신)
    task settle;
        begin
            repeat (4) @(negedge clk);
        end
    endtask

    // ---------------- 메인 시나리오 ----------------
    integer i;

    initial begin
        // ===== 1) reset =====
        $display("==== 1) reset ====");
        repeat (5) @(negedge clk);
        rst_n = 1;
        repeat (5) @(negedge clk);
        check(tx === 1'b1, "after reset: tx = 1 (idle)");
        check(!tx_full,    "after reset: TX FIFO not full");

        // ===== 2) 기준: 정상 프레임 =====
        $display("==== 2) reference: good frame ====");
        send_good(8'h3C);
        settle;
        expect_byte(8'h3C);

        // ===== 3) stop bit 가 깨진 프레임도 데이터는 저장된다 =====
        $display("==== 3) bad stop bit: data is still stored ====");
        send_bad_stop(8'h77, 10);               // stop bit 앞 10/16 동안 0
        settle;
        expect_byte(8'h77);

        // ===== 4) 깨진 프레임 뒤의 정상 프레임이 받아진다 =====
        $display("==== 4) good frame after bad stop bit ====");
        send_good(8'h5A);
        settle;
        expect_byte(8'h5A);

        // ===== 5) 깨진 프레임과 정상 프레임이 번갈아 연속으로 와도 순서대로 받는다 =====
        $display("==== 5) bad / good frames back to back ====");
        send_bad_stop(8'h11, 10);
        send_good    (8'h22);
        send_bad_stop(8'h33, 10);
        send_good    (8'h44);
        send_bad_stop(8'h55, 10);
        send_good    (8'h66);
        settle;
        expect_byte(8'h11);
        expect_byte(8'h22);
        expect_byte(8'h33);
        expect_byte(8'h44);
        expect_byte(8'h55);
        expect_byte(8'h66);

        // ===== 6) stop bit 를 더 오래 0 으로 두고(14/16), 뒤에 쉬는 시간을 둔다 =====
        $display("==== 6) longer low stop bit, then idle ====");
        send_bad_stop(8'hA5, 14);
        idle_bits(2);
        send_good(8'h0F);
        settle;
        expect_byte(8'hA5);
        expect_byte(8'h0F);

        // ===== 7) 여러 데이터 값에서도 같다 (0x00 / 0xFF) =====
        $display("==== 7) data patterns with bad stop bit ====");
        send_bad_stop(8'h00, 10);
        send_bad_stop(8'hFF, 10);
        send_good    (8'h81);
        settle;
        expect_byte(8'h00);
        expect_byte(8'hFF);
        expect_byte(8'h81);

        // 읽은 개수가 FIFO 깊이(8)를 넘지 않게 중간중간 비웠으므로 overrun 이 나면 안 된다
        check(!saw_overrun, "no rx_overrun during this test");

        // ===== 결과 =====
        $display("--------------------------------------");
        if (errors == 0) $display("RESULT: PASS");
        else             $display("RESULT: FAIL (errors = %0d)", errors);
        $display("--------------------------------------");
        $finish;
    end

    // 무한 대기 방지용
    initial begin
        #50_000_000;   // 50ms
        $display("ERROR: TIMEOUT");
        $finish;
    end

endmodule
