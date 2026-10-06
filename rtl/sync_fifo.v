`timescale 1ns / 1ps

// 동기 FIFO (클럭 1개)
//   - 데이터 개수를 세는 count 로 full / empty 를 판단한다.
//   - rd_data 는 항상 "맨 앞 데이터"를 보여준다 (rd_en 을 주면 다음 데이터로 넘어감).
//   - DEPTH 는 2의 거듭제곱(2, 4, 8, 16 ...)이어야 한다.
module sync_fifo #(
    parameter DATA_WIDTH = 8,
    parameter DEPTH      = 16
) (
    input  wire                  clk,
    input  wire                  rst_n,

    input  wire                  wr_en,
    input  wire [DATA_WIDTH-1:0] wr_data,
    output wire                  full,

    input  wire                  rd_en,
    output wire [DATA_WIDTH-1:0] rd_data,
    output wire                  empty
);

    localparam integer ADDR_W = $clog2(DEPTH);

    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1]; // 데이터 저장 공간
    reg [ADDR_W-1:0]     wr_ptr;          // 다음에 쓸 위치
    reg [ADDR_W-1:0]     rd_ptr;          // 다음에 읽을 위치
    reg [ADDR_W:0]       count;           // 저장된 데이터 개수 (0 ~ DEPTH)

    assign full    = (count == DEPTH);
    assign empty   = (count == 0);
    assign rd_data = mem[rd_ptr];

    // 가득 찼을 때 쓰기, 비었을 때 읽기는 무시한다
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
                wr_ptr      <= wr_ptr + 1'b1; // 끝에 도달하면 자동으로 0으로 돌아감
            end

            if (do_rd) begin
                rd_ptr <= rd_ptr + 1'b1;
            end

            // 개수 갱신 (읽기와 쓰기가 동시에 일어나면 개수는 그대로)
            if (do_wr && !do_rd)
                count <= count + 1'b1;
            else if (!do_wr && do_rd)
                count <= count - 1'b1;
        end
    end

endmodule
