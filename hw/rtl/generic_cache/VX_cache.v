`include "VX_cache_config.vh"

module VX_cache #(
    // Size of cache in bytes
    parameter CACHE_SIZE_BYTES              = 1024, 
    // Size of line inside a bank in bytes
    parameter BANK_LINE_SIZE_BYTES          = 16, 
    // Number of banks {1, 2, 4, 8,...}
    parameter NUM_BANKS                     = 8, 
    // Size of a word in bytes
    parameter WORD_SIZE_BYTES               = 16, 
    // Number of Word requests per cycle {1, 2, 4, 8, ...}
    parameter NUM_REQUESTS                  = 2, 
    // Number of cycles to complete stage 1 (read from memory)
    parameter STAGE_1_CYCLES                = 2, 
    // Function ID, {Dcache=0, Icache=1, Sharedmemory=2}
    parameter FUNC_ID                       = 3,

    // Queues feeding into banks Knobs {1, 2, 4, 8, ...}

    // Core Request Queue Size
    parameter REQQ_SIZE                     = 8, 
    // Miss Reserv Queue Knob
    parameter MRVQ_SIZE                     = 8, 
    // Dram Fill Rsp Queue Size
    parameter DFPQ_SIZE                     = 2, 
    // Snoop Req Queue
    parameter SNRQ_SIZE                     = 8, 

    // Queues for writebacks Knobs {1, 2, 4, 8, ...}
    // Core Writeback Queue Size
    parameter CWBQ_SIZE                     = 8, 
    // Dram Writeback Queue Size
    parameter DWBQ_SIZE                     = 4, 
    // Dram Fill Req Queue Size
    parameter DFQQ_SIZE                     = 8, 
    // Lower Level Cache Hit Queue Size
    parameter LLVQ_SIZE                     = 16, 
    // Fill Forward SNP Queue
    parameter FFSQ_SIZE                     = 8,

    // Fill Invalidator Size {Fill invalidator must be active}
    parameter FILL_INVALIDAOR_SIZE          = 16, 

    // Prefetcher
    parameter PRFQ_SIZE                     = 64,
    parameter PRFQ_STRIDE                   = 0,

    // Dram knobs
    parameter SIMULATED_DRAM_LATENCY_CYCLES = 10
 ) (
	input wire clk,
	input wire reset,

    // Core request    
    input wire [NUM_REQUESTS-1:0]                 core_req_valid,
    input wire [NUM_REQUESTS-1:0][2:0]            core_req_read,
    input wire [NUM_REQUESTS-1:0][2:0]            core_req_write,
    input wire [NUM_REQUESTS-1:0][31:0]           core_req_addr,
    input wire [NUM_REQUESTS-1:0][`WORD_SIZE_RNG] core_req_data,
    output wire                                   core_req_ready,

    // Core request meta data
    input wire [4:0]                         core_req_rd,
    input wire [NUM_REQUESTS-1:0][1:0]       core_req_wb,
    input wire [`NW_BITS-1:0]                core_req_warp_num,
    input wire [31:0]                        core_req_pc,    

    // Core response
    output wire [NUM_REQUESTS-1:0]           core_rsp_valid,
    output wire [4:0]                        core_rsp_read,
    output wire [1:0]                        core_rsp_write,
    output wire [NUM_REQUESTS-1:0][31:0]     core_rsp_addr,
    output wire [NUM_REQUESTS-1:0][`WORD_SIZE_RNG] core_rsp_data,
    input  wire                              core_rsp_ready,    

    // Core response meta data
    output wire [`NW_BITS-1:0]               core_rsp_warp_num,    
    output wire [NUM_REQUESTS-1:0][31:0]     core_rsp_pc,
    
    // DRAM request
    output wire                              dram_req_read,
    output wire                              dram_req_write,    
    output wire [31:0]                       dram_req_addr,
    output wire [`IBANK_LINE_WORDS-1:0][31:0] dram_req_data,
    input  wire                              dram_req_ready,
    
    // DRAM response
    input  wire                              dram_rsp_valid,
    input  wire [31:0]                       dram_rsp_addr,
    input  wire [`IBANK_LINE_WORDS-1:0][31:0] dram_rsp_data,
    output wire                              dram_rsp_ready,    

    // Snoop Req
    input wire                               snp_req_valid,
    input wire [31:0]                        snp_req_addr,
    output wire                              snp_req_ready,

    // Snoop Forward
    output wire                              snp_fwd_valid,
    output wire [31:0]                       snp_fwd_addr,
    input  wire                              snp_fwd_ready
);

    wire [NUM_BANKS-1:0][NUM_REQUESTS-1:0]                per_bank_valids;
    
    wire [NUM_BANKS-1:0]                                  per_bank_core_rsp_pop;
    wire [NUM_BANKS-1:0]                                  per_bank_core_rsp_valid;
    wire [NUM_BANKS-1:0][`LOG2UP(NUM_REQUESTS)-1:0]       per_bank_core_rsp_tid;
    wire [NUM_BANKS-1:0][4:0]                             per_bank_core_rsp_rd;
    wire [NUM_BANKS-1:0][1:0]                             per_bank_core_rsp_wb;
    wire [NUM_BANKS-1:0][`NW_BITS-1:0]                    per_bank_core_rsp_warp_num;
    wire [NUM_BANKS-1:0][`WORD_SIZE_RNG]                  per_bank_core_rsp_data;
    wire [NUM_BANKS-1:0][31:0]                            per_bank_core_rsp_pc;
    wire [NUM_BANKS-1:0][31:0]                            per_bank_core_rsp_addr;

    wire                                                  dfqq_full;
    wire [NUM_BANKS-1:0]                                  per_bank_dram_fill_req_valid;
    wire [NUM_BANKS-1:0][31:0]                            per_bank_dram_fill_req_addr;
`DEBUG_BEGIN  
    wire [NUM_BANKS-1:0]                                  per_bank_dram_fill_req_is_snp;
`DEBUG_END
    wire [NUM_BANKS-1:0]                                  per_bank_dram_fill_rsp_ready;

    wire [NUM_BANKS-1:0]                                  per_bank_dram_wb_queue_pop;
    wire [NUM_BANKS-1:0]                                  per_bank_dram_wb_req_valid;    
    wire [NUM_BANKS-1:0][31:0]                            per_bank_dram_wb_req_addr;
    wire [NUM_BANKS-1:0][`BANK_LINE_WORDS-1:0][`WORD_SIZE-1:0] per_bank_dram_wb_req_data;

    wire [NUM_BANKS-1:0]                                  per_bank_reqq_full;
    wire [NUM_BANKS-1:0]                                  per_bank_snp_req_full;

    wire [NUM_BANKS-1:0]                                  per_bank_snp_fwd_valid;
    wire [NUM_BANKS-1:0][31:0]                            per_bank_snp_fwd_addr;
    wire [NUM_BANKS-1:0]                                  per_bank_snp_fwd_pop;

    assign core_req_ready = ~(|per_bank_reqq_full);
    assign snp_req_ready  = ~(|per_bank_snp_req_full);

    // assign dram_rsp_ready = (NUM_BANKS == 1) ? per_bank_dram_fill_rsp_ready[0] : per_bank_dram_fill_rsp_ready[dram_rsp_addr[`BANK_SELECT_ADDR_RNG]];
    assign dram_rsp_ready = (|per_bank_dram_fill_rsp_ready);

    VX_cache_dram_req_arb  #(
        .CACHE_SIZE_BYTES              (CACHE_SIZE_BYTES),
        .BANK_LINE_SIZE_BYTES          (BANK_LINE_SIZE_BYTES),
        .NUM_BANKS                     (NUM_BANKS),
        .WORD_SIZE_BYTES               (WORD_SIZE_BYTES),
        .NUM_REQUESTS                  (NUM_REQUESTS),
        .STAGE_1_CYCLES                (STAGE_1_CYCLES),
        .REQQ_SIZE                     (REQQ_SIZE),
        .MRVQ_SIZE                     (MRVQ_SIZE),
        .DFPQ_SIZE                     (DFPQ_SIZE),
        .SNRQ_SIZE                     (SNRQ_SIZE),
        .CWBQ_SIZE                     (CWBQ_SIZE),
        .DWBQ_SIZE                     (DWBQ_SIZE),
        .DFQQ_SIZE                     (DFQQ_SIZE),
        .LLVQ_SIZE                     (LLVQ_SIZE),
        .FILL_INVALIDAOR_SIZE          (FILL_INVALIDAOR_SIZE),
        .PRFQ_SIZE                     (PRFQ_SIZE),
        .PRFQ_STRIDE                   (PRFQ_STRIDE),
        .SIMULATED_DRAM_LATENCY_CYCLES (SIMULATED_DRAM_LATENCY_CYCLES)
    ) cache_dram_req_arb (
        .clk                           (clk),
        .reset                         (reset),
        .dfqq_full                     (dfqq_full),
        .per_bank_dram_fill_req_valid  (per_bank_dram_fill_req_valid),
        .per_bank_dram_fill_req_addr   (per_bank_dram_fill_req_addr),
        .per_bank_dram_wb_queue_pop    (per_bank_dram_wb_queue_pop),
        .per_bank_dram_wb_req_valid    (per_bank_dram_wb_req_valid),        
        .per_bank_dram_wb_req_addr     (per_bank_dram_wb_req_addr),
        .per_bank_dram_wb_req_data     (per_bank_dram_wb_req_data),
        .dram_req_read                 (dram_req_read),
        .dram_req_write                (dram_req_write),        
        .dram_req_addr                 (dram_req_addr),
        .dram_req_data                 (dram_req_data),  
        .dram_req_ready                (dram_req_ready)
    );

    VX_cache_core_req_bank_sel  #(
        .CACHE_SIZE_BYTES              (CACHE_SIZE_BYTES),
        .BANK_LINE_SIZE_BYTES          (BANK_LINE_SIZE_BYTES),
        .NUM_BANKS                     (NUM_BANKS),
        .WORD_SIZE_BYTES               (WORD_SIZE_BYTES),
        .NUM_REQUESTS                  (NUM_REQUESTS),
        .STAGE_1_CYCLES                (STAGE_1_CYCLES),
        .REQQ_SIZE                     (REQQ_SIZE),
        .MRVQ_SIZE                     (MRVQ_SIZE),
        .DFPQ_SIZE                     (DFPQ_SIZE),
        .SNRQ_SIZE                     (SNRQ_SIZE),
        .CWBQ_SIZE                     (CWBQ_SIZE),
        .DWBQ_SIZE                     (DWBQ_SIZE),
        .DFQQ_SIZE                     (DFQQ_SIZE),
        .LLVQ_SIZE                     (LLVQ_SIZE),
        .FILL_INVALIDAOR_SIZE          (FILL_INVALIDAOR_SIZE),
        .SIMULATED_DRAM_LATENCY_CYCLES (SIMULATED_DRAM_LATENCY_CYCLES)
    ) cache_core_req_bank_sell (
        .core_req_valid  (core_req_valid),
        .core_req_addr   (core_req_addr),
        .per_bank_valids (per_bank_valids)
    );

    VX_cache_wb_sel_merge  #(
        .CACHE_SIZE_BYTES             (CACHE_SIZE_BYTES),
        .BANK_LINE_SIZE_BYTES         (BANK_LINE_SIZE_BYTES),
        .NUM_BANKS                    (NUM_BANKS),
        .WORD_SIZE_BYTES              (WORD_SIZE_BYTES),
        .NUM_REQUESTS                 (NUM_REQUESTS),
        .STAGE_1_CYCLES               (STAGE_1_CYCLES),
        .FUNC_ID                      (FUNC_ID),
        .REQQ_SIZE                    (REQQ_SIZE),
        .MRVQ_SIZE                    (MRVQ_SIZE),
        .DFPQ_SIZE                    (DFPQ_SIZE),
        .SNRQ_SIZE                    (SNRQ_SIZE),
        .CWBQ_SIZE                    (CWBQ_SIZE),
        .DWBQ_SIZE                    (DWBQ_SIZE),
        .DFQQ_SIZE                    (DFQQ_SIZE),
        .LLVQ_SIZE                    (LLVQ_SIZE),
        .FILL_INVALIDAOR_SIZE         (FILL_INVALIDAOR_SIZE),
        .SIMULATED_DRAM_LATENCY_CYCLES(SIMULATED_DRAM_LATENCY_CYCLES)
    ) cache_core_rsp_sel_merge (
        .per_bank_wb_valid   (per_bank_core_rsp_valid),
        .per_bank_wb_tid     (per_bank_core_rsp_tid),
        .per_bank_wb_rd      (per_bank_core_rsp_rd),
        .per_bank_wb_pc      (per_bank_core_rsp_pc),
        .per_bank_wb_wb      (per_bank_core_rsp_wb),
        .per_bank_wb_warp_num(per_bank_core_rsp_warp_num),
        .per_bank_wb_data    (per_bank_core_rsp_data),
        .per_bank_wb_pop     (per_bank_core_rsp_pop),
        .per_bank_wb_addr    (per_bank_core_rsp_addr),

        .core_rsp_ready      (core_rsp_ready),
        .core_rsp_valid      (core_rsp_valid),
        .core_rsp_read       (core_rsp_read),
        .core_rsp_write      (core_rsp_write),
        .core_rsp_warp_num   (core_rsp_warp_num),
        .core_rsp_data       (core_rsp_data),
        .core_rsp_addr       (core_rsp_addr),
        .core_rsp_pc         (core_rsp_pc)
    );

    // Snoop Forward Logic
    VX_snp_fwd_arb #(
        .NUM_BANKS(NUM_BANKS)
    ) snp_fwd_arb(
        .per_bank_snp_fwd_valid (per_bank_snp_fwd_valid),
        .per_bank_snp_fwd_addr  (per_bank_snp_fwd_addr),
        .per_bank_snp_fwd_pop   (per_bank_snp_fwd_pop),
        .snp_fwd_valid          (snp_fwd_valid),
        .snp_fwd_addr           (snp_fwd_addr),
        .snp_fwd_ready          (snp_fwd_ready)
    );

    // Snoop Forward Logic

    genvar curr_bank;
    generate
        for (curr_bank = 0; curr_bank < NUM_BANKS; curr_bank=curr_bank+1) begin
            wire [NUM_REQUESTS-1:0]                curr_bank_core_req_valids;
            wire [NUM_REQUESTS-1:0][31:0]          curr_bank_core_req_addr;
            wire [NUM_REQUESTS-1:0][`WORD_SIZE_RNG] curr_bank_core_req_data;
            wire [4:0]                             curr_bank_core_req_rd;
            wire [NUM_REQUESTS-1:0][1:0]           curr_bank_core_req_wb;
            wire [`NW_BITS-1:0]                    curr_bank_core_warp_num;
            wire [NUM_REQUESTS-1:0][2:0]           curr_bank_core_req_read;  
            wire [NUM_REQUESTS-1:0][2:0]           curr_bank_core_req_write;
            wire [31:0]                            curr_bank_core_req_pc;

            wire                                   curr_bank_core_rsp_pop;
            wire                                   curr_bank_core_rsp_valid;
            wire [`LOG2UP(NUM_REQUESTS)-1:0]       curr_bank_core_rsp_tid;
            wire [31:0]                            curr_bank_core_rsp_pc;
            wire [4:0]                             curr_bank_core_rsp_rd;
            wire [1:0]                             curr_bank_core_rsp_wb;
            wire [`NW_BITS-1:0]                    curr_bank_core_rsp_warp_num;
            wire [`WORD_SIZE_RNG]                  curr_bank_core_rsp_data;
            wire [31:0]                            curr_bank_core_rsp_addr;

            wire                                   curr_bank_dram_fill_rsp_valid;
            wire [31:0]                            curr_bank_dram_fill_rsp_addr;
            wire [`BANK_LINE_WORDS-1:0][`WORD_SIZE-1:0] curr_bank_dram_fill_rsp_data;
            wire                                   curr_bank_dram_fill_rsp_ready;

            wire                                   curr_bank_dram_fill_req_full;
            wire                                   curr_bank_dram_fill_req_valid;
            wire                                   curr_bank_dram_fill_req_is_snp;
            wire[31:0]                             curr_bank_dram_fill_req_addr;

            wire                                   curr_bank_dram_wb_req_pop;
            wire                                   curr_bank_dram_wb_req_valid;
            wire[31:0]                             curr_bank_dram_wb_req_addr;
            wire[`BANK_LINE_WORDS-1:0][`WORD_SIZE-1:0] curr_bank_dram_wb_req_data;

            wire                                   curr_bank_snp_req;
            wire[31:0]                             curr_bank_snp_req_addr;

            wire                                   curr_bank_reqq_full;

            wire                                   curr_bank_snp_fwd_valid;
            wire[31:0]                             curr_bank_snp_fwd_addr;
            wire                                   curr_bank_snp_fwd_pop;
            wire                                   curr_bank_snp_req_full;            

            // Core Req
            assign curr_bank_core_req_valids     = per_bank_valids[curr_bank];
            assign curr_bank_core_req_addr       = core_req_addr;
            assign curr_bank_core_req_data       = core_req_data;
            assign curr_bank_core_req_rd         = core_req_rd;
            assign curr_bank_core_req_wb         = core_req_wb;
            assign curr_bank_core_req_pc         = core_req_pc;
            assign curr_bank_core_warp_num       = core_req_warp_num;
            assign curr_bank_core_req_read       = core_req_read;
            assign curr_bank_core_req_write      = core_req_write;
            assign per_bank_reqq_full[curr_bank] = curr_bank_reqq_full;

            // Core WB
            assign curr_bank_core_rsp_pop                = per_bank_core_rsp_pop[curr_bank];
            assign per_bank_core_rsp_valid   [curr_bank] = curr_bank_core_rsp_valid;
            assign per_bank_core_rsp_tid     [curr_bank] = curr_bank_core_rsp_tid;
            assign per_bank_core_rsp_rd      [curr_bank] = curr_bank_core_rsp_rd;
            assign per_bank_core_rsp_wb      [curr_bank] = curr_bank_core_rsp_wb;
            assign per_bank_core_rsp_warp_num[curr_bank] = curr_bank_core_rsp_warp_num;
            assign per_bank_core_rsp_data    [curr_bank] = curr_bank_core_rsp_data;
            assign per_bank_core_rsp_pc      [curr_bank] = curr_bank_core_rsp_pc;
            assign per_bank_core_rsp_addr    [curr_bank] = curr_bank_core_rsp_addr;

            // Dram fill request
            assign curr_bank_dram_fill_req_full             = dfqq_full;
            assign per_bank_dram_fill_req_valid[curr_bank]  = curr_bank_dram_fill_req_valid;
            assign per_bank_dram_fill_req_addr[curr_bank]   = curr_bank_dram_fill_req_addr;
            assign per_bank_dram_fill_req_is_snp[curr_bank] = curr_bank_dram_fill_req_is_snp;

            // Dram fill response
            assign curr_bank_dram_fill_rsp_valid           = (NUM_BANKS == 1) || (dram_rsp_valid && (curr_bank_dram_fill_rsp_addr[`BANK_SELECT_ADDR_RNG] == curr_bank));
            assign curr_bank_dram_fill_rsp_addr            = dram_rsp_addr;
            assign curr_bank_dram_fill_rsp_data            = dram_rsp_data;
            assign per_bank_dram_fill_rsp_ready[curr_bank] = curr_bank_dram_fill_rsp_ready;

            // Dram writeback request
            assign curr_bank_dram_wb_req_pop               = per_bank_dram_wb_queue_pop[curr_bank];
            assign per_bank_dram_wb_req_valid[curr_bank]   = curr_bank_dram_wb_req_valid;            
            assign per_bank_dram_wb_req_addr[curr_bank]    = curr_bank_dram_wb_req_addr;
            assign per_bank_dram_wb_req_data[curr_bank]    = curr_bank_dram_wb_req_data;

            // Snoop Request
            assign curr_bank_snp_req                = snp_req_valid && (snp_req_addr[`BANK_SELECT_ADDR_RNG] == curr_bank);
            assign curr_bank_snp_req_addr           = snp_req_addr;
            assign per_bank_snp_req_full[curr_bank] = curr_bank_snp_req_full;

            // Snoop Fwd            
            assign per_bank_snp_fwd_valid[curr_bank] = curr_bank_snp_fwd_valid;
            assign per_bank_snp_fwd_addr[curr_bank]  = curr_bank_snp_fwd_addr;
            assign curr_bank_snp_fwd_pop             = per_bank_snp_fwd_pop[curr_bank];
            
            VX_bank #(
                .CACHE_SIZE_BYTES             (CACHE_SIZE_BYTES),
                .BANK_LINE_SIZE_BYTES         (BANK_LINE_SIZE_BYTES),
                .NUM_BANKS                    (NUM_BANKS),
                .WORD_SIZE_BYTES              (WORD_SIZE_BYTES),
                .NUM_REQUESTS                 (NUM_REQUESTS),
                .STAGE_1_CYCLES               (STAGE_1_CYCLES),
                .FUNC_ID                      (FUNC_ID),
                .REQQ_SIZE                    (REQQ_SIZE),
                .MRVQ_SIZE                    (MRVQ_SIZE),
                .DFPQ_SIZE                    (DFPQ_SIZE),
                .SNRQ_SIZE                    (SNRQ_SIZE),
                .CWBQ_SIZE                    (CWBQ_SIZE),
                .DWBQ_SIZE                    (DWBQ_SIZE),
                .DFQQ_SIZE                    (DFQQ_SIZE),
                .LLVQ_SIZE                    (LLVQ_SIZE),
                .FFSQ_SIZE                    (FFSQ_SIZE),
                .FILL_INVALIDAOR_SIZE         (FILL_INVALIDAOR_SIZE),
                .SIMULATED_DRAM_LATENCY_CYCLES(SIMULATED_DRAM_LATENCY_CYCLES)
            ) bank (
                .clk                     (clk),
                .reset                   (reset),                
                // Core request
                .core_req_valids         (curr_bank_core_req_valids),                  
                .core_req_read           (curr_bank_core_req_read),
                .core_req_write          (curr_bank_core_req_write),              
                .core_req_addr           (curr_bank_core_req_addr),
                .core_req_data           (curr_bank_core_req_data),
                .core_req_rd             (curr_bank_core_req_rd),
                .core_req_wb             (curr_bank_core_req_wb),
                .core_req_pc             (curr_bank_core_req_pc),
                .core_req_warp_num       (curr_bank_core_warp_num),
                .core_req_full           (curr_bank_reqq_full),
                .core_req_ready          (core_req_ready),                

                // Core response                
                .core_rsp_valid          (curr_bank_core_rsp_valid),
                .core_rsp_tid            (curr_bank_core_rsp_tid),
                .core_rsp_rd             (curr_bank_core_rsp_rd),
                .core_rsp_wb             (curr_bank_core_rsp_wb),
                .core_rsp_warp_num       (curr_bank_core_rsp_warp_num),
                .core_rsp_data           (curr_bank_core_rsp_data),
                .core_rsp_pc             (curr_bank_core_rsp_pc),
                .core_rsp_addr           (curr_bank_core_rsp_addr),
                .core_rsp_pop            (curr_bank_core_rsp_pop),

                // Dram fill request
                .dram_fill_req_valid     (curr_bank_dram_fill_req_valid),
                .dram_fill_req_addr      (curr_bank_dram_fill_req_addr),
                .dram_fill_req_is_snp    (curr_bank_dram_fill_req_is_snp),
                .dram_fill_req_full      (curr_bank_dram_fill_req_full),

                // Dram fill response
                .dram_fill_rsp_valid     (curr_bank_dram_fill_rsp_valid),
                .dram_fill_rsp_addr      (curr_bank_dram_fill_rsp_addr),
                .dram_fill_rsp_data      (curr_bank_dram_fill_rsp_data),
                .dram_fill_rsp_ready     (curr_bank_dram_fill_rsp_ready),

                // Dram writeback request               
                .dram_wb_req_valid       (curr_bank_dram_wb_req_valid),
                .dram_wb_req_addr        (curr_bank_dram_wb_req_addr),
                .dram_wb_req_data        (curr_bank_dram_wb_req_data),   
                .dram_wb_req_pop         (curr_bank_dram_wb_req_pop),

                // Snoop request
                .snp_req_valid           (curr_bank_snp_req),
                .snp_req_addr            (curr_bank_snp_req_addr),
                .snp_req_full            (curr_bank_snp_req_full),

                // Snoop forwarding
                .snp_fwd_valid           (curr_bank_snp_fwd_valid),
                .snp_fwd_addr            (curr_bank_snp_fwd_addr),
                .snp_fwd_pop             (curr_bank_snp_fwd_pop)
            );
        end

    endgenerate
    
endmodule