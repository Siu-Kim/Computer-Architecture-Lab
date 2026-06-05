`timescale 1ns / 1ps
`include "GLOBAL.v"

module HAZARD(
    // ID Stage 정보
    input [31:0] inst_ID,
    input        branch_taken, // ID stage에서 계산된 실제 Branch Taken 여부
    input        is_jump,
    // EX Stage 정보
    input [4:0]  wr_addr_EX,
    input        RegWrite_EX,
    
    // MEM Stage 정보
    input [4:0]  wr_addr_MEM,
    input        RegWrite_MEM,

    // WB Stage 정보
    input [4:0]  wr_addr_WB,
    input        RegWrite_WB,

    // 파이프라인 제어 출력
    output reg   flush_IF_ID,
    output reg   flush_ID_EX,
    output reg   latchWriteID,
	output reg   latchWriteEX,
	output reg   latchWriteMEM,
	output reg   latchWriteWB
    );

    reg          stall;
    
    wire [5:0] opcode = inst_ID[31:26];
    wire [4:0] rs_ID  = inst_ID[25:21];
    wire [4:0] rt_ID  = inst_ID[20:16];

    // 현재 명령어가 rs, rt를 실제로 사용하는지 판별 (불필요한 Stall 방지)
    wire use_rs = (opcode == `OP_RTYPE) || (opcode == `OP_BEQ) || (opcode == `OP_BNE) || 
                  (opcode == `OP_ADDIU) || (opcode == `OP_SLTI) || (opcode == `OP_SLTIU) || 
                  (opcode == `OP_ANDI) || (opcode == `OP_ORI) || (opcode == `OP_XORI) || 
                  (opcode == `OP_LW) || (opcode == `OP_SW);
                  
    wire use_rt = (opcode == `OP_RTYPE) || (opcode == `OP_BEQ) || (opcode == `OP_BNE) || 
                  (opcode == `OP_SW);

    // 1. Data Hazard 조건 (Forwarding이 없으므로 EX, MEM stage 모두 검사)
    wire hazard_EX  = RegWrite_EX  && (wr_addr_EX != 5'd0) && 
        ((use_rs && (rs_ID == wr_addr_EX)) || (use_rt && (rt_ID == wr_addr_EX)));
    wire hazard_MEM = RegWrite_MEM && (wr_addr_MEM != 5'd0) &&
        ((use_rs && (rs_ID == wr_addr_MEM)) || (use_rt && (rt_ID == wr_addr_MEM)));
    wire hazard_WB = RegWrite_WB && (wr_addr_WB != 5'd0) &&
        ((use_rs && (rs_ID == wr_addr_WB)) || (use_rt && (rt_ID == wr_addr_WB)));
    always @(*) begin
        latchWriteMEM = 1; latchWriteWB = 1;
        // Stall 조건 합산
        stall = hazard_EX | hazard_MEM | hazard_WB;

        // Stall 시 PC와 IF/ID 래치는 멈춤 (0)
        latchWriteID = ~stall;
        
        // ID/EX 래치는 Stall 시 NOP 주입을 위해 Flush
        flush_ID_EX = stall;
        latchWriteEX = !flush_ID_EX;
        // IF/ID Flush (Control Hazard)
        // Data Hazard로 인해 Stall 중일 경우, register 값이 정상적인 값이 X
        // -> stall이 아닐 때만 flush
        flush_IF_ID = ~stall && (branch_taken || is_jump);
    end

endmodule