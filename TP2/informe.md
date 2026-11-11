<p align="center">
  <img src="./assets/Isologotipo_FCEFyN_y_UNC-original_Sin_fondo-Con_bajada.png" alt="Isologotipo de la Facultad de Ciencias Exactas, Físicas y Naturales y la Universidad Nacional de Córdoba" width="70%" />
</p>

# TP2 — Implementación de un Sistema UART-ALU sobre Basys 3

|              |                              |
|--------------|------------------------------|
| **Materia:** | Arquitectura de Computadoras |
| **Carrera:** | Ingeniería en Computación    |
| **Alumnos:** | García, Lautaro Misael       |
|              | Renaudo Gaggioli, Valentino  |
| **Fecha:**   | Noviembre, 2026              |

---

## Índice

1. [Objetivos](#1-objetivos)
2. [Descripción general del sistema](#2-descripción-general-del-sistema)
3. [Protocolo de comunicación serie UART](#3-protocolo-de-comunicación-serie-uart)
   - 3.1. [Estructura de la trama serie](#31-estructura-de-la-trama-serie)
   - 3.2. [Protocolo de aplicación para transacciones con la ALU](#32-protocolo-de-aplicación-para-transacciones-con-la-alu)
4. [Arquitectura de la implementación](#4-arquitectura-de-la-implementación)
   - 4.1. [Baud Rate Generator (`uart_brg`)](#41-baud-rate-generator-uart_brg)
   - 4.2. [Receptor UART (`uart_rx`)](#42-receptor-uart-uart_rx)
   - 4.3. [Transmisor UART (`uart_tx`)](#43-transmisor-uart-uart_tx)
   - 4.4. [Colas FIFO desacopladoras (`fifo`)](#44-colas-fifo-desacopladoras-fifo)
   - 4.5. [Circuito de interfaz (`uart_alu_interface`)](#45-circuito-de-interfaz-uart_alu_interface)
   - 4.6. [Subsistema de procesamiento (`alu_top` / `alu_ctrl` / `alu`)](#46-subsistema-de-procesamiento-alu_top--alu_ctrl--alu)
   - 4.7. [Módulo superior de integración (`top`)](#47-módulo-superior-de-integración-top)
5. [Disposición y mapeo de I/O](#5-disposición-y-mapeo-de-io)
   - 5.1. [Interfaz física con la Basys 3](#51-interfaz-física-con-la-basys-3)
   - 5.2. [Mapeo de pines y restricciones físicas](#52-mapeo-de-pines-y-restricciones-físicas)
6. [Herramienta de software en Python (`alu_cli.py`)](#6-herramienta-de-software-en-python-alu_clipy)
   - 6.1. [Interfaz interactiva de usuario (TUI de ventana completa)](#61-interfaz-interactiva-de-usuario-tui-de-ventana-completa)
   - 6.2. [Modo de ejecución directa por línea de comandos (CLI)](#62-modo-de-ejecución-directa-por-línea-de-comandos-cli)
   - 6.3. [Emulador local (`MockSerial`) y verificación cruzada](#63-emulador-local-mockserial-y-verificación-cruzada)
7. [Verificación mediante simulación](#7-verificación-mediante-simulación)
   - 7.1. [Simulación del receptor UART (`tb_uart_rx`)](#71-simulación-del-receptor-uart-tb_uart_rx)
   - 7.2. [Simulación del transmisor UART (`tb_uart_tx`)](#72-simulación-del-transmisor-uart-tb_uart_tx)
   - 7.3. [Simulación de loopback UART (`tb_uart_loopback`)](#73-simulación-de-loopback-uart-tb_uart_loopback)
   - 7.4. [Simulación de la interfaz UART-ALU (`tb_uart_alu_interface`)](#74-simulación-de-la-interfaz-uart-alu-tb_uart_alu_interface)
   - 7.5. [Simulación de integración de nivel superior (`tb_top`)](#75-simulación-de-integración-de-nivel-superior-tb_top)
   - 7.6. [Automatización de pruebas (`test.sh`)](#76-automatización-de-pruebas-testsh)
8. [Decisiones técnicas y de diseño](#8-decisiones-técnicas-y-de-diseño)
   - 8.1. [Estrategia de sobremuestreo a 16x y sincronización](#81-estrategia-de-sobremuestreo-a-16x-y-sincronización)
   - 8.2. [Desacoplamiento temporal mediante memorias FIFO circulares](#82-desacoplamiento-temporal-mediante-memorias-fifo-circulares)
   - 8.3. [Diseño de las FSMs y codificación de estados](#83-diseño-de-las-fsms-y-codificación-de-estados)
   - 8.4. [Preservación de compatibilidad con Verilog-2001](#84-preservación-de-compatibilidad-con-verilog-2001)
   - 8.5. [Modelo de referencia dual y validación en host](#85-modelo-de-referencia-dual-y-validación-en-host)
9. [Ensayos experimentales sobre hardware](#9-ensayos-experimentales-sobre-hardware)
10. [Conclusiones](#10-conclusiones)

---

## 1. Objetivos

El objetivo de este trabajo es diseñar e implementar en Verilog un transceptor serie asíncrono **UART** (*Universal Asynchronous Receiver-Transmitter*) junto con su circuito de interfaz y máquina de estados de control para operar de forma remota la ALU de 8 bits desarrollada en el TP1 sobre la placa FPGA Digilent Basys 3. Adicionalmente, se busca desarrollar una herramienta de software en Python (con interfaz TUI y CLI) que permita enviar operaciones desde una PC, recibir el resultado por puerto serie y validar automáticamente el comportamiento del hardware.

---

## 2. Descripción general del sistema

El sistema reemplaza la carga manual por switches y pulsadores del TP1 por un enlace serie full-duplex a través del puente USB-RS232 integrado en la Basys 3. La arquitectura se divide en cinco bloques principales dentro de la FPGA:

1. **Generador de tasa de baudios (`uart_brg`):** divide el reloj de 100 MHz para generar pulsos de muestreo a 16 veces la frecuencia de baudios (`s_tick`).
2. **Receptor y transmisor UART (`uart_rx` y `uart_tx`):** deserializan los bytes entrantes desde la línea `RsRx` y serializan las respuestas hacia `RsTx`.
3. **Circuito de interfaz (`uart_alu_interface`):** incorpora dos colas FIFO (`u_fifo_rx` y `u_fifo_tx`) para desacoplar la velocidad del enlace serie respecto de la lógica de procesamiento.
4. **Controlador de protocolo (`alu_ctrl`):** máquina de estados que extrae secuencialmente el operando A, el operando B y el código de operación desde la FIFO de recepción, y deposita el resultado en la FIFO de transmisión.
5. **Núcleo aritmético-lógico (`alu`):** bloque combinacional de 8 bits que calcula el resultado y actualiza las banderas `Zero` y `Overflow`.

**Figura 1 — Diagrama en bloques general del sistema UART-ALU**

<p align="center">
  <img src="./assets/diag-bloques-sistema.png" alt="Diagrama en bloques general del sistema completo UART-ALU" width="80%" />
</p>

---

## 3. Protocolo de comunicación serie UART

### 3.1. Estructura de la trama serie

La comunicación física emplea el formato estándar **8N1** a una velocidad por defecto de **9600 baudios**:

- **Estado de reposo (*Idle*):** nivel lógico alto (`1`).
- **Bit de inicio (*Start*):** transición a nivel bajo (`0`) durante 1 período de bit.
- **Bits de datos (`NB_DATA = 8`):** 8 bits transmitidos comenzando por el bit menos significativo (*LSB first*).
- **Paridad:** sin bit de paridad (*None*).
- **Bit de parada (*Stop*, `NB_STOP = 1`):** nivel lógico alto (`1`) durante 1 período de bit.

**Figura 2 — Estructura temporal de la trama UART (8N1)**

<p align="center">
  <img src="./assets/uart-frame-8n1.png" alt="Estructura temporal de la trama serie UART 8N1" width="75%" />
</p>

### 3.2. Protocolo de aplicación para transacciones con la ALU

Cada operación se compone del envío secuencial de **3 bytes** desde la PC hacia la FPGA, seguido de **1 byte** de respuesta desde la FPGA hacia la PC:

1. **Byte 1 — Operando A:** valor de 8 bits (`i_operand_a`).
2. **Byte 2 — Operando B:** valor de 8 bits (`i_operand_b`).
3. **Byte 3 — Código de operación:** se toman los 6 bits menos significativos (`i_operation[5:0]`).
4. **Respuesta — Resultado:** una vez recibido el tercer byte, la FPGA transmite de regreso 1 byte con el resultado calculado (`o_result`) y retiene tanto el resultado como las banderas en los LEDs de la placa.

Los códigos de operación implementados mantienen la codificación de la ALU del TP1:

| Operación | Mnemónico | Código binario (`[5:0]`) | Hexadecimal | Descripción |
| :--- | :---: | :---: | :---: | :--- |
| Suma | `ADD` | `100000` | `0x20` | `A + B` (con detección de overflow en C2) |
| Resta | `SUB` | `100010` | `0x22` | `A - B` (con detección de overflow en C2) |
| AND lógico | `AND` | `100100` | `0x24` | `A & B` |
| OR lógico | `OR` | `100101` | `0x25` | `A \| B` |
| XOR lógico | `XOR` | `100110` | `0x26` | `A ^ B` |
| Shift aritmético der. | `SRA` | `000011` | `0x03` | `$signed(A) >>> B[3:0]` |
| Shift lógico der. | `SRL` | `000010` | `0x02` | `A >> B[3:0]` |
| NOR lógico | `NOR` | `100111` | `0x27` | `~(A \| B)` |

---

## 4. Arquitectura de la implementación

### 4.1. Baud Rate Generator (`uart_brg`)

El módulo `uart_brg` implementa un contador módulo `COUNT_LIMIT` que genera un pulso de habilitación (`rate` / `s_tick`) de un ciclo de reloj de duración a una frecuencia 16 veces superior a la tasa de baudios configurada. Para el reloj del sistema de $100\text{ MHz}$ y $9600\text{ baudios}$:

$$
\text{TICK\_CYCLES} = \left\lfloor \frac{100\,000\,000}{9600 \times 16} \right\rfloor = 651 \implies \text{COUNT\_LIMIT} = 650
$$

Esto produce una tasa efectiva de $\approx 9600{,}61\text{ bps}$ (error relativo del $0{,}006\%$, despreciable frente a la tolerancia de $\pm 2\%$ del protocolo UART).

**Figura 3 — Esquemático RTL del Baud Rate Generator (`uart_brg`)**

<p align="center">
  <img src="./assets/rtl-uart-brg.png" alt="Esquemático RTL del módulo uart_brg" width="65%" />
</p>

### 4.2. Receptor UART (`uart_rx`)

El módulo `uart_rx` recibe la línea serie asíncrona `i_rx` y reconstruye los bytes entrantes. En su etapa de entrada cuenta con un **sincronizador de doble flip-flop** (`rx_sync1_q` y `rx_sync2_q`) inicializado en alto para evitar problemas de metaestabilidad al cruzar al dominio de reloj de 100 MHz.

Su máquina de estados posee cuatro estados codificados en *One-Hot*:

- `StIdle` (`4'b0001`): aguarda un flanco de bajada (`rx_sync == 0`) y reinicia el contador de ticks.
- `StStart` (`4'b0010`): cuenta hasta `tick_counter_q == 7` (punto medio del bit de inicio). Allí verifica que `rx_sync` continúe en `0` para descartar pulsos de ruido espurios (*glitches*); si es válido, pasa a `StData`.
- `StData` (`4'b0100`): cada 16 ticks (`tick_counter_q == 15`), muestrea el centro de cada bit de datos y lo desplaza desde el MSB hacia el LSB en `data_q` (`{rx_sync, data_q[7:1]}`). Tras 8 bits, avanza a `StStop`.
- `StStop` (`4'b1000`): espera los 16 ticks del bit de parada, emite un pulso de un ciclo en `o_rx_done` y retorna a `StIdle`.

**Figura 4 — Diagrama de estados (FSM) del receptor UART (`uart_rx`)**

<p align="center">
  <img src="./assets/fsm-uart-rx.png" alt="Diagrama de estados de la FSM del módulo uart_rx" width="70%" />
</p>

**Figura 5 — Esquemático RTL del receptor UART (`uart_rx`)**

<p align="center">
  <img src="./assets/rtl-uart-rx.png" alt="Esquemático RTL del módulo uart_rx" width="70%" />
</p>

### 4.3. Transmisor UART (`uart_tx`)

El módulo `uart_tx` toma un byte paralelo en `i_d_in` cuando recibe el pulso `i_tx_start` y lo serializa por la línea `o_tx`. Su FSM también utiliza cuatro estados en codificación *One-Hot*:

- `StIdle` (`4'b0001`): mantiene `o_tx = 1`. Al activarse `i_tx_start`, captura `i_d_in` en `data_q` y pasa a `StStart`.
- `StStart` (`4'b0010`): coloca `o_tx = 0` durante 16 ticks (`tick_counter_q == 15`).
- `StData` (`4'b0100`): expone `data_q[0]` en la salida y desplaza el registro a la derecha cada 16 ticks hasta completar los 8 bits.
- `StStop` (`4'b1000`): restablece `o_tx = 1` durante 16 ticks, activa el pulso `o_tx_done` por un ciclo de reloj y regresa a `StIdle`.

**Figura 6 — Diagrama de estados (FSM) del transmisor UART (`uart_tx`)**

<p align="center">
  <img src="./assets/fsm-uart-tx.png" alt="Diagrama de estados de la FSM del módulo uart_tx" width="70%" />
</p>

**Figura 7 — Esquemático RTL del transmisor UART (`uart_tx`)**

<p align="center">
  <img src="./assets/rtl-uart-tx.png" alt="Esquemático RTL del módulo uart_tx" width="70%" />
</p>

### 4.4. Colas FIFO desacopladoras (`fifo`)

El módulo `fifo` implementa una memoria circular síncrona parametrizable (`NB_DATA = 8`, `FIFO_DEPTH = 8`) con arquitectura de lectura **FWFT** (*First-Word Fall-Through*):

- El dato apuntado por el puntero de lectura (`mem[rd_ptr_q]`) está permanentemente expuesto en `o_r_data` siempre que `o_empty` sea `0`.
- El pulso `i_rd` confirma el consumo del dato actual e incrementa `rd_ptr_q`, lo que permite a las máquinas consumidoras capturar el dato y avanzar el puntero en el mismo ciclo de reloj sin penalidad de latencia.
- Un contador de ocupación (`count_q`) gestiona las señales `o_empty` (`count_q == 0`) y `o_full` (`count_q == FIFO_DEPTH`), soportando operaciones de lectura y escritura simultáneas (`{i_wr, i_rd} == 2'b11`).

**Figura 8 — Esquemático RTL de la memoria FIFO circular (`fifo`)**

<p align="center">
  <img src="./assets/rtl-fifo.png" alt="Esquemático RTL del módulo fifo" width="65%" />
</p>

### 4.5. Circuito de interfaz (`uart_alu_interface`)

Este módulo conecta los bloques `uart_rx` y `uart_tx` con el subsistema de la ALU mediante dos instancias del módulo `fifo`:

- **Lado recepción (`u_fifo_rx`):** cada pulso `i_rx_done` escribe directamente `i_rx_data` en la FIFO de recepción. Hacia la ALU expone la interfaz estándar `o_r_data`, `o_rx_empty` e `i_rd`.
- **Lado transmisión (`u_fifo_tx` + FSM serializadora):** la ALU deposita resultados mediante `i_w_data` e `i_wr`. Una FSM interna de dos estados (`StTxIdle` y `StTxWait`) monitorea `tx_fifo_empty`: en cuanto detecta un byte pendiente, lo extrae (`tx_fifo_rd = 1`), dispara `o_tx_start` hacia `uart_tx` y aguarda en `StTxWait` hasta recibir la confirmación `i_tx_done`.

**Figura 9 — Esquemático RTL del circuito de interfaz (`uart_alu_interface`)**

<p align="center">
  <img src="./assets/rtl-uart-alu-interface.png" alt="Esquemático RTL del módulo uart_alu_interface" width="75%" />
</p>

### 4.6. Subsistema de procesamiento (`alu_top` / `alu_ctrl` / `alu`)

El módulo `alu_top` encapsula al controlador `alu_ctrl` y al núcleo combinacional `alu`:

- **`alu_ctrl`:** implementa una FSM *One-Hot* de cuatro estados que ejecuta el protocolo de 3 bytes:
  1. `StWaitOpA` (`4'b0001`): si `!i_rx_empty`, emite `o_rd = 1`, almacena el byte en `operand_a_q` y pasa a `StWaitOpB`.
  2. `StWaitOpB` (`4'b0010`): al llegar el segundo byte (`!i_rx_empty`), emite `o_rd = 1`, lo guarda en `operand_b_q` y transita a `StWaitOpCode`.
  3. `StWaitOpCode` (`4'b0100`): al recibir el tercer byte, captura los 6 bits inferiores en `operation_q` y avanza a `StSendResult`.
  4. `StSendResult` (`4'b1000`): con los tres registros cargados, el resultado combinacional `i_alu_result` ya es válido. Si `!i_tx_full`, escribe `o_w_data = i_alu_result` con `o_wr = 1` y regresa a `StWaitOpA`.
- **`alu`:** realiza de forma combinacional las 8 operaciones sobre `o_operand_a` y `o_operand_b`, generando `o_result`, `o_zero` y `o_overflow`.

**Figura 10 — Diagrama de estados de la FSM de control (`alu_ctrl`)**

<p align="center">
  <img src="./assets/fsm-alu-ctrl.png" alt="Diagrama de estados de la máquina de estados alu_ctrl" width="70%" />
</p>

**Figura 11 — Esquemático RTL del subsistema `alu_top`**

<p align="center">
  <img src="./assets/rtl-alu-top.png" alt="Esquemático RTL del módulo alu_top" width="75%" />
</p>

### 4.7. Módulo superior de integración (`top`)

El módulo `top` instancia e interconecta estructuralmente `uart_brg`, `uart_rx`, `uart_tx`, `uart_alu_interface` y `alu_top`, vinculando sus entradas/salidas a los pines de la Basys 3. Como los registros `operand_a_q`, `operand_b_q` y `operation_q` dentro de `alu_ctrl` conservan su valor hasta que ingresa una nueva operación, las salidas hacia `LED[15:0]` permanecen estables para su inspección visual.

**Figura 12 — Esquemático RTL del módulo superior `top`**

<p align="center">
  <img src="./assets/rtl-top.png" alt="Esquemático RTL del módulo top integrado" width="80%" />
</p>

---

## 5. Disposición y mapeo de I/O

### 5.1. Interfaz física con la Basys 3

A diferencia del TP1, no se utilizan los switches para el ingreso de datos; toda la carga se realiza por el puerto USB-UART. Los recursos físicos utilizados en la placa son:

- **Reloj del sistema (`CLK100MHZ`):** oscilador interno de 100 MHz.
- **Reset (`btnR`):** pulsador derecho configurado como reset síncrono activo en alto; limpia las FIFOs, reinicia las máquinas de estado a reposo y pone en cero los registros de la ALU.
- **Enlace serie (`RsRx` / `RsTx`):** líneas conectadas al puente FTDI FT2232HQ de la Basys 3.
- **Visualización en LEDs (`LED[15:0]`):** mantiene exactamente la misma disposición que el TP1:
  - `LED[7:0]`: último resultado calculado por la ALU (`w_data`).
  - `LED[13:8]`: forzados a `0` (apagados).
  - `LED[14]`: bandera `Zero` (`1` si el resultado es `0x00`).
  - `LED[15]`: bandera `Overflow` (`1` ante desbordamiento con signo en `ADD` o `SUB`).

### 5.2. Mapeo de pines y restricciones físicas

El archivo `TP2/constr/Basys3_Master.xdc` define las restricciones de pines con estándar `LVCMOS33`:

| Señal en `top` | Pin FPGA (Artix-7) | Periférico en Basys 3 | Dirección | Descripción |
| :--- | :---: | :--- | :---: | :--- |
| `CLK100MHZ` | `W5` | Oscillator 100 MHz | Input | Reloj principal (período 10 ns) |
| `btnR` | `T17` | Pushbutton Right (`BTNR`) | Input | Reset síncrono general |
| `RsRx` | `B18` | USB-RS232 (`UART_TXD_IN`) | Input | Recepción serie (PC $\to$ FPGA) |
| `RsTx` | `A18` | USB-RS232 (`UART_RXD_OUT`) | Output | Transmisión serie (FPGA $\to$ PC) |
| `LED[7:0]` | `V14, U14, U15, W18, V19, U19, E19, U16` | `LD7` – `LD0` | Output | Resultado de 8 bits de la ALU |
| `LED[13:8]` | `N3, P3, U3, W3, V3, V13` | `LD13` – `LD8` | Output | Sin uso (permanecen en `0`) |
| `LED[14]` | `P1` | `LD14` | Output | Flag `Zero` |
| `LED[15]` | `L1` | `LD15` | Output | Flag `Overflow` |

---

## 6. Herramienta de software en Python (`alu_cli.py`)

Para interactuar con la FPGA se desarrolló el script `TP2/alu_cli.py`, basado en `pyserial` y `curses`, que opera tanto en modo gráfico de terminal (**TUI**) como por línea de comandos (**CLI**).

### 6.1. Interfaz interactiva de usuario (TUI de ventana completa)

Al ejecutar `python3 TP2/alu_cli.py -p /dev/ttyUSB1` (o `--mock` sin hardware), se despliega una interfaz dividida en paneles que permite:

- **Ejecución de programa de prueba paso a paso (`ESPACIO` / `ENTER`):** recorre una batería predefinida de casos de prueba que cubren las 8 operaciones y casos borde de `Zero` y `Overflow`.
- **Modo de avance por Instrucción vs. Byte a Byte (`B`):** permite alternar entre enviar el paquete de 3 bytes de una sola vez o enviar un único byte por pulsación (`Byte 1: OpA` $\to$ `Byte 2: OpB` $\to$ `Byte 3: Opcode`), mostrando en pantalla en qué estado exacto (`StWaitOpA`, `StWaitOpB`, `StWaitOpCode`, `StSendResult`) se encuentra la FSM `alu_ctrl` de la FPGA.
- **Ingreso manual de operaciones (`I` o teclas `1`–`8`):** abre una ventana modal para elegir la operación e ingresar operandos en formato decimal con/sin signo, hexadecimal (`0x..`) o binario (`0b..`).
- **Representación en vivo de LEDs y telemetría:** grafica el estado de `LD15` a `LD0` tal como se ven en la placa física, junto con el desglose binario, hexadecimal y en complemento a dos de los bytes transmitidos y recibidos.

**Figura 13 — Captura de pantalla de la interfaz interactiva TUI (`alu_cli.py`) en terminal**

<p align="center">
  <img src="./assets/tui-main-interface.png" alt="Captura de pantalla de la interfaz TUI en modo interactivo" width="80%" />
</p>

**Figura 14 — Cuadro de diálogo interactivo para ingreso manual de operaciones en la TUI**

<p align="center">
  <img src="./assets/tui-manual-input.png" alt="Cuadro modal para el ingreso manual de operandos y códigos de operación" width="80%" />
</p>

### 6.2. Modo de ejecución directa por línea de comandos (CLI)

El script también admite la ejecución puntual desde consola pasando la operación y los operandos por argumentos (`--op`, `-a`, `-b`). Por ejemplo:

```bash
python3 TP2/alu_cli.py -p /dev/ttyUSB1 --op SRA -a -16 -b 2
```

En este modo envía los 3 bytes, mide el tiempo de respuesta de ida y vuelta, imprime una tabla comparativa entre el byte recibido desde la FPGA y el valor esperado localmente (`[PASS]` / `[FAIL]`), y dibuja el mapa de LEDs resultante.

**Figura 15 — Captura de la ejecución por línea de comandos (CLI puntual con verificación)**

<p align="center">
  <img src="./assets/cli-operation-output.png" alt="Salida formateada por consola de una operación ejecutada por CLI" width="75%" />
</p>

### 6.3. Emulador local (`MockSerial`) y verificación cruzada

El script incluye una clase `MockSerial` que emula en software la máquina de estados `alu_ctrl` y la ALU de 8 bits cuando se invoca con `--mock` (o al presionar `M` en la TUI). Además, en todas las transacciones con la FPGA real, el modelo de referencia en Python calcula en paralelo el resultado y las banderas `Zero`/`Overflow` para contrastar automáticamente cada respuesta recibida por puerto serie.

---

## 7. Verificación mediante simulación

El diseño cuenta con cinco bancos de prueba (*testbenches*) auto-verificables en `TP2/src/`, compilados y ejecutados con **Icarus Verilog** (`iverilog -g2001`).

### 7.1. Simulación del receptor UART (`tb_uart_rx`)

Inyecta tramas serie sobre `i_rx` verificando la correcta recepción de patrones de borde (`0x00`, `0xFF`, `0x55`, `0xA5`), la recepción de bytes consecutivos y el rechazo efectivo de pulsos de ruido espurios (*glitches* menores a medio período de bit) durante el bit de inicio.

**Figura 16 — Forma de onda / Salida de consola de la simulación de `tb_uart_rx`**

<p align="center">
  <img src="./assets/tb-uart-rx.png" alt="Consola / Forma de onda de simulación tb_uart_rx" width="75%" />
</p>

### 7.2. Simulación del transmisor UART (`tb_uart_tx`)

Dispara transmisiones con `i_tx_start` y muestrea la salida `o_tx` en cada período de bit para comprobar el bit de *start*, el orden *LSB first* de los 8 bits de datos, el bit de *stop* y la generación del pulso `o_tx_done`.

**Figura 17 — Forma de onda / Salida de consola de la simulación de `tb_uart_tx`**

<p align="center">
  <img src="./assets/tb-uart-tx.png" alt="Consola / Forma de onda de simulación tb_uart_tx" width="75%" />
</p>

### 7.3. Simulación de loopback UART (`tb_uart_loopback`)

Conecta `uart_brg`, `uart_tx` y `uart_rx` en lazo cerrado (`o_tx` unido a `i_rx`) para validar que ambos módulos operen sincronizados a partir del mismo pulso `s_tick` y reconstruyan secuencias de bytes sin errores de trama.

**Figura 18 — Forma de onda / Salida de consola de la simulación de loopback**

<p align="center">
  <img src="./assets/tb-uart-loopback.png" alt="Consola / Forma de onda de simulación tb_uart_loopback" width="75%" />
</p>

### 7.4. Simulación de la interfaz UART-ALU (`tb_uart_alu_interface`)

Verifica la interacción entre `uart_alu_interface` y `alu_top`, comprobando las 8 operaciones de la ALU, las banderas `o_zero` y `o_overflow`, el *handshake* `o_tx_start`/`i_tx_done`, el encolado en ráfaga sobre las FIFOs y la recuperación tras un reset.

**Figura 19 — Forma de onda / Salida de consola de la simulación de `tb_uart_alu_interface`**

<p align="center">
  <img src="./assets/tb-uart-alu-interface.png" alt="Consola / Forma de onda de simulación tb_uart_alu_interface" width="75%" />
</p>

### 7.5. Simulación de integración de nivel superior (`tb_top`)

Evalúa el módulo `top` completo desde los pines `RsRx`, `RsTx`, `btnR` y `LED[15:0]`. Emula a la PC transmitiendo paquetes de 3 tramas UART completas para probar operaciones aritméticas (incluyendo casos de `Zero` en `0x20 - 0x20` y `Overflow` en `0x7F + 0x01` y `0x80 - 0x01`), lógicas, de desplazamiento, envíos *back-to-back* sin pausa y reset a mitad de una transacción.

**Figura 20 — Forma de onda / Salida de consola de la simulación de integración `tb_top`**

<p align="center">
  <img src="./assets/tb-top.png" alt="Consola / Forma de onda de simulación tb_top" width="75%" />
</p>

### 7.6. Automatización de pruebas (`test.sh`)

El script `TP2/test.sh` permite ejecutar de forma individual o conjunta (`./TP2/test.sh all`) todas las suites de simulación con las banderas `-g2001 -Wall`, deteniendo la ejecución si algún caso arroja error.

**Figura 21 — Ejecución del script automatizado de pruebas `test.sh`**

<p align="center">
  <img src="./assets/test-sh-output.png" alt="Ejecución completa del conjunto de testbenches mediante test.sh" width="75%" />
</p>

---

## 8. Decisiones técnicas y de diseño

### 8.1. Estrategia de sobremuestreo a 16x y sincronización

Se adoptó una tasa de sobremuestreo de 16 ticks por bit para que `uart_rx` pueda detectar el flanco de bajada del bit de *start*, contar 7 ticks hasta su centro (descartando pulsos de ruido breves si la línea vuelve a alto) y luego muestrear cada bit de datos cada 16 ticks en el centro del ojo de la señal. Además, el doble flip-flop en `i_rx` protege a la FSM contra violaciones de *setup/hold* provenientes del dominio asíncrono externo.

### 8.2. Desacoplamiento temporal mediante memorias FIFO circulares

El diseño de `fifo` con salida *First-Word Fall-Through* (FWFT) y profundidad de 8 bytes independiza por completo la velocidad de recepción serie respecto del consumo en `alu_ctrl`. Gracias a ello, la PC puede transmitir múltiples paquetes en ráfaga (*back-to-back*) sin perder bytes mientras el transmisor serie evacúa los resultados previos.

### 8.3. Diseño de las FSMs y codificación de estados

Todas las máquinas de estado (`uart_rx`, `uart_tx`, `uart_alu_interface` y `alu_ctrl`) se estructuraron separando la lógica secuencial de estado (`_q`) de la lógica combinacional de próximo estado (`_d`), empleando codificación **One-Hot** (adecuada para arquitecturas FPGA ricas en flip-flops) y cláusulas `default` de recuperación hacia el estado inicial ante cualquier estado inválido.

### 8.4. Preservación de compatibilidad con Verilog-2001

Todos los módulos fueron escritos respetando estrictamente el estándar **IEEE 1364-2001 (Verilog-2001)**, utilizando bloques `always @(posedge i_clock)` y `always @(*)`, tipos `reg`/`wire` explícitos y funciones estándar como `$clog2`, lo que garantiza síntesis directa en Xilinx Vivado y simulación limpia en Icarus Verilog con `-g2001`.

### 8.5. Modelo de referencia dual y validación en host

Dado que la trama de retorno por UART consta de 1 byte (los 8 bits del resultado), las banderas `Zero` y `Overflow` se exponen físicamente en `LED[14]` y `LED[15]`, mientras que `alu_cli.py` calcula su valor esperado mediante el modelo de referencia local. De esta manera se mantiene intacto el protocolo de 3 bytes de entrada por 1 byte de salida y a la vez se cuenta con validación automática en la PC.

---

## 9. Ensayos experimentales sobre hardware

Una vez superadas las simulaciones, el diseño fue sintetizado e implementado en **Xilinx Vivado** aplicando las restricciones de `Basys3_Master.xdc` y programado sobre la placa **Digilent Basys 3**. Conectando la placa por USB y ejecutando `alu_cli.py`, se verificó en hardware tanto la secuencia automática de pruebas como el envío manual byte a byte y la correspondencia exacta de los LEDs (`LD15`–`LD0`) con el panel de la TUI.

**Figura 22 — Conexión física de la placa Digilent Basys 3 al puesto de trabajo**

<p align="center">
  <img src="./assets/foto-basys3-setup.png" alt="Fotografía del montaje experimental de la Basys 3 conectada por USB" width="75%" />
</p>

**Figura 23 — Verificación de operación en hardware con visualización de LEDs**

<p align="center">
  <img src="./assets/foto-basys3-leds.png" alt="Fotografía en primer plano de los LEDs de la Basys 3 indicando resultado y flags" width="75%" />
</p>

---

## 10. Conclusiones

La implementación desarrollada permitió integrar un subsistema de comunicación serie UART completo con la ALU de 8 bits sobre la FPGA Basys 3. La división modular entre generador de baudios, transceptor serie (`uart_rx`/`uart_tx`), interfaz con colas FIFO FWFT (`uart_alu_interface`) y controlador de protocolo (`alu_ctrl`) facilitó tanto el diseño como la verificación escalonada mediante *testbenches* unitarios y de sistema completo.

Por último, el desarrollo de la herramienta `alu_cli.py` con modos TUI y CLI resultó clave durante las pruebas en placa, ya que permitió inspeccionar el avance de la máquina de estados byte a byte, contrastar automáticamente cada resultado recibido contra un modelo de referencia y visualizar en tiempo real el estado de los LEDs y banderas de la ALU.
