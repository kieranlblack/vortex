`include "VX_define.vh"

module VX_amo_alu_unit #(
    // we don't care about the different cores.
    // parameter CORE_ID = 0
    parameter DATAW = 32
) (
    input wire              clk,
    input wire              reset,
    
    // Inputs
    //VX_amo_alu_req_if.slave     amo_alu_req_if,
    input wire [4:0]        alu_op
    input wire [31:0]       alu_in1;
    input wire [31:0]       alu_in2;
    output reg [31:0]       alu_result;
);   
    // `UNUSED_PARAM (CORE_ID)
    `UNUSED_PARAM (DATAW)
    // wire ready_in;


    // removed after removing the if.
    // wire alu_op = amo_alu_req_if.op_mod;
    // this will just be inputed.
    // wire [31:0] alu_in1 = amo_alu_req_if.rs1_data;
    // this one stays the same
    // wire [31:0] alu_in2 = amo_alu_req_if.rs2_data;

    // i think this is wrong?
    wire alu_signed = ~(alu_op == `INST_AMO_MIN && alu_op == `INST_AMO_MAX);

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


    // output
    // our alu is finished in 1 cycle. and it doesnt need to be sure to be ready in the future. The ready for our amo
    // instructions is handle by the same wires that handle the ld instruction
    /*
    wire                          alu_valid_in;
    wire                          alu_ready_in;
    wire                          alu_valid_out;
    wire                          alu_ready_out;
    wire [`NUM_THREADS-1:0][31:0] alu_data;

    assign alu_ready_out = 1'b1;
    assign ready_in = alu_ready_in;
    assign alu_valid_in = alu_req_if.valid;

    // assign alu_req_if.ready = ready_in;
    */

/*
`ifdef DBG_TRACE_PIPELINE
    always @(posedge clk) begin
        if (branch_ctl_if.valid) begin
            dpi_trace("%d: core%0d-branch: wid=%0d, PC=%0h, taken=%b, dest=%0h\n", 
                $time, CORE_ID, branch_ctl_if.wid, alu_commit_if.PC, branch_ctl_if.taken, branch_ctl_if.dest);
        end
    end
`endif
*/

endmodule