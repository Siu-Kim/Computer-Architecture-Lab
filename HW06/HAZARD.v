`timescale 1ns / 1ps
`include "GLOBAL.v"

module HAZARD(
    // ID Stage 정보
    input [31:0] inst_ID,
    input        is_branch,
    input        mispredicted,

    // EX Stage 정보
    input [4:0]  wr_addr_EX,
    input        MemRead_EX,
    input        RegWrite_EX,

    // MEM Stage 정보
    input [4:0]  wr_addr_MEM,
    input        MemRead_MEM,
    input        RegWrite_MEM,

    // 파이프라인 제어 출력
    output reg   flush_IF_ID,
    output reg   flush_ID_EX,
    output reg   latchWriteID,
	output reg   latchWriteEX,
	output reg   latchWriteMEM,
	output reg   latchWriteWB
    );

    reg          stall;
    reg          load_use_stall;
    reg          branch_load_MEM_stall;

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

    always @(*) begin
        latchWriteMEM = 1; latchWriteWB = 1;

        // 1. Load-Use Stall: LW가 EX에 있고 다음 명령어(ID)가 해당 레지스터를 사용하는 경우
        //    Forwarding으로 해결 불가 (메모리 읽기가 끝나지 않았으므로) → 1 cycle stall
        load_use_stall = MemRead_EX && (wr_addr_EX != 5'd0) &&
            ((use_rs && (rs_ID == wr_addr_EX)) || (use_rt && (rt_ID == wr_addr_EX)));

        // 2. Branch-Load-MEM Stall: Branch가 ID에 있고 LW가 MEM에 있을 때
        //    LW의 실제 데이터(mem_read_data)는 MEM stage 종료 후에야 얻을 수 있어
        //    branch comparator에 forwarding 불가 → 1 cycle stall 후 WB에서 RF internal fwd로 해결
        branch_load_MEM_stall = is_branch && MemRead_MEM && (wr_addr_MEM != 5'd0) &&
            ((rs_ID == wr_addr_MEM) || (rt_ID == wr_addr_MEM));

        stall = load_use_stall | branch_load_MEM_stall;

        // Stall 시 PC와 IF/ID 래치는 멈춤 (0)
        latchWriteID = ~stall;

        // ID/EX 래치는 Stall 시 NOP 주입을 위해 Flush
        flush_ID_EX = stall;
        latchWriteEX = !flush_ID_EX;

        // IF/ID Flush (Control Hazard)
        // Data Hazard로 인해 Stall 중일 경우 register 값이 정상적인 값이 아님
        // → stall이 아닐 때만 flush
        flush_IF_ID = mispredicted;
    end

endmodule