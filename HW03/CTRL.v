`timescale 1ns / 1ps
`include "GLOBAL.v"

module CTRL(
	// input opcode and funct
	input [5:0] opcode,
	input [5:0] funct,

	// output various ports
	output reg RegDst,
	output reg Jump,
	output reg Branch,
	output reg JR,
	output reg MemRead,
	output reg MemtoReg,
	output reg MemWrite,
	output reg ALUSrc,
	output reg SignExtend,
	output reg RegWrite,
	output reg [3:0] ALUOp,
	output reg SavePC
    );

	always @(*) begin
		// FIXME
		RegDst = 0; Jump = 0; Branch = 0; JR = 0; MemRead = 0; 
		MemtoReg = 0; MemWrite = 0; ALUSrc = 0; SignExtend = 0;
		RegWrite = 0; SavePC = 0; ALUOp = 4'bxxxx;

		case(opcode)
			`OP_RTYPE: begin
				RegWrite = 1'b1;
				RegDst = 1'b1;
				ALUSrc = 1'b0;
				
				case(funct)
					`FUNCT_SLL: ALUOp = 4'b0100;
					`FUNCT_SRL: ALUOp = 4'b0110;
					`FUNCT_SRA: ALUOp = 4'b0101;
					`FUNCT_JR: JR = 1'b1; RegWrite = 0; RegDst = 0; ALUSrc = 0;
					`FUNCT_ADDU: ALUOp = 4'b0000;
					`FUNCT_SUBU: ALUOp = 4'b0111;
					`FUNCT_AND: ALUOp = 4'b0001;
					`FUNCT_OR: ALUOp = 4'b0011;
					`FUNCT_XOR: ALUOp = 4'b1000;
					`FUNCT_NOR: ALUOp = 4'b0010;
					`FUNCT_SLT: ALUOp = 4'b1001;
					`FUNCT_SLTU: ALUOp = 4'b1010;
				endcase
			end 

			`OP_J: begin
				Jump = 1'b1;
			end

			`OP_JAL: begin
				SavePC = 1'b1;
				RegWrite = 1'b1;
				Jump = 1'b1;
			end

			`OP_BEQ: begin
				Branch = 1'b1;
				ALUOp = 4'b0111;
				SignExtend = 1'b1;
			end

			`OP_BNE: begin
				Branch = 1'b1;
				ALUOp = 4'b0111;
				SignExtend = 1'b1;

			end

			`OP_ADDIU: begin
				RegWrite = 1'b1;
				ALUSrc = 1'b1;
				ALUOp = 4'b0000;
				SignExtend = 1'b1;
			end

			`OP_SLTI: begin
				RegWrite = 1'b1;
				ALUSrc = 1'b1;
				ALUOp = 4'b1001;
				SignExtend = 1'b1;
			end

			`OP_SLTIU: begin
				RegWrite = 1'b1;
				ALUSrc = 1'b1;
				ALUOp = 4'b1010;
				SignExtend = 1'b1;
			end

			`OP_ANDI: begin
				RegWrite = 1'b1;
				ALUSrc = 1'b1;
				ALUOp = 4'b0001;
				SignExtend = 1'b1;
			end

			`OP_ORI: begin
				RegWrite = 1'b1;
				ALUSrc = 1'b1;
				ALUOp = 4'b0011;
				SignExtend = 1'b1;
			end
			`OP_XORI: begin
				RegWrite = 1'b1;
				ALUSrc = 1'b1;
				ALUOp = 4'b1000;
				SignExtend = 1'b1;
			end

			`OP_LUI: begin
				RegWrite = 1'b1;
				ALUSrc = 1'b1;
				ALUOp = 4'b1101;
				SignExtend = 1'b1;
			end

			//memory access
			`OP_LW: begin 
				MemRead = 1'b1;
				MemtoReg = 1'b1;
				RegWrite = 1'b1;
				ALUSrc = 1'b1;
				ALUOp = `ALU_ADDU;
				signExtend = 1'b1;
			end
			//memory access
			`OP_SW: begin 
				MemWrite = 1'b1;
				ALUSrc = 1'b1;
				ALUOp = `ALU_ADDU;
				signExtend = 1'b1;
			end
		endcase
	end
endmodule


