// =============================================================================
// Modulo      : uart_alu_interface
// Archivo     : uart_alu_interface.v
// Descripcion : Circuito de Interfaz (Interface Circuit) entre la UART (Rx/Tx)
//               y el subsistema de la ALU.
//
// Diagrama de bloques (Ref: Presentacion FSM, diapositiva 21):
//
//                 +---------+
//   rx ---------->| uart_rx |--- d_out (i_rx_data) -----\
//                 |         |--- rx_done (i_rx_done) ---\
//                 +---------+                           |
//                                                       v
//                                            +---------------------+  r_data (o_r_data)    +----------+
//                                            |                     |---------------------->|          |
//                                            |  Interface Circuit  |  rx_empty (o_rx_empty)|   ALU    |
//                                            |                     |---------------------->| (Control |
//                                            |  - RX FIFO Buffer   |<-- rd (i_rd) ---------|  + Core) |
//                                            |  - TX FIFO Buffer   |                       |          |
//                                            |  - TX Serializer    |<-- w_data (i_w_data) -|          |
//                                            |                     |<-- wr (i_wr) ---------|          |
//                                            |                     |--- tx_full (o_tx_full)|          |
//                                            +---------------------+                       +----------+
//                                                       |
//                 +---------+                           |
//   tx <----------| uart_tx |<-- d_in (o_tx_data) ------/
//                 |         |<-- tx_start (o_tx_start) -/
//                 |         |--- tx_done (i_tx_done) ---/
//                 +---------+
// =============================================================================

module uart_alu_interface #(
    // PARAMETROS
    parameter NB_DATA    = 8,
    parameter FIFO_DEPTH = 8
) (
    // RELOJ Y RESET
    input  wire               i_clock,
    input  wire               i_reset,

    // -------------------------------------------------------------------------
    // LADO UART RX
    // -------------------------------------------------------------------------
    input  wire [NB_DATA-1:0] i_rx_data,     // Dato recibido desde uart_rx (d_out)
    input  wire               i_rx_done,     // Pulso de byte completado (rx_done)

    // -------------------------------------------------------------------------
    // LADO UART TX
    // -------------------------------------------------------------------------
    output reg  [NB_DATA-1:0] o_tx_data,     // Dato a transmitir hacia uart_tx (d_in)
    output reg                o_tx_start,    // Disparo de transmision (tx_start)
    input  wire               i_tx_done,     // Fin de transmision (tx_done)

    // -------------------------------------------------------------------------
    // LADO ALU (Interfaz tipo FIFO de la presentacion)
    // -------------------------------------------------------------------------
    output wire [NB_DATA-1:0] o_r_data,      // Dato disponible recibido
    input  wire               i_rd,          // Lectura / pop de un byte desde la ALU
    output wire               o_rx_empty,    // 1 si no hay datos en RX FIFO

    input  wire [NB_DATA-1:0] i_w_data,      // Dato a transmitir escrito por la ALU
    input  wire               i_wr,          // Escritura / push de un byte hacia TX FIFO
    output wire               o_tx_full      // 1 si TX FIFO esta llena
);

    // -------------------------------------------------------------------------
    // Señales de interconexion con FIFOs
    // -------------------------------------------------------------------------
    wire [NB_DATA-1:0] tx_fifo_r_data;
    wire               tx_fifo_empty;
    reg                tx_fifo_rd;

    // -------------------------------------------------------------------------
    // Instancia 1: FIFO de Recepcion (RX FIFO)
    // -------------------------------------------------------------------------
    fifo #(
        .NB_DATA    (NB_DATA),
        .FIFO_DEPTH (FIFO_DEPTH)
    ) u_fifo_rx (
        .i_clock    (i_clock),
        .i_reset    (i_reset),
        .i_wr       (i_rx_done),
        .i_w_data   (i_rx_data),
        .o_full     (),              // Monitoreo opcional
        .i_rd       (i_rd),
        .o_r_data   (o_r_data),
        .o_empty    (o_rx_empty)
    );

    // -------------------------------------------------------------------------
    // Instancia 2: FIFO de Transmision (TX FIFO)
    // -------------------------------------------------------------------------
    fifo #(
        .NB_DATA    (NB_DATA),
        .FIFO_DEPTH (FIFO_DEPTH)
    ) u_fifo_tx (
        .i_clock    (i_clock),
        .i_reset    (i_reset),
        .i_wr       (i_wr),
        .i_w_data   (i_w_data),
        .o_full     (o_tx_full),
        .i_rd       (tx_fifo_rd),
        .o_r_data   (tx_fifo_r_data),
        .o_empty    (tx_fifo_empty)
    );

    // -------------------------------------------------------------------------
    // FSM de control de transmision (Serializer hacia UART TX)
    // -------------------------------------------------------------------------
    localparam [1:0] StTxIdle = 2'b01;
    localparam [1:0] StTxWait = 2'b10;

    reg [1:0]         tx_state_q,   tx_state_d;
    reg [NB_DATA-1:0] tx_data_q,    tx_data_d;
    reg               tx_start_q,   tx_start_d;

    // BLOQUE 1 - Logica Secuencial
    always @(posedge i_clock) begin : Seq_tx_fsm
        if (i_reset) begin
            tx_state_q <= StTxIdle;
            tx_data_q  <= {NB_DATA{1'b0}};
            tx_start_q <= 1'b0;
        end else begin
            tx_state_q <= tx_state_d;
            tx_data_q  <= tx_data_d;
            tx_start_q <= tx_start_d;
        end
    end

    // BLOQUE 2 - Logica Combinacional de FSM
    always @(*) begin : Comb_tx_fsm
        tx_state_d = tx_state_q;
        tx_data_d  = tx_data_q;
        tx_start_d = 1'b0;
        tx_fifo_rd = 1'b0;

        case (tx_state_q)
            StTxIdle: begin
                if (!tx_fifo_empty) begin
                    tx_fifo_rd = 1'b1;
                    tx_data_d  = tx_fifo_r_data;
                    tx_start_d = 1'b1;
                    tx_state_d = StTxWait;
                end
            end

            StTxWait: begin
                if (i_tx_done) begin
                    tx_state_d = StTxIdle;
                end
            end

            default: begin
                tx_state_d = StTxIdle;
            end
        endcase
    end

    // Asignacion de salidas hacia UART TX
    always @(*) begin : Output_assignment
        o_tx_data  = tx_data_q;
        o_tx_start = tx_start_q;
    end

endmodule
