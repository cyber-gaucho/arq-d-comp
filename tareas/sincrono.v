// REVISAR
module modulo_sincrono
(
    input wire A,
    input wire B,
    input wire C,
    input wire D,
    input wire clk,
    output reg x,
    output reg y
);

    // Registros de entrada
    reg A_reg;
    reg B_reg;
    reg C_reg;
    reg D_reg;

    // flop de entrada
    always @(posedge clk) begin
        A_reg = A;
        B_reg = B;
        C_reg = C;
        D_reg = D;
    end

    // combinacional intermedio
    wire e;
    assign e = A_reg & B_reg;
    
    wire f;
    assign f = e | C_reg;
    
    wire g;
    assign g = C_reg & D_reg;

    wire h;
    assign h = ~f;

    wire x_comb;
    wire y_comb;

    assign x_comb = h | g;
    assign y_comb = g & D_reg & C_reg;

    // Registros de salida
    always @(posedge clk) begin
        x = x_comb;
        y = y_comb;
    end

endmodule
