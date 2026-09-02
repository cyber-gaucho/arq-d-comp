`timescale 1ns / 1ps

module tb_btn_reg;

    parameter WIDTH = 8;

    reg               clk = 0;
    reg               rst = 0;
    reg               btn = 0;
    reg  [WIDTH-1:0] sw  = 0;
    wire [WIDTH-1:0] data;

    btn_reg #(
        .WIDTH(WIDTH)
    ) u_dut (
        .i_clk (clk),
        .i_rst (rst),
        .i_btn (btn),
        .i_sw  (sw),
        .o_data(data)
    );

    always #5 clk = ~clk;

    integer pass_cnt = 0;
    integer fail_cnt = 0;

    task check;
        input [WIDTH-1:0] exp;
        input [127:0] name;
        begin
            #1;
            if (data !== exp) begin
                $display("FAIL [%0s] got=0x%02X exp=0x%02X", name, data, exp);
                fail_cnt = fail_cnt + 1;
            end else begin
                $display("PASS [%0s]", name);
                pass_cnt = pass_cnt + 1;
            end
        end
    endtask

    initial begin
        $display("=== Inicio testbench btn_reg ===");

        rst = 1;
        repeat (2) @(posedge clk);
        rst = 0;
        check({WIDTH{1'b0}}, "reset initial state");

        sw = 8'hA5;
        @(negedge clk); btn = 1;
        @(posedge clk); #1;
        check(8'hA5, "capture on rising edge");

        sw = 8'h5A;
        repeat (2) @(posedge clk);
        check(8'hA5, "ignore while button held");

        @(negedge clk); btn = 0;
        repeat (2) @(posedge clk);

        sw = 8'h3C;
        @(negedge clk); btn = 1;
        @(posedge clk); #1;
        check(8'h3C, "second capture works");

        rst = 1;
        @(posedge clk); #1;
        check({WIDTH{1'b0}}, "async reset clears data");

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
