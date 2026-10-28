# UART 설계 사양서 (Design Specification)

## 1. 개요

**8N1 UART** (8 data bits, No parity, 1 stop bit)를 가장 단순한 형태로 만든 RTL 설계입니다.
FIFO와 별도의 보레이트 생성기 없이, 송신기와 수신기가 각자 시스템 클럭을 세어 비트 타이밍을 만듭니다.

| 항목 | 사양 |
|---|---|
| 프레임 형식 | 8N1 (start 1 + data 8 + stop 1 = 10 bit), LSB first |
| 라인 idle 레벨 | High (`1`) |
| 기본 클럭 / 보레이트 | 50 MHz / 115200 bps (파라미터로 변경 가능) |
| 비트 타이밍 | `CLKS_PER_BIT = CLK_FREQ / BAUD_RATE` 클럭 (정수 나눗셈, 내림) |
| RX 샘플링 | start 하강 엣지부터 카운터를 세어 비트 중앙에서 1회 샘플 |
| 버퍼 | 없음 (TX 1바이트 래치, RX 1바이트 출력 레지스터) |
| 클럭 도메인 | 단일 클럭 (`clk`) |
| 리셋 | 비동기, Active-Low (`rst_n`) |
| 오류 검출 | 없음 (framing / parity / overrun 검출하지 않음) |
| 미지원 | 패리티, 2 stop bit, 흐름 제어(RTS/CTS), 런타임 보레이트 변경 |

## 2. 파일 구성

| 파일 | 설명 |
|---|---|
| [rtl/uart_top.v](../rtl/uart_top.v) | 최상위 모듈. `uart_tx`와 `uart_rx`를 연결만 함 |
| [rtl/uart_tx.v](../rtl/uart_tx.v) | 송신기 (11비트 시프트 레지스터 + 비트 카운터) |
| [rtl/uart_rx.v](../rtl/uart_rx.v) | 수신기 FSM (2-FF 동기화기, 비트 카운터, 마커 시프트 레지스터) |
| [tb/tb_uart_top.v](../tb/tb_uart_top.v) | loopback 테스트벤치 |

## 3. 블록 다이어그램

```
                 uart_top
 ┌──────────────────────────────────────┐
 │ tx_start ──►┌──────────┐              │
 │ tx_data  ──►│ uart_tx  │──────────────┼──► tx
 │ tx_busy  ◄──│          │              │
 │             └──────────┘              │
 │                                       │
 │ rx_data  ◄──┌──────────┐              │
 │ rx_done  ◄──│ uart_rx  │◄─────────────┼─── rx
 │             │(2FF sync │              │
 │             │  + FSM)  │              │
 │             └──────────┘              │
 └──────────────────────────────────────┘
```

TX 경로와 RX 경로는 서로 독립적입니다. 두 모듈 모두 시스템 `clk`를 직접 사용합니다.

## 4. 최상위 인터페이스 (`uart_top`)

### 4.1 파라미터

| 파라미터 | 기본값 | 설명 |
|---|---|---|
| `CLK_FREQ` | `50_000_000` | 입력 클럭 주파수 [Hz] |
| `BAUD_RATE` | `115200` | 목표 보레이트 [bps] |

`uart_tx`, `uart_rx`도 같은 두 파라미터를 가지며, `uart_top`이 그대로 전달합니다.

### 4.2 포트

| 포트 | 방향 | 폭 | 설명 |
|---|---|---|---|
| `clk` | in | 1 | 시스템 클럭 |
| `rst_n` | in | 1 | 비동기 리셋, Active-Low |
| `tx_start` | in | 1 | **1클럭 펄스**. `tx_data`를 받아 전송 시작. `tx_busy`=1일 때는 사용 금지 (무시되지 않고 동작이 정의되지 않음) |
| `tx_data` | in | 8 | 송신할 바이트. `tx_start`가 1인 클럭에 샘플됨 |
| `tx_busy` | out | 1 | 전송 중이면 1 (start bit 시작부터 stop bit 끝까지) |
| `rx_data` | out | 8 | 수신한 바이트. **`rx_done`이 1인 클럭에만 유효** |
| `rx_done` | out | 1 | **1클럭 펄스**. 1바이트 수신 완료 |
| `tx` | out | 1 | 시리얼 출력 (idle = 1) |
| `rx` | in | 1 | 시리얼 입력 (idle = 1), `clk`와 비동기 |

### 4.3 사용 방법

**송신**
```
if (!tx_busy) begin tx_start <= 1; tx_data <= byte; end   // 1클럭 후 tx_start <= 0
```
- `tx_busy`가 0일 때만 `tx_start`를 올립니다. 버퍼가 없으므로, 연속 전송하려면 `tx_busy`가 내려가길 기다린 뒤 다음 바이트를 넣어야 합니다.
- `tx_start`를 올린 다음 클럭에 `tx_busy`가 1이 됩니다.

**수신**
```
if (rx_done) use(rx_data);
```
- `rx_done`은 1클럭만 뜨고 `rx_data`는 다음 프레임 수신이 시작되면 덮어써지므로, `rx_done`인 클럭에 바로 받아 가야 합니다.
- 받아 가지 못해도 에러 표시는 없습니다 (overrun 개념 없음).

## 5. 모듈별 상세

### 5.1 비트 타이밍

```
CLKS_PER_BIT = CLK_FREQ / BAUD_RATE        (정수 나눗셈, 내림)
```

실제 보레이트는 `CLK_FREQ / CLKS_PER_BIT`이며, 내림 때문에 목표보다 약간 높습니다.

**50 MHz 기준 보레이트 오차**

| 목표 [bps] | CLKS_PER_BIT | 실제 [bps] | 오차 | 사용 가능 여부 (±2% 기준) |
|---|---|---|---|---|
| 9600 | 5208 | 9600.6 | +0.006% | O |
| 19200 | 2604 | 19201.2 | +0.006% | O |
| 38400 | 1302 | 38402.5 | +0.006% | O |
| 57600 | 868 | 57603.7 | +0.006% | O |
| **115200** | **434** | **115207.4** | **+0.006%** | **O (기본값)** |
| 230400 | 217 | 230414.7 | +0.006% | O |
| 460800 | 108 | 462963.0 | +0.47% | O |
| 921600 | 54 | 925925.9 | +0.47% | O |

> 상대 장치와의 보레이트 오차 합이 대략 ±2% 이내여야 안정적으로 통신됩니다.
> `CLKS_PER_BIT`가 작을수록 정수 절삭 오차가 커지므로, 높은 보레이트에서는 `CLK_FREQ / BAUD_RATE`가 정수에 가까운지 확인해야 합니다.

### 5.2 `uart_tx` — 송신기

DFF 수를 줄이기 위해 FSM, 비트 번호, `tx`/`tx_busy` 레지스터 없이 **11비트 시프트 레지스터 `shreg`** 하나로 프레임을 표현합니다.

```
shreg   = { 마커(1), ~stop(0), ~data[7:0], ~start(1) }   (마커를 뺀 프레임은 반전해서 저장)
tx      = ~shreg[0]
tx_busy = |shreg
```

내부 카운터 `cnt`가 `0 ~ CLKS_PER_BIT-1`을 세고, `CLKS_PER_BIT-1`에 도달하면(`bit_done`) 다음 비트로 넘어갑니다.

| 조건 | 동작 |
|---|---|
| idle (`shreg==0`) | `tx=1`, `tx_busy=0`. `tx_start`가 오면 위 프레임을 `shreg`에 로드 → **다음 클럭부터 `tx=0`(start bit)**, `tx_busy=1` |
| 전송 중, `bit_done` | `shreg`를 오른쪽으로 한 칸 시프트 (위에서 0 입력). 다음 비트가 `shreg[0]`으로 내려옴 (LSB first) |
| stop bit 중 (`shreg[10:2]==0`, 마커가 `shreg[1]`) | `bit_done`이면 시프트 대신 `shreg=0`으로 클리어 → `tx_busy=0`, idle |

- `tx`는 플립플롭 출력에 인버터 하나만 거치므로 글리치가 없습니다.
- `cnt`는 idle 동안 항상 0이므로 `tx_start` 때 따로 클리어하지 않습니다.

- 각 비트는 정확히 `CLKS_PER_BIT` 클럭 동안 유지됩니다.
- `tx_start`를 받은 클럭의 다음 에지에서 바로 start bit가 나가므로 시작 지연이 없습니다.
- 1 프레임 = 10 × `CLKS_PER_BIT` 클럭. `tx_busy`가 내려간 뒤 다음 `tx_start`를 넣으면 프레임 사이에 수 클럭의 idle 간격이 생깁니다.

```
tx       ‾‾‾‾\_________/ D0 / D1 / ... / D7 /‾‾‾‾‾‾‾‾‾‾‾‾‾/‾‾‾
              START                            STOP        idle
tx_busy  ___/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\____
```

### 5.3 `uart_rx` — 수신기

**입력 동기화**: `rx`는 `clk`와 무관한 비동기 입력이므로 메타스테이블(metastability) 위험이 있습니다.
`rx_sync0` → `rx_sync1` 2-FF 동기화기를 거치고, FSM은 반드시 `rx_sync1`만 참조합니다. 리셋 값은 `1`(idle)입니다.

FSM: `IDLE → START → DATA(×8) → STOP → IDLE`

| 상태 | 동작 |
|---|---|
| `IDLE` | `cnt=CLKS_PER_BIT-CLKS_PER_BIT/2`. `rx_sync1==0` (하강 엣지) 감지 시 `START`로 |
| `START` | 반 비트 시간(`CLKS_PER_BIT/2`) 후 = start bit 중앙에서 재확인. 여전히 `0`이면 `cnt=0`으로 리셋하고 `DATA`로, `1`이면 글리치로 판단하고 `IDLE`로 복귀. 이때 `shreg`에 마커 `9'b1_0000_0000`을 로드 |
| `DATA` | 1비트 시간(`CLKS_PER_BIT`)마다 = 각 비트 중앙에서 `rx_sync1`을 `shreg` 맨 위로 시프트 입력. 마커가 `shreg[1]`에 있을 때 받은 비트(bit7) 후 `STOP`으로 |
| `STOP` | 1비트 시간 후 = stop bit 중앙에서 `rx_done` 1클럭 펄스, `IDLE`로. stop bit 값은 검사하지 않음 |

DFF 수를 줄이기 위한 구조:
- 비교기는 `bit_done`(`cnt==CLKS_PER_BIT-1`) 하나만 씁니다. `START`의 반 비트는 카운터를 중간값부터 세어서 만듭니다.
- 비트 번호 레지스터 대신 9비트 `shreg`의 마커로 8비트를 셉니다. 8비트를 받으면 마커가 `shreg[0]`에 도착하고, `rx_data = shreg[8:1]`에 LSB 순서대로 놓입니다.
- `shreg`는 데이터 전용이라 리셋하지 않습니다. 리셋 직후 첫 수신 전까지 `rx_data`는 X입니다.
- `rx_done = (state==STOP) && bit_done` 조합 출력입니다. 같은 `clk`로 동작하는 로직에서 받아야 합니다.

**샘플링 타이밍**

```
rx     ‾‾‾‾\__________/‾‾‾‾‾‾‾‾‾‾\__________/ ... ‾‾‾‾‾‾‾‾‾‾‾‾
           |  START   |   D0     |   D1     |     |  STOP    |
sample           ▲          ▲          ▲                 ▲
              +0.5 bit   +1 bit     +1 bit    ...    rx_done
             (START 확인) (D0 샘플)  (D1 샘플)
```

- 카운터가 start 하강 엣지를 감지한 시점부터 시작하므로, 샘플 위치는 항상 각 비트의 중앙에서 동기화기 지연(약 3클럭)만큼만 벗어납니다. 16배 오버샘플링은 사용하지 않습니다.
- 비트당 **1회 샘플**(다수결 투표 없음). 반 비트 미만의 start bit 글리치는 `START` 상태에서 걸러집니다.
- `rx_data`는 수신 중에 비트가 들어올 때마다 바로 갱신되므로, **`rx_done`이 뜬 클럭이 아닌 시점의 값은 신뢰할 수 없습니다.**
- `rx_done`은 stop bit **중앙**에서 발생하므로 프레임이 완전히 끝나기 약 반 비트 전에 데이터가 나옵니다.
  이후 `IDLE`은 stop bit의 `1` 동안 대기하다 다음 하강 엣지를 기다리므로 연속 수신에 문제 없습니다.
- stop bit가 `0`이어도 `rx_done`은 올라가고 데이터는 그대로 출력됩니다 (오류를 알리지 않음).

## 6. 타이밍 요약

| 항목 | 값 (50 MHz, 115200 bps 기준) |
|---|---|
| 1 비트 시간 | `CLKS_PER_BIT` = 434 clk ≈ 8.68 µs |
| 1 프레임 (10 bit) | 4340 clk ≈ 86.8 µs |
| `tx_start` → `tx` start bit | 다음 클럭 에지 (약 1 clk) |
| `rx` start edge → `rx_done` | 약 9.5 비트 + 동기화 지연 수 clk |
| 최대 처리량 | 약 `BAUD_RATE / 10` byte/s (115200 bps → 약 11,520 byte/s) |

## 7. 설계 제약 및 주의사항

1. **`CLKS_PER_BIT ≥ 2` 필요**: `CLK_FREQ / BAUD_RATE < 2`이면 `$clog2`가 0이 되어 카운터 폭이 0이 됩니다.
   실제로는 RX가 비트 중앙을 잡으려면 `CLKS_PER_BIT`가 충분히 커야 하므로 최소 16 이상을 권장합니다.
2. **버퍼 없음**: `tx_busy`일 때 `tx_start`를 주면 안 되고, `rx_done` 클럭에 `rx_data`를 못 받아 가면 데이터를 잃습니다.
3. **오류 미검출**: framing error, parity error, overrun 모두 검출하지 않습니다.
4. **리셋**: `rst_n`은 비동기 assert / 비동기 deassert. 리셋 해제 동기화기는 포함되어 있지 않으므로,
   상위에서 동기화된 리셋을 넣어 주는 것을 권장합니다.
5. **상태 플래그는 1클럭 펄스**: `rx_done`은 래치되지 않으므로 필요하면 상위에서 sticky 레지스터로 잡아야 합니다.

## 8. 검증

### 8.1 테스트벤치 구성

[tb/tb_uart_top.v](../tb/tb_uart_top.v) 하나입니다. `uart_top`의 `tx`와 `rx`를 같은 신호로 묶은 **loopback** 구성입니다.
`uart_top`의 **포트만** 사용하고 내부 신호를 직접 참조하지 않으며, 파라미터를 덮어쓰지 않고 기본값(50 MHz / 115200 bps)을 그대로 씁니다.
따라서 합성 후 netlist 시뮬레이션에서도 `uart_top dut (` 줄의 **모듈 이름만** netlist의 top 이름으로 바꾸면 그대로 동작합니다.
(합성된 netlist에는 파라미터가 남지 않으므로 `#(...)` 덮어쓰기를 넣으면 안 됩니다. 기본값이 아닌 클럭/보레이트를 쓰려면 RTL의 기본값을 바꾸고, 테스트벤치의 클럭 주기(`always #10`)도 같이 맞춰야 합니다.)

### 8.2 시뮬레이션 실행 (ModelSim)

작업 폴더(예: `sim/`)를 만들어 그 안에서 실행합니다. 산출물(`work/`, 로그, 파형)은 저장소에 넣지 않습니다.

```sh
mkdir sim && cd sim
vlib work
vlog ../rtl/*.v ../tb/tb_uart_top.v
vsim -c -do "run -all; quit -f" work.tb_uart_top
```

합성 후 시뮬레이션은 `../rtl/*.v` 대신 netlist 파일을 컴파일하고, 테스트벤치의 모듈 이름만 netlist의 top 이름으로 바꾸면 됩니다.

### 8.3 테스트 항목

| 내용 | 확인 방법 |
|---|---|
| loopback | 0x55, 0xA3, 0x00, 0xFF 4바이트를 `tx_busy`가 내려갈 때마다 연속 송신하고, `rx_done` 때마다 `rx_data`가 송신한 값과 같은지 비교 |

결과는 바이트마다 `PASS` / `FAIL`로 출력되고, 마지막 줄에 `ALL PASS` 또는 `N ERRORS`가 출력됩니다.
ModelSim ALTERA STARTER EDITION 10.1d에서 `ALL PASS`를 확인했습니다.

### 8.4 아직 검증되지 않은 항목

- 외부에서 만든 프레임 수신 (loopback 이외의 `rx` 직접 구동)
- stop bit가 깨진 프레임, start bit 글리치
- TX/RX 보레이트가 서로 다른 경우(오차 허용 범위)
- 프레임 도중 리셋
- 기본 파라미터 이외의 `CLK_FREQ` / `BAUD_RATE` 조합
