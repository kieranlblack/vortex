#!/bin/bash

CMD_POLY_EVAL_PATH=$QUARTUS_HOME/dspba/backend/linux64

OPTIONS="-target Arria10 -lang verilog -frequency 300 -enableHardFP 1 -printMachineReadable -faithfulRounding  -noChanValid -enable -speedgrade 2"

export LD_LIBRARY_PATH=$CMD_POLY_EVAL_PATH:$LD_LIBRARY_PATH

CMD="$CMD_POLY_EVAL_PATH/cmdPolyEval $OPTIONS"

EXP_BITS=8
MAN_BITS=23
FBITS="f$(($EXP_BITS + $MAN_BITS + 1))"

echo Generating IP cores for $FBITS
{
    $CMD -name acl_fp_div  FPDiv  $EXP_BITS $MAN_BITS 0
    $CMD -name acl_fp_sqrt FPSqrt $EXP_BITS $MAN_BITS
    $CMD -name acl_fp_ftoi FPToFXP $EXP_BITS $MAN_BITS 32 0 1
    $CMD -name acl_fp_ftou FPToFXP $EXP_BITS $MAN_BITS 32 0 0
    $CMD -name acl_fp_itof FXPToFP 32 0 1 $EXP_BITS $MAN_BITS
    $CMD -name acl_fp_utof FXPToFP 32 0 0 $EXP_BITS $MAN_BITS
} > log.txt 2>&1

cp $QUARTUS_HOME/dspba/backend/Libraries/sv/base/dspba_library_ver.sv .