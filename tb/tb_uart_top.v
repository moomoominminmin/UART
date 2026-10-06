`timescale 1ns / 1ps

// uart_top 테스트벤치 (합성 전/후 공용)
//
// ★ 합성 후(netlist) 시뮬레이션으로 바꾸는 방법
//    아래 "uart_top dut (" 줄에서 모듈 이름만 netlist 의 이름으로 바꾸면 된다.
//    - 이 테스트벤치는 uart_top 의 "포트"만 사용한다. (내부 신호를 직접 읽지 않음)
//    - 파라미터를 바꾸지 않고 uart_top 의 기본값을 그대로 쓴다.
//      (합성된 netlist 는 파라미터가 이미 고정되어 있기 때문)
//    - 아래 PARITY_EN / PARITY_ODD 는 uart_top 의 기본값과 같게 맞춰 둘 것.
//
// 테스트 순서
//   1) 리셋 직후 상태 확인
//   2) 송신 : tx 핀의 파형이 올바른지 확인
//   3) 수신 : rx 핀에 직접 파형을 만들어 넣고 받은 데이터 확인
//   4) 루프백 : tx 를 rx 에 연결해서 보낸 데이터 = 받은 데이터 확인
//   5) framing error : stop bit 가 깨진 프레임을 넣어 보기
//   6) parity error  : 패리티가 틀린 프레임을 넣어 보기 (PARITY_EN=1 일 때만)
//   7) overrun : RX FIFO 가 가득 찬 상태에서 더 받아 보기
//
// 신호 규칙: 입력은 clk 의 하강 에지(negedge)에서만 바꾸고 읽는다.
//            (DUT 는 상승 에지에서 동작하므로 서로 겹치지 않아 값이 안정적이다)
module tb_uart_top;

    // ---------------- 설정 ----------------
    localparam CLK_PERIOD = 20;     // 50MHz -> 20ns
    localparam BIT_NS     = 8680;   // 115200bps 의 1비트 시간 (1e9 / 115200)
    localparam PARITY_EN  = 0;      // uart_top 기본값과 같게 맞출 것
    localparam PARITY_ODD = 0;

    // ---------------- 신호 ----------------
    reg        clk = 0;
    reg        rst_n = 0;

    reg        wr_en = 0;
    reg  [7:0] wr_data = 0;
    wire       tx_full, tx_empty;

    reg        rd_en = 0;
    wire [7:0] rd_data;
    wire       rx_empty;

    wire       rx_overrun, framing_error, parity_error;
    wire       tx;

    reg        rx_ext   = 1;   // 테스트벤치가 rx 핀에 직접 넣는 신호 (쉬는 동안 1)
    reg        loopback = 0;   // 1 이면 tx 를 rx 에 연결 (루프백)
    wire       rx_pin = loopback ? tx : rx_ext;

    // ---------------- 테스트할 모듈 ----------------
    uart_top dut (                      // <-- 합성 후에는 여기 모듈 이름만 바꾼다
        .clk          (clk),
        .rst_n        (rst_n),
        .wr_en        (wr_en),
        .wr_data      (wr_data),
        .tx_full      (tx_full),
        .tx_empty     (tx_empty),
        .rd_en        (rd_en),
        .rd_data      (rd_data),
        .rx_empty     (rx_empty),
        .rx_overrun   (rx_overrun),
        .framing_error(framing_error),
        .parity_error (parity_error),
        .tx           (tx),
        .rx           (rx_pin)
    );

    always #(CLK_PERIOD/2) clk = ~clk;

    // ---------------- 에러 플래그 기록 ----------------
    // rx_overrun 등은 1클럭짜리 펄스라서 놓치기 쉽다. 한 번이라도 1이 되면 기억해 둔다.
    reg saw_overrun = 0, saw_framing = 0, saw_parity = 0;
    always @(posedge clk) begin
        if (rx_overrun)    saw_overrun <= 1;
        if (framing_error) saw_framing <= 1;
        if (parity_error)  saw_parity  <= 1;
    end

    task clear_flags;
        begin
            saw_overrun = 0;
            saw_framing = 0;
            saw_parity  = 0;
        end
    endtask

    // ---------------- 검사 도구 ----------------
    integer errors = 0;

    // cond 가 거짓이면 에러로 센다
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

    // ---------------- 사용자 인터페이스 동작 ----------------

    // TX FIFO 에 1바이트 쓰기 (가득 차 있으면 자리가 날 때까지 기다림)
    task write_byte(input [7:0] d);
        begin
            @(negedge clk);
            while (tx_full) @(negedge clk);
            wr_data = d;
            wr_en   = 1;
            @(negedge clk);
            wr_en   = 0;
        end
    endtask

    // RX FIFO 에서 1바이트 읽기 (데이터가 올 때까지 기다림)
    task read_byte(output [7:0] d);
        begin
            @(negedge clk);
            while (rx_empty) @(negedge clk);
            d     = rd_data;   // 맨 앞 데이터가 이미 rd_data 에 나와 있다
            rd_en = 1;         // 1클럭 동안 rd_en 을 주면 다음 데이터로 넘어간다
            @(negedge clk);
            rd_en = 0;
        end
    endtask

    // 1바이트를 읽어서 기대값과 비교
    task expect_byte(input [7:0] expected);
        reg [7:0] got;
        begin
            read_byte(got);
            if (got === expected) begin
                $display("[%0t] OK    : got 0x%02h", $time, got);
            end else begin
                $display("[%0t] ERROR : got 0x%02h, expected 0x%02h", $time, got, expected);
                errors = errors + 1;
            end
        end
    endtask

    // ---------------- 시리얼 라인 동작 ----------------

    // rx 핀에 UART 프레임을 직접 만들어 넣는다 (외부 장치가 보내는 것처럼)
    //   bad_parity=1 : 패리티 비트를 일부러 틀리게 보냄
    //   bad_stop=1   : stop bit 를 일부러 0 으로 보냄
    task send_serial(input [7:0] d, input bad_parity, input bad_stop);
        integer i;
        reg     p;
        begin
            p = PARITY_ODD ? ~(^d) : (^d);
            if (bad_parity) p = ~p;

            rx_ext = 0;                       // start bit
            #(BIT_NS);
            for (i = 0; i < 8; i = i + 1) begin   // data bit (LSB 먼저)
                rx_ext = d[i];
                #(BIT_NS);
            end
            if (PARITY_EN) begin              // parity bit
                rx_ext = p;
                #(BIT_NS);
            end

            if (bad_stop) begin
                // stop bit 를 0 으로 만들되, 비트 끝까지 0 으로 두면 수신기가
                // 그 0 을 새 start bit 로 착각한다. 그래서 가운데를 지나서
                // 조금만 0 으로 유지하고 나머지는 1 로 돌려놓는다.
                rx_ext = 0;
                #(BIT_NS * 10 / 16);
                rx_ext = 1;
                #(BIT_NS * 6 / 16);
            end else begin
                rx_ext = 1;                   // stop bit
                #(BIT_NS);
            end
        end
    endtask

    // tx 핀을 지켜보며 프레임이 올바른지 검사한다.
    // start bit 의 하강 에지를 기다린 뒤, 각 비트의 가운데에서 값을 읽는다.
    task check_tx_frame(input [7:0] expected);
        integer i;
        reg [7:0] got;
        reg       got_parity, exp_parity;
        begin
            @(negedge tx);
            #(BIT_NS / 2);                    // start bit 가운데
            check(tx === 1'b0, "tx start bit = 0");

            for (i = 0; i < 8; i = i + 1) begin
                #(BIT_NS);
                got[i] = tx;
            end
            check(got === expected, "tx data bits (LSB first)");

            if (PARITY_EN) begin
                #(BIT_NS);
                got_parity = tx;
                exp_parity = PARITY_ODD ? ~(^expected) : (^expected);
                check(got_parity === exp_parity, "tx parity bit");
            end

            #(BIT_NS);
            check(tx === 1'b1, "tx stop bit = 1");
        end
    endtask

    // ---------------- 메인 시나리오 ----------------
    integer   i;
    reg [7:0] tmp;

    initial begin
        // ===== 1) reset =====
        $display("==== 1) reset ====");
        repeat (5) @(negedge clk);
        rst_n = 1;
        repeat (5) @(negedge clk);
        check(tx === 1'b1,   "after reset: tx = 1 (idle)");
        check(tx_empty,      "after reset: TX FIFO empty");
        check(rx_empty,      "after reset: RX FIFO empty");
        check(!tx_full,      "after reset: TX FIFO not full");

        // ===== 2) 송신 =====
        $display("==== 2) TX: check waveform on tx pin ====");
        fork
            write_byte(8'h55);
            check_tx_frame(8'h55);
        join
        fork
            write_byte(8'hA3);
            check_tx_frame(8'hA3);
        join

        // ===== 3) 수신 =====
        $display("==== 3) RX: drive rx pin directly ====");
        send_serial(8'h3C, 0, 0);
        expect_byte(8'h3C);
        send_serial(8'h00, 0, 0);
        expect_byte(8'h00);
        send_serial(8'hFF, 0, 0);
        expect_byte(8'hFF);

        // 연속으로 3바이트를 받은 뒤 한꺼번에 읽기 (FIFO 가 순서대로 보관)
        send_serial(8'h11, 0, 0);
        send_serial(8'h22, 0, 0);
        send_serial(8'h33, 0, 0);
        expect_byte(8'h11);
        expect_byte(8'h22);
        expect_byte(8'h33);
        check(rx_empty, "RX FIFO empty after reading all");

        // ===== 4) 루프백 =====
        $display("==== 4) loopback: tx -> rx ====");
        loopback = 1;
        for (i = 0; i < 5; i = i + 1)
            write_byte(8'h80 + i);
        for (i = 0; i < 5; i = i + 1)
            expect_byte(8'h80 + i);

        // 여기까지는 정상 동작이므로 에러 플래그가 한 번도 뜨면 안 된다
        check(!saw_framing, "no framing_error in normal operation");
        check(!saw_parity,  "no parity_error in normal operation");
        check(!saw_overrun, "no rx_overrun in normal operation");
        loopback = 0;

        // ===== 5) framing error =====
        $display("==== 5) framing error ====");
        clear_flags;
        send_serial(8'h77, 0, 1);               // stop bit 를 깨뜨림
        repeat (10) @(negedge clk);
        check(saw_framing, "bad stop bit -> framing_error");
        read_byte(tmp);                         // 잘못 받은 바이트도 FIFO 에는 들어있음 -> 비워 둔다

        clear_flags;
        send_serial(8'h5A, 0, 0);               // 이어서 정상 프레임이 잘 받아지는지
        expect_byte(8'h5A);
        check(!saw_framing, "next good frame has no framing_error");

        // ===== 6) parity error =====
        if (PARITY_EN) begin
            $display("==== 6) parity error ====");
            clear_flags;
            send_serial(8'h96, 1, 0);           // 패리티 비트를 틀리게
            repeat (10) @(negedge clk);
            check(saw_parity,   "bad parity -> parity_error");
            check(!saw_framing, "no framing_error for a parity-only error");
            read_byte(tmp);
        end else begin
            $display("==== 6) parity error: skipped (PARITY_EN=0) ====");
        end

        // ===== 7) overrun =====
        // RX FIFO(16개)를 비우지 않고 20바이트를 루프백으로 보낸다.
        $display("==== 7) overrun ====");
        clear_flags;
        loopback = 1;
        for (i = 0; i < 20; i = i + 1)
            write_byte(i);
        wait (tx_empty);
        #(BIT_NS * 14);                         // 마지막 프레임이 끝날 때까지 기다림
        check(saw_overrun, "RX FIFO full + new byte -> rx_overrun");

        // FIFO 에는 먼저 온 16개(0~15)만 남아 있어야 한다
        for (i = 0; i < 16; i = i + 1)
            expect_byte(i);
        check(rx_empty, "RX FIFO empty after reading 16 bytes");
        loopback = 0;

        // ===== 결과 =====
        $display("--------------------------------------");
        if (errors == 0) $display("RESULT: PASS");
        else             $display("RESULT: FAIL (errors = %0d)", errors);
        $display("--------------------------------------");
        $finish;
    end

    // 무한 대기 방지용 (시뮬레이션이 멈춰 있으면 실패로 끝냄)
    initial begin
        #50_000_000;   // 50ms
        $display("ERROR: TIMEOUT");
        $finish;
    end

endmodule
