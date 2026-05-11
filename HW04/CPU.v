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
	wire [1:0]		RegDst;
	wire			MemRead;
	wire [1:0]		MemtoReg;
	wire 			MemWrite;
	wire			SignExtend;
	wire			RegWrite;
	wire [3:0]		ALUOp;
	wire 			PCWrite;
	wire 			PCWriteCond;
	wire 			IorD;
	wire 			ALUSrcA;
	wire [1:0]		ALUSrcB;
	wire [1:0]		PCSource;
	wire 			IRWrite;
	wire 			InstDone;
	wire [2:0]	 	NextState;
	reg  [2:0]		CurrState;

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
	reg [31:0]		operand1;
	reg [31:0]		operand2;
	wire [31:0]		alu_result;

	// Define PC
	reg [31:0]	PC;
	reg [31:0]	PC_next;

	// Define Microarchitecture register
	reg  [31:0]		mem_data_reg;
	reg  [31:0]		IR;
	reg  [31:0]		alu_out;
	reg  [31:0]		rd_dataA;
	reg  [31:0]		rd_dataB;
	reg  [31:0]		npc_reg;
	
	// Define the wires
	wire alu_zero; // alu_zero wire for Branch (PCWriteCond signal and-gate)
	wire [31:0] branch_imme = (ext_imm << 2);
	wire [31:0] jump_target = {PC[31:28], immj, 2'b00};
	assign ext_imm = SignExtend ? {{16{immi[15]}}, immi[15:0]} : {16'd0, immi[15:0]}; // sign-extender
	assign alu_zero = (opcode == 6'd4) ? (alu_result == 32'd0) : (alu_result != 32'd0);
	
	assign inst	  = IR;
	assign opcode = inst[31:26];
	assign rs 	  = inst[25:21];
	assign rt 	  = inst[20:16];
	assign rd 	  = inst[15:11];
	assign shamt  = inst[10:6];
	assign funct  = inst[5:0];
	assign immi	  = inst[15:0];
	assign immj   = inst[25:0];
	assign halt	  = (inst == 32'b0);

	//IorD signal mux 
	assign mem_addr = (IorD) ? alu_out : PC;
	
	always @(*) begin
		//ALUSrcA - operand1 mux
		operand1 = ALUSrcA ? rd_dataA : PC;
		//ALUSrcB - operand2 mux
		case(ALUSrcB)
			2'b00: begin
				operand2 = rd_dataB;
			end 
			2'b01: begin 
				operand2 = 4;
			end
			2'b10: begin
				operand2 = ext_imm;
			end
			2'b11: begin
				operand2 = branch_imme;
			end
		endcase

		//PCSource signal mux for PC update
		case(PCSource)
			2'b00: PC_next = alu_result;
			2'b01: PC_next = alu_out;
			2'b10: PC_next = jump_target;
			2'b11: PC_next = rd_data1;
		endcase
		
		//RegDst signal mux -> 0: rt / 1: rd / 2: $r31
		case(RegDst)
			2'b00: begin
				wr_addr = rt;
			end
			2'b01: begin
				wr_addr = rd;
			end
			2'b10: begin
				wr_addr = 5'd31;
			end
		endcase
		
		//MemtoReg signal mux -> 0: ALUOut / 1: MDR / 2: PC(for jal)
		case(MemtoReg)
			2'b00: begin
				wr_data = alu_out;
			end
			2'b01: begin
				wr_data = mem_data_reg;
			end
			2'b10: begin
				wr_data = npc_reg;
			end
		endcase
	end

	// Update the Clock & move to next state of FSM(multicycle)
	// write microarchitectural state (register)
	always @(posedge clk) begin
		if (rst) begin
			PC <= 0;
			CurrState = 0;
			IR <= 0;
			mem_data_reg <= 0;
			rd_dataA <= 0;
			rd_dataB <= 0;
			alu_out <= 0;
			npc_reg <= 0;
		end	
		else begin
			//state register는 blocking!
			if(InstDone == 1) CurrState <= 3'b000;
			else CurrState <= NextState;

			//PC update signal
			if(PCWrite == 1 || (PCWriteCond && alu_zero)) begin
				PC <= PC_next;
			end
			//다른 microarchitecture 레지스터(non-blocking)
			alu_out <= alu_result;
			if(CurrState == 3'b000) begin
				npc_reg <= alu_result;
			end

			if(IRWrite && MemRead) begin //instruction
				IR <= mem_read_data;
			end
			if(MemRead && IorD && CurrState == 3'b011) begin 
				mem_data_reg <= mem_read_data;
			end
			if(CurrState == 3'b001) begin
				rd_dataA <= rd_data1;
				rd_dataB <= rd_data2;
			end
		end
	end
	

	CTRL ctrl (
		.opcode(opcode),
		.funct(funct),
		.CurrState(CurrState),
		.NextState(NextState),
		.RegDst(RegDst),
		.MemRead(MemRead),
		.MemWrite(MemWrite),
		.MemtoReg(MemtoReg),
		.SignExtend(SignExtend),
		.RegWrite(RegWrite),
		.ALUOp(ALUOp),
		.PCWrite(PCWrite),
		.PCWriteCond(PCWriteCond),
		.IorD(IorD),
		.ALUSrcA(ALUSrcA),
		.ALUSrcB(ALUSrcB),
		.PCSource(PCSource),
		.IRWrite(IRWrite),
		.InstDone(InstDone)
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
		.mem_addr(mem_addr),
		.MemWrite(MemWrite),
		.mem_write_data(rd_dataB),
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
