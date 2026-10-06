# 변경 사항 설명 (초심자용 단순화)

학부 수준에서 읽고 이해할 수 있도록 RTL과 테스트벤치를 정리했습니다.
**기능(포트, 동작)은 그대로**이고, 코드 구조와 테스트벤치만 단순해졌습니다.

## 1. 한눈에 보기

| 항목 | 변경 전 | 변경 후 |
|---|---|---|
| RTL 파일 | 5개 (434줄 합계) | 5개 (같은 구성, 주석은 한글, 군더더기 제거) |
| 테스트벤치 | 6개 (약 1,200줄) | **1개** (`tb/tb_uart_top.v`) |
| 테스트벤치가 보는 것 | 내부 신호까지 참조 (`dut_a.tx_tick`, `dut.u_rx...`) | `uart_top`의 **포트만** |
| 합성 후 시뮬레이션 | 불가능 (내부 신호 참조) | `uart_top dut (` 줄의 **모듈 이름만** 바꾸면 가능 |
| 테스트 설정 | 클럭 1 MHz / 9600 bps로 덮어씀 | 기본값 50 MHz / 115200 bps 그대로 |

## 2. RTL 변경 내용

### baud_gen.v
- `OVERSAMPLE` 파라미터 삭제 → 16으로 고정 (바꿀 일이 없고, 신경 쓸 것만 늘림).
- 카운터 이름을 의미가 드러나게 변경: `rx_cnt` → `clk_cnt`, `os_cnt` → `tick_cnt`.
- 카운터를 2개의 `always` 블록에서 **1개**로 합침.
- `tick_cnt`를 4비트로 두어, 15 다음에 0으로 돌아가는 비교/삼항 연산자를 없앰.

### uart_tx.v
- 아무데도 쓰이지 않던 출력 `tx_done` 삭제.
- 패리티 비트 계산에 "짝수 패리티 = 데이터 XOR" 설명을 주석으로 추가.
- `PARITY_EN ? PARITY : STOP` 삼항 연산자를 `if / else`로 풀어 씀.

### uart_rx.v
- `OVERSAMPLE` 파라미터, `OS_CNT_W`, `MID` 같은 계산식 삭제 → 4비트 카운터 `cnt`와 숫자 `7`, `15`를 직접 사용.
  (start bit는 절반 = 8 tick, 나머지 비트는 한 비트 = 16 tick 이라는 것이 코드에서 바로 보임)
- 상태별로 "무엇을 하는지" 한글 주석 추가. 2-FF 동기화기가 왜 필요한지 설명.

### sync_fifo.v
- `case ({do_wr, do_rd})`를 `if / else if`로 변경.
- 포인터와 `count`의 역할을 주석으로 설명.

### uart_top.v
- 이름 정리: `pop_tx` → `tx_start`, `tx_fifo_empty` → `tx_empty` 직접 사용, `rx_fifo_full` → `rx_full`.
- 안 쓰는 신호(`tx_done`) 삭제, 송신/수신 경로를 구획별로 주석 정리.
- **포트와 파라미터는 변경 없음** (`PARITY_EN`, `PARITY_ODD`, `parity_error` 포함).

## 3. 테스트벤치 변경 내용

### 3.1 6개 → 1개
삭제한 파일: `tb_baud_gen.v`, `tb_uart_tx.v`, `tb_uart_rx.v`, `tb_uart_loopback.v`, `tb_uart_top_pair.v`
(git 기록에는 남아 있어 필요하면 복구할 수 있습니다.)
하위 모듈 단위 테스트는 합성 후에 하위 모듈이 사라지거나 이름이 바뀌어 재사용할 수 없습니다.
기능은 top 테스트벤치 하나로 모두 확인합니다.

### 3.2 합성 전/후 공용으로 만든 방법
1. **포트만 사용**: `dut.u_rx.state` 같은 계층 참조를 모두 없앴습니다.
2. **파라미터를 덮어쓰지 않음**: 합성된 netlist는 파라미터가 이미 고정되어 있으므로 `#( .CLK_FREQ(...) )` 부분을 없앴습니다.
3. **모듈 이름만 변경**: 테스트할 모듈은 아래 한 곳뿐입니다.
   ```verilog
   uart_top dut (          // <-- 합성 후에는 여기 모듈 이름만 바꾼다
   ```

### 3.3 이해하기 쉽게 바꾼 점
- **위에서 아래로 읽히는 시나리오**: `initial` 블록이 "1) 리셋 → 2) 송신 → 3) 수신 → 4) 루프백 → 5) framing → 6) parity → 7) overrun" 순서로 나옵니다.
- **작은 도구 task**를 이름으로 구분:

  | task | 하는 일 |
  |---|---|
  | `write_byte(d)` | TX FIFO에 1바이트 쓰기 (가득 차면 대기) |
  | `read_byte(d)` / `expect_byte(x)` | RX FIFO에서 읽기 / 읽어서 기대값과 비교 |
  | `send_serial(d, bad_parity, bad_stop)` | 외부 장치처럼 `rx` 핀에 프레임 만들어 넣기 |
  | `check_tx_frame(x)` | `tx` 핀 파형을 비트 중앙에서 읽어 검사 |
  | `check(조건, 이름)` | 조건이 거짓이면 ERROR 출력 + 에러 카운트 |
- **신호 규칙을 하나로 통일**: 입력은 항상 `negedge clk`에서만 바꾸고 읽습니다. 기존 코드에 있던 "posedge에서 읽으면 레이스가 난다" 류의 설명과 우회 코드가 필요 없습니다.
- **에러 플래그 기록**: 1클럭짜리 펄스(`rx_overrun`, `framing_error`, `parity_error`)는 `saw_*` 레지스터로 한 번만 기록해 두고 나중에 확인합니다.
- **스코어보드 배열 제거**: 기대값을 큐에 저장하던 방식 대신, 보낸 값과 읽은 값을 바로 비교합니다.
- **출력 메시지는 영어(ASCII)**: ModelSim 콘솔에서 한글이 깨지기 때문입니다. 주석만 한글입니다.
- 마지막 줄에 `RESULT: PASS` / `RESULT: FAIL`이 출력됩니다.

### 3.4 새로 검증하게 된 것
이전 문서에서 "미검증"이던 `rx_overrun` 발생 검사(테스트 7)와, 기본 파라미터(50 MHz / 115200 bps)에서의 시뮬레이션이 추가되었습니다.

## 4. 검증 결과

ModelSim ALTERA STARTER EDITION 10.1d에서 아래 세 설정 모두 `RESULT: PASS`를 확인했습니다.

| 설정 | PASS |
|---|---|
| 8N1 (기본값) | O |
| 8E1 (`PARITY_EN=1`, `PARITY_ODD=0`) | O |
| 8O1 (`PARITY_EN=1`, `PARITY_ODD=1`) | O |

> 합성 후(netlist) 시뮬레이션은 이 환경에 합성 결과물이 없어 직접 실행해 보지 못했습니다.
> 위 3.2의 조건(포트만 사용, 기본 파라미터)을 지켰으므로 모듈 이름만 바꾸면 돌아가도록 구성했지만, 실제 netlist로 한 번 확인해 주세요.
> 타이밍(SDF) 포함 시뮬레이션은 지연 때문에 `negedge` 기준 샘플링이 어긋날 수 있습니다.

## 5. 실행 방법

```sh
cd sim
vlib work
vlog ../rtl/*.v ../tb/*.v
vsim -c -do "run -all; quit -f" work.tb_uart_top
```

자세한 사양은 [uart_spec.md](uart_spec.md)를 참고하세요.
