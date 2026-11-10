#!/bin/bash

set -e

TARGET=${1:-all}

cd "$(dirname "$0")/src"

run_brg() {
    echo "=== Compilando y simulando UART BRG ==="
    iverilog -g2001 -Wall -o tb_uart_brg_sim uart_brg.v
    rm -f tb_uart_brg_sim
    echo "Compilacion de uart_brg.v exitosa."
    echo
}

run_tx() {
    echo "=== Testbench UART TX ==="
    iverilog -g2001 -Wall -o tb_uart_tx_sim tb_uart_tx.v uart_tx.v
    vvp tb_uart_tx_sim
    rm -f tb_uart_tx_sim
    echo
}

run_rx() {
    echo "=== Testbench UART RX ==="
    iverilog -g2001 -Wall -o tb_uart_rx_sim tb_uart_rx.v uart_rx.v
    vvp tb_uart_rx_sim
    rm -f tb_uart_rx_sim
    echo
}

run_loopback() {
    echo "=== Testbench UART Loopback ==="
    iverilog -g2001 -Wall -o tb_uart_loopback_sim tb_uart_loopback.v uart_brg.v uart_tx.v uart_rx.v
    vvp tb_uart_loopback_sim
    rm -f tb_uart_loopback_sim
    echo
}

run_interface() {
    echo "=== Testbench UART-ALU Interface ==="
    iverilog -g2001 -Wall -o tb_uart_alu_interface_sim \
        tb_uart_alu_interface.v \
        fifo.v \
        uart_alu_interface.v \
        alu.v \
        alu_ctrl.v \
        alu_top.v
    vvp tb_uart_alu_interface_sim
    rm -f tb_uart_alu_interface_sim
    echo
}

run_top() {
    echo "=== Testbench TOP (Full-System Integration) ==="
    iverilog -g2001 -Wall -o tb_top_sim tb_top.v top.v uart_brg.v uart_rx.v uart_tx.v uart_alu_interface.v fifo.v alu_top.v alu_ctrl.v alu.v
    vvp tb_top_sim
    rm -f tb_top_sim
    echo
}

case "$TARGET" in
    brg)
        run_brg
        ;;

    tx)
        run_tx
        ;;

    rx)
        run_rx
        ;;

    loopback)
        run_loopback
        ;;

    interface)
        run_interface
        ;;

    top)
        run_top
        ;;

    all)
        run_tx
        run_rx
        run_loopback
        run_interface
        run_top
        ;;

    *)
        echo "Uso: $0 [brg|tx|rx|loopback|interface|top|all]"
        exit 1
        ;;
esac

echo "=== Simulacion de TP2 finalizada correctamente ==="
