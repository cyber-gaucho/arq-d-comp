`timescale 1ns / 1ps

// =============================================================================
// Testbench   : tb_uart_alu_interface
// Archivo     : tb_uart_alu_interface.v
// Descripcion : Verifica el funcionamiento integral del Circuito de Interfaz
//               UART (uart_alu_interface) conectado al subsistema de la ALU
//               (alu_top: alu_ctrl + alu).
//
// Pruebas realizadas:
//   1. Secuencia completa del protocolo (Operando A -> Operando B -> Opcode)
//   2. Verificacion de todas las operaciones de la ALU:
//      - ADD (con y sin overflow)
//      - SUB (con y sin zero)
//      - AND, OR, XOR
//      - SRA, SRL
//      - NOR
//   3. Banderas zero y overflow hacia los LEDs
//   4. Handshake de transmision con UART TX (o_tx_start y simulación de i_tx_done)
//   5. Ingestion de bytes consecutivos (stress test de buffers FIFO)
//   6. Recuperacion correcta tras un reset asincrono / sincronico
// =============================================================================

module tb_uart_alu_interface;

    parameter NB_DATA    = 8;
    parameter NB_OP      = 6;
    parameter FIFO_DEPTH = 8;

    // Codigos de operacion (ALU MIPS del TP1)
    localparam [NB_OP-1:0] OP_ADD = 6'b100000; // 0x20
    localparam [NB_OP-1:0] OP_SUB = 6'b100010; // 0x22
    localparam [NB_OP-1:0] OP_AND = 6'b100100; // 0x24
    localparam [NB_OP-1:0] OP_OR  = 6'b100101; // 0x25
    localparam [NB_OP-1:0] OP_XOR = 6'b100110; // 0x26
    localparam [NB_OP-1:0] OP_SRA = 6'b000011; // 0x03
    localparam [NB_OP-1:0] OP_SRL = 6'b000010; // 0x02
    localparam [NB_OP-1:0] OP_NOR = 6'b100111; // 0x27

    // Señales de estimulo y reloj
    reg               clock;
    reg               reset;

    // Lado UART RX
    reg  [NB_DATA-1:0] rx_data;
    reg               rx_done;

    // Lado UART TX
    wire [NB_DATA-1:0] tx_data;
    wire              tx_start;
    reg               tx_done;

    // Señales de interconexion entre uart_alu_interface y alu_top
    wire [NB_DATA-1:0] r_data;
    wire              rd;
    wire              rx_empty;
    wire [NB_DATA-1:0] w_data;
    wire              wr;
    wire              tx_full;

    // Banderas de la ALU
    wire              zero;
    wire              overflow;

    // Contadores de verificacion
    integer pass_cnt;
    integer fail_cnt;

    // -------------------------------------------------------------------------
    // Instancia del Circuito de Interfaz (DUT 1)
    // -------------------------------------------------------------------------
    uart_alu_interface #(
        .NB_DATA    (NB_DATA),
        .FIFO_DEPTH (FIFO_DEPTH)
    ) u_interface (
        .i_clock    (clock),
        .i_reset    (reset),

        // UART RX
        .i_rx_data  (rx_data),
        .i_rx_done  (rx_done),

        // UART TX
        .o_tx_data  (tx_data),
        .o_tx_start (tx_start),
        .i_tx_done  (tx_done),

        // Lado ALU
        .o_r_data   (r_data),
        .i_rd       (rd),
        .o_rx_empty (rx_empty),
        .i_w_data   (w_data),
        .i_wr       (wr),
        .o_tx_full  (tx_full)
    );

    // -------------------------------------------------------------------------
    // Instancia del Subsistema ALU (DUT 2: alu_ctrl + alu)
    // -------------------------------------------------------------------------
    alu_top #(
        .NB_DATA (NB_DATA),
        .NB_OP   (NB_OP)
    ) u_alu_top (
        .i_clock     (clock),
        .i_reset     (reset),

        // Interfaz con Interface Circuit
        .i_r_data    (r_data),
        .i_rx_empty  (rx_empty),
        .o_rd        (rd),
        .o_w_data    (w_data),
        .o_wr        (wr),
        .i_tx_full   (tx_full),

        // Banderas
        .o_zero      (zero),
        .o_overflow  (overflow)
    );

    // -------------------------------------------------------------------------
    // Generador de Reloj: 50 MHz (periodo 20 ns -> semiperiodo 10 ns)
    // -------------------------------------------------------------------------
    always #10 clock = ~clock;

    // -------------------------------------------------------------------------
    // Task: Enviar un byte simulando la recepcion desde UART RX
    // -------------------------------------------------------------------------
    task send_rx_byte;
        input [NB_DATA-1:0] byte_val;
        begin
            @(posedge clock);
            rx_data <= byte_val;
            rx_done <= 1'b1;
            @(posedge clock);
            rx_done <= 1'b0;
            rx_data <= {NB_DATA{1'b0}};
        end
    endtask

    // -------------------------------------------------------------------------
    // Task: Ejecutar y verificar una operacion completa PC -> FPGA -> PC
    // -------------------------------------------------------------------------
    task execute_op;
        input [NB_DATA-1:0] op_a;
        input [NB_DATA-1:0] op_b;
        input [NB_OP-1:0]   opcode;
        input [NB_DATA-1:0] exp_result;
        input               exp_zero;
        input               exp_ovf;
        input [40*8-1:0]    test_name;

        integer timeout;
        reg     op_ok;
        begin
            op_ok = 1'b1;

            // Enviar Byte 1: Operando A
            send_rx_byte(op_a);
            repeat (2) @(posedge clock);

            // Enviar Byte 2: Operando B
            send_rx_byte(op_b);
            repeat (2) @(posedge clock);

            // Enviar Byte 3: Codigo de operacion
            send_rx_byte({2'b00, opcode});

            // Esperar que la interfaz genere el pulso tx_start
            timeout = 0;
            while (!tx_start && timeout < 50) begin
                @(posedge clock);
                timeout = timeout + 1;
            end

            if (timeout >= 50) begin
                $display("[FAIL] %0s: Timeout esperando tx_start", test_name);
                fail_cnt = fail_cnt + 1;
            end else begin
                // Verificar resultado transmitido y banderas
                if (tx_data !== exp_result) begin
                    $display("[FAIL] %0s: tx_data incorrecto. Esperado=0x%02h (%0d), Obtenido=0x%02h (%0d)",
                             test_name, exp_result, exp_result, tx_data, tx_data);
                    op_ok = 1'b0;
                end

                if (zero !== exp_zero) begin
                    $display("[FAIL] %0s: Flag ZERO incorrecto. Esperado=%b, Obtenido=%b",
                             test_name, exp_zero, zero);
                    op_ok = 1'b0;
                end

                if (overflow !== exp_ovf) begin
                    $display("[FAIL] %0s: Flag OVERFLOW incorrecto. Esperado=%b, Obtenido=%b",
                             test_name, exp_ovf, overflow);
                    op_ok = 1'b0;
                end

                if (op_ok) begin
                    $display("[PASS] %0s: A=0x%02h, B=0x%02h, Op=0x%02h -> Res=0x%02h [Z=%b, O=%b]",
                             test_name, op_a, op_b, opcode, tx_data, zero, overflow);
                    pass_cnt = pass_cnt + 1;
                end else begin
                    fail_cnt = fail_cnt + 1;
                end

                // Simular que el transmisor UART termina la transmision
                repeat (4) @(posedge clock);
                @(posedge clock);
                tx_done <= 1'b1;
                @(posedge clock);
                tx_done <= 1'b0;
                repeat (2) @(posedge clock);
            end
        end
    endtask

    // -------------------------------------------------------------------------
    // Bloque Principal de Pruebas
    // -------------------------------------------------------------------------
    initial begin
        clock    = 1'b0;
        reset    = 1'b1;
        rx_data  = {NB_DATA{1'b0}};
        rx_done  = 1'b0;
        tx_done  = 1'b0;
        pass_cnt = 0;
        fail_cnt = 0;

        // Reset inicial
        repeat (10) @(posedge clock);
        reset = 1'b0;
        repeat (5) @(posedge clock);

        $display("==========================================================");
        $display("=== Iniciando Testbench UART-ALU Interface (tb_uart_alu_interface) ===");
        $display("==========================================================");

        // 1. ADD normal: 15 + 27 = 42 (0x0F + 0x1B = 0x2A)
        execute_op(8'd15, 8'd27, OP_ADD, 8'd42, 1'b0, 1'b0, "ADD normal");

        // 2. ADD con overflow con signo: 127 + 1 = -128 (0x7F + 0x01 = 0x80)
        execute_op(8'h7F, 8'h01, OP_ADD, 8'h80, 1'b0, 1'b1, "ADD con overflow (+ + = -)");

        // 3. SUB normal: 50 - 20 = 30 (0x32 - 0x14 = 0x1E)
        execute_op(8'd50, 8'd20, OP_SUB, 8'd30, 1'b0, 1'b0, "SUB normal");

        // 4. SUB con resultado cero: 0x5A - 0x5A = 0x00
        execute_op(8'h5A, 8'h5A, OP_SUB, 8'h00, 1'b1, 1'b0, "SUB con resultado ZERO");

        // 5. SUB con overflow con signo: -128 - 1 = +127 (0x80 - 0x01 = 0x7F)
        execute_op(8'h80, 8'h01, OP_SUB, 8'h7F, 1'b0, 1'b1, "SUB con overflow (- + = +)");

        // 6. AND logico: 0xF0 & 0xAA = 0xA0
        execute_op(8'hF0, 8'hAA, OP_AND, 8'hA0, 1'b0, 1'b0, "AND logico");

        // 7. OR logico: 0xF0 | 0x0F = 0xFF
        execute_op(8'hF0, 8'h0F, OP_OR, 8'hFF, 1'b0, 1'b0, "OR logico");

        // 8. XOR logico: 0xAA ^ 0x55 = 0xFF
        execute_op(8'hAA, 8'h55, OP_XOR, 8'hFF, 1'b0, 1'b0, "XOR logico");

        // 9. SRA (desplazamiento aritmetico a derecha): 0xF0 (-16) >>> 2 = 0xFC (-4)
        execute_op(8'hF0, 8'd2, OP_SRA, 8'hFC, 1'b0, 1'b0, "SRA aritmetico");

        // 10. SRL (desplazamiento logico a derecha): 0xF0 >> 2 = 0x3C
        execute_op(8'hF0, 8'd2, OP_SRL, 8'h3C, 1'b0, 1'b0, "SRL logico");

        // 11. NOR logico: ~(0x0F | 0xF0) = 0x00
        execute_op(8'h0F, 8'hF0, OP_NOR, 8'h00, 1'b1, 1'b0, "NOR con resultado ZERO");

        // 12. Stress Test: Ingestion consecutiva de bytes (Back-to-back en FIFO)
        $display("\n--- Test: Ráfaga de bytes consecutivos en FIFO RX ---");
        @(posedge clock);
        rx_data <= 8'd100;
        rx_done <= 1'b1;
        @(posedge clock);
        rx_data <= 8'd25;
        rx_done <= 1'b1;
        @(posedge clock);
        rx_data <= {2'b00, OP_SUB};
        rx_done <= 1'b1;
        @(posedge clock);
        rx_done <= 1'b0;
        rx_data <= 8'h00;

        // Esperar transmision
        while (!tx_start) @(posedge clock);
        if (tx_data === 8'd75 && zero === 1'b0 && overflow === 1'b0) begin
            $display("[PASS] Rafaga consecutiva procesada con exito (100 - 25 = 75)");
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("[FAIL] Rafaga consecutiva fallo. tx_data=0x%02h", tx_data);
            fail_cnt = fail_cnt + 1;
        end
        repeat (4) @(posedge clock);
        tx_done <= 1'b1;
        @(posedge clock);
        tx_done <= 1'b0;
        repeat (5) @(posedge clock);

        // 13. Test de Reset a mitad de secuencia: enviar 2 bytes, aplicar reset y comprobar recuperacion
        $display("\n--- Test: Reset a mitad de secuencia y recuperacion ---");
        send_rx_byte(8'hAA);
        repeat (2) @(posedge clock);
        send_rx_byte(8'hBB);
        repeat (2) @(posedge clock);

        // Aplicar pulso de reset
        reset = 1'b1;
        repeat (5) @(posedge clock);
        reset = 1'b0;
        repeat (5) @(posedge clock);

        // Enviar nueva operacion limpia: 8'd12 + 8'd18 = 8'd30
        execute_op(8'd12, 8'd18, OP_ADD, 8'd30, 1'b0, 1'b0, "Operacion limpia tras reset");

        // Resumen final
        $display("\n==========================================================");
        $display("Resumen tb_uart_alu_interface: PASS=%0d, FAIL=%0d", pass_cnt, fail_cnt);
        $display("==========================================================");

        if (fail_cnt == 0) begin
            $display(">>> TESTBENCH COMPLETADO EXITOSAMENTE (TODOS LOS CASOS PASARON) <<<");
        end else begin
            $display(">>> TESTBENCH FINALIZO CON ERRORES <<<");
        end

        $finish;
    end

endmodule
