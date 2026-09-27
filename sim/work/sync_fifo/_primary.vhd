library verilog;
use verilog.vl_types.all;
entity sync_fifo is
    generic(
        DATA_WIDTH      : integer := 8;
        DEPTH           : integer := 16
    );
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        wr_en           : in     vl_logic;
        wr_data         : in     vl_logic_vector;
        full            : out    vl_logic;
        rd_en           : in     vl_logic;
        rd_data         : out    vl_logic_vector;
        empty           : out    vl_logic
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of DATA_WIDTH : constant is 1;
    attribute mti_svvh_generic_type of DEPTH : constant is 1;
end sync_fifo;
