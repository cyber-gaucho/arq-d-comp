`timescale 1ns / 1ps

// =============================================================================
// Testbench: tb_uart_rx
// Descripcion: Verifica el funcionamiento unitario del receptor UART (uart_rx).
//              Comprueba recepcion de distintos patrones (0x00, 0xFF, 0x55, 0xA5),
//              recepcion consecutiva y rechazo de pulsos espurios (glitches) en
//              el bit de inicio.
// =============================================================================

module tb_uart_rx;

    parameter NB_DATA = 8;
    parameter NB_STOP = 1;

    reg               clock;
    reg               reset;
    reg               rx;
    reg               s_tick;
    wire [NB_DATA-1:0] d_out;
    wire              rx_done;

    // Instancia de uart_rx
    uart_rx #(
        .NB_DATA(NB_DATA),
        .NB_STOP(NB_STOP)
    ) u_uart_rx (
        .o_d_out  (d_out),
        .o_rx_done(rx_done),
        .i_clock  (clock),
        .i_reset  (reset),
        .i_rx     (rx),
        .i_s_tick (s_tick)
    );

    // Reloj principal (50 MHz -> periodo 20 ns)
    always #10 clock = ~clock;

    // Generador de s_tick cada 4 ciclos de reloj
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

    // Tarea para inyectar un byte en serie por rx emulando un transmisor UART
    task send_byte;
        input [NB_DATA-1:0] byte_val;
        integer i;
        integer timeout_cnt;
        reg     done_seen;
        begin
            $display("[INFO] Enviando byte serial: 0x%02X", byte_val);

            // Bit de inicio (Start = 0)
            @(negedge clock);
            rx = 1'b0;
            wait_ticks(16);

            // Bits de datos (LSB primero)
            for (i = 0; i < NB_DATA; i = i + 1) begin
                rx = byte_val[i];
                wait_ticks(16);
            end

            // Bit(s) de parada (Stop = 1)
            rx = 1'b1;
            wait_ticks(16 * NB_STOP);

            // Esperar y validar recepcion
            timeout_cnt = 0;
            done_seen   = 1'b0;
            while (!done_seen && timeout_cnt < 100) begin
                @(posedge clock);
                timeout_cnt = timeout_cnt + 1;
                if (rx_done === 1'b1) begin
                    done_seen = 1'b1;
                end
            end

            if (done_seen && (d_out === byte_val)) begin
                $display("[PASS] Byte recibido correctamente: 0x%02X (rx_done=1)", d_out);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("[FAIL] Recepcion incorrecta. rx_done=%b, d_out=0x%02X (esperado 0x%02X)",
                         done_seen, d_out, byte_val);
                fail_cnt = fail_cnt + 1;
            end

            repeat (10) @(posedge clock);
        end
    endtask

    // Tarea para inyectar un pulso espurio (glitch) menor a medio bit de Start
    task inject_glitch;
        begin
            $display("\n--- Test: Inyectando pulso espurio / ruido en Start ---");
            @(negedge clock);
            rx = 1'b0;
            // Glitch que dura solo 3 ticks (menos de 7 ticks)
            wait_ticks(3);
            rx = 1'b1;

            // Esperar suficiente tiempo para verificar que no emita rx_done ni cambie d_out
            wait_ticks(32);

            if (rx_done === 1'b0) begin
                $display("[PASS] Glitch rechazado correctamente (no se disparo falsa recepcion)");
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("[FAIL] Glitch aceptado erroneamente como trama valida");
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    initial begin
        clock        = 0;
        reset        = 1;
        rx           = 1;
        tick_divider = 0;
        s_tick       = 0;
        pass_cnt     = 0;
        fail_cnt     = 0;

        repeat (5) @(posedge clock);
        reset = 0;
        repeat (10) @(posedge clock);

        $display("=== Iniciando Testbench UART RX ===");

        // 1. Recepcion de 0x55 (01010101)
        send_byte(8'h55);

        // 2. Recepcion de 0xAA (10101010)
        send_byte(8'hAA);

        // 3. Recepcion de 0x00
        send_byte(8'h00);

        // 4. Recepcion de 0xFF
        send_byte(8'hFF);

        // 5. Recepcion de 0xA5
        send_byte(8'hA5);

        // 6. Rechazo de glitch
        inject_glitch();

        // 7. Recepcion posterior valida para comprobar recuperacion a IDLE
        $display("\n--- Test: Recepcion valida tras glitch ---");
        send_byte(8'hC3);

        $display("\n=================================");
        $display("Resumen tb_uart_rx: PASS=%0d, FAIL=%0d", pass_cnt, fail_cnt);
        $display("=================================");
        if (fail_cnt == 0) begin
            $display("TEST COMPLETADO EXITOSAMENTE");
        end else begin
            $display("TEST FINALIZO CON ERRORES");
        end

        $finish;
    end

endmodule

