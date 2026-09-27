vsim -c work.tb_uart_top
add force -deposit clk 0
run 0
log -r /*
when {$now >= 1010000000 && $now <= 1030000000} {
  echo "T=$now rx_empty=[examine -radix bin /tb_uart_top/rx_empty] rx_done=[examine -radix bin /tb_uart_top/dut/u_rx/rx_done] rx_data=[examine -radix hex /tb_uart_top/dut/u_rx/rx_data] rxfifo_count=[examine -radix dec /tb_uart_top/dut/u_rx_fifo/count] rd_en=[examine -radix bin /tb_uart_top/rd_en]"
}
run -all
quit -f
