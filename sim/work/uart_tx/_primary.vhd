library verilog;
use verilog.vl_types.all;
entity uart_tx is
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        tx_tick         : in     vl_logic;
        tx_start        : in     vl_logic;
        tx_data         : in     vl_logic_vector(7 downto 0);
        tx              : out    vl_logic;
        tx_busy         : out    vl_logic;
        tx_done         : out    vl_logic
    );
end uart_tx;
