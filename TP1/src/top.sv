module top #(
    parameter NB_DATA = 16
)(
    output  wire    [15:0] LED,
    
    input   wire    [15:0] sw,
    input   wire    CLK100MHZ,
    input   wire    btnC,
    input   wire    btnU,
    input   wire    btnD
);

    reg [NB_DATA-1:0] operand_a_reg = {NB_DATA{1'b0}};
    reg [NB_DATA-1:0] operand_b_reg = {NB_DATA{1'b0}};
    reg [5:0] operation_reg = 6'b0;
    reg btnU_d = 1'b0;
    reg btnD_d = 1'b0;
    reg btnC_d = 1'b0;
    wire [NB_DATA-1:0] result;

    always @(posedge CLK100MHZ) begin
        btnU_d <= btnU;
        if (btnU && !btnU_d)
            operand_a_reg <= sw;
    end

    always @(posedge CLK100MHZ) begin
        btnD_d <= btnD;
        if (btnD && !btnD_d)
            operand_b_reg <= sw;
    end

    always @(posedge CLK100MHZ) begin
        btnC_d <= btnC;
        if (btnC && !btnC_d)
            operation_reg <= sw[5:0];
    end

    alu #(
        .NB_DATA(NB_DATA)
    ) u_alu (
        .o_result(result),
        .i_operand_a(operand_a_reg),
        .i_operand_b(operand_b_reg),
        .i_operation(operation_reg)
    );

    assign LED = result;
endmodule
