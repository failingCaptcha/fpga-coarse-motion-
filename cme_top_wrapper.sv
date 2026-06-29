`timescale 1ns / 1ps

module cme_top (
    input  logic        PCLK,
    input  logic        PRESETn,

    input  logic        PSEL,
    input  logic        PENABLE,
    input  logic        PWRITE,
    input  logic [15:0] PADDR,
    input  logic [31:0] PWDATA,
    output logic [31:0] PRDATA,
    output logic        PREADY,
    output logic        PSLVERR,

    input  logic [7:0]  Y_in,
    input  logic [1:0]  valid_in
);


    logic               enable;
    logic [11:0]        h_size;
    logic [10:0]        v_size;
    logic [6:0][15:0]   h_filt_coeffs;
    logic [6:0][15:0]   v_filt_coeffs;

    logic [7:0]         h_Y_out;
    logic [1:0]         h_valid_out;

    logic [7:0]         v_Y_out;
    logic [1:0]         v_valid_out;

    logic [7:0]         curr_block [0:7][0:7];
    logic [7:0]         ref_block  [0:7][0:7];
    logic signed [5:0]  search_x;
    logic signed [5:0]  search_y;
    logic [11:0]        blk_x;
    logic [11:0]        blk_y;
    logic               search_valid;
    logic               block_done;

    logic [11:0]        compute_waddr;
    logic [31:0]        compute_wdata;
    logic               compute_wen;


    logic [1:0] gated_valid_in;
    assign gated_valid_in = enable ? valid_in : 2'b00;

    cme_apb_csr u_csr (
        .PCLK           (PCLK),
        .PRESETn        (PRESETn),
        .PSEL           (PSEL),
        .PENABLE        (PENABLE),
        .PWRITE         (PWRITE),
        .PADDR          (PADDR),
        .PWDATA         (PWDATA),
        .PRDATA         (PRDATA),
        .PREADY         (PREADY),
        .PSLVERR        (PSLVERR),
        .enable_o       (enable),
        .h_size_o       (h_size),
        .v_size_o       (v_size),
        .h_filt_coeffs_o(h_filt_coeffs),
        .v_filt_coeffs_o(v_filt_coeffs),
        .compute_waddr  (compute_waddr),
        .compute_wdata  (compute_wdata),
        .compute_wen    (compute_wen)
    );


    h_decim u_h_decim (
        .PCLK           (PCLK),
        .PRESETn        (PRESETn),
        .h_filt_coeffs_i(h_filt_coeffs),
        .h_size_i       (h_size),
        .Y_in           (Y_in),
        .valid_in       (gated_valid_in),
        .Y_out          (h_Y_out),
        .valid_out      (h_valid_out)
    );


    v_decim u_v_decim (
        .PCLK           (PCLK),
        .PRESETn        (PRESETn),
        .v_filt_coeffs_i(v_filt_coeffs),
        .v_size_i       (v_size),
        .Y_in           (h_Y_out),
        .valid_in       (h_valid_out),
        .Y_out          (v_Y_out),
        .valid_out      (v_valid_out)
    );

    cme_bram_ctrl u_bram_ctrl (
        .PCLK           (PCLK),
        .PRESETn        (PRESETn),
        .Y_in           (v_Y_out),
        .valid_in       (v_valid_out),
        .curr_block     (curr_block),
        .ref_block      (ref_block),
        .search_x       (search_x),
        .search_y       (search_y),
        .blk_x_out      (blk_x),
        .blk_y_out      (blk_y),
        .search_valid   (search_valid),
        .block_done     (block_done)
    );

    cme_compute u_compute (
        .PCLK           (PCLK),
        .PRESETn        (PRESETn),
        .curr_block     (curr_block),
        .ref_block      (ref_block),
        .search_x       (search_x),
        .search_y       (search_y),
        .blk_x_in       (blk_x),
        .blk_y_in       (blk_y),
        .search_valid   (search_valid),
        .block_done     (block_done),
        .compute_waddr  (compute_waddr),
        .compute_wdata  (compute_wdata),
        .compute_wen    (compute_wen)
    );

endmodule
