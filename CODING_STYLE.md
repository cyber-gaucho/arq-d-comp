# Convenciones de código — Verilog/SystemVerilog

Este documento define las convenciones de estilo utilizadas en el repositorio para el desarrollo de RTL en Verilog/SystemVerilog.

El objetivo es mantener el código consistente, legible y fácil de mantener por todos los integrantes del proyecto y por herramientas o agentes que analicen o modifiquen el código.

Estas convenciones son de **estilo** y no modifican las reglas sintácticas o semánticas definidas por Verilog/SystemVerilog.

---

## 1. Nombres

Utilizar `lower_snake_case` para nombres de módulos, señales, variables, funciones y archivos.

```systemverilog
module uart_rx;

logic [7:0] rx_data;
logic       rx_valid;
logic       rx_busy;
```

Evitar mezclar estilos de nombres:

```systemverilog
// Evitar
module UART_RX;
logic [7:0] RxData;
logic       rxValid;
```

### Archivos

Los archivos SystemVerilog deben utilizar:

```text
lower_snake_case.sv
```

Ejemplos:

```text
uart_rx.sv
uart_tx.sv
baud_generator.sv
alu.sv
register_file.sv
```

---

## 2. Módulos e instancias

Los módulos utilizan `lower_snake_case`.

```systemverilog
module uart_rx (...);
```

Las instancias utilizan preferentemente el prefijo `u_`:

```systemverilog
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

```systemverilog
logic       rx_valid;
logic [7:0] rx_data;
logic [3:0] bit_counter;
```

Evitar abreviaturas innecesarias. Las señales deben tener nombres que indiquen claramente su función.

Preferir:

```systemverilog
logic data_valid;
```

sobre:

```systemverilog
logic dv;
```

cuando la abreviatura no sea una convención evidente del diseño.

---

## 4. Parámetros

Los parámetros constantes utilizan `UPPER_SNAKE_CASE`.

```systemverilog
parameter int DATA_WIDTH = 8;
parameter int BAUD_RATE  = 115200;
```

Ejemplo:

```systemverilog
module uart_rx #(
    parameter int DATA_WIDTH = 8
) (
    ...
);
```

---

## 5. Tipos de señales

En SystemVerilog utilizar preferentemente `logic` para las señales RTL.

```systemverilog
logic       rx_valid;
logic [7:0] rx_data;
```

No utilizar `reg` cuando `logic` sea suficiente.

`wire` puede utilizarse cuando se quiera expresar explícitamente una conexión de tipo net o cuando sea requerido por una interfaz específica.

---

## 6. Lógica secuencial

Utilizar `always_ff` para lógica secuencial asociada a un reloj.

```systemverilog
always_ff @(posedge clk) begin
    if (rst) begin
        counter_q <= '0;
    end else begin
        counter_q <= counter_d;
    end
end
```

Utilizar asignaciones no bloqueantes (`<=`) dentro de bloques secuenciales.

---

## 7. Lógica combinacional

Utilizar `always_comb` para lógica combinacional.

```systemverilog
always_comb begin
    next_state = state_q;

    case (state_q)
        ...
    endcase
end
```

Utilizar asignaciones bloqueantes (`=`) dentro de bloques combinacionales.

Evitar inferir almacenamiento accidentalmente. Las señales asignadas dentro de un bloque combinacional deben recibir un valor para todas las condiciones posibles.

---

## 8. Convención `_q` / `_d`

Cuando una señal representa el estado de un registro y su próximo valor, utilizar:

* `_q` → valor actual almacenado en el registro.
* `_d` → próximo valor calculado para el registro.

Ejemplo:

```systemverilog
logic [7:0] counter_q;
logic [7:0] counter_d;
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

```systemverilog
always_comb begin
    counter_d = counter_q;

    if (enable) begin
        counter_d = counter_q + 1;
    end
end

always_ff @(posedge clk) begin
    if (rst) begin
        counter_q <= '0;
    end else begin
        counter_q <= counter_d;
    end
end
```

Esta convención es especialmente recomendable para máquinas de estados y unidades secuenciales complejas.

---

## 9. Máquinas de estados (FSM)

Utilizar `typedef enum` para representar los estados cuando sea apropiado.

Los nombres de estados utilizan `StCamelCase`.

```systemverilog
typedef enum logic [1:0] {
    StIdle,
    StStart,
    StData,
    StStop
} state_t;
```

El estado registrado utiliza la convención `_q`:

```systemverilog
state_t state_q;
state_t state_d;
```

Ejemplo:

```systemverilog
always_comb begin
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

El reset debe denominarse `rst` cuando no sea necesario distinguir su polaridad mediante el nombre.

Cuando resulte útil indicar explícitamente que una señal es activa en bajo, utilizar el sufijo `_n`.

Ejemplo:

```systemverilog
logic rst_n;
```

Esto indica que la señal se considera activa cuando vale `0`.

No utilizar `_n` únicamente por costumbre: debe representar realmente una señal activa en bajo.

---

## 11. Reloj

Utilizar `clk` como nombre predeterminado para el reloj principal.

```systemverilog
input logic clk;
```

Si existen múltiples dominios de reloj, utilizar nombres que permitan identificar claramente cada uno:

```systemverilog
logic clk_uart;
logic clk_cpu;
logic clk_peripheral;
```

---

## 12. Constantes y literales

Cuando el tamaño de un literal sea relevante, especificarlo explícitamente.

Preferir:

```systemverilog
8'd255
4'b1010
```

sobre:

```systemverilog
255
10
```

Para poner un registro completamente en cero o en uno, utilizar el operador de replicación de tamaño:

```systemverilog
counter_q <= '0;
counter_q <= '1;
```

Esto evita depender del ancho explícito de la señal.

---

## 13. Indentación y formato

Utilizar **4 espacios** para cada nivel de indentación.

```systemverilog
always_ff @(posedge clk) begin
    if (rst) begin
        data_q <= '0;
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
4. Tipos y constantes locales
5. Señales internas
6. Instancias de submódulos
7. Lógica combinacional
8. Lógica secuencial
```

Ejemplo conceptual:

```systemverilog
module example #(
    parameter int DATA_WIDTH = 8
) (
    input  logic                 clk,
    input  logic                 rst,
    input  logic [DATA_WIDTH-1:0] data_i,
    output logic [DATA_WIDTH-1:0] data_o
);

    // Tipos y constantes

    // Señales internas
    logic [DATA_WIDTH-1:0] data_q;
    logic [DATA_WIDTH-1:0] data_d;

    // Instancias

    // Lógica combinacional
    always_comb begin
        ...
    end

    // Lógica secuencial
    always_ff @(posedge clk) begin
        ...
    end

endmodule
```

No es obligatorio mantener exactamente esta estructura cuando el módulo sea muy simple o cuando una organización diferente resulte más clara.

---

## 15. Comentarios

Los comentarios deben explicar **por qué** existe una decisión de diseño cuando el código por sí mismo no resulta suficiente para entenderla.

Preferir:

```systemverilog
// Se muestrea en el centro del bit para maximizar el margen frente
// a errores de temporización.
```

sobre:

```systemverilog
// Incrementa el contador.
bit_counter <= bit_counter + 1;
```

No utilizar comentarios para describir literalmente instrucciones cuyo comportamiento ya resulta evidente.

---

## 16. Instanciación de módulos

Preferir conexiones mediante nombres de puertos:

```systemverilog
uart_rx u_uart_rx (
    .clk       (clk),
    .rst       (rst),
    .rx        (rx),
    .data      (rx_data),
    .data_valid(rx_valid)
);
```

Evitar conexiones posicionales:

```systemverilog
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

| Elemento              | Convención            |
| --------------------- | --------------------- |
| Archivos              | `lower_snake_case.sv` |
| Módulos               | `lower_snake_case`    |
| Instancias            | `u_nombre`            |
| Señales               | `lower_snake_case`    |
| Variables             | `lower_snake_case`    |
| Parámetros            | `UPPER_SNAKE_CASE`    |
| Estados FSM           | `StCamelCase`         |
| Registro actual       | `_q`                  |
| Próximo valor         | `_d`                  |
| Reset activo bajo     | `_n`                  |
| Reloj                 | `clk`                 |
| Señales RTL           | `logic`               |
| Lógica secuencial     | `always_ff`           |
| Lógica combinacional  | `always_comb`         |
| Indentación           | 4 espacios            |
| Conexiones de módulos | Por nombre            |
