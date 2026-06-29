`timescale 1ns / 1ps

module tb_cme_bram_ctrl();

    logic PCLK;
    logic PRESETn;

    // Input Stream
    logic [7:0] Y_in;
    logic [1:0] valid_in;

    // Output to CME_COMPUTE
    logic [7:0]        curr_block [0:7][0:7];
    logic [7:0]        ref_block  [0:7][0:7];
    logic signed [5:0] search_x;
    logic signed [5:0] search_y;
    logic [11:0]       blk_x_out;
    logic [11:0]       blk_y_out;
    logic              search_valid;
    logic              block_done;

    cme_bram_ctrl dut (
        .PCLK(PCLK),
        .PRESETn(PRESETn),
        .Y_in(Y_in),
        .valid_in(valid_in),
        .curr_block(curr_block),
        .ref_block(ref_block),
        .search_x(search_x),
        .search_y(search_y),
        .blk_x_out(blk_x_out),
        .blk_y_out(blk_y_out),
        .search_valid(search_valid),
        .block_done(block_done)
    );

    // Clock Generation (150 MHz)
    initial begin
        PCLK = 0;
        forever #5 PCLK = ~PCLK;
    end

    int search_cnt = 0;
    always_ff @(posedge PCLK) begin
        if (search_valid) begin
            search_cnt++;
            if (search_cnt == 1) begin
                $display("Time: %0t | First scan started! blk(%0d,%0d) -> search_x: %0d, search_y: %0d", 
                         $time, blk_x_out, blk_y_out, search_x, search_y);
                $display("             Sample Data -> curr[0][0]: %0d, ref[0][0]: %0d", 
                         curr_block[0][0], ref_block[0][0]);
            end
        end
        if (block_done) begin
            $display("Time: %0t | block_done asserted! Total search_valid pulses: %0d", $time, search_cnt);
            if (search_cnt == 2401) $display("PASS: Search window executed exactly 49x49 (2401) times.");
            else                    $display("FAIL: Expected 2401 search scans, got %0d.", search_cnt);
            search_cnt = 0;
        end
    end

    // Task to stream a decimated line of video
    task send_line(input int length, input logic is_frame_start, input int start_val);
        begin
            for (int i = 0; i < length; i++) begin
                @ (posedge PCLK);
                #0.2 Y_in <= 8'((start_val + i) % 256);
                
                if (i == 0)      #0.2 valid_in <= is_frame_start ? 2'b11 : 2'b10;
                else             #0.2 valid_in <= 2'b01;
            end
            @ (posedge PCLK);
            #0.2 valid_in <= 2'b00;
        end
    endtask

    initial begin
        #0.2 PRESETn  <= 0;
        #0.2 Y_in     <= 0;
        #0.2 valid_in <= 0;

        // Apply Reset
        #20;
        #0.2 PRESETn <= 1;
        #20;

        $display("--- Starting CME_BRAM_CTRL Tests ---");
        $display("Feeding 35 lines of 512 pixels to cross the 32-line FSM threshold...");

        // 32 lines are the threshold, plenty of data in the buffer
        for (int line = 0; line < 35; line++) begin
            send_line(512, (line == 0), (line * 10)); // length=512, frame start if line 0
            
            // Insert a small bubble between lines
            repeat(5) @(posedge PCLK);
        end
        
        $display("Finished streaming initial 35 lines. Waiting for FSM to complete Block (0,0) search...");

        // wait for the block_done signal to assert to prove it finished.
        wait(block_done);
        
        // Wait more cycles to let the FSM transition to NEXT_BLOCK / IDLE
        repeat(10) @(posedge PCLK);

        $display("--- Tests Complete ---");
        $finish;
    end

endmodule
