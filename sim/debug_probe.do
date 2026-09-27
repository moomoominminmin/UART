run 970000ns
when {/tb_uart_rx/rx_tick == 1} {
  echo [format "t=%0t st=%b os=%b bi=%b rx=%b s1=%b done=%b data=%b" $now [examine -radix binary /tb_uart_rx/dut/state] [examine -radix binary /tb_uart_rx/dut/os_cnt] [examine -radix binary /tb_uart_rx/dut/bit_idx] [examine -radix binary /tb_uart_rx/rx] [examine -radix binary /tb_uart_rx/dut/rx_sync1] [examine -radix binary /tb_uart_rx/rx_done] [examine -radix binary /tb_uart_rx/dut/data_reg]]
}
run 210000ns
quit -f
