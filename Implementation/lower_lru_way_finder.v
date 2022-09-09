/**
*
*	Caio Vinicius - Memory Hierarchy 
*	github.com/caiovpsilveira
*
*	File: lower_lru_way_finder.v
*	Set 2022
*
*	This module informs the lower lru way offset,
*	accordingly to the current lru.
*
**/

module lower_lru_way_finder
(
	input [1:0] current_lru,
	output reg way_offset_lower_lru_way
);

	// <- MSB		LSB ->
	always @ (*) begin
		casex(current_lru)
			2'bx0: way_offset_lower_lru_way = 1'b0; //For 00 and 10: the WAY0 has the lower lru
			2'b01: way_offset_lower_lru_way = 1'b1; //The WAY1 has the lower lru
			2'b11: way_offset_lower_lru_way = 1'bx; //this should never happen
		endcase
	end
	
endmodule
