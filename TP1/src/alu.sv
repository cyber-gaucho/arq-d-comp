module alu #(
    //PARAMETERS
    parameter NB_DATA = 16
)
(
    //OUTPUTS
    output reg [NB_DATA-1:0]    o_result,
    
    //INPUTS
    input wire [NB_DATA-1:0]    i_operand_a,
    input wire [NB_DATA-1:0]    i_operand_b,
    input wire [5:0]            i_operation

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

    //ALGORITHM BEGIN
    always @(*) 
    begin : ALU_Operations
        case (i_operation)
            ADD: o_result = i_operand_a + i_operand_b;
            SUB: o_result = i_operand_a - i_operand_b;
            AND: o_result = i_operand_a & i_operand_b;
            OR : o_result = i_operand_a | i_operand_b;
            XOR: o_result = i_operand_a ^ i_operand_b;
            SRA: o_result = $signed(i_operand_a) >>> i_operand_b[4:0];  // Arithmetic right shift
            SRL: o_result = i_operand_a >> i_operand_b[4:0];            // Logical right shift
            NOR: o_result = ~(i_operand_a | i_operand_b);
            default:   o_result = {NB_DATA{1'b0}}; // Default case
        endcase
    end

endmodule

// Descripcion : ALU
// Funcion: Realiza operaciones aritméticas y lógicas sobre dos operandos
// Operación - Código
// ADD 100000
// SUB 100010
// AND 100100
// OR  100101
// XOR 100110
// SRA 000011
// SRL 000010
// NOR 100111
