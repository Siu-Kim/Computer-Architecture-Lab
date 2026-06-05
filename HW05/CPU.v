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
	wire [31:0]		PC_next_ID;
	wire [31:0]		PC_next_EX;
	wire [31:0]		PC_next_MEM;
	wire [31:0]		PC_next_WB;

	// Define PC
	reg [31:0]	PC;
	reg [31:0]	PC_next;
	
	// Define the wires
	reg [31:0] target_addr; // control operation target
	wire PCWriteSrc; // control signal for mux combined PCSrc and branch_hit
	wire branch_hit; // branch taken signal for Branch (always 1 in J/JAL/JR)
	wire [31:0] comparator;
	wire [31:0] branch_imme = (ext_imm << 2);
	wire [31:0] jump_target = {PC_next_ID[31:28], immj, 2'b00};
	wire is_jump = (opcode == `OP_J || opcode == `OP_JAL || 
		((opcode == `OP_RTYPE) && (funct == `FUNCT_JR)));

	assign ext_imm = SignExtend ? {{16{immi[15]}}, immi[15:0]} : {16'd0, immi[15:0]}; // sign-extender
	assign comparator = (rd_data1 - rd_data2);
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
		operand1 = rd_data1_EX;
		//ALUSrcB - operand2 mux
		case(ALUSrc_EX)
			1'b0: begin
				operand2 = rd_data2_EX;
			end 
			1'b1: begin 
				operand2 = ext_imm_EX;
			end
			default: begin
				operand2 = 32'b0;
			end
		endcase

		// PCSrcCtrl signal mux for target_addr of control operation
		case(PCSrcCtrl)
			2'b00: target_addr = jump_target;
			2'b01: target_addr = rd_data1;
			2'b10: target_addr = PC_next_ID + branch_imme;
		endcase

		// PCWriteSrc signal mux for PC update
		case(PCWriteSrc)
			1'b0: PC_next = PC + 4;
			1'b1: PC_next = target_addr;
		endcase
		
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
				wr_data = PC_next_WB;
			end
		endcase
	end

	// Update the Clock & move to next state of FSM(multicycle)
	// write microarchitectural state (register)
	always @(posedge clk) begin
		if (rst) begin
			PC <= 0;
		end	
		else begin
			//PC update signal (stall 시 IF/ID latchWrite와 PC 모두 업데이트 X)
			if(latchWriteID == 1) begin
				PC <= PC_next;
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
		.branch_taken(PCWriteSrc),
		.is_jump(is_jump),
		.wr_addr_EX(wr_addr_EX),
		.RegWrite_EX(RegWrite_EX),
		.wr_addr_MEM(wr_addr_MEM),
		.RegWrite_MEM(RegWrite_MEM),
		.wr_addr_WB(wr_addr_WB),
		.RegWrite_WB(RegWrite_WB),
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
		.PC_next(PC_next),
		.inst(inst),
		.inst_ID(inst_ID),
		.PC_next_ID(PC_next_ID)
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
		.PC_next_EX(PC_next_EX),
		.inst_EX(inst_EX)
	);

	EX_MEM_LATCH latchMEM(
		.clk(clk),
		.rst(rst),
		.latchWrite(latchWriteMEM),
		.inst_EX(inst_EX),
		.alu_result(alu_result),
		.rd_data2_EX(rd_data2_EX),
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
		.PC_next_MEM(PC_next_MEM),
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
		.PC_next_WB(PC_next_WB),
		.inst_WB(inst_WB)
	);

endmodule

module IF_ID_LATCH(
	input 				clk,
	input				rst,
	input				flush,
	input				latchWrite,

	input [31:0]		PC_next,
	input [31:0]		inst,

	output reg [31:0]	inst_ID,
	output reg [31:0]	PC_next_ID
	);
	always @(posedge clk) begin
		if(rst || flush) begin
			inst_ID <= `NOP; // halt와 구분되는 NOP
			PC_next_ID <= 32'b0;
		end
		else if(latchWrite) begin
			PC_next_ID <= PC_next;
			inst_ID <= inst;
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

	input [31:0]		PC_next_ID,
	
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
	output reg [31:0]	PC_next_EX,
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
			PC_next_EX <= 0;
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
			PC_next_EX <= PC_next_ID;
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
	input [31:0]		PC_next_EX,

	output reg [31:0]	alu_result_MEM,
	output reg [31:0]	rd_data2_MEM,
	output reg [4:0]	wr_addr_MEM,

	output reg 			MemWrite_MEM,
	output reg			MemRead_MEM,

	// control signal for next stage
	output reg [1:0]	MemtoReg_MEM,
	output reg 			RegWrite_MEM,
	output reg [31:0]	PC_next_MEM,
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
			PC_next_MEM <= 0;
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
			PC_next_MEM <= PC_next_EX;
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
	input [31:0]		PC_next_MEM,

	output reg [31:0]	mem_read_data_WB,
	output reg [31:0]	alu_result_WB,
	output reg [4:0]	wr_addr_WB,
	output reg [1:0]	MemtoReg_WB,
	output reg 			RegWrite_WB,
	output reg [31:0]	PC_next_WB,
	output reg [31:0]   inst_WB
	);
	always @(posedge clk) begin
		if(rst) begin
			MemtoReg_WB <= 0;
			RegWrite_WB <= 0;
			mem_read_data_WB <= 0;
			alu_result_WB <= 0;
			wr_addr_WB <= 0;
			PC_next_WB <= 0;
			inst_WB <= `NOP;
		end
		else if(latchWrite) begin
			MemtoReg_WB <= MemtoReg_MEM;
			RegWrite_WB <= RegWrite_MEM;
			mem_read_data_WB <= mem_read_data;
			alu_result_WB <= alu_result_MEM;
			wr_addr_WB <= wr_addr_MEM;
			PC_next_WB <= PC_next_MEM;
			inst_WB <= inst_MEM;
		end
	end
endmodule