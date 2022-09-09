/**
*
*	Caio Vinicius - Memory Hierarchy 
*
*	File: L1cache.v
*	Set 2022
*
*	This module implements a simple non inclusive non exclusive (NINE)
*	L1 cache. It's a DM cache, with a 2-way associative degree.
*	Each block holds four 8 bits words. It's a single bank cache.
*
**/

module L1cache //L1
#(parameter INDEX_BITS=3)
(
	input clk,
	//Up Hierarchy Interface. The up hierarchy must maintain the requested data signals until the cache finishes the request (except the u_request). (u : up)
	input u_request,
	input u_we,
	input [7:0] u_addr,
	input [7:0] u_din,
	output reg u_ready,				//signals that the request has been done
	output reg [7:0] u_dout,
	
	//Down Hierarchy Interface: This cache maintains the requested data singnals until the down_hierarchy finishes(except the d_request). (d : down)
	output reg d_request,
	output reg d_we,
	output reg [5:0] d_addr,		//Removed the block offset bits
	output reg [31:0] d_din,		//Writes down the full block
	input d_ready,
	input [31:0] d_dout
);

	localparam BLK_OFST_BITS = 2;
	localparam TAG_BITS = 8-(INDEX_BITS+BLK_OFST_BITS);

	//State machine encodings
	reg [1:0] state;
	localparam IDLE=0, CHECK_TAG=1, WRITEBACK=2, FILL=3;

	initial begin
		state = IDLE;
	end
	
	//Separetes the requested data in we, tag, index, offset and din (r : requested)
	wire r_we;
	wire [BLK_OFST_BITS-1:0] r_block_offset;
	wire [INDEX_BITS-1:0] r_index;
	wire [TAG_BITS-1:0] r_tag;
	wire [7:0] r_din;
	
	assign r_we = u_we;
	assign r_block_offset = u_addr[BLK_OFST_BITS-1:0];
	assign r_index = u_addr[(INDEX_BITS+BLK_OFST_BITS)-1:BLK_OFST_BITS];
	assign r_tag = u_addr[(TAG_BITS+INDEX_BITS+BLK_OFST_BITS)-1:(INDEX_BITS+BLK_OFST_BITS)];
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
	wire [7:0] c_din [3:0]; //this wire contains the data that corresponds to each block byte
	
	//fetched data after the read (f : fetched)
	wire f_dirty;
	wire [TAG_BITS-1:0] f_tag;
	wire [7:0] f_data [3:0]; //the bytes found in the block
	
	//Cache din multiplexers. During write operations, if the cache does not contain the block
	//and needs to request the block to the hierarchy below, it can simultaneosly write both the requested
	//block and the write request data. This is the purpose of the multiplexers below
	assign c_din[0] = (r_we && r_block_offset == 2'b00) ? r_din : (state == FILL) ? d_dout[7:0]		: f_data[0];
	assign c_din[1] = (r_we && r_block_offset == 2'b01) ? r_din : (state == FILL) ? d_dout[15:8] 	: f_data[1];
	assign c_din[2] = (r_we && r_block_offset == 2'b10) ? r_din : (state == FILL) ? d_dout[23:16]	: f_data[2];
	assign c_din[3] = (r_we && r_block_offset == 2'b11) ? r_din : (state == FILL) ? d_dout[31:24]	: f_data[3];
	
	single_port_ram#(INDEX_BITS+1,(1 + TAG_BITS + 32)) cache_ram //dirty + tag + block (4B)
	(
		//The clock is inverted of the state machine clock: during the posedge, the transition is made,
		//and during the negedge, the ram processes the transition, so it can have data on the next posedge
		.clk(~clk),
		.addr(c_addr),
		.we(c_we),
		.din({c_dirty, r_tag, c_din[3], c_din[2], c_din[1], c_din[0]}),
		.dout({f_dirty, f_tag, f_data[3], f_data[2], f_data[1], f_data[0]})
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
	
	//cache state machine (and also lower lru way data controller)
	always @ (posedge clk) begin
		
		//default signals
		state = state;
		way_offset = way_offset;
		accessed_way = accessed_way;

		u_ready = 1'b0;
		u_dout = 8'hxx;

		c_we = 1'b0;
		c_dirty = 1'bx;
		c_addr = {(INDEX_BITS+1){1'bx}};

		d_request = 1'b0;
		d_addr = 6'hxx;
		d_we = 1'bx;
		d_din = {32{1'bx}};
		
		case(state)
			IDLE: begin
				if(u_request) begin //Transition 1
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
					block_lower_lru_way = {f_data[3], f_data[2], f_data[1], f_data[0]};
				end
				
				if(hit) begin //Transition 2
					accessed_way = way_offset;

					c_addr = {r_index, way_offset};
					c_we = r_we;
					c_dirty = 1'b1;

					if(!r_we) //keep X to the write, (only to show in the simulation)
						u_dout = f_data[r_block_offset];
						
					u_ready = 1'b1;	//although the data hasn't been written yet (if it's a write request), the write will happen on the next negedge

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
				else begin //transition 5
					accessed_way = lower_lru_way_offset;

					c_we = 1'b1;
					c_dirty = r_we;
					c_addr = {r_index, lower_lru_way_offset};

					d_addr = {r_tag, r_index};
					d_we = 1'b0;
					d_request = 1'b1;

					state = FILL;
				end
			end
			WRITEBACK: begin
				if(d_ready) begin //transition 7
					c_we = 1'b1;
					c_dirty = r_we;
					c_addr = {r_index, lower_lru_way_offset};

					d_addr = {r_tag, r_index};
					d_we = 1'b0;
					d_request = 1'b1;

					state = FILL;
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
						u_dout = f_data[r_block_offset];
					u_ready = 1'b1;

					state = IDLE;
				end
				else begin //transition 8
					c_we = 1'b1;
					c_dirty = r_we;
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
	