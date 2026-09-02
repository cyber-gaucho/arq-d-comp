`timescale 1ns / 1ps

// =============================================================================
// Testbench: tb_top
// Descripcion: Verifica la captura de operandos y operacion mediante botones,
//              la salida en LEDs y los flags de cero/overflow.
// =============================================================================

module tb_top;

    localparam ADD = 6'b100000;
    localparam SUB = 6'b100010;

    reg         CLK100MHZ = 0;
    reg  [15:0] sw        = 0;
    reg         btnR      = 0;
    reg         btnU      = 0;
    reg         btnD      = 0;
    reg         btnC      = 0;

    wire [15:0] LED;

    top #(
        .NB_DATA(8)
    ) u_top (
        .LED      (LED),
        .sw       (sw),
        .CLK100MHZ(CLK100MHZ),
        .btnR     (btnR),
        .btnU     (btnU),
        .btnD     (btnD),
        .btnC     (btnC)
    );

    always #5 CLK100MHZ = ~CLK100MHZ;

    integer pass_cnt = 0;
    integer fail_cnt = 0;

    task load_sw_btn;
        input [15:0] val;
        input [1:0]  which; // 0=U, 1=D, 2=C
        begin
            sw = val;
            @(negedge CLK100MHZ);
            if (which == 2'd0) btnU = 1;
            else if (which == 2'd1) btnD = 1;
            else btnC = 1;
            @(posedge CLK100MHZ);
            @(posedge CLK100MHZ);
            @(negedge CLK100MHZ);
            if (which == 2'd0) btnU = 0;
            else if (which == 2'd1) btnD = 0;
            else btnC = 0;
            @(posedge CLK100MHZ);
            #1;
        end
    endtask

    task check_led_bits;
        input [15:0] exp;
        input [127:0] name;
        begin
            if (LED !== exp) begin
                $display("FAIL [%0s]  got=0x%04X  exp=0x%04X", name, LED, exp);
                fail_cnt = fail_cnt + 1;
            end else begin
                $display("PASS [%0s]", name);
                pass_cnt = pass_cnt + 1;
            end
        end
    endtask

    initial begin
        $display("=== Inicio testbench TOP ===");
        repeat(5) @(posedge CLK100MHZ);

        $display("--- Test 1: ADD 3+5=8 ---");
        load_sw_btn(16'h0003, 2'd0);
        load_sw_btn(16'h0005, 2'd1);
        load_sw_btn({10'b0, ADD}, 2'd2);
        repeat(4) @(posedge CLK100MHZ);
        check_led_bits(16'b00000000_00001000, "LED ADD 3+5");

        $display("--- Test 2: ADD overflow 0x7F+1 ---");
        load_sw_btn(16'h007F, 2'd0);
        load_sw_btn(16'h0001, 2'd1);
        repeat(4) @(posedge CLK100MHZ);
        check_led_bits(16'b10000000_10000000, "LED overflow result");

        $display("--- Test 3: SUB 5-5 => zero ---");
        load_sw_btn(16'h0005, 2'd0);
        load_sw_btn(16'h0005, 2'd1);
        load_sw_btn({10'b0, SUB}, 2'd2);
        repeat(4) @(posedge CLK100MHZ);
        check_led_bits(16'b01000000_00000000, "LED zero flag");

        $display("--- Test 4: reset síncrono ---");
        load_sw_btn(16'h00AA, 2'd0);
        load_sw_btn(16'h0055, 2'd1);
        load_sw_btn({10'b0, ADD}, 2'd2);
        btnR = 1;
        @(posedge CLK100MHZ); #1;
        btnR = 0;
        repeat(3) @(posedge CLK100MHZ); #1;
        check_led_bits(16'b01000000_00000000, "reset clears captured values");

        $display("--- Test 5: edge detection ---");
        load_sw_btn(16'h0005, 2'd0);
        load_sw_btn(16'h00BE, 2'd1);
        load_sw_btn({10'b0, SUB}, 2'd2);
        sw = 16'h00DE;
        @(negedge CLK100MHZ); btnD = 1;
        @(posedge CLK100MHZ); #1;
        repeat(2) @(posedge CLK100MHZ);
        @(negedge CLK100MHZ); btnD = 0;
        @(posedge CLK100MHZ); #1;
        check_led_bits(16'b00000000_00100111, "edge: captures only on rising edge");

        $display("--- Test 6: no recapture while held ---");
        load_sw_btn(16'h0005, 2'd0);
        @(negedge CLK100MHZ); btnD = 1;
        sw = 16'h00AA;
        @(posedge CLK100MHZ); #1;
        repeat(2) @(posedge CLK100MHZ);
        @(negedge CLK100MHZ); btnD = 0;
        @(posedge CLK100MHZ); #1;
        check_led_bits(16'b00000000_01011011, "edge: no recapture while held");

        $display("=========================================");
        $display("Resultado: %0d PASS  /  %0d FAIL", pass_cnt, fail_cnt);
        if (fail_cnt == 0)
            $display(">>> TODOS LOS TESTS PASARON <<<");
        else
            $display(">>> ATENCION: hay tests fallidos <<<");
        $display("=========================================");
        $finish;
    end

endmodule
