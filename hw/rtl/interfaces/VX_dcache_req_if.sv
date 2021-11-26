`ifndef VX_DCACHE_REQ_IF
`define VX_DCACHE_REQ_IF

`include "../cache/VX_cache_define.vh"

interface VX_dcache_req_if #(
    parameter NUM_REQS  = 1,
    parameter WORD_SIZE = 1,
    parameter TAG_WIDTH = 1
) ();

    wire [NUM_REQS-1:0]                         valid;
    wire [NUM_REQS-1:0]                         rw;
    wire [NUM_REQS-1:0][`INST_MOD_BITS-1:0]     op_mod;
    wire [NUM_REQS-1:0]                         is_amo;
    wire [NUM_REQS-1:0][WORD_SIZE-1:0]          byteen;
    wire [NUM_REQS-1:0][`WORD_ADDR_WIDTH-1:0]   addr;
    wire [NUM_REQS-1:0][`WORD_WIDTH-1:0]        data;
    wire [NUM_REQS-1:0][TAG_WIDTH-1:0]          tag;    
    wire [NUM_REQS-1:0]                         ready;

    modport master (
        output valid,
        output rw,
        output op_mod,
        output is_amo,
        output byteen,
        output addr,
        output data,        
        output tag,
        input  ready
    );

    modport slave (
        input  valid,
        input  rw,
        input  op_mod,
        input  is_amo,
        input  byteen,
        input  addr,
        input  data,
        input  tag,
        output ready
    );

endinterface

`endif
