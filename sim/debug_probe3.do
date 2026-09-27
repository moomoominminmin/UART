run 970000ns
set i 0
while {$i < 21} {
  run 10000ns
  echo "t=$now st=[examine -radix binary /tb_uart_rx/dut/state] os=[examine -radix binary /tb_uart_rx/dut/os_cnt] bi=[examine -radix binary /tb_uart_rx/dut/bit_idx] rx=[examine -radix binary /tb_uart_rx/rx] s1=[examine -radix binary /tb_uart_rx/dut/rx_sync1] done=[examine -radix binary /tb_uart_rx/rx_done] data=[examine -radix binary /tb_uart_rx/dut/data_reg]"
  incr i
}
quit -f
