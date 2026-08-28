module modulo_tarea
(
    input wire A,
    input wire B,
    input wire C,
    input wire D,
    output wire x,
    output wire y
);

    wire e;
    assign e = A & B;
    
    wire f;
    assign f = e | C;
    
    wire g;
    assign g = ~f;

    wire h; 
    assign h = C & D;

    assign x = f | h;
    assign y = h & D & C;
endmodule