// =============================================================================
// Modulo      : fifo
// Archivo     : fifo.v
// Descripcion : Buffer FIFO sincronico parametrizable con salida tipo FWFT
//               (First-Word Fall-Through). El dato leido o_r_data esta
//               disponible en la salida siempre que la FIFO no este vacia.
//               La lectura (i_rd) descarta el dato actual y avanza el puntero.
// =============================================================================

module fifo #(
    // PARAMETROS
    parameter NB_DATA    = 8,
    parameter FIFO_DEPTH = 8
) (
    // RELOJ Y RESET
    input  wire               i_clock,
    input  wire               i_reset,

    // PUERTO DE ESCRITURA
    input  wire               i_wr,
    input  wire [NB_DATA-1:0] i_w_data,
    output wire               o_full,

    // PUERTO DE LECTURA
    input  wire               i_rd,
    output wire [NB_DATA-1:0] o_r_data,
    output wire               o_empty
);

    // -------------------------------------------------------------------------
    // Parametros locales
    // -------------------------------------------------------------------------
    localparam ADDR_WIDTH = $clog2(FIFO_DEPTH);

    // -------------------------------------------------------------------------
    // Memoria y registros de punteros y contador
    // -------------------------------------------------------------------------
    reg [NB_DATA-1:0]    mem [FIFO_DEPTH-1:0];
    reg [ADDR_WIDTH-1:0] wr_ptr_q, wr_ptr_d;
    reg [ADDR_WIDTH-1:0] rd_ptr_q, rd_ptr_d;
    reg [ADDR_WIDTH:0]   count_q,  count_d;

    // -------------------------------------------------------------------------
    // Asignaciones continuas de banderas y dato de salida (FWFT)
    // -------------------------------------------------------------------------
    assign o_empty  = (count_q == {(ADDR_WIDTH+1){1'b0}});
    assign o_full   = (count_q == FIFO_DEPTH[ADDR_WIDTH:0]);
    assign o_r_data = mem[rd_ptr_q];

    // -------------------------------------------------------------------------
    // BLOQUE 1 - Logica Secuencial
    // -------------------------------------------------------------------------
    always @(posedge i_clock) begin : Seq_logic
        if (i_reset) begin
            wr_ptr_q <= {ADDR_WIDTH{1'b0}};
            rd_ptr_q <= {ADDR_WIDTH{1'b0}};
            count_q  <= {(ADDR_WIDTH+1){1'b0}};
        end else begin
            wr_ptr_q <= wr_ptr_d;
            rd_ptr_q <= rd_ptr_d;
            count_q  <= count_d;

            if (i_wr && !o_full) begin
                mem[wr_ptr_q] <= i_w_data;
            end
        end
    end

    // -------------------------------------------------------------------------
    // BLOQUE 2 - Logica Combinacional para punteros y contador
    // -------------------------------------------------------------------------
    always @(*) begin : Comb_pointers
        wr_ptr_d = wr_ptr_q;
        rd_ptr_d = rd_ptr_q;
        count_d  = count_q;

        case ({i_wr && !o_full, i_rd && !o_empty})
            2'b10: begin
                // Solo escritura
                wr_ptr_d = wr_ptr_q + 1'b1;
                count_d  = count_q + 1'b1;
            end
            2'b01: begin
                // Solo lectura
                rd_ptr_d = rd_ptr_q + 1'b1;
                count_d  = count_q - 1'b1;
            end
            2'b11: begin
                // Lectura y escritura simultaneas
                wr_ptr_d = wr_ptr_q + 1'b1;
                rd_ptr_d = rd_ptr_q + 1'b1;
            end
            default: begin
                // Sin operacion o condicion invalida
            end
        endcase
    end

endmodule
