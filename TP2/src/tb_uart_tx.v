`timescale 1ns / 1ps

// =============================================================================
// Testbench: tb_uart_tx
// Descripcion: Verifica el funcionamiento del transmisor UART (uart_tx)
//              comprobando bit de start, bits de datos (LSB primero),
//              bit de stop, el pulso tx_done y transmisiones consecutivas.
// =============================================================================

module tb_uart_tx;

    parameter NB_DATA = 8;
    parameter NB_STOP = 1;

    reg               clock;
    reg               reset;
    reg               tx_start;
    reg               s_tick;
    reg [NB_DATA-1:0] d_in;
    wire              tx;
    wire              tx_done;

    // Instancia de uart_tx
    uart_tx #(
        .NB_DATA(NB_DATA),
        .NB_STOP(NB_STOP)
    ) u_uart_tx (
        .o_tx      (tx),
        .o_tx_done (tx_done),
        .i_clock   (clock),
        .i_reset   (reset),
        .i_tx_start(tx_start),
        .i_s_tick  (s_tick),
        .i_d_in    (d_in)
    );

    // Reloj principal (50 MHz -> periodo 20 ns)
    always #10 clock = ~clock;

    // Generador de s_tick cada 4 ciclos de reloj para acelerar simulacion
    integer tick_divider;
    always @(posedge clock) begin
        if (reset) begin
            tick_divider <= 0;
            s_tick       <= 1'b0;
        end else begin
            if (tick_divider == 3) begin
                tick_divider <= 0;
                s_tick       <= 1'b1;
            end else begin
                tick_divider <= tick_divider + 1;
                s_tick       <= 1'b0;
            end
        end
    end

    integer pass_cnt;
    integer fail_cnt;

    task wait_ticks;
        input integer count;
        integer seen;
        begin
            seen = 0;
            while (seen < count) begin
                @(posedge clock);
                if (s_tick) seen = seen + 1;
            end
        end
    endtask

    task transmit_byte;
        input [NB_DATA-1:0] byte_val;
        integer i;
        integer timeout_cnt;
        reg     done_detected;
        begin
            @(negedge clock);
            d_in     = byte_val;
            tx_start = 1'b1;
            @(posedge clock);
            @(negedge clock);
            tx_start = 1'b0;

            // Esperar al centro del bit de Start (8 ticks)
            wait_ticks(8);
            if (tx === 1'b0) begin
                $display("[PASS] Bit de Start detectado (tx=0)");
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("[FAIL] Bit de Start incorrecto (tx=%b)", tx);
                fail_cnt = fail_cnt + 1;
            end

            // Muestrear cada bit de datos a la mitad (cada 16 ticks)
            for (i = 0; i < NB_DATA; i = i + 1) begin
                wait_ticks(16);
                if (tx === byte_val[i]) begin
                    $display("[PASS] Bit de datos [%0d] = %b correcto", i, tx);
                    pass_cnt = pass_cnt + 1;
                end else begin
                    $display("[FAIL] Bit de datos [%0d] = %b esperado %b", i, tx, byte_val[i]);
                    fail_cnt = fail_cnt + 1;
                end
            end

            // Muestrear bit de stop a la mitad (16 ticks)
            wait_ticks(16);
            if (tx === 1'b1) begin
                $display("[PASS] Bit de Stop detectado (tx=1)");
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("[FAIL] Bit de Stop incorrecto (tx=%b)", tx);
                fail_cnt = fail_cnt + 1;
            end

            // Esperar el pulso tx_done en sincronia con el reloj sin consumir ciclos de mas
            timeout_cnt   = 0;
            done_detected = 1'b0;
            while (!done_detected && timeout_cnt < 200) begin
                @(posedge clock);
                timeout_cnt = timeout_cnt + 1;
                if (tx_done === 1'b1) begin
                    done_detected = 1'b1;
                end
            end

            if (done_detected) begin
                $display("[PASS] Pulso tx_done detectado correctamente para byte 0x%02X", byte_val);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("[FAIL] Timeout esperando pulso tx_done para byte 0x%02X", byte_val);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    initial begin
        clock        = 0;
        reset        = 1;
        tx_start     = 0;
        d_in         = {NB_DATA{1'b0}};
        tick_divider = 0;
        s_tick       = 0;
        pass_cnt     = 0;
        fail_cnt     = 0;

        // Reset inicial
        repeat (5) @(posedge clock);
        reset = 0;
        repeat (5) @(posedge clock);

        // 1. Verificar estado IDLE
        if (tx === 1'b1 && tx_done === 1'b0) begin
            $display("[PASS] Estado IDLE verificado (tx=1, tx_done=0)");
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("[FAIL] Estado IDLE incorrecto (tx=%b, tx_done=%b)", tx, tx_done);
            fail_cnt = fail_cnt + 1;
        end

        // 2. Transmision 1: 0xA5 (10100101)
        $display("\n--- Test 1: Transmitiendo 0xA5 ---");
        transmit_byte(8'hA5);

        // 3. Transmision 2 consecutiva: 0x3C (00111100) para verificar vuelta a IDLE y nueva trama
        repeat (5) @(posedge clock);
        $display("\n--- Test 2: Transmitiendo 0x3C consecutivamente ---");
        transmit_byte(8'h3C);

        // Resumen
        $display("\n=================================");
        $display("Resumen tb_uart_tx: PASS=%0d, FAIL=%0d", pass_cnt, fail_cnt);
        $display("=================================");
        if (fail_cnt == 0) begin
            $display("TEST COMPLETADO EXITOSAMENTE");
        end else begin
            $display("TEST FINALIZO CON ERRORES");
        end

        $finish;
    end

endmodule

