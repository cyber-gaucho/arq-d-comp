module top #(
    parameter NB_DATA = 16
)(
    output  wire    [15:0] LED,
    output  reg     [6:0]  seg,
    output  reg     [3:0]  an,
    output  wire           dp,

    input   wire    [15:0] sw,
    input   wire    CLK100MHZ,
    input   wire    btnC,
    input   wire    btnU,
    input   wire    btnD
);

    // 7-segment glyph constants (active low, seg[6:0] = {CG,CF,CE,CD,CC,CB,CA})
    localparam SEG_BLANK = 7'h7F;  // all segments OFF
    localparam SEG_ZERO  = 7'h40;  // digit  "0"  (a,b,c,d,e,f ON  / g OFF)
    localparam SEG_O     = 7'h23;  // letter "o"  (c,d,e,g   ON  / a,b,f OFF)

    reg [NB_DATA-1:0] operand_a_reg = {NB_DATA{1'b0}};
    reg [NB_DATA-1:0] operand_b_reg = {NB_DATA{1'b0}};
    reg [5:0]         operation_reg = 6'b0;
    reg btnU_d = 1'b0;
    reg btnD_d = 1'b0;
    reg btnC_d = 1'b0;

    wire [NB_DATA-1:0] result;
    wire               alu_overflow;
    wire               alu_zero;

    // -- Button edge detection + register capture --------------------------
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

    // -- ALU instance ------------------------------------------------------
    alu #(
        .NB_DATA(NB_DATA)
    ) u_alu (
        .o_result  (result),
        .o_overflow(alu_overflow),
        .o_zero    (alu_zero),
        .i_operand_a(operand_a_reg),
        .i_operand_b(operand_b_reg),
        .i_operation(operation_reg)
    );

    assign LED = result;
    assign dp  = 1'b1;  // decimal point OFF (active low)

    // -- 7-segment multiplexed display ------------------------------------
    // 18-bit counter: bits [17:16] select active digit (~381 Hz per digit)
    reg [17:0] refresh_cnt = 18'b0;

    always @(posedge CLK100MHZ)
        refresh_cnt <= refresh_cnt + 1;

    always @(*) begin
        case (refresh_cnt[17:16])
            2'b11: begin  // an[3] leftmost — Overflow flag ("o" or blank)
                an  = 4'b0111;
                seg = alu_overflow ? SEG_O : SEG_BLANK;
            end
            2'b10: begin  // an[2] — Zero flag ("0" or blank)
                an  = 4'b1011;
                seg = alu_zero ? SEG_ZERO : SEG_BLANK;
            end
            2'b01: begin  // an[1] — unused
                an  = 4'b1101;
                seg = SEG_BLANK;
            end
            default: begin  // an[0] rightmost — unused
                an  = 4'b1110;
                seg = SEG_BLANK;
            end
        endcase
    end

endmodule
