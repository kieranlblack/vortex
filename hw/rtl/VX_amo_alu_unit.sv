`include "VX_define.vh"

module VX_amo_alu_unit #(
    parameter CORE_ID = 0
) (
    input wire              clk,
    input wire              reset,
    
    // Inputs
    VX_alu_req_if.slave     alu_req_if,

    // Outputs
    VX_commit_if.master     alu_commit_if
);   
    `UNUSED_PARAM (CORE_ID)
    
    wire [31:0] alu_result;

    wire ready_in;

    wire alu_op = alu_req_if.op_mod;
    wire alu_signed = ~(alu_op == `INST_AMO_MIN && alu_op == `INST_AMO_MAX);

    // this will just be inputed.
    wire [31:0] alu_in1 = alu_req_if.rs1_data;
    // this one stays the same
    wire [31:0] alu_in2 = alu_req_if.rs2_data;

    wire [32:0] sub_in1 = {alu_signed & alu_in1[31], alu_in1};
    wire [32:0] sub_in2 = {alu_signed & alu_in2[31], alu_in2};

    wire is_less = sub_in1 < sub_in2;


    always @(*) begin
        case(alu_op) 
            `INST_AMO_ADD: alu_result <= alu_in1 + alu_in2;
            `INST_AMO_SWAP: alu_result <= alu_in2;
            `INST_AMO_XOR: alu_result <= alu_in1 ^ alu_in2;
            `INST_AMO_OR: alu_result <= alu_in1 | alu_in2;
            `INST_AMO_AND: alu_result <= alu_in1 & alu_in2;
            `INST_AMO_MIN: alu_result <= is_less ? alu_in1 : alu_in2;
            `INST_AMO_MAX: alu_result <= is_less ? alu_in2 : alu_in1;
            `INST_AMO_MINU: alu_result <= is_less ? alu_in1 : alu_in2;
            `INST_AMO_MAXU: alu_result <= is_less ? alu_in2 : alu_in1;
            default: alu_result <= -1;
        endcase    
    end

    assign alu_ready_out = 1'b1;

    // output

    wire                          alu_valid_in;
    wire                          alu_ready_in;
    wire                          alu_valid_out;
    wire                          alu_ready_out;
    wire [`NW_BITS-1:0]           alu_wid;
    wire [31:0]                   alu_PC;
    wire [`NR_BITS-1:0]           alu_rd;   
    wire                          alu_wb; 
    wire [`NUM_THREADS-1:0][31:0] alu_data;

    assign ready_in = alu_ready_in;

    assign alu_valid_in = alu_req_if.valid;

    // can accept new request?
    assign alu_req_if.ready = ready_in;

`ifdef DBG_TRACE_PIPELINE
    always @(posedge clk) begin
        if (branch_ctl_if.valid) begin
            dpi_trace("%d: core%0d-branch: wid=%0d, PC=%0h, taken=%b, dest=%0h\n", 
                $time, CORE_ID, branch_ctl_if.wid, alu_commit_if.PC, branch_ctl_if.taken, branch_ctl_if.dest);
        end
    end
`endif

endmodule