/**
*
*	Caio Vinicius - Memory Hierarchy 
*
*	File: main_memory.v
*	Set 2022
*
*	This module simulates the main memory.
*	It returns a block containing four 8 bit words.
*	Each block is initialized by contents {4*i+3, 4*i+2, 4*i+1, 4*i};
*
**/

module main_memory
(
	input clk,
	input u_request,
	input u_we,
	input [5:0] u_addr,
	input [31:0] u_din,
	output reg u_ready,
	output [31:0] u_dout
);

	reg [31:0] mem [2**6-1:0];

	reg [5:0] addr_reg;
	
	integer i;
	//set mem[0] {0000_0011, 0000_0010, 0000_0001, 0000_0000},
	//mem[1] to {0000_0111,0000_0110,0000_0101, 0000_0100}, etc
	initial begin
		for(i=0; i<2**6; i=i+1) begin
			mem[i][7:0] = 4*i;
			mem[i][15:8] = 4*i+1;
			mem[i][23:16] = 4*i+2;
			mem[i][31:24] = 4*i+3;
		end
	end
	
	always @ (posedge clk) begin
		if(u_request) begin
			u_ready = 1'b1;
			if(u_we)
				mem[u_addr] = u_din;
		end
		else
			u_ready = 1'b0;
			
		addr_reg <= u_addr;
	end

	assign u_dout = mem[addr_reg];
	
endmodule
