`timescale 1ns / 1ps

module tb_h_decim();

    logic PCLK;
    logic PRESETn;

    logic [6:0][15:0] h_filt_coeffs_i;
    logic [11:0]      h_size_i;

    logic [7:0]       Y_in;
    logic [1:0]       valid_in;

    logic [7:0]       Y_out;
    logic [1:0]       valid_out;

    h_decim dut (
        .PCLK(PCLK),
        .PRESETn(PRESETn),
        .h_filt_coeffs_i(h_filt_coeffs_i),
        .h_size_i(h_size_i),
        .Y_in(Y_in),
        .valid_in(valid_in),
        .Y_out(Y_out),
        .valid_out(valid_out)
    );

    initial begin
        PCLK = 0;
        forever #5 PCLK = ~PCLK;
    end

    int output_count = 0;
    always_ff @(posedge PCLK) begin
        if (valid_out != 2'b00) begin
            $display("Time: %0t | Output %0d | valid_out: %0d | Y_out: %0d", 
                     $time, output_count, valid_out, Y_out);
            output_count++;
        end
    end

    initial begin
        #0.2 PRESETn       <= 0;
        #0.2 Y_in          <= 0;
        #0.2 valid_in      <= 0;
        #0.2 h_size_i      <= 12'd2048; // Max size

        #0.2 h_filt_coeffs_i[0] <= 16'd4096;
        #0.2 h_filt_coeffs_i[1] <= 16'd8192;
        #0.2 h_filt_coeffs_i[2] <= 16'd8192;
        #0.2 h_filt_coeffs_i[3] <= 16'd24576; // Center Tap
        #0.2 h_filt_coeffs_i[4] <= 16'd8192;
        #0.2 h_filt_coeffs_i[5] <= 16'd8192;
        #0.2 h_filt_coeffs_i[6] <= 16'd4096;

        #20;
        #0.2 PRESETn <= 1;
        #20;

        $display("--- Starting h_decim Tests ---");

        $display("\nTEST 1: Sending 32 pixels continuously...");
        @ (posedge PCLK);
        for (int i = 0; i < 32; i++) begin
            #0.2 Y_in <= 8'(i * 5 + 10); // Ramp: 10, 15, 20, 25...
            if (i == 0)      #0.2 valid_in <= 2'b11; // Frame Start, Line Start
            else             #0.2 valid_in <= 2'b01; // Valid pixel
            @ (posedge PCLK);
        end
        #0.2 valid_in <= 2'b00; 

        // Wait for pipeline to drain
        repeat(15) @ (posedge PCLK);
        
        if (output_count == 8) $display("PASS: Test 1 produced exactly 8 outputs (32 / 4).");
        else                   $display("FAIL: Test 1 produced %0d outputs (expected 8).", output_count);

        $display("\nTEST 2: Sending 32 pixels with intermittent stalls (bubbles)...");
        output_count = 0; 
        
        for (int i = 0; i < 32; i++) begin
            if (i % 3 == 0) begin
                #0.2 valid_in <= 2'b00;
                @ (posedge PCLK);
            end
            if (i % 5 == 0) begin
                #0.2 valid_in <= 2'b00;
                @ (posedge PCLK);
                @ (posedge PCLK);
            end

            #0.2 Y_in <= 8'(100 + i); 
            if (i == 0) #0.2 valid_in <= 2'b10;
            else        #0.2 valid_in <= 2'b01; 
            @ (posedge PCLK);
        end
        #0.2 valid_in <= 2'b00; 

        repeat(20) @ (posedge PCLK);

        if (output_count == 8) $display("PASS: Test 2 produced exactly 8 outputs despite bubbles.");
        else                   $display("FAIL: Test 2 produced %0d outputs (expected 8).", output_count);

        $display("\n--- Tests Complete ---");
        $finish;
    end

endmodule
