/**
*
*	Caio Vinicius - Memory Hierarchy 
*
*	File: L2cache.v
*	Set 2022
*
*	This module implements a simple non inclusive non exclusive
*	L2 cache. It's a DM cache, with a 2-way associative degree.
*	Differently than the L1 cache, which modifies only parts of
*	the block, the L2 cache only transfers the whole block
*	to both the hierarchy above and below.
*
**/

module L2cache
#(parameter INDEX_BITS=4)
(
	input clk,
	//Up Hierarchy Interface. Note: the up hierarchy must maintain the requested data signals until the cache finishes the request. (u : up)
	input u_request,
	input u_we,
	input [5:0] u_addr,
	input [31:0] u_din,
	output reg u_ready,
	output reg [31:0] u_dout,
	
	//Down Hierarchy Interface: This cache maintains the requested data singnals until the down_hierarchy finishes. (d : down)
	output reg d_request,
	output reg d_we,
	output reg [5:0] d_addr,
	output reg [31:0] d_din,
	input d_ready,
	input [31:0] d_dout
);

	localparam TAG_BITS = 6-(INDEX_BITS);

	//State machine encodings
	reg [1:0] state;
	localparam IDLE=0, CHECK_TAG=1, WRITEBACK=2, FILL=3;

	initial begin
		state = IDLE;
	end
	
	//Separetes the requested data in we, tag, index and din (r : requested)
	wire r_we;
	wire [INDEX_BITS-1:0] r_index;
	wire [TAG_BITS-1:0] r_tag;
	wire [31:0] r_din;
	
	assign r_we = u_we;
	assign r_index = u_addr[(INDEX_BITS)-1:0];
	assign r_tag = u_addr[(TAG_BITS+INDEX_BITS)-1:INDEX_BITS];
	assign r_din = u_din;
	
	
	//Cache and Valid RAMs (they need to be initialized as 0)
	reg [1:0] next_lru;
	reg [1:-0] next_valid;
	wire [1:0] line_lru;
	wire [1:0] line_valid;

	//These can be read on the posedge, as idealy they will remain the same trough the whole request (r_index should be constant)
	init_ram#(INDEX_BITS, 2) cache_lru
	(
		.clk(clk),
		.addr(r_index),
		.we(u_ready),	//enable update at the end of the request
		.din(next_lru),
		.dout(line_lru)
	);
	
	init_ram#(INDEX_BITS, 2) cache_valid
	(
		.clk(clk),
		.addr(r_index),
		.we(u_ready),	//enable update at the end of the request
		.din(next_valid),
		.dout(line_valid)
	);
	
	//Cache registers
	reg way_offset;		//Holds the increment, incrementing to access one way each cycle
	reg accessed_way;		//Holds the accessed way, to update the lru and valid at the end of the cycle
	
	//Block ram signals
	reg c_we;
	reg [(INDEX_BITS+1)-1:0] c_addr; //+1 because it's two ways
	reg c_dirty;
	reg [TAG_BITS-1:0] c_tag;
	wire [31:0] c_din;
	
	//fetched data after the read (f : fetched)
	wire f_dirty;
	wire [TAG_BITS-1:0] f_tag;
	wire [31:0] f_data;
	
	//block din multiplexer
	assign c_din = r_we ? r_din : (state == FILL) ? d_dout : f_data;
	
	single_port_ram#(INDEX_BITS+1,(1 + TAG_BITS + 32)) cache_ram //dirty + tag + block
	(
		//The clock is inverted of the state machine clock: during the posedge, the transition is made,
		//and during the negedge, the ram processes the transition, so it can have data on the next posedge
		.clk(~clk),
		.addr(c_addr),
		.we(c_we),
		.din({c_dirty, r_tag, c_din}),
		.dout({f_dirty, f_tag, f_data})
	);
	
	
	//Lower lru way registers: keep the lower lru content, when a writeback is required
	wire lower_lru_way_offset;						//This indicates the way offset of the first way with an LRU == 0
	reg dirty_lower_lru_way;						//Stores the dirty found on the lower lru way.
	reg [TAG_BITS-1:0] tag_lower_lru_way;		//Stores the tag found on the lower lru way.
	reg [31:0] block_lower_lru_way;				//Stores the block found on the lower lru way.
	
	lower_lru_way_finder lower_lru_way_finder
	(
		.current_lru(line_lru),
		.way_offset_lower_lru_way(lower_lru_way_offset)
	);
	
	
	//hit logic
	wire f_valid;
	assign f_valid = line_valid[way_offset];
	
	wire hit;
	assign hit = f_valid & r_tag == f_tag;
	
	//cache state machine
	always @ (posedge clk) begin
		
		//default signals
		state = state;
		way_offset = way_offset;
		accessed_way = accessed_way;

		u_ready = 1'b0;
		u_dout = {32{1'bx}};

		c_we = 1'b0;
		c_dirty = 1'bx;
		c_addr = {(INDEX_BITS+1){1'bx}};

		d_request = 1'b0;
		d_addr = 6'hxx;
		d_we = 1'bx;
		d_din = {32{1'bx}};
		
		case(state)
			IDLE: begin
				if(u_request) begin //transition 1
					way_offset = 1'b0;

					c_addr = {r_index, way_offset};

					state = CHECK_TAG;
				end
			end
			CHECK_TAG: begin
				
				//Setting the lower lru way data before the way_offset gets updated.
				if(way_offset == lower_lru_way_offset) begin
					if(!f_valid)
						dirty_lower_lru_way = 1'b0; //not writeback if its a invalid block containing trash data
					else
						dirty_lower_lru_way = f_dirty;
					tag_lower_lru_way = f_tag;
					block_lower_lru_way = f_data;
				end
				
				if(hit) begin //transition 2
					accessed_way = way_offset;

					c_addr = {r_index, way_offset};
					c_we = r_we;
					c_dirty = 1'b1;

					if(!r_we) //keep X to the write, (only to show in the simulation)
						u_dout = f_data;
					u_ready = 1'b1;

					state = IDLE;
				end
				else if(way_offset != 1'b1) begin //transition 3
					way_offset = way_offset + 1'b1;

					c_addr = {r_index, way_offset};
				end
				else if(dirty_lower_lru_way) begin //transition 4
					accessed_way = lower_lru_way_offset;

					d_addr = {tag_lower_lru_way, r_index};
					d_we = 1'b1;
					d_din = block_lower_lru_way;
					d_request = 1'b1;

					state = WRITEBACK;
				end
				else if(!r_we) begin //transition 5
					accessed_way = lower_lru_way_offset;

					c_we = 1'b1;
					c_dirty = 1'b0;
					c_addr = {r_index, lower_lru_way_offset};

					d_addr = {r_tag, r_index};
					d_we = 1'b0;
					d_request = 1'b1;

					state = FILL;
				end
				else begin //transition 10
					accessed_way = lower_lru_way_offset;

					c_we = 1'b1;
					c_dirty = 1'b1;
					c_addr = {r_index, lower_lru_way_offset};

					u_ready = 1'b1;

					state = IDLE;
				end
			end
			WRITEBACK: begin
				if(d_ready) begin
					if(!r_we) begin //transition 7
						c_we = 1'b1;
						c_dirty = 1'b0;
						c_addr = {r_index, lower_lru_way_offset};

						d_addr = {r_tag, r_index};
						d_we = 1'b0;
						d_request = 1'b1;

						state = FILL;
					end
					else begin //transition 11
						c_we = 1'b1;
						c_dirty = 1'b1;
						c_addr = {r_index, lower_lru_way_offset};

						u_ready = 1'b1;

						state = IDLE;
					end
				end
				else begin //transition 6
					d_addr = {tag_lower_lru_way, r_index};
					d_we = 1'b1;
					d_din = block_lower_lru_way;
				end
			end
			FILL: begin
				if(d_ready) begin //transition 9
					if(!r_we) //keep X to the write, (only to show in the simulation)
						u_dout = f_data;
					u_ready = 1'b1;

					state = IDLE;
				end
				else begin //transition 8
					c_we = 1'b1;
					c_dirty = 1'b0;
					c_addr = {r_index, lower_lru_way_offset};

					d_addr = {r_tag, r_index};
					d_we = 1'b0;
				end
			end
		endcase
	end
	
	//Valid and lru update logic
	always @ (negedge clk) begin
		next_lru[accessed_way] <= 1'b1;
		next_lru[~accessed_way] <= 1'b0;
	end
	
	always @ (negedge clk) begin
		next_valid[accessed_way] <= 1'b1;
		next_valid[~accessed_way] <= line_valid[~accessed_way];
	end

endmodule
