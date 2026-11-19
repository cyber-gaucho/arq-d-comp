module uart_rx #(
    parameter NB_DATA = 8,
    parameter NB_STOP = 1
) (
    // OUTPUTS
    output wire [NB_DATA-1:0] o_d_out,
    output wire               o_rx_done,

    // INPUTS
    input  wire               i_clock,
    input  wire               i_reset,
    input  wire               i_rx,
    input  wire               i_s_tick
);

    // -------------------------------------------------------------------------
    // Parametros locales
    // -------------------------------------------------------------------------
    localparam STOP_TICKS      = 16 * NB_STOP;
    localparam MAX_TICKS       = (STOP_TICKS > 16) ? STOP_TICKS : 16;
    localparam NB_TICK_COUNTER = $clog2(MAX_TICKS);
    localparam NB_DATA_COUNTER = (NB_DATA > 1) ? $clog2(NB_DATA) : 1;

    // -------------------------------------------------------------------------
    // Codificacion de estados (One-Hot)
    // -------------------------------------------------------------------------
    localparam [3:0] StIdle  = 4'b0001;
    localparam [3:0] StStart = 4'b0010;
    localparam [3:0] StData  = 4'b0100;
    localparam [3:0] StStop  = 4'b1000;

    reg [3:0]                 state_q;
    reg [3:0]                 state_d;
    reg [NB_TICK_COUNTER-1:0] tick_counter_q;
    reg [NB_DATA_COUNTER-1:0] data_counter_q;
    reg [NB_DATA-1:0]         data_q;
    reg                       rx_done_q;

    // Sincronizador de 2 etapas para entrada asincrona i_rx (prevencion de metaestabilidad)
    reg                       rx_sync1_q;
    reg                       rx_sync2_q;
    wire                      rx_sync;

    always @(posedge i_clock) begin : Rx_synchronizer
        if (i_reset) begin
            rx_sync1_q <= 1'b1;
            rx_sync2_q <= 1'b1;
        end else begin
            rx_sync1_q <= i_rx;
            rx_sync2_q <= rx_sync1_q;
        end
    end

    assign rx_sync = rx_sync2_q;

    // -------------------------------------------------------------------------
    // BLOQUE 1 - Registro de estado
    // -------------------------------------------------------------------------
    always @(posedge i_clock) begin : State_register
        if (i_reset) begin
            state_q <= StIdle;
        end else begin
            state_q <= state_d;
        end
    end

    // -------------------------------------------------------------------------
    // BLOQUE 2 - Logica de proximo estado
    // -------------------------------------------------------------------------
    always @(*) begin : Next_state_logic
        state_d = state_q;

        case (state_q)
            StIdle: begin
                if (!rx_sync) begin
                    state_d = StStart;
                end
            end

            StStart: begin
                if (i_s_tick && (tick_counter_q == 4'd7)) begin
                    // Validacion del bit de inicio: rechazo de glitch / ruido espurio
                    if (!rx_sync) begin
                        state_d = StData;
                    end else begin
                        state_d = StIdle;
                    end
                end
            end

            StData: begin
                if (i_s_tick && (tick_counter_q == 4'd15) &&
                    (data_counter_q == (NB_DATA - 1))) begin
                    state_d = StStop;
                end
            end

            StStop: begin
                if (i_s_tick && (tick_counter_q == (STOP_TICKS - 1))) begin
                    state_d = StIdle;
                end
            end

            default: begin
                // Recuperacion ante un estado invalido.
                state_d = StIdle;
            end
        endcase
    end

    // -------------------------------------------------------------------------
    // BLOQUE 3 - Registros internos del datapath
    // -------------------------------------------------------------------------
    always @(posedge i_clock) begin : Datapath_registers
        if (i_reset) begin
            tick_counter_q <= {NB_TICK_COUNTER{1'b0}};
            data_counter_q <= {NB_DATA_COUNTER{1'b0}};
            data_q         <= {NB_DATA{1'b0}};
            rx_done_q      <= 1'b0;
        end else begin
            // rx_done es un pulso de un ciclo de reloj.
            rx_done_q <= 1'b0;

            case (state_q)
                StIdle: begin
                    if (!rx_sync) begin
                        tick_counter_q <= {NB_TICK_COUNTER{1'b0}};
                    end
                end

                StStart: begin
                    if (i_s_tick) begin
                        if (tick_counter_q == 4'd7) begin
                            tick_counter_q <= {NB_TICK_COUNTER{1'b0}};
                            data_counter_q <= {NB_DATA_COUNTER{1'b0}};
                        end else begin
                            tick_counter_q <= tick_counter_q + 1'b1;
                        end
                    end
                end

                StData: begin
                    if (i_s_tick) begin
                        if (tick_counter_q == 4'd15) begin
                            tick_counter_q <= {NB_TICK_COUNTER{1'b0}};
                            data_counter_q <= data_counter_q + 1'b1;
                            // UART transmite LSB primero: el nuevo bit entra por MSB.
                            data_q <= {rx_sync, data_q[NB_DATA-1:1]};
                        end else begin
                            tick_counter_q <= tick_counter_q + 1'b1;
                        end
                    end
                end

                StStop: begin
                    if (i_s_tick) begin
                        if (tick_counter_q == (STOP_TICKS - 1)) begin
                            rx_done_q <= 1'b1;
                        end else begin
                            tick_counter_q <= tick_counter_q + 1'b1;
                        end
                    end
                end

                default: begin
                    // Los registros conservan su valor; la FSM se recupera en
                    // el siguiente ciclo mediante la logica de proximo estado.
                end
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // BLOQUE 4 - Logica de salidas
    // Las salidas se obtienen de registros, por lo que permanecen definidas
    // incluso durante la recuperacion de un estado invalido.
    // -------------------------------------------------------------------------
    assign o_rx_done = rx_done_q;
    assign o_d_out   = data_q;

endmodule
