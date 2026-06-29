`timescale 1ns / 1ps

module v_decim (
    input  logic               PCLK,
    input  logic               PRESETn,

    input  logic [6:0][15:0]   v_filt_coeffs_i,
    input  logic [10:0]        v_size_i, 

    input  logic [7:0]         Y_in,
    input  logic [1:0]         valid_in,

    output logic [7:0]         Y_out,
    output logic [1:0]         valid_out
);

    logic [9:0] fifo_mem [0:15]; 
    logic [4:0] wr_ptr;
    logic [4:0] rd_ptr;
    
    wire fifo_full  = (wr_ptr == {~rd_ptr[4], rd_ptr[3:0]});
    wire fifo_empty = (wr_ptr == rd_ptr);
    wire pop        = !fifo_empty; 

    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            wr_ptr <= 5'd0;
        end else if (valid_in != 2'b00 && !fifo_full) begin
            fifo_mem[wr_ptr[3:0]] <= {valid_in, Y_in};
            wr_ptr <= wr_ptr + 1'b1;
        end
    end

    wire [9:0] fifo_rdata = fifo_mem[rd_ptr[3:0]];
    wire [7:0] fifo_Y     = fifo_rdata[7:0];
    wire [1:0] fifo_valid = fifo_rdata[9:8];

    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            rd_ptr <= 5'd0;
        end else if (pop) begin
            rd_ptr <= rd_ptr + 1'b1;
        end
    end


    logic [11:0] x_cnt;
    logic [11:0] y_cnt;

    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            x_cnt <= 12'd0;
            y_cnt <= 12'd0;
        end else if (pop) begin
            if (fifo_valid == 2'b11) begin
                x_cnt <= 12'd0;
                y_cnt <= 12'd0;      
            end else if (fifo_valid == 2'b10) begin
                x_cnt <= 12'd0;     
                y_cnt <= y_cnt + 1'b1; 
            end else if (fifo_valid == 2'b01) begin
                x_cnt <= x_cnt + 1'b1;
            end
        end
    end


    logic [7:0] line_mem [0:5][0:511];
    logic [7:0] delay_rdata [0:5];

    logic [7:0]  fifo_Y_d1;
    logic [1:0]  valid_d1;
    logic [11:0] y_cnt_d1;

    always_ff @(posedge PCLK) begin
        if (pop) begin
    
            delay_rdata[0] <= line_mem[0][x_cnt[8:0]];
            line_mem[0][x_cnt[8:0]] <= fifo_Y;

            delay_rdata[1] <= line_mem[1][x_cnt[8:0]];
            line_mem[1][x_cnt[8:0]] <= delay_rdata[0];

            delay_rdata[2] <= line_mem[2][x_cnt[8:0]];
            line_mem[2][x_cnt[8:0]] <= delay_rdata[1];

            delay_rdata[3] <= line_mem[3][x_cnt[8:0]];
            line_mem[3][x_cnt[8:0]] <= delay_rdata[2];

            delay_rdata[4] <= line_mem[4][x_cnt[8:0]];
            line_mem[4][x_cnt[8:0]] <= delay_rdata[3];

            delay_rdata[5] <= line_mem[5][x_cnt[8:0]];
            line_mem[5][x_cnt[8:0]] <= delay_rdata[4];

            valid_d1  <= fifo_valid;
            y_cnt_d1  <= y_cnt;
            fifo_Y_d1 <= fifo_Y;
        end else begin
            valid_d1  <= 2'b00; 
        end
    end


    logic [7:0] mac_tap [0:6];
    logic [7:0] avail_lines [0:6];

    always_comb begin
        avail_lines[6] = fifo_Y_d1;
        avail_lines[5] = delay_rdata[0];
        avail_lines[4] = delay_rdata[1];
        avail_lines[3] = delay_rdata[2];
        avail_lines[2] = delay_rdata[3];
        avail_lines[1] = delay_rdata[4];
        avail_lines[0] = delay_rdata[5];

        mac_tap[6] = avail_lines[6];
        mac_tap[5] = (y_cnt_d1 < 12'd1) ? mac_tap[6] : avail_lines[5];
        mac_tap[4] = (y_cnt_d1 < 12'd2) ? mac_tap[5] : avail_lines[4];
        mac_tap[3] = (y_cnt_d1 < 12'd3) ? mac_tap[4] : avail_lines[3];
        mac_tap[2] = (y_cnt_d1 < 12'd4) ? mac_tap[3] : avail_lines[2];
        mac_tap[1] = (y_cnt_d1 < 12'd5) ? mac_tap[2] : avail_lines[1];
        mac_tap[0] = (y_cnt_d1 < 12'd6) ? mac_tap[1] : avail_lines[0];
    end


    logic [1:0] out_trigger_v;
    always_comb begin
        // Only trigger output on lines 3, 7, 11, 15... (Decimate by 4 vertically)
        if (y_cnt_d1[1:0] == 2'b11 && valid_d1 != 2'b00) begin
            if (valid_d1 == 2'b11 || valid_d1 == 2'b10) begin
                // If it's the very first output line of the frame (Line 3), mark as Frame Start '3'
                out_trigger_v = (y_cnt_d1 == 12'd3) ? 2'b11 : 2'b10;
            end else begin
                out_trigger_v = 2'b01;
            end
        end else begin
            out_trigger_v = 2'b00;
        end
    end

    logic signed [24:0] mult_res [0:6];
    logic [1:0]         pipe1_valid;

    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            pipe1_valid <= 2'b00;
            for (int i = 0; i < 7; i++) mult_res[i] <= 25'd0;
        end else begin
            pipe1_valid <= out_trigger_v;
            for (int i = 0; i < 7; i++) begin
                mult_res[i] <= $signed({1'b0, mac_tap[i]}) * $signed(v_filt_coeffs_i[i]);
            end
        end
    end

    logic signed [27:0] add_res;
    logic [1:0]         pipe2_valid;

    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            pipe2_valid <= 2'b00;
            add_res     <= 28'd0;
        end else begin
            pipe2_valid <= pipe1_valid;
            add_res <= mult_res[0] + mult_res[1] + mult_res[2] + mult_res[3] + 
                       mult_res[4] + mult_res[5] + mult_res[6];
        end
    end

    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            valid_out <= 2'b00;
            Y_out     <= 8'd0;
        end else begin
            valid_out <= pipe2_valid;
            if (pipe2_valid != 2'b00) begin
                automatic logic signed [27:0] rounded = add_res + 28'h00008000;
                automatic logic signed [27:0] shifted = rounded >>> 16;
                
                if (shifted < 0)        Y_out <= 8'd0;
                else if (shifted > 255) Y_out <= 8'd255;
                else                    Y_out <= shifted[7:0];
            end
        end
    end

endmodule
