`timescale 1ns / 1ps

// =============================================================================
// Testbench: tb_uart_loopback
// Descripcion: Conecta uart_brg, uart_tx y uart_rx en bucle cerrado (loopback).
//              Transmite varios bytes y comprueba que se reciban intactos
//              y con los flags de finalizacion correspondientes.
// =============================================================================

module tb_uart_loopback;

    localparam int unsigned CLOCK_FREQ = 100_000_000;
    // Usamos baud rate alto para acelerar los tiempos de simulacion
    localparam int unsigned BAUD_RATE  = 1_000_000;
    localparam int NB_DATA             = 8;
    localparam int NB_STOP             = 1;

    logic               clock;
    logic               reset;
    logic               s_tick;

    // Conexiones TX
    logic               tx_start;
    logic [NB_DATA-1:0] tx_data_in;
    logic               tx_line;
    logic               tx_done;

    // Conexiones RX
    logic [NB_DATA-1:0] rx_data_out;
    logic               rx_done;

    // 1. Instancia BRG
    uart_brg #(
        .BAUD_RATE (BAUD_RATE),
        .CLOCK_FREQ(CLOCK_FREQ)
    ) u_uart_brg (
        .rate   (s_tick),
        .i_clock(clock),
        .i_reset(reset)
    );

    // 2. Instancia TX
    uart_tx #(
        .NB_DATA(NB_DATA),
        .NB_STOP(NB_STOP)
    ) u_uart_tx (
        .o_tx      (tx_line),
        .o_tx_done (tx_done),
        .i_clock   (clock),
        .i_reset   (reset),
        .i_tx_start(tx_start),
        .i_s_tick  (s_tick),
        .i_d_in    (tx_data_in)
    );

    // 3. Instancia RX
    uart_rx #(
        .NB_DATA(NB_DATA),
        .NB_STOP(NB_STOP)
    ) u_uart_rx (
        .o_d_out  (rx_data_out),
        .o_rx_done(rx_done),
        .i_clock  (clock),
        .i_reset  (reset),
        .i_rx     (tx_line),
        .i_s_tick (s_tick)
    );

    // Reloj de 100 MHz (periodo 10 ns)
    always #5 clock = ~clock;

    int pass_cnt = 0;
    int fail_cnt = 0;

    task send_and_verify(input [NB_DATA-1:0] byte_to_send);
        begin
            @(negedge clock);
            tx_data_in = byte_to_send;
            tx_start   = 1'b1;
            @(posedge clock);
            @(negedge clock);
            tx_start   = 1'b0;

            // Esperar que termine la recepcion
            @(posedge rx_done);
            @(posedge clock);

            if (rx_data_out === byte_to_send) begin
                $display("[PASS] Byte transmitido: 0x%02X, Byte recibido: 0x%02X", byte_to_send, rx_data_out);
                pass_cnt++;
            end else begin
                $display("[FAIL] Byte transmitido: 0x%02X, Byte recibido: 0x%02X (INCORRECTO)", byte_to_send, rx_data_out);
                fail_cnt++;
            end

            // Esperar tx_done
            if (!tx_done) begin
                @(posedge tx_done);
            end

            repeat (20) @(posedge clock);
        end
    endtask

    initial begin
        clock      = 0;
        reset      = 1;
        tx_start   = 0;
        tx_data_in = '0;

        repeat (10) @(posedge clock);
        reset = 0;
        repeat (20) @(posedge clock);

        $display("=== Iniciando Testbench Loopback UART ===");

        send_and_verify(8'h55); // 01010101
        send_and_verify(8'hAA); // 10101010
        send_and_verify(8'h00); // 00000000
        send_and_verify(8'hFF); // 11111111
        send_and_verify(8'h3C); // 00111100
        send_and_verify(8'hC3); // 11000011

        $display("\n==========================================");
        $display("Resumen Loopback UART: PASS=%0d, FAIL=%0d", pass_cnt, fail_cnt);
        $display("==========================================");

        if (fail_cnt == 0) begin
            $display("LOOPBACK UART EXITOSO");
        end else begin
            $display("LOOPBACK UART FINALIZO CON ERRORES");
        end

        $finish;
    end

endmodule

