
module uart_top_padded (clk, rst_n, wr_en, wr_data, tx_full, tx_empty, rd_en, rd_data, rx_empty, rx_overrun, framing_error, parity_error, tx, rx);
    input clk;
    input rst_n;
    input wr_en;
    input [7:0] wr_data;
    input rd_en;
    input rx;

    output tx_full;
    output tx_empty;
    output [7:0] rd_data;
    output rx_empty;
    output rx_overrun;
    output framing_error;
    output parity_error;
    output tx;


    wire VDD, VSS;

    wire clk_int;
    wire rst_n_int;
    wire wr_en_int;
    wire [7:0] wr_data_int;
    wire rd_en_int;
    wire rx_int;

    wire tx_full_int;
    wire tx_empty_int;
    wire [7:0] rd_data_int;
    wire rx_empty_int;
    wire rx_overrun_int;
    wire framing_error_int;
    wire parity_error_int;
    wire tx_int;

    uart_top_synth i0 (
        .clk(clk_int),
        .rst_n(rst_n_int),
        .wr_en(wr_en_int),
        .wr_data(wr_data_int),
        .tx_full(tx_full_int),
        .tx_empty(tx_empty_int),
        .rd_en(rd_en_int),
        .rd_data(rd_data_int),
        .rx_empty(rx_empty_int),
        .rx_overrun(rx_overrun_int),
        .framing_error(framing_error_int),
        .parity_error(parity_error_int),
        .tx(tx_int),
        .rx(rx_int)
    );

    // ------------------------------------------------------------
    // Input pads (PIC)
    // ------------------------------------------------------------
    PIC u_pad_clk (
        .PAD (clk),
        .Y   (clk_int),
        .VDD (VDD),
        .VSS (VSS)
    );

    PIC u_pad_rst_n (
        .PAD (rst_n),
        .Y   (rst_n_int),
        .VDD (VDD),
        .VSS (VSS)
    );

    PIC u_pad_wr_en (
        .PAD (wr_en),
        .Y   (wr_en_int),
        .VDD (VDD),
        .VSS (VSS)
    );

    PIC u_pad_wr_data0 (.PAD (wr_data[0]), .Y (wr_data_int[0]), .VDD (VDD), .VSS (VSS));
    PIC u_pad_wr_data1 (.PAD (wr_data[1]), .Y (wr_data_int[1]), .VDD (VDD), .VSS (VSS));
    PIC u_pad_wr_data2 (.PAD (wr_data[2]), .Y (wr_data_int[2]), .VDD (VDD), .VSS (VSS));
    PIC u_pad_wr_data3 (.PAD (wr_data[3]), .Y (wr_data_int[3]), .VDD (VDD), .VSS (VSS));
    PIC u_pad_wr_data4 (.PAD (wr_data[4]), .Y (wr_data_int[4]), .VDD (VDD), .VSS (VSS));
    PIC u_pad_wr_data5 (.PAD (wr_data[5]), .Y (wr_data_int[5]), .VDD (VDD), .VSS (VSS));
    PIC u_pad_wr_data6 (.PAD (wr_data[6]), .Y (wr_data_int[6]), .VDD (VDD), .VSS (VSS));
    PIC u_pad_wr_data7 (.PAD (wr_data[7]), .Y (wr_data_int[7]), .VDD (VDD), .VSS (VSS));

    PIC u_pad_rd_en (
        .PAD (rd_en),
        .Y   (rd_en_int),
        .VDD (VDD),
        .VSS (VSS)
    );

    PIC u_pad_rx (
        .PAD (rx),
        .Y   (rx_int),
        .VDD (VDD),
        .VSS (VSS)
    );

    // ------------------------------------------------------------
    // Output pads (POB4)
    // ------------------------------------------------------------
    POB4 u_pad_tx_full (
        .PAD (tx_full),
        .Y   (tx_full_int),
        .VDD (VDD),
        .VSS (VSS)
    );

    POB4 u_pad_tx_empty (
        .PAD (tx_empty),
        .Y   (tx_empty_int),
        .VDD (VDD),
        .VSS (VSS)
    );

    POB4 u_pad_rd_data0 (.PAD (rd_data[0]), .Y (rd_data_int[0]), .VDD (VDD), .VSS (VSS));
    POB4 u_pad_rd_data1 (.PAD (rd_data[1]), .Y (rd_data_int[1]), .VDD (VDD), .VSS (VSS));
    POB4 u_pad_rd_data2 (.PAD (rd_data[2]), .Y (rd_data_int[2]), .VDD (VDD), .VSS (VSS));
    POB4 u_pad_rd_data3 (.PAD (rd_data[3]), .Y (rd_data_int[3]), .VDD (VDD), .VSS (VSS));
    POB4 u_pad_rd_data4 (.PAD (rd_data[4]), .Y (rd_data_int[4]), .VDD (VDD), .VSS (VSS));
    POB4 u_pad_rd_data5 (.PAD (rd_data[5]), .Y (rd_data_int[5]), .VDD (VDD), .VSS (VSS));
    POB4 u_pad_rd_data6 (.PAD (rd_data[6]), .Y (rd_data_int[6]), .VDD (VDD), .VSS (VSS));
    POB4 u_pad_rd_data7 (.PAD (rd_data[7]), .Y (rd_data_int[7]), .VDD (VDD), .VSS (VSS));

    POB4 u_pad_rx_empty (
        .PAD (rx_empty),
        .Y   (rx_empty_int),
        .VDD (VDD),
        .VSS (VSS)
    );

    POB4 u_pad_rx_overrun (
        .PAD (rx_overrun),
        .Y   (rx_overrun_int),
        .VDD (VDD),
        .VSS (VSS)
    );

    POB4 u_pad_framing_error (
        .PAD (framing_error),
        .Y   (framing_error_int),
        .VDD (VDD),
        .VSS (VSS)
    );

    POB4 u_pad_parity_error (
        .PAD (parity_error),
        .Y   (parity_error_int),
        .VDD (VDD),
        .VSS (VSS)
    );

    POB4 u_pad_tx (
        .PAD (tx),
        .Y   (tx_int),
        .VDD (VDD),
        .VSS (VSS)
    );

    PVDD u_pad_vdd (
        .VDD (VDD),
        .VSS (VSS)
    );

    PVSS u_pad_vss (
        .VDD (VDD),
        .VSS (VSS)
    );

endmodule