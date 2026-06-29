`timescale 1ns / 1ps

module tb_cme_apb_csr();
    logic PCLK, PRESETn, PSEL, PENABLE, PWRITE, PREADY, PSLVERR, compute_wen;
    logic [15:0] PADDR;
    logic [31:0] PWDATA, PRDATA, compute_wdata;
    logic [11:0] h_size_o, compute_waddr;
    logic [10:0] v_size_o;
    logic enable_o;
    logic [6:0][15:0] h_filt_coeffs_o, v_filt_coeffs_o;

    cme_apb_csr dut (.*);

    initial begin
        PCLK = 0;
        forever #5 PCLK = ~PCLK;
    end

    task apb_write(input [15:0] addr, input [31:0] data, output logic slverr);
        begin
            @ (posedge PCLK);
            #0.2 PSEL <= 1; #0.2 PENABLE <= 0; #0.2 PWRITE <= 1; #0.2 PADDR <= addr; #0.2 PWDATA <= data;
            @ (posedge PCLK);
            #0.2 PENABLE <= 1;
            @ (posedge PCLK);
            slverr = PSLVERR;
            #0.2 PSEL <= 0; #0.2 PENABLE <= 0; #0.2 PWRITE <= 0;
        end
    endtask

    task apb_read(input [15:0] addr, output [31:0] data, output logic slverr);
        begin
            @ (posedge PCLK);
            #0.2 PSEL <= 1; #0.2 PENABLE <= 0; #0.2 PWRITE <= 0; #0.2 PADDR <= addr;
            @ (posedge PCLK);
            #0.2 PENABLE <= 1;
            @ (posedge PCLK);
            data = PRDATA; slverr = PSLVERR;
            #0.2 PSEL <= 0; #0.2 PENABLE <= 0;
        end
    endtask

    logic [31:0] read_val;
    logic err_flag;

    initial begin
        #0.2 PRESETn <= 0;
        #20;
        #0.2 PRESETn <= 1;
        #20;
        apb_write(16'h4000, 32'h12345678, err_flag); 
        apb_read(16'h4000, read_val, err_flag);
        $display("Tests initialized. PSLVERR logic active.");
        $finish;
    end
endmodule
