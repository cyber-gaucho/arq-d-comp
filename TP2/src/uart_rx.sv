module uart_rx #(
    //PARAMETERS
    parameter integer NB_DATA = 8,
    // PARITY  = 0,
    parameter integer NB_STOP = 1 // 8N1 by default
)
(
    //OUTPUTS
    output wire                     o_rx_done,
    output wire  [NB_DATA-1:0]      o_d_out,

    //INPUTS
    input wire                      i_rx,       // serial input
    input wire                      i_s_tick,   // (baud rate/16) tick 
    input wire                      i_clock     // 100 MHz
    // lleva reset?
);

    parameter    s1_idle        = 4'b0001;
    parameter    s2_start       = 4'b0010;
    parameter    s3_data        = 4'b0100;
    parameter    s4_stop        = 4'b1000;

    reg [3:0]    state          = s1_idle;
    reg [3:0]    next_state     = s1_idle;
    reg [3:0]    tick_counter   = 0      ;
    reg [3:0]    data_counter            ;
    reg          rx_done        = 0      ;
    reg [NB_DATA-1:0] data               ;
    reg          reset          = 1'b0   ;     // internal reset signal


    always @(posedge i_clock)                   // Memory
        if (reset)  state <= s1_idle   ;
        else        state <= next_state;





    always @(*)                                 // Next-state logic
    begin : Next_state_logic

        next_state = state;

        case (state)
            s1_idle: begin
                // algo
                if (i_rx == 0)
                begin
                    tick_counter = 0;
                    next_state = s2_start;
                end
            end
            s2_start: begin
                // algo
                if (i_s_tick == 1)
                begin
                    if (tick_counter == 7)
                    begin
                        tick_counter = 0;
                        data_counter = 0;
                        next_state = s3_data;
                    end
                    else
                        tick_counter = tick_counter + 1;
                end
            end
            s3_data: begin
                // algo
                if (i_s_tick == 1)
                begin
                    if (tick_counter == 15)
                    begin
                        tick_counter = 0;
                        data = {i_rx, data[NB_DATA-1:1]};   // cpncatena el dato al final
                        if (data_counter == NB_DATA-1)
                        begin
                            // acá podría ir el assign
                            next_state = s4_stop;
                        end
                        else
                            data_counter = data_counter + 1;
                    end
                    else
                        tick_counter = tick_counter + 1;
                end
            end
            s4_stop: begin
                // algo
                if (i_s_tick == 1)
                begin
                    if (tick_counter == (16*NB_STOP)-1)
                    begin
                        rx_done = 1;                // ver dónde se apaga esta señal
                        next_state = s1_idle;
                    end
                    else
                        tick_counter = tick_counter + 1;
                end
            end
            default: begin
                next_state = s1_idle;
            end
        endcase
    end

// OUTPUT ASSIGMENTS
assign o_rx_done = rx_done;

// ver dónde va esto (s3 o s4)
assign o_d_out = data;

endmodule

