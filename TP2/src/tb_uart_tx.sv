`timescale 1ns / 1ps

// =============================================================================
// Testbench: tb_uart_tx
// Descripcion: Verifica el funcionamiento del transmisor UART (uart_tx)
//              comprobando bit de start, bits de datos (LSB primero),
//              bit de stop y el pulso tx_done.
// =============================================================================

module tb_uart_tx;

    localparam int NB_DATA = 8;
    localparam int NB_STOP = 1;

    logic               clock;
    logic               reset;
    logic               tx_start;
    logic               s_tick;
    logic [NB_DATA-1:0] d_in;
    logic               tx;
    logic               tx_done;

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
    int tick_divider = 0;
    always_ff @(posedge clock) begin
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

    int pass_cnt = 0;
    int fail_cnt = 0;

    task wait_ticks(input int count);
        int seen;
        seen = 0;
        while (seen < count) begin
            @(posedge clock);
            if (s_tick) seen++;
        end
    endtask

    initial begin
        clock    = 0;
        reset    = 1;
        tx_start = 0;
        d_in     = '0;

        // Reset inicial
        repeat (5) @(posedge clock);
        reset = 0;
        repeat (5) @(posedge clock);

        // 1. Verificar estado IDLE
        if (tx === 1'b1 && tx_done === 1'b0) begin
            $display("[PASS] Estado IDLE verificado (tx=1, tx_done=0)");
            pass_cnt++;
        end else begin
            $display("[FAIL] Estado IDLE incorrecto (tx=%b, tx_done=%b)", tx, tx_done);
            fail_cnt++;
        end

        // 2. Transmitir byte 8'hA5 (binario 10100101)
        @(negedge clock);
        d_in     = 8'hA5;
        tx_start = 1'b1;
        @(posedge clock);
        @(negedge clock);
        tx_start = 1'b0;

        // Esperar al centro del bit de Start (8 ticks)
        wait_ticks(8);
        if (tx === 1'b0) begin
            $display("[PASS] Bit de Start detectado (tx=0)");
            pass_cnt++;
        end else begin
            $display("[FAIL] Bit de Start incorrecto (tx=%b)", tx);
            fail_cnt++;
        end

        // Muestrear cada bit de datos a la mitad (cada 16 ticks)
        for (int i = 0; i < NB_DATA; i++) begin
            wait_ticks(16);
            if (tx === d_in[i]) begin
                $display("[PASS] Bit de datos [%0d] = %b correcto", i, tx);
                pass_cnt++;
            end else begin
                $display("[FAIL] Bit de datos [%0d] = %b esperado %b", i, tx, d_in[i]);
                fail_cnt++;
            end
        end

        // Muestrear bit de stop a la mitad (16 ticks)
        wait_ticks(16);
        if (tx === 1'b1) begin
            $display("[PASS] Bit de Stop detectado (tx=1)");
            pass_cnt++;
        end else begin
            $display("[FAIL] Bit de Stop incorrecto (tx=%b)", tx);
            fail_cnt++;
        end

        // Esperar fin de Stop y verificar pulso tx_done
        wait_ticks(8);
        @(posedge clock);
        // Esperar hasta ver tx_done o timeout
        fork : done_wait
            begin
                @(posedge tx_done);
                $display("[PASS] Pulso tx_done detectado correctamente");
                pass_cnt++;
            end
            begin
                repeat (100) @(posedge clock);
                $display("[FAIL] Timeout esperando pulso tx_done");
                fail_cnt++;
            end
        join_any
        disable done_wait;

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

