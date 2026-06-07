`timescale 1ns / 100ps

module RF (
		input clk,
		input rst,
		// Read-related ports
		input [4:0] rd_addr1,
		input [4:0] rd_addr2,
		output reg [31:0] rd_data1,
		output reg [31:0] rd_data2,
		// Write-related ports
		input RegWrite,
		input [4:0] wr_addr,
		input [31:0] wr_data
	);

    reg [31:0] register_file [0:31];
	
	// FIXME (Perform Read Operation)
	always @(*) begin
		// internal forwarding logic 추가  (wr_addr가 0이 아니고, rd_addr와 같으며, RegWrite == 1일 때 -> WB에서의 data hazard 방지를 위해 WB하려는 wr_data를 rd_data로 forwarding))
		rd_data1 = (RegWrite && wr_addr != 0 && wr_addr == rd_addr1) 
		? wr_data
		: register_file[rd_addr1];

		rd_data2 = (RegWrite && wr_addr != 0 && wr_addr == rd_addr2) 
		? wr_data
		: register_file[rd_addr2];
	end
    
	always @(posedge clk) begin
		// Reset the regsiter file to pre-defined values
		if (rst) begin
        	$readmemh("./testcase/testcase7/initial_reg.mem", register_file);
		end
		else begin
			if(RegWrite && (wr_addr != 5'd0)) begin
				register_file[wr_addr] <= wr_data;
			end
		end
	end

endmodule
