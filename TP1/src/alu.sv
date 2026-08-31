module alu #(
    //PARAMETERS
    parameter NB_DATA = 16
)
(
    //OUTPUTS
    output reg  [NB_DATA-1:0]   o_result,
    output reg                  o_overflow,
    output wire                 o_zero,

    //INPUTS
    input wire  [NB_DATA-1:0]   i_operand_a,
    input wire  [NB_DATA-1:0]   i_operand_b,
    input wire  [5:0]           i_operation

);
    //LOCAL PARAMETERS
    localparam ADD = 6'b100000;
    localparam SUB = 6'b100010;
    localparam AND = 6'b100100;
    localparam OR  = 6'b100101;
    localparam XOR = 6'b100110;
    localparam SRA = 6'b000011;
    localparam SRL = 6'b000010;
    localparam NOR = 6'b100111;

    // Zero flag: high when the result is all zeros
    assign o_zero = (o_result == {NB_DATA{1'b0}});

    //ALGORITHM BEGIN
    always @(*)
    begin : ALU_Operations
        case (i_operation)
            ADD: begin
                o_result   = i_operand_a + i_operand_b;
                // Signed overflow: pos+pos=neg  OR  neg+neg=pos
                o_overflow = (~i_operand_a[NB_DATA-1] & ~i_operand_b[NB_DATA-1] &  o_result[NB_DATA-1]) |
                             ( i_operand_a[NB_DATA-1] &  i_operand_b[NB_DATA-1] & ~o_result[NB_DATA-1]);
            end
            SUB: begin
                o_result   = i_operand_a - i_operand_b;
                // Signed overflow: pos-neg=neg  OR  neg-pos=pos
                o_overflow = (~i_operand_a[NB_DATA-1] &  i_operand_b[NB_DATA-1] &  o_result[NB_DATA-1]) |
                             ( i_operand_a[NB_DATA-1] & ~i_operand_b[NB_DATA-1] & ~o_result[NB_DATA-1]);
            end
            AND: begin
                o_result   = i_operand_a & i_operand_b;
                o_overflow = 1'b0;
            end
            OR : begin
                o_result   = i_operand_a | i_operand_b;
                o_overflow = 1'b0;
            end
            XOR: begin
                o_result   = i_operand_a ^ i_operand_b;
                o_overflow = 1'b0;
            end
            SRA: begin
                o_result   = $signed(i_operand_a) >>> i_operand_b[4:0];  // Arithmetic right shift
                o_overflow = 1'b0;
            end
            SRL: begin
                o_result   = i_operand_a >> i_operand_b[4:0];            // Logical right shift
                o_overflow = 1'b0;
            end
            NOR: begin
                o_result   = ~(i_operand_a | i_operand_b);
                o_overflow = 1'b0;
            end
            default: begin
                o_result   = {NB_DATA{1'b0}};
                o_overflow = 1'b0;
            end
        endcase
    end

endmodule

// Descripcion : ALU con flags de overflow y zero
// Funcion: Realiza operaciones aritméticas y lógicas sobre dos operandos.
//          Señaliza overflow con signo (solo ADD/SUB) y resultado igual a cero.
// Operación - Código
// ADD  100000
// SUB  100010
// AND  100100
// OR   100101
// XOR  100110
// SRA  000011
// SRL  000010
// NOR  100111
