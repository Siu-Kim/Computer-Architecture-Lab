`timescale 1ns / 1ps
`include "GLOBAL.v"

module CPU(
	input		clk,
	input		rst,
	output 		halt
	);
	
	// Split the instructions
	// Instruction-related wires
	wire [31:0]		inst;
	wire [5:0]		opcode;
	wire [4:0]		rs;
	wire [4:0]		rt;
	wire [4:0]		rd;
	wire [4:0]		shamt;
	wire [5:0]		funct;
	wire [15:0]		immi;
	wire [25:0]		immj;

	// Control-related wires
	wire			MemRead;
	wire [1:0]		MemtoReg;
	wire			MemWrite;
	wire			SignExtend;
	wire [1:0] 		RegDst;
	wire			RegWrite;
	wire [3:0] 		ALUOp;
	wire 			ALUSrc;
	wire		 	PCSrc;
	wire [1:0]	 	PCSrcCtrl;

	// Control-pipeline-related wires
	wire			MemRead_EX, MemWrite_EX, RegWrite_EX;
	wire [1:0]		MemtoReg_EX, RegDst_EX;
	wire [3:0]		ALUOp_EX;
	wire 			ALUSrc_EX;

	wire			MemRead_MEM, MemWrite_MEM, RegWrite_MEM;
	wire [1:0]		MemtoReg_MEM;

	wire 			RegWrite_WB;
	wire [1:0]		MemtoReg_WB;

	// Sign extend the immediate
	wire [31:0]		ext_imm;
	wire [31:0]		ext_imm_EX;

	// RF-related wires
	wire [4:0]		rd_addr1;
	wire [4:0]		rd_addr2;
	wire [31:0]		rd_data1;
	wire [31:0]		rd_data2;
	reg [4:0]		wr_addr;
	reg [31:0]		wr_data;

	//RF-pipeline-related wire
	wire [31:0]		rd_data1_EX;
	wire [31:0]		rd_data2_EX;
	wire [4:0]		rt_EX;
	wire [4:0]		rd_EX;
	wire [4:0]		shamt_EX;
	reg [4:0]		wr_addr_EX;

	wire [31:0]		rd_data2_MEM;
	wire [4:0]		wr_addr_MEM;
	wire [4:0]		wr_addr_WB;
	
	// MEM-related wires
	wire [31:0]		inst_addr;
	wire [31:0]		mem_addr;
	wire [31:0]		mem_write_data;
	wire [31:0]		mem_read_data;
	wire [31:0]		mem_read_data_WB;

	// ALU-related wires
	reg [31:0]		operand1;
	reg [31:0]		operand2;
	wire [31:0]		alu_result;
	wire [31:0]		alu_result_MEM;
	wire [31:0]		alu_result_WB;

	// HAZARD-related wires
	wire 			latchWriteID;
	wire 			latchWriteEX;
	wire 			latchWriteMEM;
	wire 			latchWriteWB;
	wire			flush_IF_ID;
	wire			flush_ID_EX;

	//LATCH-related wires
	wire			flush;
	wire			latchWrite;
	wire [31:0]		inst_ID;
	wire [31:0]		inst_EX;
	wire [31:0]		inst_MEM;
	wire [31:0]		inst_WB;
	wire [31:0]		PC_seq_ID;
	wire [31:0]		PC_seq_EX;
	wire [31:0]		PC_seq_MEM;
	wire [31:0]		PC_seq_WB;

	//Forwarding Unit-related wires
	wire [4:0]		rs_EX = inst_EX[25:21];  // EX stage rs (inst_EX에서 추출)
	reg				fwd_A_MEM;
	reg				fwd_A_WB;
	reg				fwd_B_MEM;
	reg				fwd_B_WB;
	reg [31:0]		rt_fwd;
	// branch comparator forwarding: wire로 선언 (assign 기반 combinatorial)
	wire			fwd_branch_rs_EX;
	wire			fwd_branch_rs_MEM;
	wire			fwd_branch_rt_EX;
	wire			fwd_branch_rt_MEM;
	wire [31:0]		branch_data1;
	wire [31:0]		branch_data2;

	// Branch Predictor-related wires
	wire [31:0]		PC_pred;
	wire [31:0]		PC_pred_ID;
	wire			pred_taken;
	wire			update_valid;
	wire [31:0]		update_PC;
	reg [31:0]		actual_PC;


	// Define PC
	reg [31:0]	PC;
	wire [31:0] PC_seq = PC + 4;	
	
	// Define the wires
	//=========================== control op resolution/forwarding ===========================================//
	reg [31:0] target_addr; // control operation target
	wire PCWriteSrc; // control signal for mux combined PCSrc and branch_hit
	wire branch_hit; // branch taken signal for Branch (always 1 in J/JAL/JR)
	wire [31:0] comparator;
	wire [31:0] branch_imme = (ext_imm << 2);
	wire [31:0] jump_target = {PC_seq_ID[31:28], immj, 2'b00};
	wire is_jump = (opcode == `OP_J || opcode == `OP_JAL || 
		((opcode == `OP_RTYPE) && (funct == `FUNCT_JR)));
	wire is_branch = (opcode == `OP_BEQ) || (opcode == `OP_BNE);

	wire mispredicted = update_valid && (actual_PC != PC_pred_ID);
	assign update_PC = PC_seq_ID - 32'd4;
	assign update_valid = (is_branch || is_jump) && latchWriteID;

	// branch op forwarding: ID stage branch가 사용하는 rs, rt(branch condition)를 EX or MEM에서 forwarding
	// wr_addr_EX == rs -> EX stage inst가 branch src와 data dependency 여부 확인
	// !MemRead_EX -> LW에서는 alu_result가 address (load-use stall에서 처리)
	assign fwd_branch_rs_EX  = RegWrite_EX  && (wr_addr_EX  != 5'd0) && (wr_addr_EX  == rs) && !MemRead_EX;
	assign fwd_branch_rs_MEM = RegWrite_MEM && (wr_addr_MEM != 5'd0) && (wr_addr_MEM == rs) && !fwd_branch_rs_EX;
	assign fwd_branch_rt_EX  = RegWrite_EX  && (wr_addr_EX  != 5'd0) && (wr_addr_EX  == rt) && !MemRead_EX;
	assign fwd_branch_rt_MEM = RegWrite_MEM && (wr_addr_MEM != 5'd0) && (wr_addr_MEM == rt) && !fwd_branch_rt_EX;

	assign branch_data1 = fwd_branch_rs_EX  ? alu_result     :  // EX ALU 결과 (combinatorial)
	                      fwd_branch_rs_MEM  ? alu_result_MEM :  // MEM stage 결과 (latch)
	                                           rd_data1;          // RF 값 (internal fwd로 WB 처리됨)
	assign branch_data2 = fwd_branch_rt_EX  ? alu_result     :
	                      fwd_branch_rt_MEM  ? alu_result_MEM :
	                                           rd_data2;
	assign comparator = branch_data1 - branch_data2;

	assign ext_imm = SignExtend ? {{16{immi[15]}}, immi[15:0]} : {16'd0, immi[15:0]}; // sign-extender
	// branch가 아니면 taken = 1 | branch이면 beq/bne에 여부 & comparator 값에 따라 결정
	assign branch_hit = (opcode == 6'd4) ? (comparator == 32'd0) : (comparator != 32'd0);
	assign PCWriteSrc = (PCSrc) & (branch_hit || is_jump); 
	// branch가 아니면 PCSrc = 0이므로 PCWriteSrc = 0
	// branch이면 hit이면 1, miss면 0

	assign opcode = inst_ID[31:26];
	assign rs 	  = inst_ID[25:21];
	assign rt 	  = inst_ID[20:16];
	assign rd 	  = inst_ID[15:11];
	assign shamt  = inst_ID[10:6];
	assign funct  = inst_ID[5:0];
	assign immi	  = inst_ID[15:0];
	assign immj   = inst_ID[25:0];
	assign halt	  = (inst_WB == 32'b0);
	
	always @(*) begin

		//================================================ ALU/Forwarding Unit ===========================================//
		//forwarding logic
		// MEM stage → EX stage forwarding (EX-EX forwarding)
		fwd_A_MEM = RegWrite_MEM && (wr_addr_MEM != 5'd0) && (wr_addr_MEM == rs_EX);
		// WB stage → EX stage forwarding (MEM-EX forwarding), MEM 우선
		fwd_A_WB  = RegWrite_WB  && (wr_addr_WB  != 5'd0) && (wr_addr_WB  == rs_EX) && !fwd_A_MEM;
		fwd_B_MEM = RegWrite_MEM && (wr_addr_MEM != 5'd0) && (wr_addr_MEM == rt_EX);
		fwd_B_WB  = RegWrite_WB  && (wr_addr_WB  != 5'd0) && (wr_addr_WB  == rt_EX) && !fwd_B_MEM;

		operand1 = 	fwd_A_MEM ? alu_result_MEM :
				   	fwd_A_WB  ? wr_data 	   : 
				   			    rd_data1_EX;

		rt_fwd 	= 	fwd_B_MEM ? alu_result_MEM :
				 	fwd_B_WB  ? wr_data 	   : 
				   			    rd_data2_EX;

		//ALUSrcB - operand2 mux
		case(ALUSrc_EX)
			1'b0: begin
				operand2 = rt_fwd;
			end 
			1'b1: begin 
				operand2 = ext_imm_EX;
			end
			default: begin
				operand2 = 32'b0;
			end
		endcase
		
		//================================================ IF Unit ===========================================//

		// PCSrcCtrl signal mux for target_addr of control operation
		case(PCSrcCtrl)
			2'b00: target_addr = jump_target;
			2'b01: target_addr = rd_data1;
			2'b10: target_addr = PC_seq_ID + branch_imme;
			default: target_addr = 32'b0;
		endcase

		// PCWriteSrc signal mux for PC update
		case(PCWriteSrc)
			1'b0: actual_PC = PC_seq_ID;
			1'b1: actual_PC = target_addr;
		endcase
		
		//================================================ Register File ===========================================//

		//RegDst signal mux -> 0: rt / 1: rd / 2: $r31
		case(RegDst_EX)
			2'b00: begin
				wr_addr_EX = rt_EX;
			end
			2'b01: begin
				wr_addr_EX = rd_EX;
			end
			2'b10: begin
				wr_addr_EX = 5'd31;
			end
			default: wr_addr_EX = 5'd0;
		endcase
		
		//MemtoReg signal mux -> 0: ALUOut from latch / 1: Memory read data from latch
		case(MemtoReg_WB)
			2'b00: begin
				wr_data = alu_result_WB;
			end
			2'b01: begin
				wr_data = mem_read_data_WB;
			end
			2'b10: begin
				wr_data = PC_seq_WB;
			end
			default: wr_data = 32'b0;
		endcase
	end

	// write microarchitectural state (register)
	always @(posedge clk) begin
		if (rst) begin
			PC <= 0;
		end	
		else if(mispredicted) begin
			PC <= actual_PC;
		end
		else begin
			//PC update signal (stall 시 IF/ID latchWrite와 PC 모두 업데이트 X)
			if(latchWriteID == 1) begin
				PC <= PC_pred;
			end
		end
	end
	

	CTRL ctrl (
		.opcode(opcode),
		.funct(funct),
		.MemRead(MemRead),
		.MemtoReg(MemtoReg),
		.MemWrite(MemWrite),
		.SignExtend(SignExtend),
		.RegDst(RegDst),
		.RegWrite(RegWrite),
		.ALUOp(ALUOp),
		.ALUSrc(ALUSrc),
		.PCSrc(PCSrc),
		.PCSrcCtrl(PCSrcCtrl)
	);

	RF rf (.clk(clk),
		.rst(rst),
		.rd_addr1(rs),
		.rd_addr2(rt),
		.rd_data1(rd_data1),
		.rd_data2(rd_data2),
		.RegWrite(RegWrite_WB),
		.wr_addr(wr_addr_WB),
		.wr_data(wr_data)
	);

	MEM mem (
		.clk(clk),
		.rst(rst),
		.inst_addr(PC),
		.inst(inst),
		.mem_addr(alu_result_MEM),
		.MemWrite(MemWrite_MEM),
		.mem_write_data(rd_data2_MEM),
		.mem_read_data(mem_read_data)
	);
	
	ALU alu (
		.operand1(operand1),
		.operand2(operand2),
		.shamt(shamt_EX),
		.funct(ALUOp_EX),
		.alu_result(alu_result)
	);

	HAZARD hazard(
		.inst_ID(inst_ID),
		.is_branch(is_branch),
		.mispredicted(mispredicted),
		.wr_addr_EX(wr_addr_EX),
		.MemRead_EX(MemRead_EX),
		.RegWrite_EX(RegWrite_EX),
		.wr_addr_MEM(wr_addr_MEM),
		.MemRead_MEM(MemRead_MEM),
		.RegWrite_MEM(RegWrite_MEM),
		.flush_IF_ID(flush_IF_ID),
		.flush_ID_EX(flush_ID_EX),
		.latchWriteID(latchWriteID),
		.latchWriteEX(latchWriteEX),
		.latchWriteMEM(latchWriteMEM),
		.latchWriteWB(latchWriteWB)
	);

	//파이프라인 래치 인스턴스
	IF_ID_LATCH latchID(
		.clk(clk),
		.rst(rst),
		.flush(flush_IF_ID),
		.latchWrite(latchWriteID),
		.PC_seq(PC_seq),
		.PC_pred(PC_pred),
		.inst(inst),
		.inst_ID(inst_ID),
		.PC_seq_ID(PC_seq_ID),
		.PC_pred_ID(PC_pred_ID)
	);

	ID_EX_LATCH latchEX(
		.clk(clk),
		.rst(rst),
		.flush(flush_ID_EX),
		.latchWrite(latchWriteEX),
		.inst_ID(inst_ID),
		.rd_data1(rd_data1),
		.rd_data2(rd_data2),
		.ALUOp(ALUOp),
		.ALUSrc(ALUSrc),
		.RegDst(RegDst),
		.ext_imm(ext_imm),
		.rt(rt),
		.rd(rd),
		.shamt(shamt),
		.MemWrite(MemWrite),
		.MemRead(MemRead),
		.MemtoReg(MemtoReg),
		.RegWrite(RegWrite),
		.rd_data1_EX(rd_data1_EX),
		.rd_data2_EX(rd_data2_EX),
		.ALUOp_EX(ALUOp_EX),
		.ALUSrc_EX(ALUSrc_EX),
		.RegDst_EX(RegDst_EX),
		.ext_imm_EX(ext_imm_EX),
		.rt_EX(rt_EX),
		.rd_EX(rd_EX),
		.shamt_EX(shamt_EX),
		.MemWrite_EX(MemWrite_EX),
		.MemRead_EX(MemRead_EX),
		.MemtoReg_EX(MemtoReg_EX),
		.RegWrite_EX(RegWrite_EX),
		.PC_seq_ID(PC_seq_ID),
		.PC_seq_EX(PC_seq_EX),
		.inst_EX(inst_EX)
	);

	EX_MEM_LATCH latchMEM(
		.clk(clk),
		.rst(rst),
		.latchWrite(latchWriteMEM),
		.inst_EX(inst_EX),
		.alu_result(alu_result),
		.rd_data2_EX(rt_fwd),
		.wr_addr_EX(wr_addr_EX),
		.MemWrite_EX(MemWrite_EX),
		.MemRead_EX(MemRead_EX),
		.MemtoReg_EX(MemtoReg_EX),
		.RegWrite_EX(RegWrite_EX),
		.alu_result_MEM(alu_result_MEM),
		.rd_data2_MEM(rd_data2_MEM),
		.wr_addr_MEM(wr_addr_MEM),
		.MemWrite_MEM(MemWrite_MEM),
		.MemRead_MEM(MemRead_MEM),
		.MemtoReg_MEM(MemtoReg_MEM),
		.RegWrite_MEM(RegWrite_MEM),
		.PC_seq_EX(PC_seq_EX),
		.PC_seq_MEM(PC_seq_MEM),
		.inst_MEM(inst_MEM)
	);

	MEM_WB_LATCH latchWB(
		.clk(clk),
		.rst(rst),
		.latchWrite(latchWriteWB),
		.inst_MEM(inst_MEM),
		.mem_read_data(mem_read_data),
		.alu_result_MEM(alu_result_MEM),
		.wr_addr_MEM(wr_addr_MEM),
		.MemtoReg_MEM(MemtoReg_MEM),
		.RegWrite_MEM(RegWrite_MEM),
		.mem_read_data_WB(mem_read_data_WB),
		.alu_result_WB(alu_result_WB),
		.wr_addr_WB(wr_addr_WB),
		.MemtoReg_WB(MemtoReg_WB),
		.RegWrite_WB(RegWrite_WB),
		.PC_seq_MEM(PC_seq_MEM),
		.PC_seq_WB(PC_seq_WB),
		.inst_WB(inst_WB)
	);

	BP bp(
		.clk(clk),
		.rst(rst),
		.PC(PC),
		.PC_pred(PC_pred),
		.pred_taken(pred_taken),
		.update_valid(update_valid),
		.update_PC(update_PC),
		.actual_PC(target_addr),
		.actual_taken(PCWriteSrc)
	);

endmodule

module IF_ID_LATCH(
	input 				clk,
	input				rst,
	input				flush,
	input				latchWrite,

	input [31:0]		PC_seq,
	input [31:0]		inst,
	input [31:0]		PC_pred,

	output reg [31:0]	inst_ID,
	output reg [31:0]	PC_seq_ID,
	output reg [31:0]	PC_pred_ID
	);
	always @(posedge clk) begin
		if(rst || flush) begin
			inst_ID <= `NOP; // halt와 구분되는 NOP
			PC_seq_ID <= 32'b0;
			PC_pred_ID <= 32'b0;
		end
		else if(latchWrite) begin
			PC_seq_ID <= PC_seq;
			inst_ID <= inst;
			PC_pred_ID <= PC_pred;
		end
	end
endmodule

module ID_EX_LATCH(
	input 				clk,
	input				rst,
	input 				flush,
	input				latchWrite,
	input [31:0]		inst_ID,

	input [31:0]		rd_data1,
	input [31:0]		rd_data2,
	input [3:0]			ALUOp,
	input 				ALUSrc,
	input [1:0]			RegDst,
	input [31:0]		ext_imm,
	input [4:0]			rt,
	input [4:0]			rd,	
	input [4:0]			shamt,

	input [31:0]		PC_seq_ID,
	
	// control signal for next stage
	input				MemWrite,
	input				MemRead,
	input [1:0]			MemtoReg,
	input 				RegWrite,

	output reg [31:0]	rd_data1_EX,
	output reg [31:0]	rd_data2_EX,

	output reg [3:0]	ALUOp_EX,
	output reg 			ALUSrc_EX,
	output reg [1:0]	MemtoReg_EX,
	output reg [1:0]	RegDst_EX,

	output reg [31:0]	ext_imm_EX,
	output reg [4:0]	rt_EX,
	output reg [4:0]	rd_EX,
	output reg [4:0]	shamt_EX,

	// control signal for next stage
	output reg 			MemWrite_EX,
	output reg			MemRead_EX,
	output reg 			RegWrite_EX,
	output reg [31:0]	PC_seq_EX,
	output reg [31:0]	inst_EX
	);

	always @(posedge clk) begin
		if(rst || flush) begin
			rd_data1_EX <= 0;
			rd_data2_EX <= 0;
			ALUOp_EX <= 0;
			ALUSrc_EX <= 0;
			RegDst_EX <= 0;
			ext_imm_EX <= 0;
			rt_EX <= 0;
			rd_EX <= 0;
			shamt_EX <= 0;
			MemWrite_EX <= 0;
			MemRead_EX <= 0;
			MemtoReg_EX <= 0;
			RegWrite_EX <= 0;
			PC_seq_EX <= 0;
			inst_EX <= `NOP;
		end
		else if(latchWrite) begin
			rd_data1_EX <= rd_data1;
			rd_data2_EX <= rd_data2;
			ALUOp_EX <= ALUOp;
			ALUSrc_EX <= ALUSrc;
			RegDst_EX <= RegDst;
			ext_imm_EX <= ext_imm;
			rt_EX <= rt;
			rd_EX <= rd;
			shamt_EX <= shamt;
			MemWrite_EX <= MemWrite;
			MemRead_EX <= MemRead;
			MemtoReg_EX <= MemtoReg;
			RegWrite_EX <= RegWrite;
			PC_seq_EX <= PC_seq_ID;
			inst_EX <= inst_ID;
		end
	end
endmodule

module EX_MEM_LATCH(
	input 				clk,
	input				rst,
	input				latchWrite,
	input [31:0]		inst_EX,

	input [31:0]		alu_result,
	input [31:0]		rd_data2_EX,
	input [4:0]			wr_addr_EX,
	input				MemWrite_EX,
	input				MemRead_EX,

	// control signal for next stage
	input [1:0]			MemtoReg_EX,
	input 				RegWrite_EX,
	input [31:0]		PC_seq_EX,

	output reg [31:0]	alu_result_MEM,
	output reg [31:0]	rd_data2_MEM,
	output reg [4:0]	wr_addr_MEM,

	output reg 			MemWrite_MEM,
	output reg			MemRead_MEM,

	// control signal for next stage
	output reg [1:0]	MemtoReg_MEM,
	output reg 			RegWrite_MEM,
	output reg [31:0]	PC_seq_MEM,
	output reg [31:0]   inst_MEM
	);
	always @(posedge clk) begin
		if(rst) begin
			MemtoReg_MEM <= 0;
			RegWrite_MEM <= 0;
			alu_result_MEM <= 0;
			rd_data2_MEM <= 0;
			wr_addr_MEM <= 0;
			MemWrite_MEM <= 0;
			MemRead_MEM <= 0;
			PC_seq_MEM <= 0;
			inst_MEM <= `NOP;
		end
		else if(latchWrite) begin
			MemtoReg_MEM <= MemtoReg_EX;
			RegWrite_MEM <= RegWrite_EX;
			
			alu_result_MEM <= alu_result;
			rd_data2_MEM <= rd_data2_EX;
			wr_addr_MEM <= wr_addr_EX;

			MemWrite_MEM <= MemWrite_EX;
			MemRead_MEM <= MemRead_EX;
			PC_seq_MEM <= PC_seq_EX;
			inst_MEM <= inst_EX;
		end
	end
endmodule

module MEM_WB_LATCH(
	input 				clk,
	input				rst,
	input				latchWrite,
	input [31:0]		inst_MEM,

	input [31:0]		mem_read_data,
	input [31:0]		alu_result_MEM,
	input [4:0]			wr_addr_MEM,

	input [1:0]			MemtoReg_MEM,
	input 				RegWrite_MEM,
	input [31:0]		PC_seq_MEM,

	output reg [31:0]	mem_read_data_WB,
	output reg [31:0]	alu_result_WB,
	output reg [4:0]	wr_addr_WB,
	output reg [1:0]	MemtoReg_WB,
	output reg 			RegWrite_WB,
	output reg [31:0]	PC_seq_WB,
	output reg [31:0]   inst_WB
	);
	always @(posedge clk) begin
		if(rst) begin
			MemtoReg_WB <= 0;
			RegWrite_WB <= 0;
			mem_read_data_WB <= 0;
			alu_result_WB <= 0;
			wr_addr_WB <= 0;
			PC_seq_WB <= 0;
			inst_WB <= `NOP;
		end
		else if(latchWrite) begin
			MemtoReg_WB <= MemtoReg_MEM;
			RegWrite_WB <= RegWrite_MEM;
			mem_read_data_WB <= mem_read_data;
			alu_result_WB <= alu_result_MEM;
			wr_addr_WB <= wr_addr_MEM;
			PC_seq_WB <= PC_seq_MEM;
			inst_WB <= inst_MEM;
		end
	end
endmodule