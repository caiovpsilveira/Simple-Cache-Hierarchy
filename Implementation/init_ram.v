/**
*
*	Caio Vinicius - Memory Hierarchy 
*
*	File: init_ram.v
*	Set 2022
*
*	This module describes a single_port_ram, with initial contents.
*	It was implemented utilizing the QuartusII templates.
*
**/

module init_ram
#(parameter ADDR_BITS=6,
  parameter DATA_WIDTH=8)
(
	input clk,
	input [ADDR_BITS-1:0] addr,
	input we,
	input [DATA_WIDTH-1:0] din,
	output [DATA_WIDTH-1:0] dout
);

	reg [ADDR_BITS-1:0] addr_reg;

	reg [DATA_WIDTH-1:0] ram [2**ADDR_BITS-1:0];
	
	assign dout = ram[addr_reg];
	
	integer i;
	initial begin
		for(i=0; i<2**ADDR_BITS;  i=i+1)
			ram[i] <= {DATA_WIDTH{1'b0}}; //power up as 0
	end
	
	always @ (posedge clk) begin
		if(we)
			ram[addr] <= din;
			
		addr_reg <= addr;
	end
	
endmodule
