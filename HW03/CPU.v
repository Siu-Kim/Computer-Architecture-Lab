`timescale 1ns / 1ps


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
	wire			RegDst;
	wire			Jump;
	wire 			Branch;
	wire 			JR;
	wire			MemRead;
	wire			MemtoReg;
	wire 			MemWrite;
	wire			ALUSrc;
	wire			SignExtend;
	wire			RegWrite;
	wire [3:0]		ALUOp;
	wire			SavePC;

	// Sign extend the immediate
	wire [31:0]		ext_imm;

	// RF-related wires
	wire [4:0]		rd_addr1;
	wire [4:0]		rd_addr2;
	wire [31:0]		rd_data1;
	wire [31:0]		rd_data2;
	reg [4:0]		wr_addr;
	reg [31:0]		wr_data;

	// MEM-related wires
	wire [31:0]		mem_addr;
	wire [31:0]		mem_write_data;
	wire [31:0]		mem_read_data;

	// ALU-related wires
	wire [31:0]		operand1;
	wire [31:0]		operand2;
	wire [31:0]		alu_result;

	// Define PC
	reg [31:0]	PC;
	reg [31:0]	PC_next;

	// Define the wires
	wire alu_zero; // alu_zero wire for Branch mux signal
	wire [31:0] pc_plus_4 = PC + 4;
	wire [31:0] branch_target = pc_plus_4 + (ext_imm << 2);
	wire [31:0] jump_target = {pc_plus_4[31:28], immj, 2'b00};

	assign opcode = inst[31:26];
	assign rs 	  = inst[25:21];
	assign rt 	  = inst[20:16];
	assign rd 	  = inst[15:11];
	assign shamt  = inst[10:6];
	assign funct  = inst[5:0];
	assign immi	  = inst[15:0];
	assign immj   = inst[25:0];

	assign halt				= (inst == 32'b0);

	assign ext_imm = SignExtend ? {{16{immi[15]}}, immi[15:0]} : 32'd0; // sign-extender
	assign operand1 = rd_data1;
	assign operand2 = ALUSrc ? ext_imm : rd_data2; // ALUSrc mux
	//beq - condition taken, alu_result == 0, wire = 1 / not taken, alu_result != 0, wire = 0 
	assign alu_zero = (opcode == `OP_BEQ) ? (alu_result == 32'd0) : (alu_result != 32'd0);

	always @(*) begin
		//register write address를 위한 두 mux 정의 (SavePC mux for jal, RegDst mux for R-type, I-type inst)
		wr_addr = SavePC ? 5'd31 : (RegDst ? rd : rt);
		//register write data를 위한 두 mux 정의(SavePC mux for jal, MemtoReg mux for mem logic)
		wr_data = SavePC ? pc_plus_4 : (MemtoReg ? mem_read_data : alu_result);

		// JR / Jump / Branch inst mux for setting the PC_next
		if(JR)
			PC_next = rd_data1;
		else if(Jump)
			PC_next = jump_target;
		else if(Branch & alu_zero)
			PC_next = branch_target;
		else
			PC_next = pc_plus_4;
	end


	// Update the Clock
	always @(posedge clk) begin
		if (rst)	PC <= 0;
		else begin
			PC <= PC_next;
		end
	end
	

	CTRL ctrl (.opcode(opcode),
		.funct(funct),
		.RegDst(RegDst),
		.Jump(Jump),
		.Branch(Branch),
		.JR(JR),
		.MemRead(MemRead),
		.MemtoReg(MemtoReg),
		.MemWrite(MemWrite),
		.ALUSrc(ALUSrc),
		.SignExtend(SignExtend),
		.RegWrite(RegWrite),
		.ALUOp(ALUOp),
		.SavePC(SavePC)
		);

	RF rf (.clk(clk),
		.rst(rst),
		.rd_addr1(rs),
		.rd_addr2(rt),
		.rd_data1(rd_data1),
		.rd_data2(rd_data2),
		.RegWrite(RegWrite),
		.wr_addr(wr_addr),
		.wr_data(wr_data)
	);

	MEM mem (
		.clk(clk),
		.rst(rst),
		.inst_addr(PC),
		.inst(inst),
		.mem_addr(alu_result),
		.MemWrite(MemWrite),
		.mem_write_data(rd_data2),
		.mem_read_data(mem_read_data)
	);
	
	ALU alu (
		.operand1(operand1),
		.operand2(operand2),
		.shamt(shamt),
		.funct(ALUOp),
		.alu_result(alu_result)
	);
	
endmodule
