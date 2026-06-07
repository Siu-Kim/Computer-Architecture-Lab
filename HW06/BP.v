`timescale 1ns / 1ps
`include "GLOBAL.v"

module BP(
    input               clk,
    input		        rst,

    input [31:0]        PC,
    output [31:0]       PC_pred,
    output              pred_taken,

    input               update_valid,
    input [31:0]        update_PC,
    input [31:0]        actual_PC,
    input               actual_taken

    );
    integer i;

    //BTB: 64 entries
    reg                 btb_valid   [0:63];
    reg [23:0]          btb_tag     [0:63];
    reg [31:0]          btb_target  [0:63];
    // PHT: 256 entries
    reg [1:0]           pht         [0:255]; // 2-bit saturation counter

    wire [5:0]          pred_btb_idx = PC[7:2];
    wire [23:0]         pred_btb_tag = PC[31:8];
    wire [7:0]          pred_pht_idx = PC[9:2];

    wire [5:0]          upd_btb_idx = update_PC[7:2];
    wire [23:0]         upd_btb_tag = update_PC[31:8];
    wire [7:0]          upd_pht_idx = update_PC[9:2];
//============================ Predict logic ====================================//
    wire                btb_hit = btb_valid[pred_btb_idx] && (btb_tag[pred_btb_idx] == pred_btb_tag);
    wire                pht_taken = pht[pred_pht_idx][1];

    assign pred_taken = btb_hit && pht_taken;
    assign PC_pred = pred_taken ? btb_target[pred_btb_idx] : (PC + 4);
    
    always @(posedge clk) begin
        if(rst) begin
            for(i = 0; i < 64; i = i+1) begin
                btb_valid[i] <= 1'b0;
            end
            for(i = 0; i < 256; i = i+1) begin
                pht[i] <= 2'b01; // Weakly Not Taken
            end
        end
        else if(update_valid) begin
    //============================= Update Logic ======================================//            
            if(actual_taken) begin
                // BTB update: actual taken인 경우에만 update
                btb_valid[upd_btb_idx]  <= 1;
                btb_tag[upd_btb_idx]    <= upd_btb_tag;
                btb_target[upd_btb_idx] <= actual_PC;

                // PHT 2-bit saturation counter update
                pht[upd_pht_idx] <= (pht[upd_pht_idx] == 2'b11) ? 2'b11 : pht[upd_pht_idx] + 1;
            end
            else begin
                pht[upd_pht_idx] <= (pht[upd_pht_idx] == 2'b00) ? 2'b00 : pht[upd_pht_idx] - 1;
            end
        end
    end
endmodule