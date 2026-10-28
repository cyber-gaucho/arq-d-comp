module uart_tx #(
    // PARAMETERS
    parameter int NB_DATA = 8,
    parameter int NB_STOP = 1
) (
    // OUTPUTS
    output logic o_tx,
    output logic o_tx_done,

    // INPUTS
    input logic               i_clock,
    input logic               i_reset,
    input logic               i_tx_start,
    input logic               i_s_tick,
    input logic [NB_DATA-1:0] i_d_in
);

    // -------------------------------------------------------------------------
    // Parametros locales
    // -------------------------------------------------------------------------
    localparam int STOP_TICKS      = 16 * NB_STOP;
    localparam int MAX_TICKS       = (STOP_TICKS > 16) ? STOP_TICKS : 16;
    localparam int NB_TICK_COUNTER = $clog2(MAX_TICKS);
    localparam int NB_DATA_COUNTER = (NB_DATA > 1) ? $clog2(NB_DATA) : 1;

    // -------------------------------------------------------------------------
    // Codificacion de estados (One-Hot)
    // -------------------------------------------------------------------------
    typedef enum logic [3:0] {
        StIdle  = 4'b0001,
        StStart = 4'b0010,
        StData  = 4'b0100,
        StStop  = 4'b1000
    } state_t;

    state_t                     state_q;
    state_t                     state_d;
    logic [NB_TICK_COUNTER-1:0] tick_counter_q;
    logic [NB_DATA_COUNTER-1:0] data_counter_q;
    logic [NB_DATA-1:0]         data_q;
    logic                       tx_q;
    logic                       tx_done_q;

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
                if (i_tx_start) begin
                    state_d = StStart;
                end
            end

            StStart: begin
                if (i_s_tick && (tick_counter_q == NB_TICK_COUNTER'(15))) begin
                    state_d = StData;
                end
            end

            StData: begin
                if (i_s_tick && (tick_counter_q == NB_TICK_COUNTER'(15)) &&
                    (data_counter_q == NB_DATA_COUNTER'(NB_DATA - 1))) begin
                    state_d = StStop;
                end
            end

            StStop: begin
                if (i_s_tick && (tick_counter_q == NB_TICK_COUNTER'(STOP_TICKS - 1))) begin
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
            tx_q           <= 1'b1;
            tx_done_q      <= 1'b0;
        end else begin
            // tx_done es un pulso de un ciclo de reloj.
            tx_done_q <= 1'b0;

            case (state_q)
                StIdle: begin
                    tx_q <= 1'b1;
                    if (i_tx_start) begin
                        data_q         <= i_d_in;
                        tick_counter_q <= '0;
                        data_counter_q <= '0;
                    end
                end

                StStart: begin
                    tx_q <= 1'b0;
                    if (i_s_tick) begin
                        if (tick_counter_q == NB_TICK_COUNTER'(15)) begin
                            tick_counter_q <= '0;
                        end else begin
                            tick_counter_q <= tick_counter_q + 1'b1;
                        end
                    end
                end

                StData: begin
                    tx_q <= data_q[0];
                    if (i_s_tick) begin
                        if (tick_counter_q == NB_TICK_COUNTER'(15)) begin
                            tick_counter_q <= '0;
                            data_q         <= {1'b0, data_q[NB_DATA-1:1]};
                            if (data_counter_q == NB_DATA_COUNTER'(NB_DATA - 1)) begin
                                data_counter_q <= '0;
                            end else begin
                                data_counter_q <= data_counter_q + 1'b1;
                            end
                        end else begin
                            tick_counter_q <= tick_counter_q + 1'b1;
                        end
                    end
                end

                StStop: begin
                    tx_q <= 1'b1;
                    if (i_s_tick) begin
                        if (tick_counter_q == NB_TICK_COUNTER'(STOP_TICKS - 1)) begin
                            tx_done_q <= 1'b1;
                        end else begin
                            tick_counter_q <= tick_counter_q + 1'b1;
                        end
                    end
                end

                default: begin
                    // Los registros conservan un valor seguro ante estado invalido.
                    tx_q <= 1'b1;
                end
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // BLOQUE 4 - Logica de salidas
    // Las salidas se obtienen de registros, garantizando senales glitch-free.
    // -------------------------------------------------------------------------
    assign o_tx      = tx_q;
    assign o_tx_done = tx_done_q;

endmodule

