/**
*
*	Caio Vinicius - Memory Hierarchy 
*
*	File: testbench_hierarchy.v
*	Set 2022
*
*	This testbench tests sequential access
*	to addresses that will be mapped to the same
*	cache line (index) on cache L2, to test
*	if the L1 and L2 caches have correct hit and misses,
*	writeback and request operations.
*
**/

module testbench_hierarchy();
	
	reg clk, u_request, u_we;
	reg [7:0] u_addr, u_din;
	wire u_ready;
	wire [7:0] u_dout;
	
	MemoryHierarchy dut(clk, u_request, u_we, u_addr, u_din, u_ready, u_dout);
	
	initial begin: sim
		integer i;
		i=0;
		clk = 1'b0;
		u_request = 1'b1; //keeping the request on 1. This tb will sync every posedge after the request has been done (transition back to IDLE)
		
		forever begin
			#1;
			i=i+1;
			if(i==101) //beware of updating this comparison if adding more test cases. If its less to the sum of the '#time;' will look like it failed some test
				$stop;
			clk = ~clk;
		end
	end
	
	/*
	
	Expected outputs and cache states accordingly to the states machines.
	For the caches, each transition takes one clock cycle
	The memory takes one cycle to answer the request
	
	L1 mapping: 000 + 000 + 00 {tag, index, offset}
	L2 mapping: 00 + 0000 + XX {tag, index} (L2 ignores the block offset, only transmits the full block)
	
	Test bench: I: index, LRU: way with lru = 1, W0: content of way 0 {dirty, tag}_byte3_byte2_byte1_byte0 (hex)
	These tests are sequencial, and tries to acess different adresses that falls into the same index for both caches L1 and L2. (index 000 for L1 and 0000 for L2)
	The initial content stored in address [i] is also i, to simplify the tests
	_____________________________________________________________________________________________________________
	1. READ 0000_0000 : read miss. 9 cycles
	
	L1: IDLE -> CHECK_TAG -> CHECK_TAG -> FILL -> FILL       -> FILL     -> FILL -> FILL  -> FILL   -> IDLE(R)
	L2: IDLE -> IDLE      -> IDLE      -> IDLE -> CHECK_TAG -> CHECK_TAG -> FILL -> FILL  -> IDLE(R)
	MEM:IDLE -> IDLE      -> IDLE      -> IDLE -> IDLE      -> IDLE      -> IDLE -> IDLE(R)
	
	L1 Index0: LRU:0 	WAY0: 0_03_02_01_00
	L2 Index0: LRU:0 	WAY0: 0_03_02_01_00
	_____________________________________________________________________________________________________________
	2. READ 0000_0010 : read hit.  2 cycles
	
	L1: IDLE -> CHECK_TAG(H) -> IDLE(R)
	
	L1 Index0: LRU:0 	WAY0(Tag 000): 0_03_02_01_00
	L2 Index0: LRU:0 	WAY0(Tag 00) : 0_03_02_01_00
	_____________________________________________________________________________________________________________
	3. WRITE 1000_0000 8'hff: write miss. 9 cycles
	
	L1: IDLE -> CHECK_TAG -> CHECK_TAG -> FILL -> FILL       -> FILL     -> FILL -> FILL  -> FILL   -> IDLE(R)
	L2: IDLE -> IDLE      -> IDLE      -> IDLE -> CHECK_TAG -> CHECK_TAG -> FILL -> FILL  -> IDLE(R)
	MEM:IDLE -> IDLE      -> IDLE      -> IDLE -> IDLE      -> IDLE      -> IDLE -> READY
	
	L1 Index0: LRU:1 	WAY0(Tag 000): 0_03_02_01_00 		WAY1(Tag 100)(Dirty): C_83_82_81_FF
	L2 Index0: LRU:1 	WAY0(Tag 00) : 0_03_02_01_00 		WAY1(Tag 10): 2_83_82_81_80
	_____________________________________________________________________________________________________________
	4. WRITE 0000_0011 8'hff: write hit. 2 cycles
	
	L1: IDLE -> CHECK_TAG(H) -> IDLE(R)
	
	L1 Index0: LRU:0 	WAY0(Tag 000)(Dirty): 8_ff_02_01_00 		WAY1(Tag 100)(Dirty): C_83_82_81_FF
	L2 Index0: LRU:1 	WAY0(Tag 00): 0_03_02_01_00 					WAY1(Tag 10): 2_83_82_81_80
	_____________________________________________________________________________________________________________
	5. READ 1100_0000: read miss 13 cycles. Here we can see that this implementation is Non inclusive non exclusive (NINE)
	
	L1 : IDLE -> CHECK_TAG -> CHECK_TAG -> WB(addr_100_000) -> WB        -> WB           -> WB      -> FILL(addr_110_000) -> FILL      -> FILL      -> FILL -> FILL  -> FILL    -> IDLE(R)
	L2 : IDLE -> IDLE      -> IDLE      -> IDLE             -> CHECK_TAG -> CHECK_TAG(H) -> IDLE(R) -> IDLE               -> CHECK_TAG -> CHECK_TAG -> FILL -> FILL  -> IDLE(R)
	MEM: IDLE -> IDLE ->   -> IDLE      -> IDLE             -> IDLE      -> IDLE         -> IDLE    -> IDLE               -> IDLE      -> IDLE      -> IDLE -> READY 
	
	after writeback L1 -> L2 (lru changes)
	L1 Index0: LRU:0 	WAY0(Tag 000)(Dirty): 8_ff_02_01_00 		WAY1(Tag 100)(Dirty, but WB): C_83_82_81_FF
	L2 Index0: LRU:1 	WAY0(Tag 00): 0_03_02_01_00 					WAY1(Tag 10)(Dirty): 			6_83_82_81_FF
	
	after filling both caches (lru changes again)
	L1 Index0: LRU:1 	WAY0(Tag 000)(Dirty): 8_ff_02_01_00 		WAY1(Tag 110): 6_C3_C2_C1_C0
	L2 Index0: LRU:0 	WAY0(Tag 11): 3_C3_C2_C1_C0 					WAY1(Tag 10)(Dirty): 6_83_82_81_FF
	_____________________________________________________________________________________________________________
	6. READ 0100_0010: read miss 15 cycles.
	
	L1 : IDLE -> C_T  -> C_T  -> WB(addr_000_000) -> WB   -> WB   -> WB               -> WB    -> WB      -> FILL(addr_010_000) -> FILL -> FILL -> FILL               -> FILL  -> FILL   -> IDLE(R)     
	L2 : IDLE -> IDLE -> IDLE -> IDLE             -> C_T  -> C_T  -> WB(addr_10_0000) -> WB    -> IDLE(R) -> IDLE               -> C_T  -> C_T  -> FILL(addr_01_0000) -> FILL  -> IDLE(R)
	MEM: IDLE -> IDLE -> IDLE -> IDLE             -> IDLE -> IDLE -> IDLE             -> READY -> IDLE    -> IDLE               -> IDLE -> IDLE -> IDLE               -> READY       
	
	
	(L1 requests a WB, allocating space for the new block, L2 has to WB to mem to receive the L1 WB)
	after L2 WB MEM
	L1 Index0: LRU:1 	WAY0(Tag 000)(Dirty): 8_ff_02_01_00 				WAY1(Tag 110): 6_C3_C2_C1_C0
	L2 Index0: LRU:0 	WAY0(Tag 11): 3_C3_C2_C1_C0 							WAY1(Tag 10)(Dirty, but WB): 6_83_82_81_FF
	MEM[100000]: 83_82_81_FF
	
	L1 WB L2 (L2 lru changes)
	L1 Index0: LRU:1 	WAY0(Tag 000)(Dirty, but WB): 8_ff_02_01_00 		WAY1(Tag 110): 6_C3_C2_C1_C0
	L2 Index0: LRU:1 	WAY0(Tag 11): 3_C3_C2_C1_C0 							WAY1(Tag 00)(Dirty): 4_ff_02_01_00
	MEM[100000]: 83_82_81_FF
	
	after both fill (l1 and l2 lru changes)
	L1 Index0: LRU:0 	WAY0(Tag 010): 2_43_42_41_40							WAY1(Tag 110): 6_C3_C2_C1_C0
	L2 Index0: LRU:0 	WAY0(Tag 01): 1_43_42_41_40 							WAY1(Tag 00)(Dirty): 4_ff_02_01_00
	MEM[100000]: 83_82_81_FF
	
	
	I believe that the test 6 is the worst case scenario, as it requires two WB and fetch data from the main memory.
	Since the wb is just a write operation from L1 to L2, it also changes the lru. If both ways of L2 were dirty,
	one operation could take 3 WB, but I believe having 2 ways and 2 bits of tag for L2 doesn't allow that. Either way, I consider
	that both L1 and L2 state machines were implemented correctly, and this cache should work in all possible cases.
	
	*/
	
	//L1: {3'bINDEX, 1'bWAY_OFFSET}
	//L2: {4'bINDEX, 1'bWAY_OFFSET}
	
	initial begin
		#1; //Wait for the first posedge. Sum = 1
		
		//nesting ifs to improve readability
		
		//1
		u_addr = 8'h00; u_we = 1'b0; u_din = 8'hxx;
		#18; //Sum = 19
		
		if(u_dout == 8'h00 && u_ready == 1'b1)
		if(dut.L1.cache_ram.ram[{3'b000,1'b0}] == 36'h0_03_02_01_00)
		if(dut.L2.cache_ram.ram[{4'h0,1'b0}] == 35'h0_03_02_01_00)
			$display("PASSED 1");
		
		//2
		u_addr = 8'h02; u_we = 1'b0; u_din = 8'hxx;
		#4; //Sum = 23
		
		if(u_dout == 8'h02 && u_ready == 1'b1)
		if(dut.L1.cache_ram.ram[{3'b000,1'b0}] == 36'h0_03_02_01_00)
		if(dut.L2.cache_ram.ram[{4'h0,1'b0}] == 35'h0_03_02_01_00)
			$display("PASSED 2");
			
		//3
		u_addr = 8'h80; u_we = 1'b1; u_din = 8'hff;
		#18; //Sum = 41
			
		if(u_ready == 1'b1) //writes have xx output for the simulation
		if(dut.L1.cache_ram.ram[{3'b000,1'b0}] == 36'h0_03_02_01_00 && dut.L1.cache_ram.ram[{3'b000,1'b1}] == 36'hc_83_82_81_ff)
		if(dut.L2.cache_ram.ram[{4'h0,1'b0}] == 35'h0_03_02_01_00 && dut.L2.cache_ram.ram[{4'h0,1'b1}] == 35'h2_83_82_81_80)
			$display("PASSED 3");
			
		//4
		u_addr = 8'h03; u_we = 1'b1; u_din = 8'hff;
		#4; //Sum = 45
		
		if(u_ready == 1'b1) //writes have xx output for the simulation
		if(dut.L1.cache_ram.ram[{3'b000,1'b0}] == 36'h8_ff_02_01_00 && dut.L1.cache_ram.ram[{3'b000,1'b1}] == 36'hc_83_82_81_ff)
		if(dut.L2.cache_ram.ram[{4'h0,1'b0}] == 35'h0_03_02_01_00 && dut.L2.cache_ram.ram[{4'h0,1'b1}] == 35'h2_83_82_81_80)
			$display("PASSED 4");
			
		//5
		u_addr = 8'hc0; u_we = 1'b0; u_din = 8'hxx;
		#26; //Sum = 71
		
		if(u_dout == 8'hc0 && u_ready == 1'b1)
		if(dut.L1.cache_ram.ram[{3'b000,1'b0}] == 36'h8_ff_02_01_00 && dut.L1.cache_ram.ram[{3'b000,1'b1}] == 36'h6_c3_c2_c1_c0)
		if(dut.L2.cache_ram.ram[{4'h0,1'b0}] == 35'h3_c3_c2_c1_c0 && dut.L2.cache_ram.ram[{4'h0,1'b1}] == 35'h6_83_82_81_ff)
			$display("PASSED 5");
			
		//6
		u_addr = 8'h42; u_we = 1'b0; u_din = 8'hxx;
		#30; //Sum 101
		
		if(u_dout == 8'h42 && u_ready == 1'b1)
		if(dut.L1.cache_ram.ram[{3'b000,1'b0}] == 36'h2_43_42_41_40 && dut.L1.cache_ram.ram[{3'b000,1'b1}] == 36'h6_c3_c2_c1_c0)
		if(dut.L2.cache_ram.ram[{4'h0,1'b0}] == 35'h1_43_42_41_40 && dut.L2.cache_ram.ram[{4'h0,1'b1}] == 35'h4_ff_02_01_00)
		if(dut.main_mem.mem[6'b100000] == 32'h83_82_81_ff)
			$display("PASSED 6");
	end
	
endmodule