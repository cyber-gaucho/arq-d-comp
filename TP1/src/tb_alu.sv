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
    parameter NB_DATA = 16;

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
        i_operand_a = 16'h0003; i_operand_b = 16'h0005;
        check(16'h0008, 1'b0, 1'b0, "ADD normal");

        // Overflow: MAX_POS + 1 → resultado negativo (pos+pos=neg)
        i_operand_a = 16'h7FFF; i_operand_b = 16'h0001;
        check(16'h8000, 1'b1, 1'b0, "ADD ovf pos+pos=neg");

        // Overflow: MIN_NEG + MIN_NEG → resultado positivo (neg+neg=pos), además zero
        i_operand_a = 16'h8000; i_operand_b = 16'h8000;
        check(16'h0000, 1'b1, 1'b1, "ADD ovf neg+neg=pos+zero");

        // Sin overflow: negativo + positivo
        i_operand_a = 16'hFFFF; i_operand_b = 16'h0001;  // -1 + 1 = 0
        check(16'h0000, 1'b0, 1'b1, "ADD no ovf + zero");

        // ----- SUB -----------------------------------------------------------
        i_operation = SUB;
        i_operand_a = 16'h000A; i_operand_b = 16'h0003;
        check(16'h0007, 1'b0, 1'b0, "SUB normal");

        // Overflow: MIN_NEG - 1 → resultado positivo (neg-pos=pos)
        i_operand_a = 16'h8000; i_operand_b = 16'h0001;
        check(16'h7FFF, 1'b1, 1'b0, "SUB ovf neg-pos=pos");

        // Overflow: MAX_POS - (-1) → resultado negativo (pos-neg=neg)
        i_operand_a = 16'h7FFF; i_operand_b = 16'hFFFF;  // 0x7FFF - (-1) = 0x8000
        check(16'h8000, 1'b1, 1'b0, "SUB ovf pos-neg=neg");

        // Zero: mismo operando
        i_operand_a = 16'h1234; i_operand_b = 16'h1234;
        check(16'h0000, 1'b0, 1'b1, "SUB zero");

        // ----- AND -----------------------------------------------------------
        i_operation = AND;
        i_operand_a = 16'hABCD; i_operand_b = 16'hFF00;
        check(16'hAB00, 1'b0, 1'b0, "AND normal");

        i_operand_a = 16'hAAAA; i_operand_b = 16'h5555;  // ningún bit en común
        check(16'h0000, 1'b0, 1'b1, "AND zero");

        // ----- OR ------------------------------------------------------------
        i_operation = OR;
        i_operand_a = 16'h00FF; i_operand_b = 16'hFF00;
        check(16'hFFFF, 1'b0, 1'b0, "OR normal");

        i_operand_a = 16'h0000; i_operand_b = 16'h0000;
        check(16'h0000, 1'b0, 1'b1, "OR zero");

        // ----- XOR -----------------------------------------------------------
        i_operation = XOR;
        i_operand_a = 16'hFFFF; i_operand_b = 16'hFFFF;
        check(16'h0000, 1'b0, 1'b1, "XOR zero");

        i_operand_a = 16'hA5A5; i_operand_b = 16'h5A5A;
        check(16'hFFFF, 1'b0, 1'b0, "XOR normal");

        // ----- NOR -----------------------------------------------------------
        i_operation = NOR;
        i_operand_a = 16'h0000; i_operand_b = 16'h0000;
        check(16'hFFFF, 1'b0, 1'b0, "NOR all zero in");

        i_operand_a = 16'hFFFF; i_operand_b = 16'h0000;
        check(16'h0000, 1'b0, 1'b1, "NOR zero out");

        // ----- SRL -----------------------------------------------------------
        i_operation = SRL;
        // 0x8000 >> 1 = 0x4000 (no rellena con signo)
        i_operand_a = 16'h8000; i_operand_b = 16'h0001;
        check(16'h4000, 1'b0, 1'b0, "SRL 0x8000>>1");

        i_operand_a = 16'hFFFF; i_operand_b = 16'h0008;
        check(16'h00FF, 1'b0, 1'b0, "SRL 0xFFFF>>8");

        i_operand_a = 16'h0001; i_operand_b = 16'h0001;
        check(16'h0000, 1'b0, 1'b1, "SRL zero");

        // ----- SRA -----------------------------------------------------------
        i_operation = SRA;
        // 0x8000 >>> 1 = 0xC000 (rellena con el bit de signo)
        i_operand_a = 16'h8000; i_operand_b = 16'h0001;
        check(16'hC000, 1'b0, 1'b0, "SRA 0x8000>>>1");

        i_operand_a = 16'hFFFF; i_operand_b = 16'h0004;  // -1 >>> 4 = -1
        check(16'hFFFF, 1'b0, 1'b0, "SRA -1>>>4");

        i_operand_a = 16'h7FFF; i_operand_b = 16'h000F;  // MAX_POS >>> 15 = 0
        check(16'h0000, 1'b0, 1'b1, "SRA zero");

        // ----- Default -------------------------------------------------------
        i_operation = 6'b000000; // no asignado
        i_operand_a = 16'hDEAD; i_operand_b = 16'hBEEF;
        check(16'h0000, 1'b0, 1'b1, "Default op");

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
