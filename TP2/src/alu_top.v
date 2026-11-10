// =============================================================================
// Modulo      : alu_top
// Archivo     : alu_top.v
// Descripcion : Subsistema de la ALU que integra la FSM de protocolo (alu_ctrl)
//               y el nucleo combinacional aritmetico-logico (alu).
//               Se conecta directamente al Circuito de Interfaz UART mediante
//               las senales tipo FIFO de la presentacion (r_data, rd, rx_empty,
//               w_data, wr, tx_full).
// =============================================================================

module alu_top #(
    // PARAMETROS
    parameter NB_DATA = 8,
    parameter NB_OP   = 6
) (
    // RELOJ Y RESET
    input  wire               i_clock,
    input  wire               i_reset,

    // -------------------------------------------------------------------------
    // INTERFAZ CON CIRCUITO DE INTERFAZ (uart_alu_interface)
    // -------------------------------------------------------------------------
    input  wire [NB_DATA-1:0] i_r_data,      // Dato recibido desde la FIFO RX
    input  wire               i_rx_empty,    // 1 si la FIFO RX esta vacia
    output wire               o_rd,          // Pulso de lectura para consumir byte

    output wire [NB_DATA-1:0] o_w_data,      // Dato a transmitir hacia la FIFO TX
    output wire               o_wr,          // Pulso de escritura para enviar byte
    input  wire               i_tx_full,     // 1 si la FIFO TX esta llena

    // -------------------------------------------------------------------------
    // BANDERAS HACIA LEDS DE LA PLACA
    // -------------------------------------------------------------------------
    output wire               o_zero,
    output wire               o_overflow
);

    // Senales internas de interconexion entre alu_ctrl y alu
    wire [NB_DATA-1:0] operand_a;
    wire [NB_DATA-1:0] operand_b;
    wire [NB_OP-1:0]   operation;
    wire [NB_DATA-1:0] alu_result;

    // -------------------------------------------------------------------------
    // Instancia 1: Controlador de Protocolo y Registros de la ALU
    // -------------------------------------------------------------------------
    alu_ctrl #(
        .NB_DATA (NB_DATA),
        .NB_OP   (NB_OP)
    ) u_alu_ctrl (
        .i_clock      (i_clock),
        .i_reset      (i_reset),

        // Lado Interface Circuit
        .i_r_data     (i_r_data),
        .i_rx_empty   (i_rx_empty),
        .o_rd         (o_rd),
        .o_w_data     (o_w_data),
        .o_wr         (o_wr),
        .i_tx_full    (i_tx_full),

        // Lado Core ALU
        .o_operand_a  (operand_a),
        .o_operand_b  (operand_b),
        .o_operation  (operation),
        .i_alu_result (alu_result)
    );

    // -------------------------------------------------------------------------
    // Instancia 2: Nucleo Combinacional de la ALU
    // -------------------------------------------------------------------------
    alu #(
        .NB_DATA (NB_DATA)
    ) u_alu (
        .i_operand_a (operand_a),
        .i_operand_b (operand_b),
        .i_operation (operation),
        .o_result    (alu_result),
        .o_overflow  (o_overflow),
        .o_zero      (o_zero)
    );

endmodule
