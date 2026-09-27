library verilog;
use verilog.vl_types.all;
entity uart_top is
    generic(
        CLK_FREQ        : integer := 50000000;
        BAUD_RATE       : integer := 115200;
        FIFO_DEPTH      : integer := 16
    );
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        wr_en           : in     vl_logic;
        wr_data         : in     vl_logic_vector(7 downto 0);
        tx_full         : out    vl_logic;
        tx_empty        : out    vl_logic;
        rd_en           : in     vl_logic;
        rd_data         : out    vl_logic_vector(7 downto 0);
        rx_empty        : out    vl_logic;
        rx_overrun      : out    vl_logic;
        framing_error   : out    vl_logic;
        tx              : out    vl_logic;
        rx              : in     vl_logic
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of CLK_FREQ : constant is 1;
    attribute mti_svvh_generic_type of BAUD_RATE : constant is 1;
    attribute mti_svvh_generic_type of FIFO_DEPTH : constant is 1;
end uart_top;
