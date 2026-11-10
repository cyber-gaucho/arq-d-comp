// =============================================================================
// Modulo      : top
// Archivo     : top.v
// Descripcion : Modulo de nivel superior (Top-Level) para el TP2 en la FPGA
//               Digilent Basys 3.
//               Integra:
//                 - Baud Rate Generator (uart_brg)
//                 - Receptor UART (uart_rx)
//                 - Transmisor UART (uart_tx)
//                 - Circuito de Interfaz / Buffers FIFO (uart_alu_interface)
//                 - Subsistema de la ALU: FSM de control y core ALU (alu_top)
//
// Entradas y Salidas fisicas:
//   - CLK100MHZ : Reloj de 100 MHz de la placa.
//   - btnR      : Reset sincrono activo en alto.
//   - RsRx      : Entrada serie UART desde el puente USB-RS232.
//   - RsTx      : Salida serie UART hacia el puente USB-RS232.
//   - LED[15:0] :
//       LED[7:0]  = Ultimo resultado calculado por la ALU (w_data retenido).
//       LED[13:8] = 0 (apagados).
//       LED[14]   = Flag Zero (o_zero).
//       LED[15]   = Flag Overflow (o_overflow).
// =============================================================================

module top #(
    // PARAMETROS DE CONFIGURACION GLOBAL
    parameter CLOCK_FREQ = 100_000_000, // 100 MHz de la Basys 3
    parameter BAUD_RATE  = 9_600,       // 9600 baudios por defecto
    parameter NB_DATA    = 8,           // Ancho de datos: 8 bits
    parameter NB_STOP    = 1,           // Bits de parada: 1
    parameter NB_OP      = 6,           // Codigo de operacion: 6 bits
    parameter FIFO_DEPTH = 8            // Profundidad de FIFOs RX/TX
) (
    // RELOJ Y RESET
    input  wire        CLK100MHZ,
    input  wire        btnR,

    // LINEAS SERIE UART (USB-RS232)
    input  wire        RsRx,
    output wire        RsTx,

    // VISUALIZACION EN LEDS
    output wire [15:0] LED
);

    // -------------------------------------------------------------------------
    // SENALES INTERNAS DE INTERCONEXION ESTRUCTURAL
    // -------------------------------------------------------------------------

    // Pulso de sobremuestreo del Baud Rate Generator (16x Baud Rate)
    wire               s_tick;

    // Conexion UART RX -> Circuito de Interfaz
    wire [NB_DATA-1:0] rx_data;
    wire               rx_done;

    // Conexion Circuito de Interfaz -> UART TX
    wire [NB_DATA-1:0] tx_data;
    wire               tx_start;
    wire               tx_done;

    // Conexion Circuito de Interfaz <-> Subsistema ALU (alu_top)
    wire [NB_DATA-1:0] r_data;
    wire               rx_empty;
    wire               rd;

    wire [NB_DATA-1:0] w_data;
    wire               wr;
    wire               tx_full;

    // Salidas de flags del subsistema ALU
    wire               alu_zero;
    wire               alu_overflow;

    // -------------------------------------------------------------------------
    // 1. GENERADOR DE BAUDIOS (Baud Rate Generator)
    // -------------------------------------------------------------------------
    uart_brg #(
        .BAUD_RATE  (BAUD_RATE),
        .CLOCK_FREQ (CLOCK_FREQ)
    ) u_uart_brg (
        .rate       (s_tick),
        .i_clock    (CLK100MHZ),
        .i_reset    (btnR)
    );

    // -------------------------------------------------------------------------
    // 2. RECEPTOR UART (uart_rx)
    // -------------------------------------------------------------------------
    uart_rx #(
        .NB_DATA    (NB_DATA),
        .NB_STOP    (NB_STOP)
    ) u_uart_rx (
        .o_d_out    (rx_data),
        .o_rx_done  (rx_done),
        .i_clock    (CLK100MHZ),
        .i_reset    (btnR),
        .i_rx       (RsRx),
        .i_s_tick   (s_tick)
    );

    // -------------------------------------------------------------------------
    // 3. TRANSMISOR UART (uart_tx)
    // -------------------------------------------------------------------------
    uart_tx #(
        .NB_DATA    (NB_DATA),
        .NB_STOP    (NB_STOP)
    ) u_uart_tx (
        .o_tx       (RsTx),
        .o_tx_done  (tx_done),
        .i_clock    (CLK100MHZ),
        .i_reset    (btnR),
        .i_tx_start (tx_start),
        .i_s_tick   (s_tick),
        .i_d_in     (tx_data)
    );

    // -------------------------------------------------------------------------
    // 4. CIRCUITO DE INTERFAZ / BUFFERS FIFO (uart_alu_interface)
    // -------------------------------------------------------------------------
    uart_alu_interface #(
        .NB_DATA    (NB_DATA),
        .FIFO_DEPTH (FIFO_DEPTH)
    ) u_uart_alu_interface (
        .i_clock    (CLK100MHZ),
        .i_reset    (btnR),

        // Lado UART RX
        .i_rx_data  (rx_data),
        .i_rx_done  (rx_done),

        // Lado UART TX
        .o_tx_data  (tx_data),
        .o_tx_start (tx_start),
        .i_tx_done  (tx_done),

        // Lado Subsistema ALU
        .o_r_data   (r_data),
        .i_rd       (rd),
        .o_rx_empty (rx_empty),

        .i_w_data   (w_data),
        .i_wr       (wr),
        .o_tx_full  (tx_full)
    );

    // -------------------------------------------------------------------------
    // 5. SUBSISTEMA DE LA ALU (alu_top: FSM alu_ctrl + core alu)
    // -------------------------------------------------------------------------
    alu_top #(
        .NB_DATA    (NB_DATA),
        .NB_OP      (NB_OP)
    ) u_alu_top (
        .i_clock    (CLK100MHZ),
        .i_reset    (btnR),

        // Interfaz FIFO con el Circuito de Interfaz
        .i_r_data   (r_data),
        .i_rx_empty (rx_empty),
        .o_rd       (rd),

        .o_w_data   (w_data),
        .o_wr       (wr),
        .i_tx_full  (tx_full),

        // Salidas hacia LEDs
        .o_zero     (alu_zero),
        .o_overflow (alu_overflow)
    );

    // -------------------------------------------------------------------------
    // 6. MAPEO DE SALIDAS A LOS LEDS DE LA BASYS 3 (misma convencion que TP1)
    // -------------------------------------------------------------------------
    assign LED[7:0]  = w_data;
    assign LED[13:8] = 6'b0;
    assign LED[14]   = alu_zero;
    assign LED[15]   = alu_overflow;

endmodule
