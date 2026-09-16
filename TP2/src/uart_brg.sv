module uart_brg #(
    //PARAMETERS
    parameter BAUD_RATE = 9600,
    parameter CLOCK_FREQ = 100000000
)
(
    //OUTPUTS
    output wire                     rate,      // tick
        
    //INPUTS
    input wire                      i_clock,   // 100 MHz
    input wire                      i_reset
);
    
    localparam integer TICK_CYCLES  = CLOCK_FREQ / (BAUD_RATE * 16);
    localparam integer COUNT_LIMIT  = (TICK_CYCLES > 0) ? TICK_CYCLES - 1 : 0;
    localparam integer NB_COUNT     = (COUNT_LIMIT < 2) ? 1 : $clog2(COUNT_LIMIT + 1);
    
    //INTERNAL SIGNALS
    reg          [NB_COUNT-1 : 0]   counter;
    wire                            count_limit;
    
    //ALGORITHM BEGIN
    always@(posedge i_clock) begin:ClockCounter
      if (i_reset | count_limit)
        counter <= '0;
      else
        counter <= counter + 1'b1;
    end

  	assign count_limit = (counter == COUNT_LIMIT);

    //OUTPUT ASSIGMENTS
    assign rate = count_limit;
endmodule

// BAUD RATE GENERATOR:
//  Genera un Tick 16 veces por Baud Rate
//  Si baud rate es 19.200 ciclos por segundo, la
//  frecuencia de muestreo debe ser 19.200 *16= 307.200
//  ticks por segundo. Si el clock de la placa es 50 Mhz,
//  hay que generar un tick cada 163 ciclos de reloj.
