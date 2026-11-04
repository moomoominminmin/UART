# UART 설계 사양서 (Design Specification)

## 1. 개요

**8N1 UART** (8 data bits, No parity, 1 stop bit)를 면적(DFF 수)이 작도록 만든 RTL 설계입니다.
FIFO는 없고, 송신기와 수신기가 **공용 프리스케일러의 tick**을 세어 비트 타이밍을 만듭니다 (1비트 = tick 16개).

| 항목 | 사양 |
|---|---|
| 프레임 형식 | 8N1 (start 1 + data 8 + stop 1 = 10 bit), LSB first |
| 라인 idle 레벨 | High (`1`) |
| 기본 클럭 / 보레이트 | 10 MHz / 9600 bps (파라미터로 변경 가능) |
| 비트 타이밍 | 공용 프리스케일러 `PRE_DIV = CLK_FREQ / (BAUD_RATE × 16)` 클럭마다 tick, 1비트 = 16 tick |
| RX 샘플링 | start 하강 엣지부터 tick 8개 뒤 start 중앙 확인, 이후 tick 16개마다 1회 샘플 |
| 버퍼 | 없음 (TX는 데이터를 저장하지 않음 → 전송 중 `tx_data` 유지 필요, RX 1바이트 출력 레지스터) |
| 클럭 도메인 | 단일 클럭 (`clk`) |
| 리셋 | 비동기, Active-Low (`rst_n`). 클럭이 도는 상태에서 2클럭 이상 유지 필요 |
| 오류 검출 | 없음 (framing / parity / overrun 검출하지 않음) |
| 미지원 | 패리티, 2 stop bit, 흐름 제어(RTS/CTS), 런타임 보레이트 변경 |

## 2. 파일 구성

| 파일 | 설명 |
|---|---|
| [rtl/uart_top.v](../rtl/uart_top.v) | 최상위 모듈. `uart_tick`, `uart_tx`, `uart_rx`를 연결만 함 |
| [rtl/uart_tick.v](../rtl/uart_tick.v) | 공용 프리스케일러 (`PRE_DIV` 클럭마다 `tick` 1클럭) |
| [rtl/uart_tx.v](../rtl/uart_tx.v) | 송신기 FSM (tick 카운터 내장) |
| [rtl/uart_rx.v](../rtl/uart_rx.v) | 수신기 FSM (2-FF 동기화기, tick 카운터 내장) |
| [tb/tb_uart_top.v](../tb/tb_uart_top.v) | loopback 테스트벤치 |

## 3. 블록 다이어그램

```
                      uart_top
 ┌────────────────────────────────────────────┐
 │             ┌───────────┐                  │
 │             │ uart_tick │ (pre: 0~64)      │
 │             └─────┬─────┘                  │
 │                   │ tick (65클럭마다)       │
 │          ┌────────┴────────┐               │
 │ tx_start ─►┌──────────┐    │               │
 │ tx_data  ─►│ uart_tx  │────┼───────────────┼──► tx
 │ tx_busy  ◄─│ (tcnt)   │    │               │
 │            └──────────┘    │               │
 │ rx_data  ◄─┌──────────┐    │               │
 │ rx_done  ◄─│ uart_rx  │◄───┘               │
 │            │(2FF sync │◄───────────────────┼─── rx
 │            │ + tcnt)  │                    │
 │            └──────────┘                    │
 └────────────────────────────────────────────┘
```

TX 경로와 RX 경로는 같은 `tick`을 쓰지만 각자의 tick 카운터(`tcnt`)를 가지므로 동시에 송수신할 수 있습니다(전이중).

## 4. 최상위 인터페이스 (`uart_top`)

### 4.1 파라미터

| 파라미터 | 기본값 | 설명 |
|---|---|---|
| `CLK_FREQ` | `10_000_000` | 입력 클럭 주파수 [Hz] |
| `BAUD_RATE` | `9600` | 목표 보레이트 [bps] |

두 파라미터는 `uart_tick`에만 전달됩니다. `uart_tx`, `uart_rx`는 파라미터 없이 `tick`만 받습니다.

### 4.2 포트

| 포트 | 방향 | 폭 | 설명 |
|---|---|---|---|
| `clk` | in | 1 | 시스템 클럭 |
| `rst_n` | in | 1 | 비동기 리셋, Active-Low |
| `tx_start` | in | 1 | **1클럭 펄스**. 전송 시작. `tx_busy`=1일 때는 사용 금지 (무시되지 않고 동작이 정의되지 않음) |
| `tx_data` | in | 8 | 송신할 바이트. **`tx_start`부터 `tx_busy`가 0이 될 때까지 값을 유지해야 함** (내부에 저장하지 않고 비트마다 직접 읽음) |
| `tx_busy` | out | 1 | 전송 중이면 1 (`tx_start` 다음 클럭부터 stop bit 끝까지) |
| `rx_data` | out | 8 | 수신한 바이트. **`rx_done`이 1인 클럭에만 유효** |
| `rx_done` | out | 1 | **1클럭 펄스** (조합 출력). 1바이트 수신 완료 |
| `tx` | out | 1 | 시리얼 출력 (idle = 1) |
| `rx` | in | 1 | 시리얼 입력 (idle = 1), `clk`와 비동기 |

### 4.3 사용 방법

**송신**
```
if (!tx_busy) begin tx_start <= 1; tx_data <= byte; end   // 1클럭 후 tx_start <= 0
```
- `tx_busy`가 0일 때만 `tx_start`를 올립니다. 버퍼가 없으므로, 연속 전송하려면 `tx_busy`가 내려가길 기다린 뒤 다음 바이트를 넣어야 합니다.
- `tx_start`를 올린 다음 클럭에 `tx_busy`가 1이 됩니다. start bit는 그 뒤 **첫 tick**에서 시작하므로 최대 `PRE_DIV`(65) 클럭 늦게 나갑니다.
- **`tx_busy`가 1인 동안 `tx_data`를 바꾸면 안 됩니다.** 바꾸면 그 뒤 비트들이 바뀐 값으로 나갑니다. 다음 바이트는 `tx_busy`가 0이 된 뒤에 넣습니다.

**수신**
```
if (rx_done) use(rx_data);
```
- `rx_done`은 1클럭만 뜨고 `rx_data`는 다음 프레임 수신이 시작되면 덮어써지므로, `rx_done`인 클럭에 바로 받아 가야 합니다.
- `rx_done`은 조합 출력이므로 같은 `clk`로 동작하는 로직에서 받아야 합니다.
- 받아 가지 못해도 에러 표시는 없습니다 (overrun 개념 없음).

## 5. 모듈별 상세

### 5.1 비트 타이밍 (`uart_tick`)

```
PRE_DIV  = CLK_FREQ / (BAUD_RATE × 16)     (정수 나눗셈, 내림)
1 tick   = PRE_DIV 클럭
1 비트   = 16 tick = 16 × PRE_DIV 클럭
```

`pre` 카운터(`$clog2(PRE_DIV)`비트)가 `0 ~ PRE_DIV-1`을 반복하고, `PRE_DIV-1`인 클럭에 `tick`이 1이 됩니다.
`pre`는 리셋 없는 DFF이고, `rst_n`이 0인 동안 0으로 지웁니다 (동기 클리어).

실제 보레이트는 `CLK_FREQ / (16 × PRE_DIV)`이며, 내림 때문에 목표보다 약간 높습니다.

**10 MHz 기준 보레이트 오차**

| 목표 [bps] | PRE_DIV | 1비트 [clk] | 실제 [bps] | 오차 | 사용 가능 여부 (±2% 기준) |
|---|---|---|---|---|---|
| **9600** | **65** | **1040** | **9615.4** | **+0.16%** | **O (기본값)** |
| 19200 | 32 | 512 | 19531.3 | +1.73% | △ (여유 거의 없음) |
| 38400 | 16 | 256 | 39062.5 | +1.73% | △ (여유 거의 없음) |
| 57600 | 10 | 160 | 62500.0 | +8.51% | **X** |
| 115200 | 5 | 80 | 125000.0 | +8.51% | **X** |

> 상대 장치와의 보레이트 오차 합이 대략 ±2% 이내여야 안정적으로 통신됩니다.
> tick 단위로 나누므로 클럭을 직접 세던 방식보다 절삭 오차가 큽니다. 10 MHz에서는 **9600 bps**를 권장하며, 19200 / 38400 bps는 상대 장치 오차까지 더하면 ±2%를 넘을 수 있습니다.

### 5.2 `uart_tx` — 송신기

FSM: `IDLE → START → DATA(×8) → STOP → IDLE`

tick 카운터 `tcnt`(4비트)가 tick마다 1씩 증가하고, 15에서 tick이 오면(`bit_done`) 1비트(16 tick)가 끝난 것입니다. 15 다음에는 저절로 0이 됩니다.

| 상태 | 동작 |
|---|---|
| `IDLE` | `tx=1`, `tcnt=0`. `tx_start`가 오면 `START`로 (`tx_busy=1`) |
| `START` | `tx=1`인 동안은 tick을 기다림(`tcnt=0` 유지). **첫 tick에서 `tx=0`(start bit)**. 16 tick 뒤 `bit_done`이면 `tx=tx_data[0]`, `DATA`로 |
| `DATA` | 16 tick마다 다음 비트 출력 (bit1 → bit7, LSB first). bit7까지 끝나면 `tx=1`(stop bit), `STOP`으로 |
| `STOP` | stop bit를 16 tick 유지. `bit_done`이면 `IDLE`로 |

- start bit를 tick에 맞춰 시작하므로, start bit를 포함한 모든 비트가 정확히 16 tick(1040클럭) 동안 유지됩니다.
- "tick을 기다리는 중"은 `START && tx==1`로 구분하므로 별도 레지스터가 필요 없습니다.
- `tx_busy = (state != IDLE)` 조합 출력입니다.
- 보낼 데이터를 저장하는 레지스터가 없습니다. 비트마다 `tx_data[bit_idx]`를 직접 읽어 `tx` 레지스터에 넣으므로, 전송 중 `tx_data`를 유지해야 합니다. `tx`는 레지스터 출력이라 `tx_data`가 바뀌어도 글리치는 생기지 않습니다.
- 리셋 DFF는 `state`, `tx`만 씁니다. `tcnt`는 IDLE과 tick 대기 중에 0으로 지우고, `bit_idx`는 쓰기 전에 항상 새 값이 들어가므로 리셋 없는 DFF를 씁니다.
- 1 프레임 = 10 × 16 tick = 10400 클럭.

```
tick     |    |    |    |    |    ...  (65클럭마다)
tx       ‾‾‾‾‾‾‾‾\_________/ D0 / D1 / ... / D7 /‾‾‾‾‾‾‾‾‾‾‾‾/‾‾‾
                  START (16 tick)                 STOP       idle
tx_busy  ___/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\____
            ↑tx_start  ↑첫 tick (최대 65클럭 뒤)
```

### 5.3 `uart_rx` — 수신기

**입력 동기화**: `rx`는 `clk`와 무관한 비동기 입력이므로 메타스테이블(metastability) 위험이 있습니다.
`rx_sync0` → `rx_sync1` 2-FF 동기화기를 거치고, FSM은 반드시 `rx_sync1`만 참조합니다. 리셋 없는 DFF이며, 리셋이 걸려 있는 2클럭 동안 `rx` 값으로 채워집니다.

FSM: `IDLE → START → DATA(×8) → STOP → IDLE`

tick 카운터 `tcnt`(4비트)가 tick마다 1씩 증가하고, 15에서 tick이 오면 `bit_done`입니다.

| 상태 | 동작 |
|---|---|
| `IDLE` | `tcnt=8`. `rx_sync1==0` 감지 시 `START`로 |
| `START` | `tcnt`가 8부터 세므로 **tick 8개(반 비트)** 뒤 `bit_done` = start bit 중앙에서 재확인. 여전히 `0`이면 `bit_idx=0`으로 하고 `DATA`로, `1`이면 글리치로 판단하고 `IDLE`로 복귀 |
| `DATA` | tick 16개마다 = 각 비트 중앙에서 `rx_sync1`을 `rx_data[bit_idx]`에 저장. bit7 후 `STOP`으로 |
| `STOP` | tick 16개 후 = stop bit 중앙에서 `rx_done` 1클럭 펄스, `IDLE`로. stop bit 값은 검사하지 않음 |

- 비교기는 `bit_done`(`tick && tcnt==15`) 하나만 씁니다. 반 비트는 카운터를 8부터 세어서 만듭니다.
- 리셋 DFF는 `state`만 씁니다. `tcnt`는 IDLE에서 매 클럭 8로 덮어쓰고, `rx_data`와 `bit_idx`는 쓰기 전에 항상 새 값이 들어가므로 리셋 없는 DFF를 씁니다. 리셋 직후 첫 수신 전까지 `rx_data`는 X입니다.
- `rx_done = (state==STOP) && bit_done` 조합 출력입니다.

**샘플링 타이밍**

```
rx     ‾‾‾‾\__________/‾‾‾‾‾‾‾‾‾‾\__________/ ... ‾‾‾‾‾‾‾‾‾‾‾‾
           |  START   |   D0     |   D1     |     |  STOP    |
sample           ▲          ▲          ▲                 ▲
              +8 tick   +16 tick   +16 tick   ...    rx_done
             (START 확인) (D0 샘플)  (D1 샘플)
```

- start 엣지는 tick 사이 아무 때나 오므로, 첫 tick까지의 간격(1~65클럭)만큼 샘플 위치가 비트 중앙보다 **최대 1 tick(약 6%) 일찍** 잡힙니다. 여기에 동기화기 지연(약 2~3클럭)이 더해집니다.
- 비트당 **1회 샘플**(다수결 투표 없음). 반 비트보다 충분히 짧은 start bit 글리치는 `START` 상태에서 걸러집니다.
- `rx_data`는 수신 중에 비트가 들어올 때마다 바로 갱신되므로, **`rx_done`이 뜬 클럭이 아닌 시점의 값은 신뢰할 수 없습니다.**
- `rx_done`은 stop bit **중앙** 부근에서 발생하므로 프레임이 완전히 끝나기 약 반 비트 전에 데이터가 나옵니다.
  이후 `IDLE`은 stop bit의 `1` 동안 대기하다 다음 start bit를 기다리므로 정상 프레임의 연속 수신에는 문제 없습니다.
- stop bit가 `0`이어도 `rx_done`은 올라가고 데이터는 그대로 출력됩니다 (오류를 알리지 않음). 이 경우 다음 프레임 수신이 틀어질 수 있습니다 (7절 6번).

### 5.4 DFF 구성

| 모듈 | 레지스터 | 비트 | 리셋 |
|---|---|---|---|
| `uart_tick` | `pre` | 7 | 없음 (동기 클리어) |
| `uart_tx` | `state` | 2 | 있음 |
| | `tx` | 1 | 있음 |
| | `tcnt` | 4 | 없음 |
| | `bit_idx` | 3 | 없음 |
| `uart_rx` | `rx_sync0`, `rx_sync1` | 2 | 없음 |
| | `state` | 2 | 있음 |
| | `tcnt` | 4 | 없음 |
| | `bit_idx` | 3 | 없음 |
| | `rx_data` | 8 | 없음 |
| **합계** | | **36** | 리셋 있음 5 / 없음 31 |

## 6. 타이밍 요약

| 항목 | 값 (10 MHz, 9600 bps 기준) |
|---|---|
| 1 tick | `PRE_DIV` = 65 clk |
| 1 비트 시간 | 16 tick = 1040 clk = 104 µs |
| 1 프레임 (10 bit) | 10400 clk = 1.04 ms |
| `tx_start` → `tx_busy` | 다음 클럭 에지 |
| `tx_start` → `tx` start bit | 다음 tick (1 ~ 65 clk) |
| `rx` start edge → `rx_done` | 약 9.5 비트 (최대 1 tick 이르게) + 동기화 지연 수 clk |
| 최대 처리량 | 약 `BAUD_RATE / 10` byte/s (9600 bps → 약 960 byte/s) |

## 7. 설계 제약 및 주의사항

1. **`PRE_DIV ≥ 2` 필요**: `CLK_FREQ / (BAUD_RATE × 16) < 2`이면 `$clog2`가 0이 되어 카운터 폭이 0이 됩니다.
   또한 `PRE_DIV`가 작을수록 절삭 오차가 커지므로 5.1절 표처럼 오차가 ±2% 안에 드는지 확인해야 합니다.
2. **버퍼 없음**: `tx_busy`일 때 `tx_start`를 주거나 `tx_data`를 바꾸면 안 되고, `rx_done` 클럭에 `rx_data`를 못 받아 가면 데이터를 잃습니다.
3. **오류 미검출**: framing error, parity error, overrun 모두 검출하지 않습니다.
4. **리셋**: `rst_n`은 비동기 assert / 비동기 deassert. 리셋 해제 동기화기는 포함되어 있지 않으므로,
   상위에서 동기화된 리셋을 넣어 주는 것을 권장합니다.
   면적을 줄이기 위해 리셋 DFF는 TX `state`(2)·`tx`(1)와 RX `state`(2)만 쓰고, 나머지는 리셋 없는 DFF입니다 (5.4절).
   따라서 **리셋은 클럭이 도는 상태에서 2클럭 이상 유지**해야 합니다. 그 동안 리셋 없는 DFF가 정해진 값으로 채워집니다.
5. **상태 플래그는 1클럭 펄스**: `rx_done`은 래치되지 않으므로 필요하면 상위에서 sticky 레지스터로 잡아야 합니다.
6. **프레임 오류 뒤 재동기화**: RX는 IDLE에서 "하강 엣지"가 아니라 "`rx==0`"을 보고 START로 갑니다.
   stop bit가 `0`인 프레임(framing error, break)을 받으면, `rx_done` 직후 아직 `0`인 라인을 새 start bit로 착각해
   **쓰레기 바이트를 1개 이상 출력하고 몇 프레임 뒤에 다시 맞춰질 수 있습니다.** 정상 프레임에서는 생기지 않습니다.

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

- 프레임 도중 리셋
- 기본 파라미터 이외의 `CLK_FREQ` / `BAUD_RATE` 조합
- 합성 후 netlist 시뮬레이션

TX 파형(비트 길이, start 지연), 외부 프레임 수신(상대 보레이트 ±3%, start 글리치, 깨진 stop bit)은
저장소에 없는 별도 테스트벤치로 확인했습니다. 깨진 stop bit 뒤에는 7절 6번의 문제가 재현됩니다.
