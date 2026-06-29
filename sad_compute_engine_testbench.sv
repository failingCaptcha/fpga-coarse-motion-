`timescale 1ns / 1ps

module tb_cme_compute();

    logic PCLK;
    logic PRESETn;

    logic [7:0]        curr_block [0:7][0:7];
    logic [7:0]        ref_block  [0:7][0:7];
    logic signed [5:0] search_x;
    logic signed [5:0] search_y;
    logic [11:0]       blk_x_in;
    logic [11:0]       blk_y_in;
    logic              search_valid;
    logic              block_done;

    logic [11:0]       compute_waddr;
    logic [31:0]       compute_wdata;
    logic              compute_wen;

    cme_compute dut (
        .PCLK(PCLK),
        .PRESETn(PRESETn),
        .curr_block(curr_block),
        .ref_block(ref_block),
        .search_x(search_x),
        .search_y(search_y),
        .blk_x_in(blk_x_in),
        .blk_y_in(blk_y_in),
        .search_valid(search_valid),
        .block_done(block_done),
        .compute_waddr(compute_waddr),
        .compute_wdata(compute_wdata),
        .compute_wen(compute_wen)
    );

    initial begin
        PCLK = 0;
        forever #5 PCLK = ~PCLK;
    end

    task feed_search_pos(
        input logic signed [5:0] sx, 
        input logic signed [5:0] sy, 
        input logic [7:0] c_val, 
        input logic [7:0] r_val, 
        input logic done
    );
        begin
            @ (posedge PCLK);
            #0.2;
            search_valid <= 1'b1;
            block_done   <= done;
            search_x     <= sx;
            search_y     <= sy;
            
            for (int r = 0; r < 8; r++) begin
                for (int c = 0; c < 8; c++) begin
                    curr_block[r][c] <= c_val;
                    ref_block[r][c]  <= r_val;
                end
            end
        end
    endtask

    always_ff @(posedge PCLK) begin
        if (compute_wen) begin
            $display("Time: %0t | compute_wen Asserted!", $time);
            $display("  -> Write Address: %0d", compute_waddr);
            $display("  -> Write Data   : 0x%08x", compute_wdata);
            
            automatic logic signed [9:0] out_x = compute_wdata[31:22];
            automatic logic signed [9:0] out_y = compute_wdata[21:12];
            automatic logic [11:0] out_sad     = compute_wdata[11:0];
            $display("  -> Unpacked     : BEST_X = %0d, BEST_Y = %0d, SAD = %0d\n", out_x, out_y, out_sad);
        end
    end

    initial begin
        #0.2 PRESETn      <= 0;
        #0.2 search_valid <= 0;
        #0.2 block_done   <= 0;
        #0.2 search_x     <= 0;
        #0.2 search_y     <= 0;
        #0.2 blk_x_in     <= 12'd2; 
        #0.2 blk_y_in     <= 12'd1; 
        
        for (int r=0; r<8; r++) for (int c=0; c<8; c++) begin
            #0.2 curr_block[r][c] <= 8'd0;
            #0.2 ref_block[r][c]  <= 8'd0;
        end

        #20;
        #0.2 PRESETn <= 1;
        #20;

        $display("--- Starting CME_COMPUTE Tests ---");
        
        // Pos 1 (First Scan): Diff = 10 per pixel -> SAD = 640
        feed_search_pos(-6'sd24, -6'sd24, 8'd50, 8'd40, 1'b0);
        
        // Pos 2 (Better Match): Diff = 2 per pixel -> SAD = 128
        feed_search_pos(-6'sd23, -6'sd24, 8'd50, 8'd48, 1'b0);
        
        // Pos 3 (Worse Match): Diff = 40 per pixel -> SAD = 2560
        feed_search_pos(-6'sd22, -6'sd24, 8'd50, 8'd10, 1'b0);
        
        // Pos 4 (Extreme Mismatch & Saturation Check): Diff = 255 -> SAD = 16320 (Saturates to 4095)
        feed_search_pos(-6'sd21, -6'sd24, 8'd255, 8'd0, 1'b1);
        
        @ (posedge PCLK);
        #0.2 search_valid <= 1'b0;
        #0.2 block_done   <= 1'b0;


        $display("Pipeline stimulated. Waiting for write back...");
        
        repeat(10) @ (posedge PCLK);

        // - Address: Y * 64 + X = 1 * 64 + 2 = 66 (0x042)
        // - Best X: Pos 2 was the best match -> -23
        // - Best Y: Pos 2 was the best match -> -24
        if (compute_wen === 1'b0) $display("FAIL: compute_wen never asserted!");
        else begin
            if (compute_waddr == 12'd66) $display("PASS: Address stride correct (66)");
            else                         $display("FAIL: Expected Address 66, got %0d", compute_waddr);
            
            automatic logic signed [9:0] check_x = compute_wdata[31:22];
            automatic logic signed [9:0] check_y = compute_wdata[21:12];
            automatic logic [11:0]       check_sad = compute_wdata[11:0];
            
            if (check_x == -10'sd23) $display("PASS: Minimum X tracked properly (-23)");
            else                     $display("FAIL: Expected Best X = -23, got %0d", check_x);
            
            if (check_y == -10'sd24) $display("PASS: Minimum Y tracked properly (-24)");
            else                     $display("FAIL: Expected Best Y = -24, got %0d", check_y);
            
            if (check_sad == 12'd128) $display("PASS: Minimum SAD captured properly (128)");
            else                      $display("FAIL: Expected Best SAD = 128, got %0d", check_sad);
        end

        $display("--- Tests Complete ---");
        $finish;
    end

endmodule
