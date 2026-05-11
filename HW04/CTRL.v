`timescale 1ns / 1ps
`include "GLOBAL.v"

module CTRL(
	// input opcode and funct
	input [5:0] opcode,
	input [5:0] funct,
	input [2:0] CurrState,

	// output various ports
	output reg [1:0] RegDst,
	output reg MemRead,
	output reg [1:0] MemtoReg,
	output reg MemWrite,
	output reg SignExtend,
	output reg RegWrite,
	output reg [3:0] ALUOp,
	output reg PCWrite,
	output reg PCWriteCond,
	output reg IorD,
	output reg ALUSrcA,
	output reg [1:0] ALUSrcB,
	output reg [1:0] PCSource,
	output reg IRWrite,
	output reg InstDone,
	output reg [2:0] NextState
    );


	`define		IF		3'b000
	`define		ID		3'b001
	`define		EX		3'b010
	`define		MEM		3'b011
	`define		WB		3'b100

	always @(*) begin
		// FIXME
		RegDst = 0; MemRead = 0; MemtoReg = 2'b00; MemWrite = 0; SignExtend = 0; RegWrite = 0;
		ALUOp = 4'bxxxx; PCWrite = 0; PCWriteCond = 0; IorD = 0; ALUSrcA = 0; ALUSrcB = 0;
		PCSource = 0; IRWrite = 0; InstDone = 0; NextState = 0;

		case(CurrState)
			//IF stage -> 모든 instruction 공통 실행
			`IF: begin
				PCWrite = 1'b1;
				PCSource = 2'b00;
				ALUSrcA = 1'b0;
				ALUSrcB = 2'b01;
				IorD = 0;
				MemRead = 1;
				MemWrite = 0;
				IRWrite = 1;
				ALUOp = `ALU_ADDU;
				NextState = `ID;
			end
			`ID: begin
				RegDst = 0;

				case(opcode)
					`OP_J: begin
						InstDone = 1;
						PCWrite = 1;
						PCSource = 2'b10;
					end
					`OP_RTYPE: begin
						if(funct == `FUNCT_JR) begin
							PCWrite = 1;
							PCSource = 2'b11;
							InstDone = 1;
						end
						else begin
							NextState = `EX;
						end
					end
					`OP_BEQ, `OP_BNE: begin
						ALUSrcA = 1'b0;
						ALUSrcB = 2'b11;
						SignExtend = 1;
						NextState = `EX;
						ALUOp = `ALU_ADDU;
					end
					default: begin
						NextState = `EX;
					end
				endcase
			end
			`EX: begin
				ALUSrcA = 1'b1;
				ALUSrcB = 2'b10;
				SignExtend = 1;
				NextState = `WB;

				case(opcode)
					//R-type 
					`OP_RTYPE: begin
						ALUSrcB = 2'b00;
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

					//I-type Control / J-type
					`OP_BEQ, `OP_BNE: begin
						PCWriteCond = 1;
						PCSource = 1;
						InstDone = 1;
						ALUOp = `ALU_SUBU;
						ALUSrcA = 1'b1; //EX stage에서는 branch condition 계산
						ALUSrcB = 2'b00;
						SignExtend = 1;
					end
					`OP_JAL: begin
						PCWrite = 1;
						PCSource = 2;
						NextState = `WB;
					end
					// I-type MEM
					`OP_LW, `OP_SW: begin
						ALUOp = `ALU_ADDU;
						NextState = `MEM;
						SignExtend = 1;
					end

					// I-type ALU
					`OP_ADDIU: begin
						ALUOp = `ALU_ADDU;
						SignExtend = 1;
					end
					`OP_SLTI: begin
						ALUOp = `ALU_SLT;		
						SignExtend = 1;					
					end
					`OP_SLTIU: begin
						ALUOp = `ALU_SLTU;
						SignExtend = 1;
					end
					`OP_ANDI: begin
						ALUOp = `ALU_AND;
						SignExtend = 0;
					end
					`OP_ORI: begin
						ALUOp = `ALU_OR;
						SignExtend = 0;
					end
					`OP_XORI: begin
						ALUOp = `ALU_XOR;
						SignExtend = 0;
					end
					`OP_LUI: begin
						ALUOp = `ALU_LUI;
						SignExtend = 0; // don't care
					end
				endcase
			end
			`MEM: begin
				IorD = 1;

				if(opcode == `OP_SW) begin
					InstDone = 1;
					MemWrite = 1;

				end
				else begin
					MemRead = 1;
					NextState = `WB;
				end
			end
			`WB: begin
				RegWrite = 1;
				InstDone = 1;

				case(opcode)
					`OP_JAL: begin
						RegDst = 2'b10;
						MemtoReg = 2'b10;
					end
					`OP_LW: begin
						MemtoReg = 2'b01;
					end
					`OP_RTYPE: begin
						RegDst = 2'b01;
						MemtoReg = 2'b00;
					end
					default: begin
						RegDst = 2'b00;
						MemtoReg = 2'b00;
					end
				endcase
			end
		endcase
	end
endmodule


