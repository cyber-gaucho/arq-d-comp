#!/bin/bash

set -e

TARGET=${1:-all}

cd "$(dirname "$0")/src"

run_alu() {
    echo "=== Testbench ALU ==="
    iverilog -g2012 -Wall -o tb_alu_sim tb_alu.sv alu.sv
    vvp tb_alu_sim
    rm -f tb_alu_sim
    echo
}

run_btn() {
    echo "=== Testbench btn_reg ==="
    iverilog -g2012 -Wall -o tb_btn_reg_sim tb_btn_reg.sv btn_reg.sv
    vvp tb_btn_reg_sim
    rm -f tb_btn_reg_sim
    echo
}

run_top() {
    echo "=== Testbench top ==="
    iverilog -g2012 -Wall -o tb_top_sim tb_top.sv top.sv btn_reg.sv alu.sv
    vvp tb_top_sim
    rm -f tb_top_sim
    echo
}

case "$TARGET" in
    alu)
        run_alu
        ;;

    btn)
        run_btn
        ;;

    top)
        run_top
        ;;

    all)
        run_alu
        run_btn
        run_top
        ;;

    *)
        echo "Uso: $0 [alu|btn|top|all]"
        exit 1
        ;;
esac

echo "=== Simulación finalizada correctamente ==="