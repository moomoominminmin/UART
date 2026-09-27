run 970000ns
set i 0
while {$i < 21} {
  run 10000ns
  echo [format "t=%0t st=%b os=%b bi=%b rx=%b s1=%b done=%b data=%b ferr=%b" $now [examine -radix binary /tb_uart_rx/dut/state] [examine -radix binary /tb_uart_rx/dut/os_cnt] [examine -radix binary /tb_uart_rx/dut/bit_idx] [examine -radix binary /tb_uart_rx/rx] [examine -radix binary /tb_uart_rx/dut/rx_sync1] [examine -radix binary /tb_uart_rx/rx_done] [examine -radix binary /tb_uart_rx/dut/data_reg] [examine -radix binary /tb_uart_rx/framing_error]]
  incr i
}
quit -f
