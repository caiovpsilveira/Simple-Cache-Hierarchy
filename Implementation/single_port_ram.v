/**
*
*	Caio Vinicius - Memory Hierarchy 
*
*	File: single_port_ram.v
*	Set 2022
*
*	This module describes a single_port_ram.
*	It was implemented utilizing the QuartusII templates.
*
**/

module single_port_ram 
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

	reg [DATA_WIDTH-1:0] ram[2**ADDR_BITS-1:0];

	always @ (posedge clk)
	begin
		if (we)
			ram[addr] <= din;

		addr_reg <= addr;
	end
	
	assign dout = ram[addr_reg];

endmodule
