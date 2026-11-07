module uart_brg #(
    // PARAMETERS
    parameter BAUD_RATE  = 9_600,
    parameter CLOCK_FREQ = 100_000_000
) (
    // OUTPUTS
    output wire rate,

    // INPUTS
    input  wire i_clock,
    input  wire i_reset
);

    // INTERNAL PARAMETERS
    localparam OVERSAMPLE_RATE = 16;
    localparam TICK_FREQUENCY  = BAUD_RATE * OVERSAMPLE_RATE;
    // A division smaller than one clock cycle is clamped to one clock cycle.
    localparam TICK_CYCLES = (TICK_FREQUENCY == 0) ? 1 :
                             (CLOCK_FREQ / TICK_FREQUENCY);
    localparam COUNT_LIMIT = (TICK_CYCLES > 0) ?
                             TICK_CYCLES - 1 : 0;
    localparam NB_COUNT = (COUNT_LIMIT < 2) ? 1 :
                          $clog2(COUNT_LIMIT + 1);

    // INTERNAL SIGNALS
    reg  [NB_COUNT-1:0] counter_q;
    wire                count_limit;

    // COMPARISON LOGIC
    assign count_limit = (counter_q == COUNT_LIMIT);

    // COUNTER REGISTER
    always @(posedge i_clock) begin : Clock_counter
        if (i_reset || count_limit) begin
            counter_q <= {NB_COUNT{1'b0}};
        end else begin
            counter_q <= counter_q + 1'b1;
        end
    end

    // OUTPUT ASSIGNMENTS
    // rate is the one-clock s_tick pulse for uart_rx and uart_tx.
    assign rate = count_limit;

endmodule
