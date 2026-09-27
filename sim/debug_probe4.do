run 958000ns
set i 0
while {$i < 40} {
  run 1000ns
  echo "t=$now st=[examine -radix binary /tb_uart_rx/dut/state] os=[examine -radix binary /tb_uart_rx/dut/os_cnt] bi=[examine -radix binary /tb_uart_rx/dut/bit_idx] rx=[examine -radix binary /tb_uart_rx/rx] s0=[examine -radix binary /tb_uart_rx/dut/rx_sync0] s1=[examine -radix binary /tb_uart_rx/dut/rx_sync1]"
  incr i
}
quit -f
