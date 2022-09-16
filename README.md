# Simple-Cache-Hierarchy
Implementation, in Verilog HDL, of a simple cache hierarchy, containing L1 and L2 caches with a non-inclusive non-exclusive policy.

The memory hierarchy is composed by the L1 and L2 caches and the main memory. Each cache is directly mapped, with a 2 way associative degree.

The L1 cache has an 8 bit address, consisting of 3 tag bits + 3 index bits + 2 block offset bits.
Each block contains four 8 bit words, plus the dirty (modified) bit and the tag bits.

The L2 cache has a 6 bit address width, consisting of 2 tag bits + 4 index bits (L2 is two times greater than L1). Since in this implementation the L2 cache only transmits full blocks between the L1 and main memory, the block offset bits can be ignored.

In this implementation, it was assumed that the main memory returned a full block containing four adjacent words. Example: the block 0 stores content of the words at addresses 0x00, 0x01, 0x02 and 0x03. The block 1 stores content of the words at addresses 0x04, 0x05, 0x06 and 0x07, and so on. The requests between L2 and the main memory only uses 6 bits, reffering to the block number.

The caches utilizes a write-back policy, only writting the data on the hierarchy below when the block needs to be replaced to allocate space for a new request, based on the pseudo-LRU.

Each cache has a single ram, in which both ways are stored. This requires one cycle to verify the block content at way 0, and another cycle to verify the block content at way 1. The cache way mapping is done by addressing the selected way with the Least Significant Bit (LSB), accordingly to the image below.

![Mapping](https://user-images.githubusercontent.com/86082269/189243797-b20b5b1e-0962-44b6-8bfb-e9f0abf7fb74.png)

The early cache schematic proposed can be seen on the image below

![cache_Esq](https://user-images.githubusercontent.com/86082269/189245652-6e2c4401-3cfc-4979-8c11-a7cf996be8ad.png)

where the following inputs, outputs and components are responsible for:

**up hierarchy interface (prefix u)**:

**u_request**: signals an operation request.\
**u_we**: read (0) or write (1) request.\
**u_addr**: Address for the read or write operation.\
**u_din**: Data input during write operations.\
**u_ready**: signals that the cache has finished doing the request.\
**u_dout**: data output during read operations.

**down hierarchy interface (prefix d)**:

**d_request**: signals an operation the the hierarchy below.\
**d_we**: read (0) or write (1) request. Write requests are made during writebacks, and read requests are made on misses.\
**d_addr**: Address for the read or write operation.\
**d_din**: Data to write during write operations (block writeback).\
**d_ready**: signals that the hierarchy below has finished doing the request.\
**d_dout**: data received (requested block) during read operations.

**Cache components**:

**Valid**: single port ram that stores which ways of each cache line contains a valid block (0 = invalid, 1 = valid). The valid bit could be placed in the block ram, but since the valid has to be initialized as 0 and the block ram not, I decided to split them.

**LRU**: single port ram that stores the bit pseudo LRU (least-recently-used). Stores which way has been least recently used (0 = least recently used). If a miss happens, the least recently used way will be used to allocate space for the new block. Since the pseudo LRU can be changed from all ways simultaneosly and needs to be initialized as 0, it's better to be stored in a separated ram.

**Lower lru way finder**: combinational circuit that finds the way offset of the least recently used way, accordingly to the current LRU state for the accessed cache line. This information is used when addressing the way that needs to be replaced.

**Blocks**: single port ram that stores the dirty bit, tag bits and the block content in each way.

**way offset**: counter that addresses different ways during the tag checking.

**accessed_way**: register that holds the way offset of the accessed way, to update the valid and lru at the end of the request.

**lower LRU way dirty**: register that holds the dirty bit value of the least recently used way. This data is used when the cache finishes checking the tags and its a miss, so that the least recently used way content has not to be fetched again to decide if it's a writeback or only fill request.

**lower LRU way tag**: register that holds the tag value of the least recently used way. Used when informing the address on writeback operations.

**lower LRU way block**: register that holds the block of the least recently used way. Used when informing the d_din in writeback operations.

**cache controller**: controls the inputs of other components and outputs, in order to the cache work properly.

# Cache controller state machine

The cache controller was modelled by a Mealy state machine, based on the proposed state machine in Computer Organization and Design: the hardware/software interface 5. ed. The controller states are:

**IDLE**: the cache is in an IDLE state, waiting for the up hierarchy to request some operation.

**CHECK_TAG**: the cache is checking for the tags in way 0 and way 1, to see if it's a hit or miss.

**WRITEBACK**: cache miss, and the least recently used way contains a modified block. The cache requests the hierarchy below to writeback, and waits until the hierarchy below finished the operation (signal d_ready).

**FILL**: the cache miss, and needs to fill the requested block. The cache requeststhe hierarchy below for the block, and waits until the block is returned (signal d_ready).

Since the L1 cache can modify only one part of the block (addressed by the block offset) and the L2 cache only writes full blocks, the controller state machines for L1 and L2 are slightly different. The controllers state machines can be seen below.

![L1_FSM](https://user-images.githubusercontent.com/86082269/189247320-c646bf6c-e31a-4922-9ec2-e4585c727862.png)

![L2_FSM](https://user-images.githubusercontent.com/86082269/189247370-64a674ac-c6b0-49d3-afac-d01c27033110.png)

The outputs and components signals for each transition can be seen on "L1_Mealy_FSM.pdf" and "L2_Mealy_FSM.pdf".
The controller updates on the posedge clk, while the blocks ram updates on the negedge ram. This enables data to be ready on the next cycle.

# Simulation

The "main memory" is ready one cycle after the request. Based on the state machine transitions, we can predict the elapsed time, in clock cycles. In this simulations, the content of word at adress i is also i, to simplify. This way, the block 0 contains data {0x03, 0x02, 0x01, 0x00}. During these tests, I will keep the u_request always on 1 and 

L1 mapping: 3 bits tag + 3 bits index + 2 bits block offset
L2 mapping: 2 bits tag + 4 bits index

### Test 1: cache empty, READ 0000_0010.

![test1_sequence](https://user-images.githubusercontent.com/86082269/189250269-452cf13c-2e4e-4150-b0dd-91f7757f5668.png)

Where each arrow represents a transition from the controllers state machines.

This test should result in a miss from both caches. Since the caches are empty, L1 should fill the block on way 0 at index 000, and L2 should fill the block at way 0, index 0000. The first 4 bits of the L1 block represents {dirty, tag}, and the first 3 bits of the L2 block represents {dirty, tag}, but the L2 will be represented as 4 bits, to be shown in hex notation {0, dirty, tag}.

The expected result is that after 8 cycles, u_ready = 1 and u_dout = 8'h02, lasting for 1 cycle, and the block contents of L1 and L2 should be

L1[000]:  LRU 01 : WAY0: 0x0_03_02_01_00\
L2[0000]: LRU 01 : WAY0: 0x0_03_02_01_00

![test1_out_signal](https://user-images.githubusercontent.com/86082269/189251359-55404d12-2f44-4856-89f4-bb66151944f0.png)

The content of the block at index 000, way 0 on L1 after this request:

![test1_L1_State](https://user-images.githubusercontent.com/86082269/189252218-0551b91f-9059-46be-a04c-143039a74174.png)

The content of the block at index 0000, way 0 on L2 after this request:

![test1_L2_State](https://user-images.githubusercontent.com/86082269/189252413-9a0b6434-eb69-4f02-afa1-5387c5c9f785.png)

### Test 2: cache state after test 1, READ 0100_0000

This address is the lowest address that will also map to index 0000 on the L2 cache.

The expected transitions are the same as the test 1, only filling the block on way 1 of both caches, as way 0 is occupied by address 0000_0000.
After 8 cycles, the expected output should be u_ready = 1 and u_dout = 8'h40, lasting for one cycle.

Since the tag is now 010 for L1 and 01 for L2, the first 4 bits of L1 will be 0010 (2) and the first 3 bits of L2 will be 001 (1). The block contents of L1 and L2 should be

L1[000]:  LRU 10 : WAY0: 0x0_03_02_01_00, WAY1: 2x0_43_42_FF_40\
L2[0000]: LRU 10 : WAY0: 0x0_03_02_01_00, WAY1: 1x0_43_42_41_40

![test2_out_signal](https://user-images.githubusercontent.com/86082269/189259844-44934fc5-8950-4484-bc75-ec82c40aef99.png)

The content of the block at index 000, way 1 on L1 after this request:

![test2_L1_State](https://user-images.githubusercontent.com/86082269/189260280-26aeb4aa-6156-4d3f-8f72-56876a731aeb.png)

The content of the block at index 0000, way 1 on L2 after this request:

![test2_L2_State](https://user-images.githubusercontent.com/86082269/189260586-e6f4b953-3563-4e31-8679-bd919afa3fa4.png)

### Test 3: cache state after test 2, WRITE 0100_0001 11111111

Since the requested address is contained in the block requested during the READ 0100_0000, placed on way 1, the state machine transitions should be:

L1: IDLE -> CHECK_TAG(W0) -> CHECK_TAG(W1) -> IDLE(R)

After 2 cycles, the output u_ready should be 1 (u_dout doesn't matter as it is a write request), lasting for 1 cycle.

Since the way 1 at L1 was modified, it's first 4 bits should be 1010 (A), and have the written data on block offset 01. The L2 cache should not have changed, as it was a hit on L1. The block contetnts on L1 and L2 should be:

L1[000]:  LRU 10 : WAY0: 0x0_03_02_01_00, WAY1(D): Ax0_43_42_FF_40\
L2[0000]: LRU 10 : WAY0: 0x0_03_02_01_00, WAY1: 1x0_43_42_41_40

![test3_out_signal](https://user-images.githubusercontent.com/86082269/189262450-f8b4c39f-566f-4644-86fc-53b50eff39cf.png)

L1 way 1 block content:

![test3_L1_State](https://user-images.githubusercontent.com/86082269/189263663-c1558c28-4806-4cbb-9c30-7185b36dccac.png)

L2 way 1 block content:

![test3_L2_State](https://user-images.githubusercontent.com/86082269/189263686-f96aa3b2-55eb-440e-bc15-71886e37d7f2.png)

### Test 4 (writeback and non-inclusive non-exclusive policy)

considering an empty cache that receives WRITE 0000_0000 11111111, WRITE 0100_0000 11111 and READ 0000_0001

The state of the cache should be:
L1[000]: LRU 01 : WAY0(D): 0x8_03_02_01_FF, WAY1(D): 0xC_43_42_41_FF\
L2[0000]: LRU 10 : WAY0: 0x0_03_02_01_00, WAY1: 1x0_43_42_41_40

Now following by a READ 1000_0010 request
since L1 does not contain the block, it will replace the way 1, as it has the LRU = 0. Since this way is modified, it will first writeback to L2. L2 will allocate way 0 to receive the writeback, as it has the LRU = 0. This test show the non inclusive non-exclusive policy, as L1 will contain address 0000_0000, and L2 won't. The writeback operation will make L2 change it's LRU to 01. After the writeback, the L1 will request the block of 1000_0010, placing it on way 1, and L2 will request the block 1000_0010, placing it on way 1. The transitions of the state machines should be

![test4_sequence](https://user-images.githubusercontent.com/86082269/189267460-bd5a5c59-5a45-4900-aee1-8da8779997f3.png)

requiring 12 clock cycles to have the data, which last for 1 cycle (13 cycles total).

The block content of L1 and L2 after the request should be

L1[000]: LRU 10: WAY0(D): 0x8_03_02_01_FF, WAY1: 0x4_83_82_81_80\
L2[0000]: LRU 10: WAY0: 0x2_83_82_81_80, WAY1(D): 1x5_43_42_41_FF

![test4_out_signal](https://user-images.githubusercontent.com/86082269/189269476-13f85d61-f5d5-4be4-9271-2a5d5175c9a7.png)

L1 content at way 0 and way 1:

![test4_L1_State](https://user-images.githubusercontent.com/86082269/189269183-864f7ecc-dc22-4d0b-afa7-9d26b150270d.png)

L2 content at way 0 and way 1:

![test4_L2_State](https://user-images.githubusercontent.com/86082269/189269204-181e0536-cdde-480f-89f3-b2ca3f587937.png)

We can see that all tests worked as expected. There are a few more tests on the testbench at "testbench_hierarchy.v".

## Final Thoughts
Looking back, I could've utilized the "dirty_lower_lru_way, "tag_lower_lru_way" and "block_lower_lru_way" as a writeback buffer. When I came up with those registers I was thinking of saving one cycle by storing the writeback contents on them, instead of requiring another cycle to fetch the data of the lower lru way again. By having a writeback buffer, the cache could fill the requested block first, and provide the requested data from the processor earlier, and writeback later.

The "accessed_way" register is probably not needed, as I could reutilize the way offset register to address the accessed_way, to update the LRU and valid at the end of the request.

This cache currently blocks the processor from doing any other instruction, as it requires the we, addr and din signals to be maintained trought the whole request. By utilizing some registers or even a FIFO, the cache could store the request, freeing the processor (non-blocking cache).

The cache could also be optmized by separating each way in a different ram bank. This would require only one cycle to check the blocks, instead of 2. This modification would require one more comparator to the hit, and the cache ram control signals would be split into w0_we, w0_addr, w0_din, w1_we, w1_addr, w1_din, etc.
