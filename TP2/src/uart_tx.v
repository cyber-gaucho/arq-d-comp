module uart_tx #(
    // PARAMETERS
    parameter NB_DATA = 8,
    parameter NB_STOP = 1
) (
    // OUTPUTS
    output wire               o_tx,
    output wire               o_tx_done,

    // INPUTS
    input  wire               i_clock,
    input  wire               i_reset,
    input  wire               i_tx_start,
    input  wire               i_s_tick,
    input  wire [NB_DATA-1:0] i_d_in
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
    reg                       tx_q;
    reg                       tx_done_q;

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
                if (i_tx_start) begin
                    state_d = StStart;
                end
            end

            StStart: begin
                if (i_s_tick && (tick_counter_q == 15)) begin
                    state_d = StData;
                end
            end

            StData: begin
                if (i_s_tick && (tick_counter_q == 15) &&
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
                        tick_counter_q <= {NB_TICK_COUNTER{1'b0}};
                        data_counter_q <= {NB_DATA_COUNTER{1'b0}};
                    end
                end

                StStart: begin
                    tx_q <= 1'b0;
                    if (i_s_tick) begin
                        if (tick_counter_q == 15) begin
                            tick_counter_q <= {NB_TICK_COUNTER{1'b0}};
                        end else begin
                            tick_counter_q <= tick_counter_q + 1'b1;
                        end
                    end
                end

                StData: begin
                    tx_q <= data_q[0];
                    if (i_s_tick) begin
                        if (tick_counter_q == 15) begin
                            tick_counter_q <= {NB_TICK_COUNTER{1'b0}};
                            data_q         <= {1'b0, data_q[NB_DATA-1:1]};
                            if (data_counter_q == (NB_DATA - 1)) begin
                                data_counter_q <= {NB_DATA_COUNTER{1'b0}};
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
                        if (tick_counter_q == (STOP_TICKS - 1)) begin
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
