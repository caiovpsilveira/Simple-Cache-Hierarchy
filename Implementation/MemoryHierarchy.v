/**
*
*	Caio Vinicius - Memory Hierarchy
*
*	File: MemoryHierarchy.v
*	Set 2022
*
*	This module simulates the processor interface
*	with the memory hierarchy. It instantiates the L1
*  and L2 caches, and the main memory.
*
**/

module MemoryHierarchy(
	input clk,
	input u_request,
	input u_we,
	input [7:0] u_addr,
	input [7:0] u_din,
	output u_ready,
	output [7:0] u_dout
);

	wire L1_d_request;
	wire L1_d_we;
	wire [5:0] L1_d_addr;
	wire [31:0] L1_d_din;
	wire L1_d_ready;
	wire [31:0] L1_d_dout;
	
	wire L2_d_request;
	wire L2_d_we;
	wire [5:0] L2_d_addr;
	wire [31:0] L2_d_din;
	wire L2_d_ready;
	wire [31:0] L2_d_dout;
	
	L1cache#(3) L1
	(
		.clk(clk),
		.u_request(u_request),
		.u_we(u_we),
		.u_addr(u_addr),
		.u_din(u_din),
		.u_ready(u_ready),
		.u_dout(u_dout),
		.d_request(L1_d_request),
		.d_we(L1_d_we),
		.d_addr(L1_d_addr),
		.d_din(L1_d_din),
		.d_ready(L1_d_ready),
		.d_dout(L1_d_dout)
	);
	
	L2cache#(4) L2
	(
		.clk(clk),
		.u_request(L1_d_request),
		.u_we(L1_d_we),
		.u_addr(L1_d_addr),
		.u_din(L1_d_din),
		.u_ready(L1_d_ready),
		.u_dout(L1_d_dout),
		.d_request(L2_d_request),
		.d_we(L2_d_we),
		.d_addr(L2_d_addr),
		.d_din(L2_d_din),
		.d_ready(L2_d_ready),
		.d_dout(L2_d_dout)
	);
	
	main_memory main_mem
	(
		.clk(clk),
		.u_request(L2_d_request),
		.u_we(L2_d_we),
		.u_addr(L2_d_addr),
		.u_din(L2_d_din),
		.u_ready(L2_d_ready),
		.u_dout(L2_d_dout)
	);

endmodule