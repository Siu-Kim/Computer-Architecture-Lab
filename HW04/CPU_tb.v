`timescale 1ns / 1ps


module CPU_tb;
	integer i;
	integer FAILED;

    reg clk;
    reg rst;
    
	wire halt;

	// Have the reference register & mem
    reg [31:0] register_file [0:31];
	reg [31:0] memory [0:8191];

    CPU cpu (.clk(clk), .rst(rst), .halt(halt));

	/*
	always @(posedge clk) begin
		if((cpu.funct == 6'd8) && (cpu.opcode == 6'd0)) begin
			$display("JR inst | PC: %h | $r31: %h | nextPC: %h", cpu.PC, cpu.rf.register_file[31], cpu.PC_next);
		end
		else if(cpu.opcode == 6'd3) begin
			$display("JAL isnst | PC: %h | $r31: %h | nextPC: %h | npc_reg: %h", cpu.PC, cpu.rf.register_file[31], cpu.PC_next, cpu.npc_reg);
		end
		else if(cpu.opcode == 6'd2) begin
			$display("J inst | PC: %h | nextPC: %h", cpu.PC, cpu.PC_next);
		end

	end
	*/

	initial begin : REF_INIT
		$readmemh("reference_mem.mem", memory);
		$readmemh("reference_reg.mem", register_file);
	end
    

    initial begin : CLOCK_GENERATOR
        clk = 1'b0;
        forever #5 clk = ~clk;
    end
    
    initial begin : Settings
		FAILED = 0;
        rst = 1;
        #15
        rst = 0;
		@(posedge halt);
		$display("Program Terminate\n");

		for (i = 0; i < 32; i = i + 1) begin
			if (cpu.rf.register_file[i] != register_file[i]) begin
				FAILED = 1;
			end
		end
		for (i = 0; i < 8192; i = i + 1) begin
			if (cpu.mem.memory[i] != memory[i]) begin
				FAILED = 1;
			end
		end

		if (FAILED) begin
			$display("Simulation failed.");
			for (i = 0; i < 32; i = i + 1) begin
				$display("index: %d, dat: %h, %h", i, cpu.rf.register_file[i], register_file[i]);
			end
		end
		else
			$display("Simulation success!!!");
		$finish();
    end

endmodule
