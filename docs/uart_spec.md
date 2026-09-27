# UART 설계 사양서 (Design Specification)

## 1. 개요

FIFO 버퍼를 내장한 **8N1 UART** (8 data bits, No parity, 1 stop bit) RTL 설계입니다.
사용하는 쪽 모듈은 바이트 단위의 `tx_start` / `rx_done` 타이밍을 신경 쓸 필요 없이,
FIFO 스타일의 `wr_en` / `rd_en` / `full` / `empty` 핸드셰이크만으로 송수신할 수 있습니다.

| 항목 | 사양 |
|---|---|
| 프레임 형식 | 8N1 (start 1 + data 8 + stop 1 = 10 bit), LSB first |
| 라인 idle 레벨 | High (`1`) |
| 기본 클럭 / 보레이트 | 50 MHz / 115200 bps (파라미터로 변경 가능) |
| RX 샘플링 | 16x 오버샘플링, 비트 중앙 1회 샘플 |
| TX/RX 버퍼 | 각각 16-byte 동기 FIFO (파라미터로 변경 가능) |
| 클럭 도메인 | 단일 클럭 (`clk`) |
| 리셋 | 비동기, Active-Low (`rst_n`) |
| 오류 검출 | Framing error, RX FIFO overrun |
| 미지원 | Parity, 2 stop bit, 흐름 제어(RTS/CTS), 런타임 보레이트 변경 |

## 2. 파일 구성

| 파일 | 설명 |
|---|---|
| [rtl/uart_top.v](../rtl/uart_top.v) | 최상위 모듈. baud_gen + TX/RX 코어 + FIFO 2개 연결 |
| [rtl/baud_gen.v](../rtl/baud_gen.v) | 보레이트 틱 생성기 (`rx_tick` 16x, `tx_tick` 1x) |
| [rtl/uart_tx.v](../rtl/uart_tx.v) | 송신기 FSM |
| [rtl/uart_rx.v](../rtl/uart_rx.v) | 수신기 FSM (2-FF 동기화기 포함) |
| [rtl/sync_fifo.v](../rtl/sync_fifo.v) | 범용 동기 FIFO |
| [tb/tb_baud_gen.v](../tb/tb_baud_gen.v) | baud_gen 단위 테스트 |
| [tb/tb_uart_tx.v](../tb/tb_uart_tx.v) | uart_tx 단독(단위) 테스트. tick을 자체 생성해 baud_gen 없이 검증 |
| [tb/tb_uart_rx.v](../tb/tb_uart_rx.v) | uart_rx 단독(단위) 테스트. tick/rx 라인을 자체 생성해 baud_gen/uart_tx 없이 검증 |
| [tb/tb_uart_loopback.v](../tb/tb_uart_loopback.v) | uart_tx → uart_rx 직접 루프백 테스트 |
| [tb/tb_uart_top.v](../tb/tb_uart_top.v) | uart_top 통합 테스트 (FIFO 포함 루프백, backpressure) |

## 3. 블록 다이어그램

```
                            uart_top
 ┌──────────────────────────────────────────────────────────────────┐
 │                  ┌────────────┐                                  │
 │                  │  baud_gen  │── tx_tick (1x) ──┐               │
 │                  │            │── rx_tick (16x) ─┼───────┐       │
 │                  └────────────┘                  │       │       │
 │                                                  ▼       │       │
 │ wr_en   ──►┌───────────┐ rd_data  ┌──────────┐           │       │
 │ wr_data ──►│  TX FIFO  │─────────►│ uart_tx  │───────────┼──────►│── tx
 │ tx_full ◄──│ (16 x 8b) │◄─pop_tx──│          │           │       │
 │ tx_empty◄──└───────────┘          └──────────┘           ▼       │
 │                                                    ┌──────────┐  │
 │ rd_en   ──►┌───────────┐  wr_en = rx_done          │ uart_rx  │◄─│── rx
 │ rd_data ◄──│  RX FIFO  │◄──────────────────────────│ (2FF sync│  │
 │ rx_empty◄──│ (16 x 8b) │  wr_data = rx_data        │  + FSM)  │  │
 │            └───────────┘                           └──────────┘  │
 │ rx_overrun    ◄── rx_done && rx_fifo_full                        │
 │ framing_error ◄── uart_rx.framing_error                          │
 └──────────────────────────────────────────────────────────────────┘
```

- **TX 경로**: `wr_data` → TX FIFO → `uart_tx` → `tx`
  `pop_tx = !tx_busy && !tx_fifo_empty` — 송신기가 비어 있고 FIFO에 데이터가 있으면 즉시 꺼내서 전송 시작.
- **RX 경로**: `rx` → `uart_rx` → RX FIFO → `rd_data`
  한 바이트 수신이 끝나면(`rx_done`) 자동으로 RX FIFO에 push.

## 4. 최상위 인터페이스 (`uart_top`)

### 4.1 파라미터

| 파라미터 | 기본값 | 설명 |
|---|---|---|
| `CLK_FREQ` | `50_000_000` | 입력 클럭 주파수 [Hz] |
| `BAUD_RATE` | `115200` | 목표 보레이트 [bps] |
| `FIFO_DEPTH` | `16` | TX/RX FIFO 깊이 [byte]. **2의 거듭제곱이어야 함** (7.3 참고) |

### 4.2 포트

| 포트 | 방향 | 폭 | 설명 |
|---|---|---|---|
| `clk` | in | 1 | 시스템 클럭 |
| `rst_n` | in | 1 | 비동기 리셋, Active-Low |
| `wr_en` | in | 1 | 1이면 해당 클럭에 `wr_data`를 TX FIFO에 push. `tx_full`=1이면 무시됨 |
| `wr_data` | in | 8 | 송신할 바이트 |
| `tx_full` | out | 1 | TX FIFO 가득 참 — 쓰기 전 반드시 확인 |
| `tx_empty` | out | 1 | TX FIFO 비어 있음 (주의: 마지막 바이트가 아직 라인에서 전송 중일 수 있음) |
| `rd_en` | in | 1 | 1이면 해당 클럭에 RX FIFO head를 pop. `rx_empty`=1이면 무시됨 |
| `rd_data` | out | 8 | RX FIFO head 값 (show-ahead). `rx_empty`=0일 때만 유효 |
| `rx_empty` | out | 1 | RX FIFO 비어 있음 |
| `rx_overrun` | out | 1 | **1클럭 펄스**. RX FIFO가 가득 찬 상태에서 새 바이트 수신 → 새 바이트는 버려짐 |
| `framing_error` | out | 1 | **1클럭 펄스**. 방금 수신한 바이트의 stop bit가 `0`이었음 |
| `tx` | out | 1 | 시리얼 출력 (idle = 1) |
| `rx` | in | 1 | 시리얼 입력 (idle = 1), `clk`와 비동기 |

### 4.3 사용 방법 (핸드셰이크 규칙)

**송신**
```
if (!tx_full) begin wr_en <= 1; wr_data <= byte; end
```
- `wr_en`을 1클럭 동안 올리면 1바이트가 push 됨. 연속 클럭에 연속 push 가능.
- `tx_full`일 때의 쓰기는 **조용히 버려짐** (TX 쪽 overflow 플래그 없음).

**수신**
```
if (!rx_empty) begin use(rd_data); rd_en <= 1; end
```
- RX FIFO는 **show-ahead(FWFT)** 방식: `rx_empty`=0이면 `rd_data`에 이미 head 값이 나와 있음.
  `rd_en`을 1클럭 올리면 다음 클럭에 다음 바이트로 넘어감.
- 즉 `rd_en`을 올리는 **그 클럭에** `rd_data`를 읽어야 함 (다음 클럭에는 이미 다음 값).

## 5. 모듈별 상세

### 5.1 `baud_gen` — 보레이트 틱 생성기

```
RX_DIV  = floor(CLK_FREQ / (BAUD_RATE * OVERSAMPLE))
rx_tick = (rx_cnt == RX_DIV-1)                  // RX_DIV 클럭마다 1클럭 펄스
tx_tick = rx_tick && (os_cnt == OVERSAMPLE-1)   // rx_tick 16개마다 1클럭 펄스
```

- `rx_tick`이 기본 틱이며, `tx_tick`은 `rx_tick`을 16개 세서 만들어짐.
  따라서 `tx_tick` 1주기 안에는 항상 정확히 16개의 `rx_tick`이 들어감.
  (TX/RX 분주기를 따로 두면 `CLK_FREQ/BAUD_RATE`와 `RX_DIV*16`의 절삭 오차가 달라 서로 어긋나므로 이 구조를 채택.)
- 실제 보레이트 = `CLK_FREQ / (RX_DIV * 16)`. 분주비는 **내림(floor)** 으로 계산되므로 실제 보레이트는 항상 목표보다 약간 높음.

**50 MHz 기준 보레이트 오차**

| 목표 [bps] | RX_DIV | 실제 [bps] | 오차 | 사용 가능 여부 (±2% 기준) |
|---|---|---|---|---|
| 9600 | 325 | 9615.4 | +0.16% | O |
| 19200 | 162 | 19290.1 | +0.47% | O |
| 38400 | 81 | 38580.2 | +0.47% | O |
| 57600 | 54 | 57870.4 | +0.47% | O |
| **115200** | **27** | **115740.7** | **+0.47%** | **O (기본값)** |
| 230400 | 13 | 240384.6 | +4.34% | X |
| 460800 | 6 | 520833.3 | +13.0% | X |

> 상대 장치와의 보레이트 오차 합이 대략 ±2% 이내여야 안정적으로 통신됩니다.
> 높은 보레이트가 필요하면 `CLK_FREQ`를 올리거나 분주 방식을 바꿔야 합니다.

### 5.2 `uart_tx` — 송신기

FSM: `IDLE → START → DATA(×8) → STOP → IDLE`

| 상태 | 동작 |
|---|---|
| `IDLE` | `tx=1`. `tx_start`가 오면 `tx_data`를 `data_reg`에 래치, `tx_busy=1`, `START`로 |
| `START` | 다음 `tx_tick`에서 `tx=0` (start bit) 출력, `DATA`로 |
| `DATA` | `tx_tick`마다 `data_reg[bit_idx]` 출력 (bit0 → bit7, LSB first). bit7 후 `STOP`으로 |
| `STOP` | `tx_tick`에서 `tx=1` (stop bit) 출력, `tx_busy=0`, `tx_done` 1클럭 펄스, `IDLE`로 |

- stop bit는 `IDLE`로 돌아간 뒤에도 `tx=1`이 유지되고, 다음 프레임의 start bit는 다음 `tx_tick`에서야 나가므로
  **stop bit 길이는 항상 정확히 1비트**. 연속 전송 시 프레임 간격 없이 10비트/바이트로 전송됨.
- `tx_start` → start bit 출력까지 지연: 다음 `tx_tick`까지 **0 ~ 1 비트 시간**.
- 최대 처리량: `BAUD_RATE / 10` byte/s (115200 bps → 11,520 byte/s).

```
tx_tick  ─┐_______________┌┐___________┌┐___ ... ___┌┐___________┌┐____
tx       ───────────────┐  ┌──────────┐              ┌──────────────────
(idle=1)                └──┘ D0 ... D7└── ... ───────┘ STOP(1) ... idle
                         START
```

### 5.3 `uart_rx` — 수신기

**입력 동기화**: `rx`는 `clk`와 무관한 비동기 입력이므로, setup/hold 위반으로 인한 **메타스테이블(metastability)** 위험이 있음.
`rx_sync0`(비동기 신호를 직접 받아 메타스테이블에 빠질 수 있는 희생 플롭) → `rx_sync1`(한 클럭 더 기다려 값이 안정된 뒤에만 사용)의
2-FF 동기화기를 거쳐, FSM은 반드시 `rx_sync1`만 참조함. 리셋 값은 `1`(idle).

FSM: `IDLE → START → DATA(×8) → STOP → IDLE`

| 상태 | 동작 |
|---|---|
| `IDLE` | `rx_sync1==0` (falling edge) 감지 시 `START`로 |
| `START` | `rx_tick` 8개(`os_cnt`가 `MID`=7에 도달) 후 = start bit 중앙에서 재확인. 여전히 `0`이면 `DATA`로, `1`이면 글리치로 판단하고 `IDLE`로 복귀 |
| `DATA` | `rx_tick` 16개마다(= 다음 비트 중앙) `rx_sync1`을 `data_reg[bit_idx]`에 저장. bit7 후 `STOP`으로 |
| `STOP` | 16틱 후(stop bit 중앙) `rx_data` 갱신, `rx_done` 1클럭 펄스, stop bit가 `0`이면 `framing_error` 동시 펄스. `IDLE`로 |

**샘플링 타이밍** (start bit falling edge 기준, 1비트 = 16 rx_tick)

```
rx     ‾‾‾‾\__________/‾‾‾‾‾‾‾‾‾‾\__________/ ... ‾‾‾‾‾‾‾‾‾‾‾‾
           |  START   |   D0     |   D1     |     |  STOP    |
sample           ▲          ▲          ▲                 ▲
              ~8 tick   +16 tick   +16 tick   ...    rx_done
             (확인)     (D0 샘플)  (D1 샘플)          (~9.5 bit)
```

- 샘플 지점은 각 비트의 약 7/16 ~ 8/16 지점(≈ 중앙). `rx_tick` 위상과 동기화기 지연(2클럭)에 따라 최대 1/16 비트의 흔들림이 있음.
- 비트당 **1회 샘플**(다수결 투표 없음). 반 비트 미만의 start bit 글리치는 `START` 상태에서 걸러짐.
- `rx_done`은 stop bit **중앙**에서 발생하므로 프레임이 라인에서 완전히 끝나기 약 반 비트 전에 데이터가 나옴.
  이후 `IDLE`은 stop bit의 `1` 동안 대기하다 다음 falling edge를 기다리므로 연속 수신에 문제 없음.

**Framing error 처리**: `framing_error`가 발생해도 `rx_done`은 함께 올라가므로 **해당 바이트는 RX FIFO에 그대로 저장됨**.
사용자 로직이 오류 바이트를 걸러내려면 `framing_error` 펄스를 별도로 기록해야 합니다.

### 5.4 `sync_fifo` — 동기 FIFO

| 항목 | 내용 |
|---|---|
| 구조 | `DEPTH` x `DATA_WIDTH` 레지스터 배열, `wr_ptr` / `rd_ptr` / `count` |
| full / empty | 점유 카운터 `count` (0 ~ DEPTH) 비교: `full = (count == DEPTH)`, `empty = (count == 0)` |
| 읽기 방식 | 조합 읽기 `rd_data = mem[rd_ptr]` (show-ahead / FWFT) |
| 동시 read/write | 둘 다 유효하면 `count` 변화 없음, 포인터는 각각 증가 |
| 보호 | `full`일 때 write 무시, `empty`일 때 read 무시 |
| 메모리 리셋 | 없음 (`mem`은 리셋되지 않음 → 비어 있을 때 `rd_data`는 X/이전 값) |

## 6. 타이밍 요약

| 항목 | 값 (50 MHz, 115200 bps 기준) |
|---|---|
| 1 비트 시간 | `RX_DIV * 16` = 432 clk ≈ 8.64 µs |
| 1 프레임 (10 bit) | 4320 clk ≈ 86.4 µs |
| `wr_en` → `tx` start bit | 약 1~2 clk + 0~1 비트 (다음 `tx_tick` 대기) |
| `rx` start edge → `rx_empty`=0 | 약 9.5 비트 + 동기화/FIFO 지연 수 clk |
| TX FIFO 16바이트 소진 시간 | 약 1.38 ms |

## 7. 설계 제약 및 주의사항

1. **`RX_DIV ≥ 2` 필요**: `CLK_FREQ / (BAUD_RATE*16) < 2`이면 `$clog2(RX_DIV)`가 0이 되어 카운터 폭이 0이 됨.
   즉 `CLK_FREQ ≥ 32 × BAUD_RATE`여야 함. 오차를 고려하면 실제로는 훨씬 여유 있게 잡아야 함 (5.1 표 참고).
2. **`tx_empty` ≠ 송신 완료**: TX FIFO가 비어도 `uart_tx`는 마지막 바이트를 전송 중일 수 있음.
   `tx_busy`는 top 포트로 나와 있지 않으므로, "라인까지 완전히 전송 완료"가 필요하면 포트 추가가 필요.
3. **`FIFO_DEPTH`는 2의 거듭제곱**: 포인터가 `$clog2(DEPTH)` 비트의 자연 오버플로로 wrap-around 하므로,
   2의 거듭제곱이 아니면 포인터가 배열 범위를 벗어남.
4. **리셋**: `rst_n`은 비동기 assert / 비동기 deassert. 리셋 해제 동기화기는 포함되어 있지 않으므로,
   상위에서 동기화된 리셋을 넣어 주는 것을 권장.
5. **TX 쪽 overflow 미검출**: `tx_full`일 때의 `wr_en`은 플래그 없이 버려짐.
6. **상태 플래그는 1클럭 펄스**: `rx_overrun`, `framing_error`는 래치되지 않으므로 필요하면 상위에서 sticky 레지스터로 잡아야 함.

## 8. 검증

### 8.1 시뮬레이션 실행 (ModelSim)

```sh
cd sim
vlib work
vlog ../rtl/*.v ../tb/*.v
vsim -c -do "run -all; quit -f" work.tb_baud_gen
vsim -c -do "run -all; quit -f" work.tb_uart_tx
vsim -c -do "run -all; quit -f" work.tb_uart_rx
vsim -c -do "run -all; quit -f" work.tb_uart_loopback
vsim -c -do "run -all; quit -f" work.tb_uart_top
```

테스트벤치는 빠른 시뮬레이션을 위해 `CLK_FREQ = 1 MHz`, `BAUD_RATE = 9600`을 사용합니다
(`RX_DIV` = 6, 실제 약 10417 bps. TX와 RX가 같은 baud_gen을 공유하므로 루프백에는 영향 없음).

### 8.2 테스트 항목 및 결과

ModelSim ALTERA STARTER EDITION 10.1d (Quartus 13.0sp1)에서 현재 RTL로 실행한 결과입니다.

| 테스트벤치 | 검증 내용 | 결과 |
|---|---|---|
| `tb_baud_gen` | `rx_tick` 주기 = `RX_DIV`, `tx_tick` 주기 = `RX_DIV*16`, `tx_tick` 1주기당 `rx_tick` 16개 | PASS |
| `tb_uart_tx` | `uart_tx` 단독. idle=1, start bit=0, data 8bit(LSB first) 순서/값, stop bit=1, `tx_busy`/`tx_done` 타이밍, 백투백(연속) 전송 | PASS (7/7 byte) |
| `tb_uart_rx` | `uart_rx` 단독. 정상 프레임 5종 수신, 고의로 stop bit를 깨뜨린 `framing_error` 발생 케이스, start bit 미만 글리치 거부, 글리치 이후 정상 프레임 복구 | PASS (7/7 frame) |
| `tb_uart_loopback` | `uart_tx` → `uart_rx` 직결, 0x55 / 0xA5 / 0x00 / 0xFF / 0x3C 송수신 일치, framing error 없음 | PASS (5/5) |
| `tb_uart_top` | ① FIFO 포함 루프백 4바이트 순서/값 일치 ② 연속 write 시 `tx_full` assert 및 수락된 바이트 전부 순서대로 수신 ③ 전 구간 framing error 없음 | PASS (errors=0) |

`tb_uart_rx`의 `framing_error` 테스트를 만들면서 발견한 점: `uart_rx`의 `STOP` 상태는 stop bit의 **끝이 아니라 중앙**에서 샘플링하고 곧바로 `IDLE`로 복귀한다 (5.3 참고).
따라서 테스트벤치가 "깨진 stop bit"를 재현하려고 stop bit 구간 전체(16틱)를 계속 `0`으로 유지하면, `IDLE`로 돌아간 직후에도 라인이 여전히 낮은 상태라서
그 나머지 절반을 새로운 start bit로 오인해 버리는 "phantom frame"이 발생한다 (DUT 버그 아님, 테스트 자극 자체가 실제로는 벌어지지 않을 파형이었음).
그래서 `send_frame`의 bad-stop 경로는 stop bit를 **샘플링 지점을 살짝 지날 만큼만** `0`으로 유지하고, 같은 비트 구간의 나머지는 다시 `1`로 돌려놓도록 작성했다.

### 8.3 아직 검증되지 않은 항목

- `rx_overrun` 발생 (tb_uart_top 헤더 주석에는 있으나 실제 테스트는 미구현)
- TX/RX 보레이트가 서로 다른 경우(오차 허용 범위) 수신
- 프레임 도중 리셋
- 기본 파라미터(50 MHz / 115200)에서의 시뮬레이션
- 연속된 framing error(stop bit 위반 프레임 바로 뒤에 또 다른 프레임)가 이어지는 경우
