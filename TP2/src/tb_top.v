`timescale 1ns / 1ps

// =============================================================================
// Testbench: tb_top
// Descripcion: Testbench de integracion a nivel de sistema completo (top.v)
//              para el TP2. Emula a una PC comunicandose con la FPGA mediante
//              la interfaz serie asincrona UART (lineas RsRx y RsTx).
//
// Pruebas implementadas:
//   1. Operacion ADD basica (0x0A + 0x05 = 0x0F)
//   2. Operacion SUB con Zero Flag (0x20 - 0x20 = 0x00, zero=1)
//   3. Operacion ADD con Overflow Flag (0x7F + 0x01 = 0x80, ovf=1)
//   4. Operacion SUB con Overflow Flag (0x80 - 0x01 = 0x7F, ovf=1)
//   5. Operaciones logicas: AND, OR, XOR, NOR
//   6. Operaciones de desplazamiento: SRA, SRL
//   7. Operaciones consecutivas (back-to-back) sin pausas
//   8. Comprobacion de recuperacion limpia ante Reset (btnR) a mitad de trama
// =============================================================================

module tb_top;

    // Configuramos BAUD_RATE = 625_000 para que la division con 100 MHz sea exacta:
    // TICK_CYCLES = 100_000_000 / (625_000 * 16) = 10 ciclos exactos por tick.
    // Duracion de 1 bit = 16 ticks = 160 ciclos de reloj = 1600 ns.
    parameter CLOCK_FREQ = 100_000_000;
    parameter BAUD_RATE  = 625_000;
    parameter NB_DATA    = 8;
    parameter NB_OP      = 6;

    // Codigos de operacion de la ALU
    localparam [NB_OP-1:0] OP_ADD = 6'b100000;
    localparam [NB_OP-1:0] OP_SUB = 6'b100010;
    localparam [NB_OP-1:0] OP_AND = 6'b100100;
    localparam [NB_OP-1:0] OP_OR  = 6'b100101;
    localparam [NB_OP-1:0] OP_XOR = 6'b100110;
    localparam [NB_OP-1:0] OP_SRA = 6'b000011;
    localparam [NB_OP-1:0] OP_SRL = 6'b000010;
    localparam [NB_OP-1:0] OP_NOR = 6'b100111;

    // Duracion exacta de 1 bit de UART (16 ticks * 10 ciclos * 10 ns = 1600 ns)
    localparam BIT_PERIOD_NS = 1600;

    reg         CLK100MHZ;
    reg         btnR;
    reg         RsRx;
    wire        RsTx;
    wire [15:0] LED;

    // Instancia del Top-Level
    top #(
        .CLOCK_FREQ (CLOCK_FREQ),
        .BAUD_RATE  (BAUD_RATE),
        .NB_DATA    (NB_DATA),
        .NB_STOP    (1),
        .NB_OP      (NB_OP),
        .FIFO_DEPTH (8)
    ) u_top (
        .CLK100MHZ  (CLK100MHZ),
        .btnR       (btnR),
        .RsRx       (RsRx),
        .RsTx       (RsTx),
        .LED        (LED)
    );

    // Reloj de 100 MHz (periodo 10 ns)
    always #5 CLK100MHZ = ~CLK100MHZ;

    integer pass_cnt;
    integer fail_cnt;

    // Variables para el receptor en segundo plano del testbench
    reg [NB_DATA-1:0] bg_rx_data;
    reg               bg_rx_done;
    integer           bg_bit_idx;

    // Receptor serie paralelo que escucha RsTx continuamente
    always begin : PC_Background_Receiver
        @(negedge RsTx);
        // Centro del Start bit
        #(BIT_PERIOD_NS / 2);
        // Muestreo de cada bit de datos
        for (bg_bit_idx = 0; bg_bit_idx < NB_DATA; bg_bit_idx = bg_bit_idx + 1) begin
            #(BIT_PERIOD_NS);
            bg_rx_data[bg_bit_idx] = RsTx;
        end
        // Fin de bit de Stop
        #(BIT_PERIOD_NS);
        bg_rx_done = 1'b1;
        @(posedge CLK100MHZ);
    end

    // -------------------------------------------------------------------------
    // TAREA: Transmitir 1 byte serie desde la PC hacia la FPGA por RsRx
    // -------------------------------------------------------------------------
    task pc_send_byte;
        input [NB_DATA-1:0] data;
        integer i;
        begin
            // Start bit (0)
            RsRx = 1'b0;
            #(BIT_PERIOD_NS);

            // Data bits (LSB primero)
            for (i = 0; i < NB_DATA; i = i + 1) begin
                RsRx = data[i];
                #(BIT_PERIOD_NS);
            end

            // Stop bit (1)
            RsRx = 1'b1;
            #(BIT_PERIOD_NS);
        end
    endtask

    // -------------------------------------------------------------------------
    // TAREA: Ejecutar transaccion completa PC <-> FPGA y verificar resultado
    // -------------------------------------------------------------------------
    task verify_transaction;
        input [NB_DATA-1:0] op_a;
        input [NB_DATA-1:0] op_b;
        input [NB_OP-1:0]   opcode;
        input [NB_DATA-1:0] exp_result;
        input               exp_zero;
        input               exp_overflow;
        input [128*8:1]     test_name;

        integer timeout_cnt;
        begin
            $display("\n[TEST] %0s", test_name);

            // Limpiar bandera de recepcion antes de lanzar la operacion
            bg_rx_done = 1'b0;

            // 1. Enviar Byte 1: Operando A
            pc_send_byte(op_a);
            #(BIT_PERIOD_NS * 2);

            // 2. Enviar Byte 2: Operando B
            pc_send_byte(op_b);
            #(BIT_PERIOD_NS * 2);

            // 3. Enviar Byte 3: Codigo de Operacion
            pc_send_byte({2'b00, opcode});

            // 4. Esperar que el receptor en segundo plano complete la trama
            timeout_cnt = 0;
            while (!bg_rx_done && timeout_cnt < 20000) begin
                #(BIT_PERIOD_NS / 10);
                timeout_cnt = timeout_cnt + 1;
            end

            // Dejar asentar un par de ciclos de reloj para verificar LEDs
            repeat (10) @(posedge CLK100MHZ);

            // 5. Verificaciones
            // a) Byte devuelto por UART
            if (bg_rx_done && (bg_rx_data == exp_result)) begin
                $display("  [PASS] UART Tx Result: 0x%02X (esperado 0x%02X)", bg_rx_data, exp_result);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("  [FAIL] UART Tx Result: 0x%02X (esperado 0x%02X, done=%b)", bg_rx_data, exp_result, bg_rx_done);
                fail_cnt = fail_cnt + 1;
            end

            // b) LED[7:0] de la placa
            if (LED[7:0] == exp_result) begin
                $display("  [PASS] LED[7:0] Result: 0x%02X", LED[7:0]);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("  [FAIL] LED[7:0] Result: 0x%02X (esperado 0x%02X)", LED[7:0], exp_result);
                fail_cnt = fail_cnt + 1;
            end

            // c) LED[14] Zero Flag
            if (LED[14] == exp_zero) begin
                $display("  [PASS] LED[14] Zero Flag: %b", LED[14]);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("  [FAIL] LED[14] Zero Flag: %b (esperado %b)", LED[14], exp_zero);
                fail_cnt = fail_cnt + 1;
            end

            // d) LED[15] Overflow Flag
            if (LED[15] == exp_overflow) begin
                $display("  [PASS] LED[15] Overflow Flag: %b", LED[15]);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("  [FAIL] LED[15] Overflow Flag: %b (esperado %b)", LED[15], exp_overflow);
                fail_cnt = fail_cnt + 1;
            end

            #(BIT_PERIOD_NS * 4);
        end
    endtask

    // -------------------------------------------------------------------------
    // SECUENCIA PRINCIPAL DE SIMULACION
    // -------------------------------------------------------------------------
    initial begin
        CLK100MHZ  = 0;
        btnR       = 1;
        RsRx       = 1;
        bg_rx_done = 0;
        bg_rx_data = 0;
        pass_cnt   = 0;
        fail_cnt   = 0;

        // Reset inicial
        repeat (10) @(posedge CLK100MHZ);
        btnR = 0;
        repeat (20) @(posedge CLK100MHZ);

        $display("=================================================");
        $display("=== Iniciando Testbench Integracion (tb_top) ===");
        $display("=================================================");

        // Test 1: ADD normal (10 + 5 = 15)
        verify_transaction(8'd10, 8'd5, OP_ADD, 8'd15, 1'b0, 1'b0, "ADD normal (10 + 5)");

        // Test 2: SUB con Zero (0x20 - 0x20 = 0x00)
        verify_transaction(8'h20, 8'h20, OP_SUB, 8'h00, 1'b1, 1'b0, "SUB con resultado Zero (0x20 - 0x20)");

        // Test 3: ADD con Overflow (0x7F + 0x01 = 0x80 -> 127 + 1 = -128)
        verify_transaction(8'h7F, 8'h01, OP_ADD, 8'h80, 1'b0, 1'b1, "ADD con Overflow positivo (0x7F + 0x01)");

        // Test 4: SUB con Overflow (0x80 - 0x01 = 0x7F -> -128 - 1 = +127)
        verify_transaction(8'h80, 8'h01, OP_SUB, 8'h7F, 1'b0, 1'b1, "SUB con Overflow negativo (0x80 - 0x01)");

        // Test 5: AND logico (0xF0 & 0xAA = 0xA0)
        verify_transaction(8'hF0, 8'hAA, OP_AND, 8'hA0, 1'b0, 1'b0, "AND bit a bit (0xF0 & 0xAA)");

        // Test 6: OR logico (0x0F | 0xAA = 0xAF)
        verify_transaction(8'h0F, 8'hAA, OP_OR, 8'hAF, 1'b0, 1'b0, "OR bit a bit (0x0F | 0xAA)");

        // Test 7: XOR logico (0xFF ^ 0x0F = 0xF0)
        verify_transaction(8'hFF, 8'h0F, OP_XOR, 8'hF0, 1'b0, 1'b0, "XOR bit a bit (0xFF ^ 0x0F)");

        // Test 8: NOR logico (~(0x00 | 0x00) = 0xFF)
        verify_transaction(8'h00, 8'h00, OP_NOR, 8'hFF, 1'b0, 1'b0, "NOR bit a bit (~(0x00 | 0x00))");

        // Test 9: SRA (Shift Aritmetico Derecho): 0x80 >>> 2 = 0xE0 (-128 / 4 = -32)
        verify_transaction(8'h80, 8'd2, OP_SRA, 8'hE0, 1'b0, 1'b0, "SRA (0x80 >>> 2 = 0xE0)");

        // Test 10: SRL (Shift Logico Derecho): 0x80 >> 2 = 0x20
        verify_transaction(8'h80, 8'd2, OP_SRL, 8'h20, 1'b0, 1'b0, "SRL (0x80 >> 2 = 0x20)");

        // Test 11: Operaciones consecutivas
        verify_transaction(8'd7, 8'd8, OP_ADD, 8'd15, 1'b0, 1'b0, "Operacion consecutiva 1 (7 + 8)");
        verify_transaction(8'd20, 8'd5, OP_SUB, 8'd15, 1'b0, 1'b0, "Operacion consecutiva 2 (20 - 5)");

        // Test 12: Recuperacion ante Reset sincrono (btnR) a mitad de secuencia
        $display("\n[TEST] Prueba de recuperacion ante Reset (btnR) durante transaccion");
        pc_send_byte(8'h55); // Envia op_a
        #(BIT_PERIOD_NS);
        // Disparar reset en medio de la secuencia
        @(posedge CLK100MHZ);
        btnR = 1'b1;
        repeat (10) @(posedge CLK100MHZ);
        btnR = 1'b0;
        repeat (20) @(posedge CLK100MHZ);

        // Enviar nueva operacion limpia tras reset
        verify_transaction(8'd3, 8'd4, OP_ADD, 8'd7, 1'b0, 1'b0, "Operacion limpia post-Reset (3 + 4 = 7)");

        // Resumen
        $display("\n=================================================");
        $display("Resumen tb_top: PASS = %0d, FAIL = %0d", pass_cnt, fail_cnt);
        $display("=================================================");
        if (fail_cnt == 0) begin
            $display(">>> TEST COMPLETO DE INTEGRACION EXITOSO <<<");
        end else begin
            $display(">>> TEST FINALIZO CON ERRORES <<<");
        end

        $finish;
    end

endmodule
