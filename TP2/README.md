# TP2: Sistema UART-ALU

## Cliente TUI / CLI de Comunicación Serie (`alu_cli.py`)

El script `TP2/alu_cli.py` proporciona una aplicación interactiva de terminal (**TUI de ventana completa**) y una interfaz de línea de comandos (**CLI**) en Python para enviar operaciones a la Basys 3 por puerto serie (`8N1`, `9600` baudios por defecto), verificar automáticamente el resultado recibido frente al modelo de referencia local y visualizar el estado de los LEDs físicos de la placa.

### Requisitos

```bash
pip install pyserial
```

### 1. Ejecución de la Interfaz Interactiva (TUI Paso a Paso)

Para abrir el monitor interactivo en la ventana de la terminal conectados a la Basys 3 (o usando `--mock` para probar sin placa física):

```bash
# Conectando al puerto serie de la Basys 3 (auto-detecta /dev/ttyUSB1 por defecto)
python3 TP2/alu_cli.py -p /dev/ttyUSB1 --baud 9600

# En modo emulador local (sin hardware conectado)
python3 TP2/alu_cli.py --mock
```

**Controles dentro de la ventana TUI:**
- `ESPACIO` / `ENTER`: Ejecuta la instrucción actual (`▶`) del programa de demostración pregrabado y avanza al siguiente paso.
- `↑` / `↓`: Navega libremente por las instrucciones del programa para inspeccionarlas o re-ejecutarlas.
- `B`: Alterna entre **Paso por Instrucción Completa** (envía los 3 bytes juntos) y **Paso Byte a Byte** (`Byte 1: OpA` → `Byte 2: OpB` → `Byte 3: Opcode`), permitiendo observar la transición de estados de la FSM (`StWaitOpA` → `StWaitOpB` → `StWaitOpCode` → `StSendResult`).
- `I` o teclas `1`–`8`: Abre el cuadro de ingreso manual para enviar cualquier operación (`ADD`, `SUB`, `AND`, `OR`, `XOR`, `SRA`, `SRL`, `NOR`) con operandos en decimal (con/sin signo), hexadecimal (`0x..`) o binario (`0b..`).
- `A`: Ejecuta automáticamente la secuencia completa del programa de demostración.
- `R`: Reinicia el estado del programa de demostración al paso `#01`.
- `M`: Alterna entre el puerto serie físico y el emulador local (`MockSerial`).
- `Q` / `ESC`: Cierra la aplicación y restaura la terminal.

### 2. Ejemplo de Ejecución Directa por Línea de Comandos

También es posible enviar una operación puntual desde la terminal indicando el mnemónico (`--op`) y los operandos (`-a` y `-b`):

```bash
$ python3 TP2/alu_cli.py -p /dev/ttyUSB1 --op SRA -a -16 -b 2

==============================================================================
 OPERACIÓN UART-ALU: SRA — Shift aritmetico derecho (A >>> B[3:0])
==============================================================================
CAMPO                | SIN SIGNO | CON SIGNO (C2) | HEX    | BINARIO (BITS)
------------------------------------------------------------------------------
Byte 1: Operando A   | 240       | -16            | 0xF0   | 0b1111_0000
Byte 2: Operando B   | 2         | +2             | 0x02   | 0b0000_0010
Byte 3: Operación    | 3         | SRA            | 0x03   | 0b00_000011
------------------------------------------------------------------------------
Recibido (FPGA)      | 252       | -4             | 0xFC   | 0b1111_1100
Esperado (Local PC)  | 252       | -4             | 0xFC   | 0b1111_1100
------------------------------------------------------------------------------
 Verificación Automática : [PASS (Coincide)] (Tiempo: 3.1 ms)
 Banderas Esperadas      : Zero (LED[14]) = 0  |  Overflow (LED[15]) = 0
==============================================================================
 Mapa de LEDs en Basys 3:
   LED[15] (OVF)  : [○] (0)
   LED[14] (ZERO) : [○] (0)
   LED[13:8]      : [○] [○] [○] [○] [○] [○] (apagados)
   LED[7:0] (RES) : [●] [●] [●] [●] [●] [●] [○] [○]
                    LD7 LD6 LD5 LD4 LD3 LD2 LD1 LD0
```

