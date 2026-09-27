library verilog;
use verilog.vl_types.all;
entity uart_rx is
    generic(
        OVERSAMPLE      : integer := 16
    );
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        rx_tick         : in     vl_logic;
        rx              : in     vl_logic;
        rx_data         : out    vl_logic_vector(7 downto 0);
        rx_done         : out    vl_logic;
        framing_error   : out    vl_logic
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of OVERSAMPLE : constant is 1;
end uart_rx;
