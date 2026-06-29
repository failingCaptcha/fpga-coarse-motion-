`timescale 1ns / 1ps

module tb_v_decim();

    logic PCLK;
    logic PRESETn;

    logic [6:0][15:0] v_filt_coeffs_i;
    logic [10:0]      v_size_i;

    logic [7:0]       Y_in;
    logic [1:0]       valid_in;

    logic [7:0]       Y_out;
    logic [1:0]       valid_out;

    v_decim dut (
        .PCLK(PCLK),
        .PRESETn(PRESETn),
        .v_filt_coeffs_i(v_filt_coeffs_i),
        .v_size_i(v_size_i),
        .Y_in(Y_in),
        .valid_in(valid_in),
        .Y_out(Y_out),
        .valid_out(valid_out)
    );

    initial begin
        PCLK = 0;
        forever #5 PCLK = ~PCLK;
    end

    //  Outputs
    int output_pixel_cnt = 0;
    int output_line_cnt  = 0;
    int frame_start_cnt  = 0;

    always_ff @(posedge PCLK) begin
        if (valid_out != 2'b00) begin
            output_pixel_cnt++;
            if (valid_out == 2'b11) begin
                frame_start_cnt++;
                output_line_cnt++;
                $display("Time: %0t | Frame Start Output (valid=3) | Y_out: %0d", $time, Y_out);
            end else if (valid_out == 2'b10) begin
                output_line_cnt++;
                $display("Time: %0t | Line Start Output (valid=2) | Y_out: %0d", $time, Y_out);
            end
        end
    end

    task send_frame(input int width, input int height, input int start_val, input logic add_bubbles);
        int current_val = start_val;
        begin
            for (int y = 0; y < height; y++) begin
                for (int x = 0; x < width; x++) begin
                    
                    if (add_bubbles && (x % 5 == 2 || y % 3 == 1 && x == 4)) begin
                        @ (posedge PCLK);
                        #0.2 valid_in <= 2'b00;
                        @ (posedge PCLK);
                    end

                    @ (posedge PCLK);
                    #0.2 Y_in <= 8'(current_val);
                    
                    if (x == 0 && y == 0)      #0.2 valid_in <= 2'b11; // Frame Start
                    else if (x == 0)           #0.2 valid_in <= 2'b10; // Line Start
                    else                       #0.2 valid_in <= 2'b01; // Valid Pixel
                    
                    current_val++;
                end
            end
            @ (posedge PCLK);
            #0.2 valid_in <= 2'b00;
        end
    endtask

    initial begin
        #0.2 PRESETn       <= 0;
        #0.2 Y_in          <= 0;
        #0.2 valid_in      <= 0;
        #0.2 v_size_i      <= 11'd1088; // Max size
        
        // Setup a symmetric Low Pass Filter (Sum = 65536 -> 1.0 gain in Q1.15)
        #0.2 v_filt_coeffs_i[0] <= 16'd4096;
        #0.2 v_filt_coeffs_i[1] <= 16'd8192;
        #0.2 v_filt_coeffs_i[2] <= 16'd8192;
        #0.2 v_filt_coeffs_i[3] <= 16'd24576; // Center Tap
        #0.2 v_filt_coeffs_i[4] <= 16'd8192;
        #0.2 v_filt_coeffs_i[5] <= 16'd8192;
        #0.2 v_filt_coeffs_i[6] <= 16'd4096;

        #20;
        #0.2 PRESETn <= 1;
        #20;

        $display("--- Starting v_decim Tests ---");

        $display("\nTEST 1: Sending 16x12 frame (Continuous)...");
        output_pixel_cnt = 0;
        output_line_cnt  = 0;
        frame_start_cnt  = 0;
        
        send_frame(16, 12, 10, 1'b0); 
        
        repeat(50) @ (posedge PCLK);
        
        // Decimating 12 lines by 4 = 3 lines. 3 lines * 16 pixels = 48 outputs.
        if (output_pixel_cnt == 48) $display("PASS: Test 1 produced exactly 48 pixels.");
        else                        $display("FAIL: Test 1 produced %0d pixels (expected 48).", output_pixel_cnt);
        
        if (output_line_cnt == 3)   $display("PASS: Test 1 produced exactly 3 lines.");
        else                        $display("FAIL: Test 1 produced %0d lines (expected 3).", output_line_cnt);

        if (frame_start_cnt == 1)   $display("PASS: Test 1 flagged exactly 1 Frame Start (valid=3).");
        else                        $display("FAIL: Test 1 flagged %0d Frame Starts (expected 1).", frame_start_cnt);

        $display("\nTEST 2: Sending 16x8 frame with bubbles (stalls)...");
        output_pixel_cnt = 0;
        output_line_cnt  = 0;
        frame_start_cnt  = 0;
        
        send_frame(16, 8, 100, 1'b1); 
        
        repeat(50) @ (posedge PCLK);

        if (output_pixel_cnt == 32) $display("PASS: Test 2 produced exactly 32 pixels despite bubbles.");
        else                        $display("FAIL: Test 2 produced %0d pixels (expected 32).", output_pixel_cnt);

        if (output_line_cnt == 2)   $display("PASS: Test 2 produced exactly 2 lines.");
        else                        $display("FAIL: Test 2 produced %0d lines (expected 2).", output_line_cnt);

        $display("\n--- Tests Complete ---");
        $finish;
    end

endmodule
