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
					`FUNCT_SLL: begin 
						ALUOp = 4'b0100;
					end
					`FUNCT_SRL: begin 
						ALUOp = 4'b0110;
					end
					`FUNCT_SRA: begin 
						ALUOp = 4'b0101;
					end
					`FUNCT_JR : begin 
						JR = 1'b1;
						RegWrite = 1'b0; 
						RegDst = 1'b0; 
						ALUSrc = 1'b0;
					end
					`FUNCT_ADDU: begin 
						ALUOp = 4'b0000;
					end
					`FUNCT_SUBU: begin 
						ALUOp = 4'b0111;
					end
					`FUNCT_AND: begin 
						ALUOp = 4'b0001;
					end
					`FUNCT_OR: begin 
						ALUOp = 4'b0011;
					end
					`FUNCT_XOR: begin 
						ALUOp = 4'b1000;
					end
					`FUNCT_NOR: begin 
						ALUOp = 4'b0010;
					end 
					`FUNCT_SLT: begin 
						ALUOp = 4'b1001;
					end
					`FUNCT_SLTU: begin 
						ALUOp = 4'b1010;
					end
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
			end

			`OP_ORI: begin
				RegWrite = 1'b1;
				ALUSrc = 1'b1;
				ALUOp = 4'b0011;
			end
			`OP_XORI: begin
				RegWrite = 1'b1;
				ALUSrc = 1'b1;
				ALUOp = 4'b1000;
			end

			`OP_LUI: begin
				RegWrite = 1'b1;
				ALUSrc = 1'b1;
				ALUOp = 4'b1101;
			end

			//memory access
			`OP_LW: begin 
				MemRead = 1'b1;
				MemtoReg = 1'b1;
				RegWrite = 1'b1;
				ALUSrc = 1'b1;
				ALUOp = `ALU_ADDU;
				SignExtend = 1'b1;
			end
			//memory access
			`OP_SW: begin 
				MemWrite = 1'b1;
				ALUSrc = 1'b1;
				ALUOp = `ALU_ADDU;
				SignExtend = 1'b1;
			end
		endcase
	end
endmodule


