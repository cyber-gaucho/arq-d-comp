# Convenciones de código — Verilog-2001 (RTL) y Testbenches

Este documento define las convenciones de estilo utilizadas en el repositorio para el desarrollo de RTL en **Verilog-2001** (IEEE 1364-2001).

El objetivo es mantener el código consistente, legible y fácil de mantener por todos los integrantes del proyecto y por herramientas o agentes que analicen o modifiquen el código.

* **Código RTL sintetizable:** debe escribirse exclusivamente en **Verilog-2001** y utilizar la extensión `.v`.
* **Testbenches:** pueden utilizar SystemVerilog (`.sv`) cuando esté técnicamente justificado, pero se debe priorizar Verilog-2001 (`.v`) para mantener la compatibilidad con las herramientas y criterios de la cátedra.

Estas convenciones son de **estilo** y no modifican las reglas sintácticas o semánticas definidas por el estándar.

---

## 1. Nombres

Utilizar `lower_snake_case` para nombres de módulos, señales, variables, funciones y archivos.

```verilog
module uart_rx;

wire [7:0] rx_data;
wire       rx_valid;
reg        rx_busy;
```

Evitar mezclar estilos de nombres:

```verilog
// Evitar
module UART_RX;
wire [7:0] RxData;
reg        rxValid;
```

### Archivos

Los archivos de módulos sintetizables (RTL) deben utilizar la extensión `.v`:

```text
lower_snake_case.v
```

Ejemplos:

```text
uart_rx.v
uart_tx.v
uart_brg.v
alu.v
register_file.v
```

Los archivos de testbench utilizan el prefijo `tb_` (`tb_uart_tx.v` o `tb_uart_tx.sv` cuando se emplee SystemVerilog en simulación).

---

## 2. Módulos e instancias

Los módulos utilizan `lower_snake_case`.

```verilog
module uart_rx (...);
```

Las instancias utilizan preferentemente el prefijo `u_`:

```verilog
uart_rx u_uart_rx (
    .clk  (clk),
    .rst  (rst),
    .rx   (rx),
    .data (data)
);
```

El prefijo `u_` permite distinguir visualmente una instancia de una señal o variable.

---

## 3. Señales y variables

Utilizar `lower_snake_case`.

```verilog
wire       rx_valid;
wire [7:0] rx_data;
reg  [3:0] bit_counter;
```

Evitar abreviaturas innecesarias. Las señales deben tener nombres que indiquen claramente su función.

Preferir:

```verilog
wire data_valid;
```

sobre:

```verilog
wire dv;
```

cuando la abreviatura no sea una convención evidente del diseño.

---

## 4. Parámetros

Los parámetros constantes utilizan `UPPER_SNAKE_CASE`. En Verilog-2001 no se especifica el tipo `int` ni `int unsigned` en la declaración de `parameter` o `localparam`.

```verilog
parameter DATA_WIDTH = 8;
parameter BAUD_RATE  = 115200;
```

Ejemplo:

```verilog
module uart_rx #(
    parameter DATA_WIDTH = 8
) (
    ...
);
```

Utilizar `localparam` para constantes internas que no deban sobreescribirse al instanciar el módulo.

---

## 5. Tipos de señales y equivalencias SystemVerilog → Verilog-2001

En Verilog-2001 no existe el tipo `logic`. Se debe distinguir explícitamente entre redes (`wire`) y variables procedurales (`reg`):

* **`wire`:** para puertos de entrada (`input wire`), señales conducidas por asignaciones continuas (`assign`) o conectadas a salidas de submódulos.
* **`reg`:** para señales asignadas dentro de bloques procedurales (`always @(posedge clk)` o `always @(*)`). Nota: un `reg` asignado en un bloque combinacional `always @(*)` sintetiza lógica combinacional, no un registro físico.

```verilog
wire       rx_valid;
reg  [7:0] rx_data_q;
reg  [7:0] rx_data_d;
```

### Equivalencias entre SystemVerilog y Verilog-2001

| Construcción SystemVerilog (no usar en RTL) | Equivalente en Verilog-2001 (usar en RTL) |
| ------------------------------------------- | ----------------------------------------- |
| `logic`                                     | `wire` (asignación continua / entradas) o `reg` (bloques `always`) |
| `parameter int X = 8;` / `localparam int`   | `parameter X = 8;` / `localparam`         |
| `always_ff @(posedge clk)`                  | `always @(posedge clk)`                   |
| `always_comb`                               | `always @(*)`                             |
| `typedef enum logic [N-1:0] { ... } state_t;` | `localparam [N-1:0] StIdle = ...;` + `reg [N-1:0] state_q, state_d;` |
| `'0` / `'1` (literales de relleno sin ancho) | `{WIDTH{1'b0}}` / `{WIDTH{1'b1}}` o literal con ancho explícito (`4'd0`) |
| `WIDTH'(expr)` (cast explícito de ancho)    | Literal dimensionado (`4'd15`) o expresión del ancho correspondiente |

---

## 6. Lógica secuencial

Utilizar `always @(posedge clk)` para lógica secuencial asociada a un reloj.

```verilog
always @(posedge clk) begin
    if (rst) begin
        counter_q <= {WIDTH{1'b0}};
    end else begin
        counter_q <= counter_d;
    end
end
```

Utilizar asignaciones no bloqueantes (`<=`) dentro de bloques secuenciales.

---

## 7. Lógica combinacional

Utilizar `always @(*)` para lógica combinacional procedural, o `assign` para expresiones simples.

```verilog
always @(*) begin
    next_state = state_q;

    case (state_q)
        ...
    endcase
end
```

Utilizar asignaciones bloqueantes (`=`) dentro de bloques combinacionales.

Evitar inferir almacenamiento (*latches*) accidentalmente. Las señales asignadas dentro de un bloque combinacional deben recibir un valor por defecto o para todas las condiciones posibles.

---

## 8. Convención `_q` / `_d`

Cuando una señal representa el estado de un registro y su próximo valor, utilizar:

* `_q` → valor actual almacenado en el registro.
* `_d` → próximo valor calculado para el registro.

Ejemplo:

```verilog
reg [7:0] counter_q;
reg [7:0] counter_d;
```

La estructura habitual es:

```text
counter_q
    │
    ▼
lógica combinacional
    │
    ▼
counter_d
    │
    ▼
registro
    │
    └──────────► counter_q
```

Ejemplo:

```verilog
always @(*) begin
    counter_d = counter_q;

    if (enable) begin
        counter_d = counter_q + 1'b1;
    end
end

always @(posedge clk) begin
    if (rst) begin
        counter_q <= 8'd0;
    end else begin
        counter_q <= counter_d;
    end
end
```

Esta convención es especialmente recomendable para máquinas de estados y unidades secuenciales complejas.

---

## 9. Máquinas de estados (FSM)

En Verilog-2001, definir la codificación de estados mediante `localparam` con ancho explícito y declarar los registros de estado actual y próximo con `reg`.

Los nombres de estados utilizan `StCamelCase`.

```verilog
localparam [3:0] StIdle  = 4'b0001;
localparam [3:0] StStart = 4'b0010;
localparam [3:0] StData  = 4'b0100;
localparam [3:0] StStop  = 4'b1000;
```

El estado registrado utiliza la convención `_q` y el próximo estado `_d`:

```verilog
reg [3:0] state_q;
reg [3:0] state_d;
```

Ejemplo:

```verilog
always @(*) begin
    state_d = state_q;

    case (state_q)
        StIdle: begin
            ...
        end

        StStart: begin
            ...
        end

        StData: begin
            ...
        end

        StStop: begin
            ...
        end

        default: begin
            state_d = StIdle;
        end
    endcase
end
```

---

## 10. Reset y señales activas en bajo

El reset debe denominarse `rst` (o `i_reset`) cuando no sea necesario distinguir su polaridad mediante el nombre.

Cuando resulte útil indicar explícitamente que una señal es activa en bajo, utilizar el sufijo `_n`.

Ejemplo:

```verilog
wire rst_n;
```

Esto indica que la señal se considera activa cuando vale `0`.

No utilizar `_n` únicamente por costumbre: debe representar realmente una señal activa en bajo.

---

## 11. Reloj

Utilizar `clk` (o `i_clock`) como nombre predeterminado para el reloj principal.

```verilog
input wire clk;
```

Si existen múltiples dominios de reloj, utilizar nombres que permitan identificar claramente cada uno:

```verilog
wire clk_uart;
wire clk_cpu;
wire clk_peripheral;
```

---

## 12. Constantes y literales

Cuando el tamaño de un literal sea relevante, especificarlo explícitamente.

Preferir:

```verilog
8'd255
4'b1010
```

sobre:

```verilog
255
10
```

Para poner un registro parametrizado completamente en cero o en uno en Verilog-2001, utilizar el operador de replicación:

```verilog
counter_q <= {NB_COUNT{1'b0}};
counter_q <= {NB_COUNT{1'b1}};
```

Esto evita depender de literales sin tamaño (`'0` / `'1`), que son exclusivos de SystemVerilog.

---

## 13. Indentación y formato

Utilizar **4 espacios** para cada nivel de indentación.

```verilog
always @(posedge clk) begin
    if (rst) begin
        data_q <= {DATA_WIDTH{1'b0}};
    end else begin
        data_q <= data_d;
    end
end
```

Reglas generales:

* Utilizar espacios alrededor de operadores.
* Mantener una indentación consistente.
* Utilizar `begin` y `end` incluso cuando un bloque contenga una sola sentencia, cuando esto mejore la consistencia del código.
* Separar visualmente secciones importantes del módulo mediante líneas en blanco.
* Evitar líneas excesivamente largas cuando dificulten la lectura.

---

## 14. Organización de un módulo

Cuando sea posible, organizar los módulos siguiendo una estructura consistente:

```text
1. Declaración del módulo
2. Parámetros
3. Puertos
4. Constantes locales (localparam)
5. Señales internas (wire / reg)
6. Instancias de submódulos
7. Lógica combinacional
8. Lógica secuencial
```

Ejemplo conceptual:

```verilog
module example #(
    parameter DATA_WIDTH = 8
) (
    input  wire                  clk,
    input  wire                  rst,
    input  wire [DATA_WIDTH-1:0] data_i,
    output wire [DATA_WIDTH-1:0] data_o
);

    // Constantes locales

    // Señales internas
    reg [DATA_WIDTH-1:0] data_q;
    reg [DATA_WIDTH-1:0] data_d;

    // Instancias

    // Lógica combinacional
    always @(*) begin
        ...
    end

    // Lógica secuencial
    always @(posedge clk) begin
        ...
    end

    assign data_o = data_q;

endmodule
```

No es obligatorio mantener exactamente esta estructura cuando el módulo sea muy simple o cuando una organización diferente resulte más clara.

---

## 15. Comentarios

Los comentarios deben explicar **por qué** existe una decisión de diseño cuando el código por sí mismo no resulta suficiente para entenderla.

Preferir:

```verilog
// Se muestrea en el centro del bit para maximizar el margen frente
// a errores de temporización.
```

sobre:

```verilog
// Incrementa el contador.
bit_counter <= bit_counter + 1'b1;
```

No utilizar comentarios para describir literalmente instrucciones cuyo comportamiento ya resulta evidente.

---

## 16. Instanciación de módulos

Preferir conexiones mediante nombres de puertos:

```verilog
uart_rx u_uart_rx (
    .clk       (clk),
    .rst       (rst),
    .rx        (rx),
    .data      (rx_data),
    .data_valid(rx_valid)
);
```

Evitar conexiones posicionales:

```verilog
uart_rx u_uart_rx (
    clk,
    rst,
    rx,
    rx_data,
    rx_valid
);
```

Las conexiones explícitas facilitan la revisión del código y reducen errores al modificar interfaces.

---

## 17. Regla general

La consistencia tiene prioridad sobre la aplicación mecánica de una convención.

Estas reglas deben utilizarse como guía para mantener un código uniforme, pero una excepción está justificada cuando:

* mejora significativamente la legibilidad;
* responde a una restricción de Vivado o de una herramienta;
* sigue una interfaz o IP externa;
* refleja una convención establecida por la cátedra;
* o evita introducir complejidad innecesaria.

Cuando exista una excepción relevante, documentarla mediante un comentario cuando sea necesario.

---

## Resumen

| Elemento              | Convención                     |
| --------------------- | ------------------------------ |
| Lenguaje RTL          | Verilog-2001                   |
| Archivos RTL          | `lower_snake_case.v`           |
| Archivos Testbench    | `tb_<modulo>.v` (o `.sv`)      |
| Módulos               | `lower_snake_case`             |
| Instancias            | `u_nombre`                     |
| Señales               | `lower_snake_case`             |
| Variables             | `lower_snake_case`             |
| Parámetros            | `UPPER_SNAKE_CASE`             |
| Estados FSM           | `StCamelCase` (`localparam`)   |
| Registro actual       | `_q`                           |
| Próximo valor         | `_d`                           |
| Reset activo bajo     | `_n`                           |
| Reloj                 | `clk` / `i_clock`              |
| Señales RTL           | `wire` / `reg`                 |
| Lógica secuencial     | `always @(posedge clk)` (`<=`) |
| Lógica combinacional  | `always @(*)` (`=`) / `assign` |
| Indentación           | 4 espacios                     |
| Conexiones de módulos | Por nombre                     |
