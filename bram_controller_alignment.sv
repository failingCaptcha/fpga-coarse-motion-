`timescale 1ns / 1ps

module cme_bram_ctrl (
    input  logic               PCLK,
    input  logic               PRESETn,

    // Input Stream (From V_DECIM)
    input  logic [7:0]         Y_in,
    input  logic [1:0]         valid_in,

    // Output to CME_COMPUTE
    output logic [7:0]         curr_block [0:7][0:7], 
    output logic [7:0]         ref_block  [0:7][0:7], 
    output logic signed [5:0]  search_x,              
    output logic signed [5:0]  search_y,              
    output logic [11:0]        blk_x_out,             
    output logic [11:0]        blk_y_out,             
    output logic               search_valid,         
    output logic               block_done             
);


    logic [9:0] fifo_mem [0:15];
    logic [4:0] wr_ptr, rd_ptr;
    
    wire fifo_full  = (wr_ptr == {~rd_ptr[4], rd_ptr[3:0]});
    wire fifo_empty = (wr_ptr == rd_ptr);
    wire pop        = !fifo_empty; // Always drain into BRAM

    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) wr_ptr <= 5'd0;
        else if (valid_in != 2'b00 && !fifo_full) begin
            fifo_mem[wr_ptr[3:0]] <= {valid_in, Y_in};
            wr_ptr <= wr_ptr + 1'b1;
        end
    end

    wire [9:0] fifo_rdata = fifo_mem[rd_ptr[3:0]];
    wire [7:0] fifo_Y     = fifo_rdata[7:0];
    wire [1:0] fifo_valid = fifo_rdata[9:8];

    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) rd_ptr <= 5'd0;
        else if (pop) rd_ptr <= rd_ptr + 1'b1;
    end

    logic [11:0] wr_x;
    logic [11:0] wr_y;
    logic [31:0] total_lines_written; // Absolute tracker for read/write safety

    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            wr_x <= 12'd0;
            wr_y <= 12'd0;
            total_lines_written <= 32'd0;
        end else if (pop) begin
            if (fifo_valid == 2'b11) begin
                wr_x <= 12'd0;
                wr_y <= 12'd0;
            end else if (fifo_valid == 2'b10) begin
                wr_x <= 12'd0;
                wr_y <= (wr_y == 12'd511) ? 12'd0 : wr_y + 1'b1; // Wrap at 512 lines
                total_lines_written <= total_lines_written + 1'b1;
            end else if (fifo_valid == 2'b01) begin
                wr_x <= wr_x + 1'b1;
            end
        end
    end

    // 8 Independent Simple Dual-Port BRAM Banks (64 lines * 512 pixels each)
    logic [7:0] bank_mem [0:7][0:32767];
    logic [2:0] wr_bank;
    logic [14:0] wr_addr;

    assign wr_bank = wr_y[2:0];
    assign wr_addr = {wr_y[8:3], wr_x[8:0]}; // 6-bit row, 9-bit col

    always_ff @(posedge PCLK) begin
        if (pop && fifo_valid != 2'b00) begin
            bank_mem[wr_bank][wr_addr] <= fifo_Y;
        end
    end

    logic signed [12:0] rx_req, ry_req;
    logic [14:0] bank_rd_addr [0:7];
    logic [7:0]  bank_rdata [0:7];
    logic        rd_req_valid;

    always_comb begin
        for (int i = 0; i < 8; i++) begin
            // Address logic: Row increments if the bank index is less than the starting Y bank
            automatic logic [5:0] base_row = ry_req[8:3];
            automatic logic       row_inc  = (i < ry_req[2:0]) ? 1'b1 : 1'b0;
            bank_rd_addr[i] = {(base_row + row_inc), rx_req[8:0]};
        end
    end

    always_ff @(posedge PCLK) begin
        for (int i = 0; i < 8; i++) begin
            bank_rdata[i] <= bank_mem[i][bank_rd_addr[i]];
        end
    end


    logic [2:0] align_shift, align_shift_d1;
    logic       out_of_bounds, out_of_bounds_d1;

    assign align_shift = ry_req[2:0];
    
    // Check if the requested coordinate is physically outside the 512x272 decimated frame
    assign out_of_bounds = (rx_req < 0 || rx_req >= 512 || ry_req < 0 || ry_req >= 272);

    always_ff @(posedge PCLK) begin
        align_shift_d1   <= align_shift;
        out_of_bounds_d1 <= out_of_bounds;
    end

    logic [7:0] aligned_col [0:7];
    always_comb begin
        for (int i = 0; i < 8; i++) begin
            if (out_of_bounds_d1) aligned_col[i] = 8'd0; // Pad with 0s for out of bounds
            else                  aligned_col[i] = bank_rdata[(align_shift_d1 + i) % 8];
        end
    end

    typedef enum logic [2:0] {
        IDLE, LOAD_CURR, WAIT_SEARCH, PREFETCH_REF, SCAN_REF, NEXT_ROW, NEXT_BLOCK
    } fsm_state_t;

    fsm_state_t state;
    
    logic [11:0] blk_x, blk_y;
    logic signed [5:0] sx, sy;
    logic [5:0] fetch_cnt;

    // Pipeline tracking for valid pulses
    logic [1:0] state_d1; // 1 = loading curr, 2 = scanning ref
    logic signed [5:0] sx_d1, sy_d1;

    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            state <= IDLE;
            blk_x <= 12'd0;
            blk_y <= 12'd0;
            sx <= -6'sd24;
            sy <= -6'sd24;
            fetch_cnt <= 6'd0;
            state_d1 <= 2'd0;
            search_valid <= 1'b0;
            block_done <= 1'b0;
            for (int r=0; r<8; r++) for (int c=0; c<8; c++) begin
                curr_block[r][c] <= 8'd0;
                ref_block[r][c]  <= 8'd0;
            end
        end else begin
            // Default shift register pipeline
            search_valid <= 1'b0;
            block_done   <= 1'b0;
            sx_d1 <= sx;
            sy_d1 <= sy;

            // Shift Register Data Push
            if (state_d1 == 2'd1) begin // Loading Curr Block
                for (int r = 0; r < 8; r++) begin
                    curr_block[r][0] <= curr_block[r][1];
                    curr_block[r][1] <= curr_block[r][2];
                    curr_block[r][2] <= curr_block[r][3];
                    curr_block[r][3] <= curr_block[r][4];
                    curr_block[r][4] <= curr_block[r][5];
                    curr_block[r][5] <= curr_block[r][6];
                    curr_block[r][6] <= curr_block[r][7];
                    curr_block[r][7] <= aligned_col[r];
                end
            end else if (state_d1 == 2'd2) begin // Loading/Scanning Ref Block
                for (int r = 0; r < 8; r++) begin
                    ref_block[r][0] <= ref_block[r][1];
                    ref_block[r][1] <= ref_block[r][2];
                    ref_block[r][2] <= ref_block[r][3];
                    ref_block[r][3] <= ref_block[r][4];
                    ref_block[r][4] <= ref_block[r][5];
                    ref_block[r][5] <= ref_block[r][6];
                    ref_block[r][6] <= ref_block[r][7];
                    ref_block[r][7] <= aligned_col[r];
                end
                
                // If we are actively scanning (not just prefetching the first 8 cols)
                if (fetch_cnt > 6'd8) begin
                    search_valid <= 1'b1;
                    search_x     <= sx_d1;
                    search_y     <= sy_d1;
                    blk_x_out    <= blk_x;
                    blk_y_out    <= blk_y;
                end
            end

            // Main State Machine
            case (state)
                IDLE: begin
                    state_d1 <= 2'd0;
                    // Safety Check: Ensure write pointer is ahead of the search window bottom edge (y + 24 + 8)
                    if (total_lines_written >= (blk_y * 8) + 32) begin
                        state <= LOAD_CURR;
                        fetch_cnt <= 6'd0;
                    end
                end

                LOAD_CURR: begin
                    rx_req <= blk_x * 8 + fetch_cnt;
                    ry_req <= blk_y * 8;
                    state_d1 <= 2'd1;
                    
                    if (fetch_cnt == 6'd7) begin
                        state <= PREFETCH_REF;
                        fetch_cnt <= 6'd0;
                        sx <= -6'sd24;
                        sy <= -6'sd24;
                    end else begin
                        fetch_cnt <= fetch_cnt + 1'b1;
                    end
                end

                PREFETCH_REF: begin
                    rx_req <= blk_x * 8 + sx + fetch_cnt;
                    ry_req <= blk_y * 8 + sy;
                    state_d1 <= 2'd2; // Routes data to ref_block
                    
                    if (fetch_cnt == 6'd7) begin
                        state <= SCAN_REF;
                        fetch_cnt <= 6'd8;
                    end else begin
                        fetch_cnt <= fetch_cnt + 1'b1;
                    end
                end

                SCAN_REF: begin
                    rx_req <= blk_x * 8 + sx + fetch_cnt;
                    ry_req <= blk_y * 8 + sy;
                    state_d1 <= 2'd2;
                    sx <= sx + 1'b1; 
                    
                    // 49 locations means fetch_cnt goes up to 8 + 48 = 56
                    if (fetch_cnt == 6'd56) begin
                        state <= NEXT_ROW;
                    end else begin
                        fetch_cnt <= fetch_cnt + 1'b1;
                    end
                end

                NEXT_ROW: begin
                    state_d1 <= 2'd0;
                    if (sy == 6'sd24) begin
                        state <= NEXT_BLOCK;
                        block_done <= 1'b1;
                    end else begin
                        state <= PREFETCH_REF;
                        fetch_cnt <= 6'd0;
                        sy <= sy + 1'b1;
                        sx <= -6'sd24;
                    end
                end

                NEXT_BLOCK: begin
                    state_d1 <= 2'd0;
                    // 512 / 8 = 64 blocks wide
                    if (blk_x == 12'd63) begin
                        blk_x <= 12'd0;
                        blk_y <= blk_y + 1'b1;
                        if (blk_y == 12'd33) blk_y <= 12'd0; 
                    end else begin
                        blk_x <= blk_x + 1'b1;
                    end
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule
