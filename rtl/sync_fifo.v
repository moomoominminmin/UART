`timescale 1ns / 1ps

// Generic synchronous FIFO (single clock domain).
// full/empty use an occupancy counter (rather than an extra pointer bit),
// which keeps the full/empty comparisons simple at the cost of one extra
// counter register.
module sync_fifo #(
    parameter DATA_WIDTH = 8,
    parameter DEPTH      = 16
) (
    input  wire                    clk,
    input  wire                    rst_n,

    input  wire                    wr_en,
    input  wire [DATA_WIDTH-1:0]   wr_data,
    output wire                    full,

    input  wire                    rd_en,
    output wire [DATA_WIDTH-1:0]   rd_data,
    output wire                    empty
);

    localparam integer ADDR_W = $clog2(DEPTH);

    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    reg [ADDR_W-1:0]     wr_ptr;
    reg [ADDR_W-1:0]     rd_ptr;
    reg [ADDR_W:0]       count; // 0..DEPTH, one extra bit vs the pointers

    assign full    = (count == DEPTH);
    assign empty   = (count == 0);
    assign rd_data = mem[rd_ptr]; // combinational read of the current head

    wire do_wr = wr_en && !full;
    wire do_rd = rd_en && !empty;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= 0;
            rd_ptr <= 0;
            count  <= 0;
        end else begin
            if (do_wr) begin
                mem[wr_ptr] <= wr_data;
                wr_ptr      <= wr_ptr + 1'b1;
            end
            if (do_rd) begin
                rd_ptr <= rd_ptr + 1'b1;
            end
            case ({do_wr, do_rd})
                2'b10:   count <= count + 1'b1;
                2'b01:   count <= count - 1'b1;
                default: count <= count; // 00: no change, 11: write+read cancel out
            endcase
        end
    end

endmodule
