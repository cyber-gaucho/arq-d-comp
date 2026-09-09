# TP1 — Implementación de una ALU de 8 bits sobre Basys3

| | |
|---|---|
| **Materia:** | Arquitectura de Computadoras |
| **Carrera:** | Ingeniería en Computación |
| **Alumnos:** | García, Lautaro Misael |
|              | Renaudo Gaggioli, Valentino |
| **Fecha:** |-|

---

## 1. Objetivos

El objetivo del trabajo es diseñar e implementar una Unidad Aritmético-Lógica (ALU) sobre una FPGA Digilent Basys3. La ALU debe operar sobre dos operandos de 8 bits y permitir seleccionar entre ocho operaciones aritméticas, lógicas y de desplazamiento mediante un código de operación de 6 bits.

Además de generar el resultado, el diseño incorpora dos flags:

- **Zero:** indica que el resultado de la operación es igual a cero.
- **Overflow:** indica un desbordamiento en complemento a dos para las operaciones aritméticas `ADD` y `SUB`.

La interfaz física utiliza los switches de la placa para ingresar los datos y los pulsadores para capturar los operandos y la operación. El resultado y los flags se visualizan mediante los LEDs.

El proyecto también incluye testbenches para verificar individualmente la ALU, el registro de captura por botón y la integración completa del sistema.

---

## 2. Descripción general del sistema

El sistema está compuesto por tres bloques principales, los cuales permiten ingresar dos operandos y un código de operación utilizando los switches de la Basys3.

1. **Registro del operando A.**
2. **Registro del operando B.**
3. **Registro del código de operación.**
4. **ALU combinacional.**

El módulo `top` realiza la interconexión entre estos bloques y asigna las señales internas a los recursos físicos de la Basys3.

Los switches constituyen un bus de entrada compartido. Cuando se presiona un pulsador, el valor presente en los switches se almacena en el registro correspondiente.

La secuencia normal de utilización es:

1. Colocar el valor del operando A en `sw[7:0]` y presionar `btnU`.
2. Colocar el valor del operando B en `sw[7:0]` y presionar `btnD`.
3. Colocar el código de operación en `sw[5:0]` y presionar `btnC`.
4. Observar el resultado en `LED[7:0]`.
5. Observar las flags `Zero` y `Overflow` en `LED[14]` y `LED[15]`.

El botón `btnR` realiza un reset síncrono de los registros.

**Figura 1 — Diagrama general del sistema**

*[Insertar un diagrama de bloques con: switches → registros A/B/OP → ALU → LEDs. Indicar también los botones `btnU`, `btnD`, `btnC` y `btnR`.]*

---

## 3. Arquitectura de la implementación

La implementación se divide en los módulos `alu`, `btn_reg` y `top`.

### 3.1. Módulo `btn_reg`

El módulo `btn_reg` implementa un registro parametrizable utilizado para almacenar los operandos y el código de operación.

Sus entradas principales son:

- `i_clk`: reloj de 100 MHz de la Basys3.
- `i_rst`: reset síncrono.
- `i_btn`: pulsador utilizado como señal de captura.
- `i_sw`: valor presente en los switches.

Su salida es:

- `o_data`: valor almacenado.

La captura se realiza detectando el flanco ascendente de `i_btn`. Para ello, el módulo almacena en `r_btn_prev` el estado anterior del pulsador.

La condición de captura es:

```text
i_btn = 1
i_btn anterior = 0
```

De esta forma, un pulsador mantenido presionado no provoca múltiples capturas. El valor queda almacenado hasta que se produzca una nueva captura o un reset.

El parámetro `WIDTH` permite reutilizar el módulo tanto para los operandos de 8 bits como para el código de operación de 6 bits.

**Figura 2 — Módulo `btn_reg`**

*[Insertar el esquemático RTL generado por Vivado del módulo `btn_reg` o un diagrama equivalente.]*

---

### 3.2. Módulo `alu`

La ALU recibe dos operandos de ancho parametrizable y un código de operación de 6 bits.

Sus salidas son:

- `o_result`: resultado de la operación.
- `o_overflow`: flag de overflow.
- `o_zero`: flag de resultado cero.

La lógica de selección de operaciones se implementa mediante una estructura `case`, por lo que la ALU funciona como lógica combinacional.

El ancho de datos se define mediante el parámetro `NB_DATA`, cuyo valor utilizado en el `top` es 8.

---

## 4. Operaciones implementadas

La ALU implementa las ocho operaciones requeridas mediante los siguientes códigos:

| Operación | Código | Descripción |
|---|---|---|
| `ADD` | `100000` | Suma de A y B |
| `SUB` | `100010` | Resta de A y B |
| `AND` | `100100` | AND bit a bit |
| `OR` | `100101` | OR bit a bit |
| `XOR` | `100110` | XOR bit a bit |
| `SRA` | `000011` | Desplazamiento aritmético a derecha |
| `SRL` | `000010` | Desplazamiento lógico a derecha |
| `NOR` | `100111` | NOR bit a bit |

### 4.1. Operaciones aritméticas

`ADD` realiza:

```text
A + B
```

mientras que `SUB` realiza:

```text
A - B
```

El resultado se mantiene en el ancho configurado de la ALU. Para una implementación de 8 bits, esto implica que los bits que exceden dicho ancho no forman parte de `o_result`.

### 4.2. Operaciones lógicas

Las operaciones `AND`, `OR`, `XOR` y `NOR` se realizan bit a bit sobre los dos operandos.

Por ejemplo:

```text
A = 10101010
B = 01010101

A AND B = 00000000
A OR  B = 11111111
A XOR B = 11111111
A NOR B = 00000000
```

### 4.3. Desplazamiento aritmético

`SRA` realiza un desplazamiento hacia la derecha conservando el signo del operando A. Para ello, A se interpreta explícitamente como un valor con signo mediante `$signed`.

La cantidad de desplazamiento se obtiene a partir de los bits bajos de B.

### 4.4. Desplazamiento lógico

`SRL` realiza un desplazamiento lógico hacia la derecha de A. En este caso se introducen ceros por la izquierda.

La cantidad de desplazamiento también se obtiene a partir de los bits bajos de B.

### 4.5. Operación por defecto

Si el código de operación no coincide con ninguna de las ocho operaciones definidas, la ALU genera:

```text
resultado = 0
overflow = 0
```

Como consecuencia, la flag `Zero` también queda activa.

---

## 5. Flags

### 5.1. Flag `Zero`

La flag `Zero` se genera comparando el resultado de la ALU con cero:

```text
o_zero = (o_result == 0)
```

Por lo tanto:

- `Zero = 1` cuando `o_result` es cero.
- `Zero = 0` cuando `o_result` es distinto de cero.

La flag se aplica a todas las operaciones, no solamente a `ADD` y `SUB`.

Por ejemplo:

```text
A = 0xAA
B = 0xAA
A XOR B = 0x00
Zero = 1
```

### 5.2. Flag `Overflow`

La flag `Overflow` se utiliza exclusivamente en las operaciones `ADD` y `SUB`.

Para una ALU de 8 bits con representación en complemento a dos, el rango de valores con signo es:

```text
-128 ≤ x ≤ 127
```

En `ADD`, se detecta overflow cuando:

- dos operandos positivos producen un resultado negativo; o
- dos operandos negativos producen un resultado positivo.

La condición implementada es equivalente a:

```text
(~signA & ~signB & signResult) |
( signA &  signB & ~signResult)
```

En `SUB`, se detecta overflow cuando:

- un operando positivo menos uno negativo produce un resultado negativo; o
- un operando negativo menos uno positivo produce un resultado positivo.

La condición implementada es equivalente a:

```text
(~signA & signB & signResult) |
( signA & ~signB & ~signResult)
```

Por ejemplo:

```text
0x7F + 0x01 = 0x80
```

El valor matemático es `128`, que no puede representarse en 8 bits con signo. Por lo tanto:

```text
resultado = 0x80
Overflow = 1
```

El diseño conserva el resultado de 8 bits producido por la operación; no implementa saturación.

### 5.3. Carry

No se implementa una flag `Carry` en este diseño. La condición de desbordamiento considerada para las operaciones aritméticas es específicamente `Overflow` en representación signed.

Esto diferencia el desbordamiento de complemento a dos (`Overflow`) del acarreo correspondiente a una interpretación unsigned (`Carry`).

---

## 6. Integración mediante `top`

El módulo `top` conecta los registros de entrada con la ALU.

Se utilizan tres instancias de `btn_reg`:

- Una instancia de ancho 8 para el operando A.
- Una instancia de ancho 8 para el operando B.
- Una instancia de ancho 6 para el código de operación.

Las conexiones son:

```text
sw[7:0] → registro A
sw[7:0] → registro B
sw[5:0] → registro OP
```


La ALU recibe los tres valores almacenados y genera continuamente el resultado y las flags.

Por tratarse de una ALU combinacional, el resultado se actualiza automáticamente cuando cambia cualquiera de sus entradas registradas.

**Figura 3 — Esquemático RTL de `top`**

*[Insertar el esquemático RTL generado por Vivado del módulo `top`.]*

---

## 7. Interfaz física con la Basys3

### 7.1. Switches

Aunque la entrada `sw` posee 16 bits, el diseño utiliza:

- `sw[7:0]` para los operandos.
- `sw[5:0]` para el código de operación.

Los switches `sw[15:8]` no intervienen en el funcionamiento del sistema.

### 7.2. Pulsadores

| Pulsador | Función |
|---|---|
| `btnU` | Capturar operando A |
| `btnD` | Capturar operando B |
| `btnC` | Capturar código de operación |
| `btnR` | Reset síncrono |

La captura se realiza sincronizada con el reloj de 100 MHz mediante detección del flanco ascendente del estado del botón.

### 7.3. LEDs

La salida de 16 bits se distribuye de la siguiente forma:

| LEDs | Función |
|---|---|
| `LED[7:0]` | Resultado de la ALU |
| `LED[13:8]` | Sin utilizar, forzados a cero |
| `LED[14]` | `Zero` |
| `LED[15]` | `Overflow` |

Por ejemplo, si el resultado es `0x08`, los ocho LEDs inferiores representan:

```text
00001000
```

Si se produce overflow con `0x7F + 0x01`, se obtiene:

```text
LED[15] = 1
LED[14] = 0
LED[7:0] = 10000000
```

---

## 8. Mapeo de pines

El archivo `Basys3_Master.xdc` establece la correspondencia entre las señales del módulo `top` y los pines físicos de la FPGA.

El reloj de 100 MHz está conectado al pin `W5`.

Los switches y LEDs utilizan las asignaciones estándar de la Basys3 incluidas en el archivo de constraints.

Los pulsadores utilizados por el diseño son:

| Señal | Pulsador | Pin |
|---|---|---|
| `btnC` | Center | `U18` |
| `btnU` | Up | `T18` |
| `btnD` | Down | `U17` |
| `btnR` | Right | `T17` |

La señal `btnL` permanece definida en el archivo maestro de constraints, pero no forma parte de las entradas del módulo `top` y no se utiliza en el diseño.

El archivo también contiene las asignaciones de los 16 switches y los 16 LEDs correspondientes a la Basys3.

---

## 9. Verificación mediante simulación

El proyecto contiene tres testbenches:

- `tb_alu.sv`
- `tb_btn_reg.sv`
- `tb_top.sv`

Las pruebas se ejecutan utilizando Icarus Verilog mediante el script `test.sh`.

### 9.1. Testbench de la ALU

`tb_alu.sv` verifica las ocho operaciones y las flags `Zero` y `Overflow`.

Se incluyen casos normales y casos límite.

Los casos de prueba abarcan:

- `ADD` normal.
- `ADD` con overflow positivo.
- `ADD` de dos valores negativos con overflow.
- `ADD` sin overflow con resultado cero.
- `SUB` normal.
- `SUB` con overflow.
- `SUB` con resultado cero.
- `AND` normal y con resultado cero.
- `OR` normal y con resultado cero.
- `XOR` normal y con resultado cero.
- `NOR` normal y con resultado cero.
- `SRL` con distintos desplazamientos.
- `SRA` con operandos positivos y negativos.
- Código de operación no definido.

El archivo contiene **23 casos de prueba efectivos**.

**Figura 4 — Resultado de la simulación de `tb_alu`**

*[Insertar captura de la consola mostrando los casos `PASS` y el resumen final de la simulación.]*

### 9.2. Testbench de `btn_reg`

`tb_btn_reg.sv` verifica:

1. Estado inicial después del reset.
2. Captura de un valor cuando se detecta el flanco ascendente del botón.
3. Ausencia de recaptura mientras el botón permanece presionado.
4. Funcionamiento de una segunda captura después de liberar y volver a presionar el botón.
5. Limpieza del registro mediante reset.

**Figura 5 — Resultado de la simulación de `tb_btn_reg`**

*[Insertar captura de la consola mostrando los casos `PASS` y el resumen final.]*

### 9.3. Testbench de integración

`tb_top.sv` verifica la interacción entre los registros, la ALU y los LEDs.

Los casos implementados son:

| Prueba | Funcionamiento verificado |
|---|---|
| Test 1 | `3 + 5 = 8` |
| Test 2 | `0x7F + 1`, detección de overflow |
| Test 3 | `5 - 5 = 0`, detección de Zero |
| Test 4 | Reset de los valores capturados |
| Test 5 | Captura solamente en el flanco ascendente |
| Test 6 | No recaptura mientras el botón permanece presionado |

**Figura 6 — Resultado de la simulación de `tb_top`**

*[Insertar captura de la consola mostrando las seis pruebas y el resumen final.]*

---

## 10. Script de automatización de pruebas

El archivo `test.sh` automatiza la compilación y ejecución de los tres testbenches.

Por defecto:

```bash
./test.sh
```

ejecuta:

```text
tb_alu
tb_btn_reg
tb_top
```

También es posible ejecutar individualmente:

```bash
./test.sh alu
./test.sh btn
./test.sh top
```

o ejecutar explícitamente todas las pruebas:

```bash
./test.sh all
```

El script utiliza:

```text
iverilog -g2012 -Wall
```

para compilar los módulos y posteriormente `vvp` para ejecutar las simulaciones.

Además, `set -e` hace que el script finalice ante un error de compilación o ejecución.

---

## 11. Síntesis e implementación en Vivado

El proyecto está preparado para ser sintetizado en Vivado utilizando como dispositivo objetivo el correspondiente a la Basys3:

```text
xc7a35tcpg236-1
```

El flujo de implementación previsto es:

1. Crear el proyecto de Vivado.
2. Seleccionar el dispositivo de la Basys3.
3. Agregar `alu.sv`.
4. Agregar `btn_reg.sv`.
5. Agregar `top.sv`.
6. Agregar `Basys3_Master.xdc`.
7. Establecer `top` como módulo superior.
8. Ejecutar síntesis.
9. Ejecutar implementación.
10. Generar el bitstream.
11. Programar la FPGA.

**Figura 7 — Proyecto en Vivado**

*[Insertar captura del proyecto con los módulos fuente y el archivo `.xdc`.]*

**Figura 8 — Síntesis**

*[Insertar captura del resultado de síntesis indicando que el proceso finalizó correctamente.]*

**Figura 9 — Implementación**

*[Insertar captura del resultado de implementación y, si se desea, del resumen de utilización de recursos.]*

---

## 12. Prueba sobre hardware

La prueba sobre hardware consiste en programar la Basys3 con el bitstream generado por Vivado y repetir las operaciones verificadas previamente mediante simulación.

Un ejemplo de prueba es:

### Caso: suma normal

```text
A = 3
B = 5
OP = ADD
```

Resultado esperado:

```text
Resultado = 8
Zero = 0
Overflow = 0
```

Otro caso representativo es:

### Caso: overflow

```text
A = 0x7F
B = 0x01
OP = ADD
```

Resultado esperado:

```text
Resultado = 0x80
Zero = 0
Overflow = 1
```

Finalmente:

### Caso: resultado cero

```text
A = 5
B = 5
OP = SUB
```

Resultado esperado:

```text
Resultado = 0x00
Zero = 1
Overflow = 0
```

**Figura 10 — Prueba física sobre la Basys3**

*[Insertar fotografía de la Basys3 funcionando. Conviene mostrar claramente la posición de los switches, el pulsador utilizado y los LEDs encendidos.]*

---

## 13. Decisiones de diseño

### 13.1. Parametrización del ancho de datos

La ALU y el registro `btn_reg` utilizan parámetros para definir su ancho.

El `top` utiliza:

```text
NB_DATA = 8
```

por lo que los operandos y el resultado son de 8 bits.

Esta parametrización permite reutilizar los módulos para otros anchos de datos sin modificar la estructura general.

### 13.2. Captura por flanco de botón

En lugar de utilizar directamente el pulsador como reloj, el diseño utiliza el reloj de 100 MHz de la FPGA y detecta el flanco ascendente del botón.

Esta decisión permite mantener un único reloj de sistema y hace que la captura ocurra únicamente cuando el botón cambia de estado de liberado a presionado.

El registro `r_btn_prev` almacena el estado anterior del botón para realizar esta detección.

### 13.3. Reset

El reset se implementa de forma síncrona. Cuando `btnR` está activo durante un flanco del reloj, los registros de operandos y operación se limpian.

La ALU es combinacional, por lo que al quedar los registros en cero, el resultado correspondiente también se actualiza.

### 13.4. Tratamiento del overflow

Se eligió detectar overflow signed en complemento a dos para `ADD` y `SUB`.

No se implementó saturación. Por lo tanto, el resultado mantiene los bits correspondientes a la operación de 8 bits y la flag `Overflow` informa que el valor matemático excedió el rango representable.

### 13.5. Ausencia de Carry

No se agregó una flag `Carry`, dado que las flags implementadas por este diseño son `Zero` y `Overflow`.

### 13.6. Código de operación

Los ocho códigos de operación se definen mediante `localparam`, evitando utilizar directamente valores numéricos dentro de cada decisión del `case`.

Esto mejora la legibilidad y permite relacionar cada operación con su código de manera explícita.

---

## 14. Estructura del proyecto

La organización final del proyecto es:

```text
TP1/
├── src/
│   ├── alu.sv
│   ├── btn_reg.sv
│   ├── top.sv
│   ├── tb_alu.sv
│   ├── tb_btn_reg.sv
│   └── tb_top.sv
├── constr/
│   └── Basys3_Master.xdc
├── test.sh
├── README.md
└── informe.md
```

Cada archivo cumple una función específica:

- `alu.sv`: implementación de la ALU.
- `btn_reg.sv`: registro parametrizable con captura por flanco del botón.
- `top.sv`: integración de todos los bloques.
- `tb_alu.sv`: verificación de la ALU.
- `tb_btn_reg.sv`: verificación del registro de captura.
- `tb_top.sv`: verificación de integración.
- `Basys3_Master.xdc`: asignación de señales a pines físicos.
- `test.sh`: automatización de las simulaciones.
- `README.md`: documentación técnica del proyecto.
- `informe.md`: informe correspondiente al trabajo práctico.

---

## 15. Conclusiones

La implementación permitió desarrollar una ALU parametrizable utilizando SystemVerilog y trasladar su funcionamiento a una FPGA Digilent Basys3.

La separación del diseño en módulos permite distinguir claramente la lógica combinacional de la lógica secuencial. La ALU se encarga exclusivamente de realizar las operaciones y generar las flags, mientras que los registros almacenan los operandos y el código de operación antes de enviarlos a la unidad de procesamiento.

La detección del flanco ascendente de los pulsadores permite utilizar los botones como mecanismo de captura sin convertirlos directamente en señales de reloj. De esta manera, los datos ingresados mediante los switches permanecen almacenados hasta una nueva captura o hasta realizar un reset.

La implementación de `Zero` y `Overflow` permite además incorporar información de estado a las operaciones, particularmente en los casos aritméticos donde el resultado puede exceder el rango representable con signo.

Finalmente, la inclusión de testbenches independientes y de un script de automatización permite estructurar la verificación en diferentes niveles, facilitando la detección de errores tanto en los módulos individuales como en la integración completa del sistema.
