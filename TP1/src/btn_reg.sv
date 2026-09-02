module btn_reg #(
    parameter WIDTH = 8
)(
    input  wire                 i_clk,
    input  wire                 i_rst,
    input  wire                 i_btn,
    input  wire [WIDTH-1:0]     i_sw,
    output reg  [WIDTH-1:0]     o_data
);

    reg r_btn_prev = 1'b0;

    always @(posedge i_clk) begin
        if (i_rst) begin
            o_data      <= {WIDTH{1'b0}};
            r_btn_prev  <= 1'b0;
        end else begin
            if (i_btn && !r_btn_prev)
                o_data <= i_sw;
            r_btn_prev <= i_btn;
        end
    end

endmodule

// Button register module
// This module captures the value of the input switch (i_sw) when the button (i_btn) is pressed. 
// The captured value is stored in the output register (o_data). The module also includes
// a reset signal (i_rst) that clears the output register and the previous button state. 
// The r_btn_prev register is used to detect the rising edge of the button press, ensuring 
// that the value is only captured once per button press.
// The WIDTH parameter allows for flexibility in the size of the data being captured.
