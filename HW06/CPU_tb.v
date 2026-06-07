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

	initial begin : REF_INIT
		$readmemh("./testcase/testcase7/reference_mem.mem", memory);
		$readmemh("./testcase/testcase7/reference_reg.mem", register_file);
	end
    

    initial begin : CLOCK_GENERATOR
        clk = 1'b0;
        forever #5 clk = ~clk;
    end
    
	// =================================================================
	// [추가 항목 1] 로그 생성용 변수 선언 및 초기화 블록
	// =================================================================
	integer log_file;
	integer cycle_count;

	initial begin : LOG_FILE_INIT
		log_file = $fopen("cpu_trace.log", "w");
		cycle_count = 0;
		if (log_file == 0) begin
			$display("Error: cpu_trace.log 파일을 생성할 수 없습니다.");
		end
	end

	// =================================================================
	// [추가 항목 2] 매 클럭마다 내부 파이프라인 상태를 파일에 기록
	// =================================================================
	always @(posedge clk) begin
		if (!rst && log_file != 0) begin
			cycle_count = cycle_count + 1;
			// ※ 주의: cpu.inst_ID, cpu.stall 등은 실제 CPU.v 내부 변수명과 일치해야 합니다.
			$fdisplay(log_file, "[Cycle %4d] PC: %h | opcode: %h | inst_ID: %h | Flush: %b || WB_RegWrite: %b | WB_Addr: %d | WB_Data: %h",
					 cycle_count,
					 cpu.PC,
					 cpu.opcode,
					 cpu.inst_ID,
					 cpu.flush_IF_ID,
					 cpu.RegWrite_WB,
					 cpu.wr_addr_WB,
					 cpu.wr_data
			);
		end
	end

	// =================================================================


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
		else begin
			$display("Simulation success!!!");
		end
		
		// =============================================================
		// [추가 항목 3] 시뮬레이션 종료 직전 파일 안전하게 닫기
		// =============================================================
		if (log_file != 0) begin
			$fclose(log_file);
		end

		$finish();
    end

endmodule
