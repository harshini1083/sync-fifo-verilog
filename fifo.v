
// Pointers are 1 bit wider than the address so full/empty can be told apart.
module sync_fifo #(
    parameter DATA_W = 8,
    parameter ADDR_W = 4            // depth = 2^ADDR_W = 16
)(
    input                   clk,
    input                   rst_n,  // active-low async reset
    input                   wr_en,
    input                   rd_en,
    input  [DATA_W-1:0]     din,
    output reg [DATA_W-1:0] dout,   // registered output: 1-cycle read latency
    output                  full,
    output                  empty
);
    reg [DATA_W-1:0] mem [0:(1<<ADDR_W)-1];
    reg [ADDR_W:0]   wptr, rptr;

    wire do_wr = wr_en && !full;    // writes ignored when full
    wire do_rd = rd_en && !empty;   // reads ignored when empty

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wptr <= 0;
            rptr <= 0;
            dout <= 0;
        end else begin
            if (do_wr) begin
                mem[wptr[ADDR_W-1:0]] <= din;
                wptr <= wptr + 1'b1;
            end
            if (do_rd) begin
                dout <= mem[rptr[ADDR_W-1:0]];
                rptr <= rptr + 1'b1;
            end
        end
    end

    assign empty = (wptr == rptr);
    assign full  = (wptr[ADDR_W-1:0] == rptr[ADDR_W-1:0]) &&
                   (wptr[ADDR_W]     != rptr[ADDR_W]);
endmodule
