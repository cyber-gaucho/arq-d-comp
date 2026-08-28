module contador_de_clocks 
#(
  //PARAMETERS
  parameter COUNT_LIMIT = 7                                    ,
  parameter NB_COUNT    = 4
)
(
  //OUTPUTS
  output wire                     o_count                      ,
    
  //INPUTS
  input wire                      i_clock                      ,
  input wire                      i_reset
);
    //INTERNAL SIGNALS
  	reg          [NB_COUNT-1 : 0]  counter                     ;
    wire                           count_limit                 ;

    //ALGORITHM BEGIN
    always@(posedge i_clock) begin:ClockCounter
      if (i_reset | count_limit)
      		counter <= 'b0                ;
      else
            counter <= counter + 'b1     ;
    end

  	assign count_limit = (counter == COUNT_LIMIT);

    //OUTPUT ASSIGMENTS
    assign o_count = count_limit;
endmodule


//// Escribir el código para un contador simple de pulsos de clock,
//// el contador deberá emitir un pulso en alto "o_count" al alcanzar la
//// cuenta "N_COUNT" (N_COUNT es un parámetro del módulo), la duración de este 
//// pulso es de 1 clock.  Además de la entrada de clock "i_clock", el contador 
//// debe agregar una entrada "i_valid" la cual indica si el pulso de clock 
//// entrante es valido o no, en caso de no serlo la cuenta no debe avanzar.
