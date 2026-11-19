// =============================================================================
// Modulo      : alu_ctrl
// Archivo     : alu_ctrl.v
// Descripcion : FSM de control de la ALU y ejecucion del protocolo PC <-> FPGA.
//               Consume los bytes deserializados de la FIFO de recepcion
//               (Operando A, Operando B, Codigo de Operacion), alimenta a la ALU
//               y escribe el resultado en la FIFO de transmision de la interfaz.
//
// Protocolo:
//   1. Byte 1: Operando A (NB_DATA bits)
//   2. Byte 2: Operando B (NB_DATA bits)
//   3. Byte 3: Codigo de operacion (NB_OP bits)
//   4. Respuesta: Resultado ALU escrito a w_data / wr
// =============================================================================

module alu_ctrl #(
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
    input  wire [NB_DATA-1:0] i_r_data,      // Dato recibido listo para leer
    input  wire               i_rx_empty,    // 1 si la FIFO RX esta vacia
    output reg                o_rd,          // Pulso de lectura para consumir byte

    output reg  [NB_DATA-1:0] o_w_data,      // Dato a transmitir hacia TX FIFO
    output reg                o_wr,          // Pulso de escritura para enviar byte
    input  wire               i_tx_full,     // 1 si la FIFO TX esta llena

    // -------------------------------------------------------------------------
    // INTERFAZ CON EL NUCLEO DE LA ALU (alu.v)
    // -------------------------------------------------------------------------
    output reg  [NB_DATA-1:0] o_operand_a,   // Registro operando A hacia ALU
    output reg  [NB_DATA-1:0] o_operand_b,   // Registro operando B hacia ALU
    output reg  [NB_OP-1:0]   o_operation,   // Registro operacion hacia ALU
    input  wire [NB_DATA-1:0] i_alu_result   // Resultado combinacional desde la ALU
);

    // -------------------------------------------------------------------------
    // Codificacion de estados (One-Hot)
    // -------------------------------------------------------------------------
    localparam [3:0] StWaitOpA     = 4'b0001;
    localparam [3:0] StWaitOpB     = 4'b0010;
    localparam [3:0] StWaitOpCode  = 4'b0100;
    localparam [3:0] StSendResult  = 4'b1000;

    // -------------------------------------------------------------------------
    // Registros internos y proximos estados (_q / _d)
    // -------------------------------------------------------------------------
    reg [3:0]         state_q,     state_d;
    reg [NB_DATA-1:0] operand_a_q, operand_a_d;
    reg [NB_DATA-1:0] operand_b_q, operand_b_d;
    reg [NB_OP-1:0]   operation_q, operation_d;

    // -------------------------------------------------------------------------
    // BLOQUE 1 - Logica Secuencial (Registros sincronos con reset activo en alto)
    // -------------------------------------------------------------------------
    always @(posedge i_clock) begin : Seq_logic
        if (i_reset) begin
            state_q     <= StWaitOpA;
            operand_a_q <= {NB_DATA{1'b0}};
            operand_b_q <= {NB_DATA{1'b0}};
            operation_q <= {NB_OP{1'b0}};
        end else begin
            state_q     <= state_d;
            operand_a_q <= operand_a_d;
            operand_b_q <= operand_b_d;
            operation_q <= operation_d;
        end
    end

    // -------------------------------------------------------------------------
    // BLOQUE 2 - Logica Combinacional de FSM y control de puertos
    // -------------------------------------------------------------------------
    always @(*) begin : Comb_logic
        state_d     = state_q;
        operand_a_d = operand_a_q;
        operand_b_d = operand_b_q;
        operation_d = operation_q;

        o_rd        = 1'b0;
        o_wr        = 1'b0;
        o_w_data    = i_alu_result;

        case (state_q)
            StWaitOpA: begin
                if (!i_rx_empty) begin
                    o_rd        = 1'b1;
                    operand_a_d = i_r_data;
                    state_d     = StWaitOpB;
                end
            end

            StWaitOpB: begin
                if (!i_rx_empty) begin
                    o_rd        = 1'b1;
                    operand_b_d = i_r_data;
                    state_d     = StWaitOpCode;
                end
            end

            StWaitOpCode: begin
                if (!i_rx_empty) begin
                    o_rd        = 1'b1;
                    operation_d = i_r_data[NB_OP-1:0];
                    state_d     = StSendResult;
                end
            end

            StSendResult: begin
                if (!i_tx_full) begin
                    o_w_data = i_alu_result;
                    o_wr     = 1'b1;
                    state_d  = StWaitOpA;
                end
            end

            default: begin
                state_d = StWaitOpA;
            end
        endcase
    end

    // -------------------------------------------------------------------------
    // Conexiones de salida hacia la ALU
    // -------------------------------------------------------------------------
    always @(*) begin : Output_assignment
        o_operand_a = operand_a_q;
        o_operand_b = operand_b_q;
        o_operation = operation_q;
    end

endmodule
