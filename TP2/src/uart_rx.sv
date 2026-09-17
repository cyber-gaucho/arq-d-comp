module uart_rx #(
    parameter int NB_DATA = 8,
    parameter int NB_STOP = 1
) (
    // OUTPUTS
    output logic [NB_DATA-1:0] o_d_out,
    output logic               o_rx_done,

    // INPUTS
    input logic i_clock,
    input logic i_reset,
    input logic i_rx,
    input logic i_s_tick
);

    // -------------------------------------------------------------------------
    // Codificacion de estados (One-Hot)
    // -------------------------------------------------------------------------
    typedef enum logic [3:0] {
        StIdle  = 4'b0001,
        StStart = 4'b0010,
        StData  = 4'b0100,
        StStop  = 4'b1000
    } state_t;

    state_t             state_q;
    state_t             state_d;
    logic [3:0]         tick_counter_q;
    logic [3:0]         data_counter_q;
    logic [NB_DATA-1:0] data_q;
    logic               rx_done_q;

    // -------------------------------------------------------------------------
    // BLOQUE 1 - Registro de estado
    // -------------------------------------------------------------------------
    always_ff @(posedge i_clock) begin : State_register
        if (i_reset) begin
            state_q <= StIdle;
        end else begin
            state_q <= state_d;
        end
    end

    // -------------------------------------------------------------------------
    // BLOQUE 2 - Logica de proximo estado
    // -------------------------------------------------------------------------
    always_comb begin : Next_state_logic
        state_d = state_q;

        case (state_q)
            StIdle: begin
                if (!i_rx) begin
                    state_d = StStart;
                end
            end

            StStart: begin
                if (i_s_tick && (tick_counter_q == 4'd7)) begin
                    state_d = StData;
                end
            end

            StData: begin
                if (i_s_tick && (tick_counter_q == 4'd15) &&
                    (data_counter_q == NB_DATA - 1)) begin
                    state_d = StStop;
                end
            end

            StStop: begin
                if (i_s_tick && (tick_counter_q == (16 * NB_STOP) - 1)) begin
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
    always_ff @(posedge i_clock) begin : Datapath_registers
        if (i_reset) begin
            tick_counter_q <= '0;
            data_counter_q <= '0;
            data_q         <= '0;
            rx_done_q      <= 1'b0;
        end else begin
            // rx_done es un pulso de un ciclo de reloj.
            rx_done_q <= 1'b0;

            case (state_q)
                StIdle: begin
                    if (!i_rx) begin
                        tick_counter_q <= '0;
                    end
                end

                StStart: begin
                    if (i_s_tick) begin
                        if (tick_counter_q == 4'd7) begin
                            tick_counter_q <= '0;
                            data_counter_q <= '0;
                        end else begin
                            tick_counter_q <= tick_counter_q + 1'b1;
                        end
                    end
                end

                StData: begin
                    if (i_s_tick) begin
                        if (tick_counter_q == 4'd15) begin
                            tick_counter_q <= '0;
                            data_counter_q <= data_counter_q + 1'b1;
                            // UART transmite LSB primero: el nuevo bit entra por MSB.
                            data_q <= {i_rx, data_q[NB_DATA-1:1]};
                        end else begin
                            tick_counter_q <= tick_counter_q + 1'b1;
                        end
                    end
                end

                StStop: begin
                    if (i_s_tick) begin
                        if (tick_counter_q == (16 * NB_STOP) - 1) begin
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
