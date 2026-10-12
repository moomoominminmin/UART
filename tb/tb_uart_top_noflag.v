`timescale 1ns / 1ps

// uart_top 테스트벤치 (rx_empty / tx_empty / parity_error 포트를 쓰지 않는 버전)
//
// tb_uart_top.v 와 같은 시나리오지만, 위 3개 포트는 DUT 에 연결하지 않고
// 테스트벤치 안에서도 전혀 읽지 않는다. 대신 아래 방법으로 대체한다.
//   - tx_empty      : 프레임 시간만큼 기다린다 (wait_frames)
//   - rx_empty      : 프레임을 보낸 뒤 시간이 지나면 FIFO 에 들어 있다고 보고 읽는다
//   - parity_error  : 직접 확인할 수 없으므로 parity error 검사는 하지 않는다
//                     (틀린 패리티 프레임을 넣어도 다음 정상 프레임이 잘 받아지는지만 본다)
//
// 합성 후(netlist) 시뮬레이션: "uart_top dut (" 의 모듈 이름만 바꾸면 된다.
// PARITY_EN / PARITY_ODD 는 uart_top 의 기본값과 같게 맞춰 둘 것.
//
// 신호 규칙: 입력은 clk 의 하강 에지(negedge)에서만 바꾸고 읽는다.
module tb_uart_top_noflag;

    // ---------------- 설정 ----------------
    localparam CLK_PERIOD = 20;     // 50MHz -> 20ns
    localparam BIT_NS     = 8680;   // 115200bps 의 1비트 시간
    localparam PARITY_EN  = 0;      // 패리티를 뺀 DUT 에 맞춤 (패리티 있는 DUT 면 1)
    localparam PARITY_ODD = 0;
    localparam FRAME_BITS = 10 + PARITY_EN;   // start + data 8 + parity + stop
    localparam FRAME_NS   = BIT_NS * FRAME_BITS;

    // ---------------- 신호 ----------------
    reg        clk = 0;
    reg        rst_n = 0;

    reg        wr_en = 0;
    reg  [7:0] wr_data = 0;
    wire       tx_full;

    reg        rd_en = 0;
    wire [7:0] rd_data;

    wire       rx_overrun, framing_error;
    wire       tx;

    reg        rx_ext   = 1;
    reg        loopback = 0;
    wire       rx_pin = loopback ? tx : rx_ext;

    // ---------------- 테스트할 모듈 ----------------
    // tx_empty, rx_empty, parity_error 포트는 DUT 에 없다고 보고 아예 쓰지 않는다.
    uart_top dut (                      // <-- 합성 후에는 여기 모듈 이름만 바꾼다
        .clk          (clk),
        .rst_n        (rst_n),
        .wr_en        (wr_en),
        .wr_data      (wr_data),
        .tx_full      (tx_full),
        .rd_en        (rd_en),
        .rd_data      (rd_data),
        .rx_overrun   (rx_overrun),
        .framing_error(framing_error),
        .tx           (tx),
        .rx           (rx_pin)
    );
    
    always #(CLK_PERIOD/2) clk = ~clk;

    // ---------------- 에러 플래그 기록 (1클럭 펄스를 기억) ----------------
    reg saw_overrun = 0, saw_framing = 0;
    always @(posedge clk) begin
        if (rx_overrun)    saw_overrun <= 1;
        if (framing_error) saw_framing <= 1;
    end

    task clear_flags;
        begin
            saw_overrun = 0;
            saw_framing = 0;
        end
    endtask

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

    // ---------------- 사용자 인터페이스 동작 ----------------

    // n 프레임 시간 + 약간의 여유만큼 기다린다 (tx_empty / rx_empty 대신)
    task wait_frames(input integer n);
        begin
            #(FRAME_NS * n + BIT_NS * 2);
        end
    endtask

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

    // RX FIFO 에서 1바이트 읽기. 데이터가 이미 들어 있다고 보고 바로 읽는다.
    task read_byte(output [7:0] d);
        begin
            @(negedge clk);
            d     = rd_data;
            rd_en = 1;
            @(negedge clk);
            rd_en = 0;
        end
    endtask

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

    // rx 핀에 UART 프레임을 직접 만들어 넣는다
    task send_serial(input [7:0] d, input bad_parity, input bad_stop);
        integer i;
        reg     p;
        begin
            p = PARITY_ODD ? ~(^d) : (^d);
            if (bad_parity) p = ~p;

            rx_ext = 0;                       // start bit
            #(BIT_NS);
            for (i = 0; i < 8; i = i + 1) begin
                rx_ext = d[i];
                #(BIT_NS);
            end
            if (PARITY_EN) begin
                rx_ext = p;
                #(BIT_NS);
            end

            if (bad_stop) begin
                // 0 을 끝까지 유지하면 새 start bit 로 오인되므로 일부만 0 으로 둔다
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

    // tx 핀의 프레임이 올바른지 검사 (start bit 하강 에지부터 각 비트 가운데에서 읽음)
    task check_tx_frame(input [7:0] expected);
        integer i;
        reg [7:0] got;
        reg       got_parity, exp_parity;
        begin
            @(negedge tx);
            #(BIT_NS / 2);
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
        check(tx === 1'b1, "after reset: tx = 1 (idle)");
        check(!tx_full,    "after reset: TX FIFO not full");

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
        repeat (4) @(negedge clk);
        expect_byte(8'h3C);
        send_serial(8'h00, 0, 0);
        repeat (4) @(negedge clk);
        expect_byte(8'h00);
        send_serial(8'hFF, 0, 0);
        repeat (4) @(negedge clk);
        expect_byte(8'hFF);

        // 연속 3바이트를 받은 뒤 한꺼번에 읽기
        send_serial(8'h11, 0, 0);
        send_serial(8'h22, 0, 0);
        send_serial(8'h33, 0, 0);
        repeat (4) @(negedge clk);
        expect_byte(8'h11);
        expect_byte(8'h22);
        expect_byte(8'h33);

        // ===== 4) 루프백 =====
        $display("==== 4) loopback: tx -> rx ====");
        loopback = 1;
        for (i = 0; i < 5; i = i + 1)
            write_byte(8'h80 + i);
        wait_frames(5);                         // 5바이트가 모두 돌아올 때까지
        for (i = 0; i < 5; i = i + 1)
            expect_byte(8'h80 + i);

        check(!saw_framing, "no framing_error in normal operation");
        check(!saw_overrun, "no rx_overrun in normal operation");
        loopback = 0;

        // ===== 5) framing error =====
        $display("==== 5) framing error ====");
        clear_flags;
        send_serial(8'h77, 0, 1);               // stop bit 를 깨뜨림
        repeat (10) @(negedge clk);
        check(saw_framing, "bad stop bit -> framing_error");
        read_byte(tmp);                         // 잘못 받은 바이트도 FIFO 에 들어 있음 -> 비움

        clear_flags;
        send_serial(8'h5A, 0, 0);
        repeat (4) @(negedge clk);
        expect_byte(8'h5A);
        check(!saw_framing, "next good frame has no framing_error");

        // ===== 6) 틀린 패리티 프레임 (parity_error 포트 없이 확인 가능한 것만) =====
        if (PARITY_EN) begin
            $display("==== 6) bad parity frame (parity_error not observed) ====");
            clear_flags;
            send_serial(8'h96, 1, 0);
            repeat (10) @(negedge clk);
            check(!saw_framing, "no framing_error for a parity-only error");
            read_byte(tmp);                     // FIFO 에 들어 있으면 비워 둔다

            send_serial(8'hC3, 0, 0);           // 이어서 정상 프레임이 받아지는지
            repeat (4) @(negedge clk);
            expect_byte(8'hC3);
        end else begin
            $display("==== 6) bad parity: skipped (PARITY_EN=0) ====");
        end

        // ===== 7) overrun =====
        // RX FIFO(16개)를 비우지 않고 20바이트를 루프백으로 보낸다.
        $display("==== 7) overrun ====");
        clear_flags;
        loopback = 1;
        for (i = 0; i < 20; i = i + 1)
            write_byte(i);
        wait_frames(17);                        // TX FIFO 에 남은 바이트가 모두 돌아올 때까지 (tx_empty 대신)
        check(saw_overrun, "RX FIFO full + new byte -> rx_overrun");

        // FIFO 에는 먼저 온 16개(0~15)만 남아 있어야 한다
        for (i = 0; i < 16; i = i + 1)
            expect_byte(i);
        loopback = 0;

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
