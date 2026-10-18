`timescale 1ns/1ps
// Self-checking testbench for sync_fifo
// - Reference model (ref_mem) mirrors what the FIFO should hold
// - Every read is compared against the reference model
// - full/empty flags are checked every cycle
module tb_fifo;
    localparam DATA_W = 8, ADDR_W = 4, DEPTH = 1 << ADDR_W;

    reg               clk = 0, rst_n = 0, wr_en = 0, rd_en = 0;
    reg  [DATA_W-1:0] din = 0;
    wire [DATA_W-1:0] dout;
    wire              full, empty;

    sync_fifo #(DATA_W, ADDR_W) dut (
        .clk(clk), .rst_n(rst_n), .wr_en(wr_en), .rd_en(rd_en),
        .din(din), .dout(dout), .full(full), .empty(empty)
    );

    always #5 clk = ~clk;

    // ---------------- reference model / scoreboard ----------------
    reg [DATA_W-1:0] ref_mem [0:4095];
    integer wr_idx = 0, rd_idx = 0;
    integer errors = 0, reads_checked = 0;
    reg [DATA_W-1:0] exp_val;
    reg w_ok, r_ok;

    // Inputs change on negedge, so at posedge they are stable.
    // Decide accept/ignore from the PRE-edge count, same as the DUT does.
    always @(posedge clk) begin
        if (!rst_n) begin
            wr_idx = 0;
            rd_idx = 0;
        end else begin
            w_ok = wr_en && ((wr_idx - rd_idx) < DEPTH);
            r_ok = rd_en && ((wr_idx - rd_idx) > 0);
            if (r_ok) begin
                exp_val = ref_mem[rd_idx % 4096];
                rd_idx  = rd_idx + 1;
            end
            if (w_ok) begin
                ref_mem[wr_idx % 4096] = din;
                wr_idx = wr_idx + 1;
            end
            if (r_ok) begin
                #1;   // dout is registered, so it updates right after the edge
                reads_checked = reads_checked + 1;
                if (dout !== exp_val) begin
                    $display("[%0t] MISMATCH: got %0d, expected %0d", $time, dout, exp_val);
                    errors = errors + 1;
                end
            end
        end
    end

    // Flag check every cycle (mid-cycle, after outputs settle)
    always @(negedge clk) begin
        if (rst_n) begin
            if (empty !== ((wr_idx - rd_idx) == 0)) begin
                $display("[%0t] ERROR: empty=%b but count=%0d", $time, empty, wr_idx - rd_idx);
                errors = errors + 1;
            end
            if (full !== ((wr_idx - rd_idx) == DEPTH)) begin
                $display("[%0t] ERROR: full=%b but count=%0d", $time, full, wr_idx - rd_idx);
                errors = errors + 1;
            end
        end
    end

    // ---------------- stimulus tasks ----------------
    task push(input [DATA_W-1:0] d);
    begin
        @(negedge clk); wr_en = 1; rd_en = 0; din = d;
        @(negedge clk); wr_en = 0;
    end
    endtask

    task pop;
    begin
        @(negedge clk); rd_en = 1; wr_en = 0;
        @(negedge clk); rd_en = 0;
    end
    endtask

    task push_pop(input [DATA_W-1:0] d);   // simultaneous read + write
    begin
        @(negedge clk); wr_en = 1; rd_en = 1; din = d;
        @(negedge clk); wr_en = 0; rd_en = 0;
    end
    endtask

    integer i, r;

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_fifo);

        // reset
        repeat (3) @(negedge clk);
        rst_n = 1;

        // TEST 1: write 5, read 5
        $display("TEST 1: basic write/read");
        for (i = 0; i < 5; i = i + 1) push(10 + i);
        for (i = 0; i < 5; i = i + 1) pop;

        // TEST 2: fill completely, then try extra writes (must be ignored)
        $display("TEST 2: fill to full + overflow attempts");
        for (i = 0; i < DEPTH; i = i + 1) push(100 + i);
        push(8'hEE); push(8'hEF); push(8'hF0);          // should be dropped
        if (!full) begin $display("ERROR: full not asserted"); errors = errors + 1; end

        // TEST 3: drain completely, then try extra reads (must be ignored)
        $display("TEST 3: drain to empty + underflow attempts");
        for (i = 0; i < DEPTH; i = i + 1) pop;
        pop; pop;                                       // should be ignored
        if (!empty) begin $display("ERROR: empty not asserted"); errors = errors + 1; end

        // TEST 4: simultaneous read + write
        $display("TEST 4: simultaneous read/write");
        push(8'hA1); push(8'hA2); push(8'hA3);
        for (i = 0; i < 6; i = i + 1) push_pop(8'hB0 + i);
        while (wr_idx != rd_idx) pop;

        // TEST 5: simultaneous R/W when empty and when full
        $display("TEST 5: simultaneous R/W at empty and at full");
        push_pop(8'h55);                                // empty: only write takes effect
        for (i = 0; i < DEPTH; i = i + 1) push(i);      // now full
        push_pop(8'h77);                                // full: only read takes effect
        while (wr_idx != rd_idx) pop;

        // TEST 6: reset in the middle of operation
        $display("TEST 6: reset mid-operation");
        for (i = 0; i < 6; i = i + 1) push(200 + i);
        @(negedge clk); rst_n = 0;
        @(negedge clk); @(negedge clk);
        if (!empty) begin $display("ERROR: not empty after reset"); errors = errors + 1; end
        rst_n = 1;
        for (i = 0; i < 4; i = i + 1) push(30 + i);
        for (i = 0; i < 4; i = i + 1) pop;

        // TEST 7: constrained-random traffic
        $display("TEST 7: 500 random operations");
        for (i = 0; i < 500; i = i + 1) begin
            r = $urandom % 3;
            case (r)
                0: push($urandom);
                1: pop;
                2: push_pop($urandom);
            endcase
        end

        repeat (3) @(negedge clk);
        $display("-----------------------------------");
        $display("Reads checked: %0d", reads_checked);
        if (errors == 0) $display("RESULT: PASS");
        else             $display("RESULT: FAIL (%0d errors)", errors);
        $finish;
    end

    // watchdog
    initial begin
        #2000000;
        $display("TIMEOUT");
        $finish;
    end
endmodule
