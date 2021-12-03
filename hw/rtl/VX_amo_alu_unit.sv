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
    input wire [4:0]        alu_op,
    input wire [31:0]       alu_in1,
    input wire [31:0]       alu_in2,
    output reg [31:0]       alu_result
);   
    // `UNUSED_PARAM (CORE_ID)
    // im not sure if we need this.
    `UNUSED_PARAM (DATAW)

    wire alu_signed = ~(alu_op == `INST_AMO_MINU || alu_op == `INST_AMO_MAXU);

    wire [32:0] sub_in1 = {alu_signed & alu_in1[31], alu_in1};
    wire [32:0] sub_in2 = {alu_signed & alu_in2[31], alu_in2};

    wire is_less = sub_in1 < sub_in2;

    always @(posedge clk) begin
        if (reset) begin
            alu_result <= 32'b0;
        end else begin
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
                default: alu_result <= 32'b0;
            endcase    
        end
    end

endmodule