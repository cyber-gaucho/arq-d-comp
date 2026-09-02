`timescale 1ns / 1ps

// =============================================================================
// Testbench: tb_alu
// Descripcion: Verifica todas las operaciones de la ALU junto con los flags
//              o_overflow y o_zero. Imprime PASS/FAIL por caso de prueba.
// =============================================================================

module tb_alu;

    // -------------------------------------------------------------------------
    // Parámetros
    // -------------------------------------------------------------------------
    parameter NB_DATA = 8;

    // -------------------------------------------------------------------------
    // Señales
    // -------------------------------------------------------------------------
    reg  [NB_DATA-1:0] i_operand_a;
    reg  [NB_DATA-1:0] i_operand_b;
    reg  [5:0]         i_operation;

    wire [NB_DATA-1:0] o_result;
    wire               o_overflow;
    wire               o_zero;

    // -------------------------------------------------------------------------
    // Opcodes (deben coincidir con los localparam de alu.sv)
    // -------------------------------------------------------------------------
    localparam ADD = 6'b100000;
    localparam SUB = 6'b100010;
    localparam AND = 6'b100100;
    localparam OR  = 6'b100101;
    localparam XOR = 6'b100110;
    localparam SRA = 6'b000011;
    localparam SRL = 6'b000010;
    localparam NOR = 6'b100111;

    // -------------------------------------------------------------------------
    // Instancia bajo prueba
    // -------------------------------------------------------------------------
    alu #(
        .NB_DATA(NB_DATA)
    ) u_alu (
        .o_result   (o_result),
        .o_overflow (o_overflow),
        .o_zero     (o_zero),
        .i_operand_a(i_operand_a),
        .i_operand_b(i_operand_b),
        .i_operation(i_operation)
    );

    // -------------------------------------------------------------------------
    // Contadores de resultados
    // -------------------------------------------------------------------------
    integer pass_cnt = 0;
    integer fail_cnt = 0;

    // -------------------------------------------------------------------------
    // Tarea de verificación
    // -------------------------------------------------------------------------
    task check;
        input [NB_DATA-1:0] exp_result;
        input               exp_overflow;
        input               exp_zero;
        input [127:0]       test_name;
        begin
            #1; // deja propagarse la lógica combinacional
            if (o_result   !== exp_result   ||
                o_overflow !== exp_overflow ||
                o_zero     !== exp_zero)
            begin
                $display("FAIL [%0s]  a=0x%04X b=0x%04X op=%06b | got result=0x%04X ovf=%b zero=%b | exp result=0x%04X ovf=%b zero=%b",
                    test_name, i_operand_a, i_operand_b, i_operation,
                    o_result, o_overflow, o_zero,
                    exp_result, exp_overflow, exp_zero);
                fail_cnt = fail_cnt + 1;
            end else begin
                $display("PASS [%0s]", test_name);
                pass_cnt = pass_cnt + 1;
            end
        end
    endtask

    // -------------------------------------------------------------------------
    // Estímulos
    // -------------------------------------------------------------------------
    initial begin
        $display("=== Inicio testbench ALU (NB_DATA=%0d) ===", NB_DATA);

        // ----- ADD -----------------------------------------------------------
        i_operation = ADD;
        i_operand_a = 8'h03; i_operand_b = 8'h05;
        check(8'h08, 1'b0, 1'b0, "ADD normal");

        // Overflow: MAX_POS + 1 -> resultado negativo (pos+pos=neg)
        i_operand_a = 8'h7F; i_operand_b = 8'h01;
        check(8'h80, 1'b1, 1'b0, "ADD ovf pos+pos=neg");

        // Overflow: MIN_NEG + MIN_NEG -> resultado positivo (neg+neg=pos), además zero
        i_operand_a = 8'h80; i_operand_b = 8'h80;
        check(8'h00, 1'b1, 1'b1, "ADD ovf neg+neg=pos+zero");

        // Sin overflow: negativo + positivo
        i_operand_a = 8'hFF; i_operand_b = 8'h01;  // -1 + 1 = 0
        check(8'h00, 1'b0, 1'b1, "ADD no ovf + zero");

        // ----- SUB -----------------------------------------------------------
        i_operation = SUB;
        i_operand_a = 8'h0A; i_operand_b = 8'h03;
        check(8'h07, 1'b0, 1'b0, "SUB normal");

        // Overflow: MIN_NEG - 1 -> resultado positivo (neg-pos=pos)
        i_operand_a = 8'h80; i_operand_b = 8'h01;
        check(8'h7F, 1'b1, 1'b0, "SUB ovf neg-pos=pos");

        // Overflow: MAX_POS - (-1) -> resultado negativo (pos-neg=neg)
        i_operand_a = 8'h7F; i_operand_b = 8'hFF;  // 0x7F - (-1) = 0x80
        check(8'h80, 1'b1, 1'b0, "SUB ovf pos-neg=neg");

        // Zero: mismo operando
        i_operand_a = 8'h12; i_operand_b = 8'h12;
        check(8'h00, 1'b0, 1'b1, "SUB zero");

        // ----- AND -----------------------------------------------------------
        i_operation = AND;
        i_operand_a = 8'hAB; i_operand_b = 8'hF0;
        check(8'hA0, 1'b0, 1'b0, "AND normal");

        i_operand_a = 8'hAA; i_operand_b = 8'h55;  // ningún bit en común
        check(8'h00, 1'b0, 1'b1, "AND zero");

        // ----- OR ------------------------------------------------------------
        i_operation = OR;
        i_operand_a = 8'h0F; i_operand_b = 8'hF0;
        check(8'hFF, 1'b0, 1'b0, "OR normal");

        i_operand_a = 8'h00; i_operand_b = 8'h00;
        check(8'h00, 1'b0, 1'b1, "OR zero");

        // ----- XOR -----------------------------------------------------------
        i_operation = XOR;
        i_operand_a = 8'hFF; i_operand_b = 8'hFF;
        check(8'h00, 1'b0, 1'b1, "XOR zero");

        i_operand_a = 8'hA5; i_operand_b = 8'h5A;
        check(8'hFF, 1'b0, 1'b0, "XOR normal");

        // ----- NOR -----------------------------------------------------------
        i_operation = NOR;
        i_operand_a = 8'h00; i_operand_b = 8'h00;
        check(8'hFF, 1'b0, 1'b0, "NOR all zero in");

        i_operand_a = 8'hFF; i_operand_b = 8'h00;
        check(8'h00, 1'b0, 1'b1, "NOR zero out");

        // ----- SRL -----------------------------------------------------------
        i_operation = SRL;
        i_operand_a = 8'h80; i_operand_b = 8'h01;
        check(8'h40, 1'b0, 1'b0, "SRL 0x80>>1");

        i_operand_a = 8'hFF; i_operand_b = 8'h08;
        check(8'h00, 1'b0, 1'b1, "SRL 0xFF>>8");

        i_operand_a = 8'h01; i_operand_b = 8'h01;
        check(8'h00, 1'b0, 1'b1, "SRL zero");

        // ----- SRA -----------------------------------------------------------
        i_operation = SRA;
        i_operand_a = 8'h80; i_operand_b = 8'h01;
        check(8'hC0, 1'b0, 1'b0, "SRA 0x80>>>1");

        i_operand_a = 8'hFF; i_operand_b = 8'h04;  // -1 >>> 4 = -1
        check(8'hFF, 1'b0, 1'b0, "SRA -1>>>4");

        i_operand_a = 8'h7F; i_operand_b = 8'h0F;  // MAX_POS >>> 15 = 0
        check(8'h00, 1'b0, 1'b1, "SRA zero");

        // ----- Default -------------------------------------------------------
        i_operation = 6'b000000; // no asignado
        i_operand_a = 8'hDE; i_operand_b = 8'hEF;
        check(8'h00, 1'b0, 1'b1, "Default op");

        // ----- Resumen -------------------------------------------------------
        $display("=========================================");
        $display("Resultado: %0d PASS  /  %0d FAIL", pass_cnt, fail_cnt);
        if (fail_cnt == 0)
            $display(">>> TODOS LOS TESTS PASARON <<<");
        else
            $display(">>> ATENCIÓN: hay tests fallidos <<<");
        $display("=========================================");
        $finish;
    end

endmodule
