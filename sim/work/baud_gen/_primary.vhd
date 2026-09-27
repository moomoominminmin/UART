library verilog;
use verilog.vl_types.all;
entity baud_gen is
    generic(
        CLK_FREQ        : integer := 50000000;
        BAUD_RATE       : integer := 115200;
        OVERSAMPLE      : integer := 16
    );
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        tx_tick         : out    vl_logic;
        rx_tick         : out    vl_logic
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of CLK_FREQ : constant is 1;
    attribute mti_svvh_generic_type of BAUD_RATE : constant is 1;
    attribute mti_svvh_generic_type of OVERSAMPLE : constant is 1;
end baud_gen;
