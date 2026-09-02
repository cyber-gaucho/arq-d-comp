module top #(
    parameter NB_DATA = 8
)(
    output wire [15:0] LED,

    input  wire [15:0] sw,
    input  wire        CLK100MHZ,
    input  wire        btnR,
    input  wire        btnU,
    input  wire        btnD,
    input  wire        btnC
);

    wire [NB_DATA-1:0] operand_a;
    wire [NB_DATA-1:0] operand_b;
    wire [5:0]         operation;
    wire [NB_DATA-1:0] result;
    wire               alu_overflow;
    wire               alu_zero;

    btn_reg #(
        .WIDTH(NB_DATA)
    ) u_operand_a (
        .i_clk (CLK100MHZ),
        .i_rst (btnR),
        .i_btn (btnU),
        .i_sw  (sw[NB_DATA-1:0]),
        .o_data(operand_a)
    );

    btn_reg #(
        .WIDTH(NB_DATA)
    ) u_operand_b (
        .i_clk (CLK100MHZ),
        .i_rst (btnR),
        .i_btn (btnD),
        .i_sw  (sw[NB_DATA-1:0]),
        .o_data(operand_b)
    );

    btn_reg #(
        .WIDTH(6)
    ) u_operation (
        .i_clk (CLK100MHZ),
        .i_rst (btnR),
        .i_btn (btnC),
        .i_sw  (sw[5:0]),
        .o_data(operation)
    );

    alu #(
        .NB_DATA(NB_DATA)
    ) u_alu (
        .o_result   (result),
        .o_overflow (alu_overflow),
        .o_zero     (alu_zero),
        .i_operand_a(operand_a),
        .i_operand_b(operand_b),
        .i_operation(operation)
    );

    assign LED[7:0]   = result;
    assign LED[13:8]  = 6'b0;
    assign LED[14]    = alu_zero;
    assign LED[15]    = alu_overflow;

endmodule
