`timescale 1ns / 1ps

// =============================================================================
// Testbench: tb_top
// Descripcion: Verifica la captura de operandos y operacion mediante botones,
//              el resultado en los LEDs y los glifos del display de 7 segmentos.
// =============================================================================

module tb_top;

    // -------------------------------------------------------------------------
    // Constantes del display (activo bajo, seg[6:0] = {CG,CF,CE,CD,CC,CB,CA})
    // -------------------------------------------------------------------------
    localparam SEG_BLANK = 7'h7F;
    localparam SEG_ZERO  = 7'h40;   // digito "0"
    localparam SEG_O     = 7'h23;   // letra  "o"

    // Opcodes
    localparam ADD = 6'b100000;
    localparam SUB = 6'b100010;

    // -------------------------------------------------------------------------
    // Senales
    // -------------------------------------------------------------------------
    reg         CLK100MHZ = 0;
    reg  [15:0] sw        = 0;
    reg         btnU      = 0;
    reg         btnD      = 0;
    reg         btnC      = 0;

    wire [15:0] LED;
    wire [6:0]  seg;
    wire [3:0]  an;
    wire        dp;

    // -------------------------------------------------------------------------
    // Instancia bajo prueba
    // -------------------------------------------------------------------------
    top u_top (
        .LED      (LED),
        .seg      (seg),
        .an       (an),
        .dp       (dp),
        .sw       (sw),
        .CLK100MHZ(CLK100MHZ),
        .btnC     (btnC),
        .btnU     (btnU),
        .btnD     (btnD)
    );

    // -------------------------------------------------------------------------
    // Clock 100 MHz -> periodo 10 ns
    // -------------------------------------------------------------------------
    always #5 CLK100MHZ = ~CLK100MHZ;

    // -------------------------------------------------------------------------
    // Contadores
    // -------------------------------------------------------------------------
    integer pass_cnt = 0;
    integer fail_cnt = 0;

    // -------------------------------------------------------------------------
    // Macros de ciclo de reloj
    // -------------------------------------------------------------------------
    // Carga sw y pulsa el boton indicado durante 3 flancos de subida:
    //   posedge 1: btn sube, btn_d=0  → flanco detectado → captura sw
    //   posedge 2: estabilizacion
    //   posedge 3: btn baja
    task load_sw_btn;
        input [15:0] val;
        input        which; // 0=U, 1=D, 2=C (solo valores 0..2)
        input integer which_i;
        begin
            sw = val;
            @(negedge CLK100MHZ);
            if      (which_i == 0) btnU = 1;
            else if (which_i == 1) btnD = 1;
            else                   btnC = 1;
            @(posedge CLK100MHZ); // ciclo 1: captura
            @(posedge CLK100MHZ); // ciclo 2: estabilizacion
            @(negedge CLK100MHZ);
            if      (which_i == 0) btnU = 0;
            else if (which_i == 1) btnD = 0;
            else                   btnC = 0;
            @(posedge CLK100MHZ);
            #1;
        end
    endtask

    // -------------------------------------------------------------------------
    // Verificacion de valor
    // -------------------------------------------------------------------------
    task check_val;
        input [15:0] got;
        input [15:0] exp;
        input [127:0] name;
        begin
            if (got !== exp) begin
                $display("FAIL [%0s]  got=0x%04X  exp=0x%04X", name, got, exp);
                fail_cnt = fail_cnt + 1;
            end else begin
                $display("PASS [%0s]", name);
                pass_cnt = pass_cnt + 1;
            end
        end
    endtask

    // -------------------------------------------------------------------------
    // Verificacion del display: espera hasta ver el anodo esperado, luego chequea seg
    // -------------------------------------------------------------------------
    task check_seg;
        input [3:0] exp_an;
        input [6:0] exp_seg;
        input [127:0] name;
        integer timeout;
        begin
            timeout = 0;
            while (an !== exp_an && timeout < 300000) begin
                @(posedge CLK100MHZ);
                timeout = timeout + 1;
            end
            #1;
            if (an !== exp_an || seg !== exp_seg) begin
                $display("FAIL [%0s]  an=0b%04b seg=0b%07b | exp_an=0b%04b exp_seg=0b%07b",
                    name, an, seg, exp_an, exp_seg);
                fail_cnt = fail_cnt + 1;
            end else begin
                $display("PASS [%0s]", name);
                pass_cnt = pass_cnt + 1;
            end
        end
    endtask

    // -------------------------------------------------------------------------
    // Estimulos
    // -------------------------------------------------------------------------
    initial begin
        $display("=== Inicio testbench TOP ===");
        repeat(5) @(posedge CLK100MHZ);

        // =====================================================================
        // Test 1: ADD  3 + 5 = 8  (sin overflow, sin zero)
        // =====================================================================
        $display("--- Test 1: ADD 3+5=8 ---");
        load_sw_btn(16'h0003, 1'b0, 0); // operando A = 3  (btnU)
        load_sw_btn(16'h0005, 1'b0, 1); // operando B = 5  (btnD)
        load_sw_btn({10'b0, ADD}, 1'b0, 2); // operacion ADD (btnC)
        repeat(4) @(posedge CLK100MHZ); #1;

        check_val(LED, 16'h0008, "LED ADD 3+5");
        check_seg(4'b0111, SEG_BLANK, "SEG ovf=0 blank");
        check_seg(4'b1011, SEG_BLANK, "SEG zero=0 blank");

        // =====================================================================
        // Test 2: ADD overflow  0x7FFF + 1 = 0x8000
        // =====================================================================
        $display("--- Test 2: ADD overflow 0x7FFF+1 ---");
        load_sw_btn(16'h7FFF, 1'b0, 0); // operando A
        load_sw_btn(16'h0001, 1'b0, 1); // operando B (op sigue siendo ADD)
        repeat(4) @(posedge CLK100MHZ); #1;

        check_val(LED, 16'h8000, "LED ADD ovf result");
        check_seg(4'b0111, SEG_O,     "SEG ovf=1 shows o");
        check_seg(4'b1011, SEG_BLANK, "SEG zero=0 blank");

        // =====================================================================
        // Test 3: SUB  5 - 5 = 0  (zero flag)
        // =====================================================================
        $display("--- Test 3: SUB 5-5=0 (zero) ---");
        load_sw_btn(16'h0005, 1'b0, 0);
        load_sw_btn(16'h0005, 1'b0, 1);
        load_sw_btn({10'b0, SUB}, 1'b0, 2);
        repeat(4) @(posedge CLK100MHZ); #1;

        check_val(LED, 16'h0000, "LED SUB zero");
        check_seg(4'b0111, SEG_BLANK, "SEG ovf=0 blank");
        check_seg(4'b1011, SEG_ZERO,  "SEG zero=1 shows 0");

        // =====================================================================
        // Test 4: Deteccion de flanco - boton ya alto no recaptura
        // =====================================================================
        $display("--- Test 4: Edge detection ---");
        // Flanco ascendente de btnD con sw=0xBEEF -> operando B = 0xBEEF
        sw = 16'hBEEF;
        @(negedge CLK100MHZ); btnD = 1;
        @(posedge CLK100MHZ);   // flanco detectado: operand_b_reg <= 0xBEEF
        #1;                     // deja que el DUT capture sw=0xBEEF antes de cambiarlo
        // btn_d=1 ahora; cambiar sw ya no afecta operand_b_reg
        sw = 16'hDEAD;
        @(posedge CLK100MHZ);   // sin nuevo flanco (btnD y btnD_d ambos en 1)
        @(negedge CLK100MHZ); btnD = 0;
        @(posedge CLK100MHZ); #1;
        // A=5 (Test3), B=0xBEEF, op=SUB -> 5 - 0xBEEF = 0x4116 (wrapping 16-bit)
        check_val(LED, 16'h4116, "Edge: B=BEEF not DEAD");

        // Restaurar B=5 para siguientes tests
        load_sw_btn(16'h0005, 1'b0, 1);

        // =====================================================================
        // Test 5: dp siempre apagado (activo bajo -> debe ser 1)
        // =====================================================================
        $display("--- Test 5: dp siempre OFF ---");
        #1;
        check_val({15'b0, dp}, 16'h0001, "dp always off");

        // =====================================================================
        // Resumen
        // =====================================================================
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
