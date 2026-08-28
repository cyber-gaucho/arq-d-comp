module sumador_for #(
    //Parameters 
    parameter N_TERM  =  4,
    parameter NB_DATA =  4)
    (
    //Inputs
    input       wire                                    i_clock,
    input       wire        [N_TERM*NB_DATA-1:0]        i_data_bus,
    //Outputs
    output      reg         [NB_DATA       -1:0]        o_sum
    );
    //Internal signals
    integer                  i;
    reg      [NB_DATA-1:0]   data;

    always @(*)
    begin : iteration
        data = 0;
        for(i=0; i<N_TERM; i=i+1)
        begin
            data  = data + i_data_bus[i*NB_DATA +: NB_DATA];
        end
    end



    always @(posedge  i_clock)
    begin : register
        o_sum  <=  data;
    end

endmodule

//  Description : 3. SUMADOR FOR
// Escribir el código de un sumador de N_TERM elementos (N_TERM es un  
// parámetro del módulo) de NB_DATA bits cada elemento.
// Los datos de entrada vienen juntos (concatenados) en un bus llamado 
// i_data_bus.
// i_data_bus[NB_DATA-1:0] tiene el primer dato de entrada, 
// i_data_bus[2*NB_DATA-1:NB_DATA] tiene el segundo dato de entrada 
// i_data_bus[3*NB_DATA-1:2*NB_DATA] tiene el segundo dato de entrada, y asi 
// sucesivamente.  
// El tamaño de la salida "suma" (o_sum) tiene que ser tambien de NB_DATA
// debe estar registrada
// Para escribir el módulo, usar un bloque "always" que contenga un bucle  
// "for".
