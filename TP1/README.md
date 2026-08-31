# TP1 — ALU Simple con Flags en Basys3

Implementación de una ALU (Unidad Aritmético-Lógica) de 16 bits sobre la placa **Digilent Basys3** (FPGA Artix-7). Soporta 8 operaciones y señaliza los flags de **Overflow** y **Zero** en el display de 7 segmentos.

---

## Estructura del proyecto

```
TP1/
├── src/
│   ├── alu.sv        # Módulo ALU: operaciones + flags o_overflow y o_zero
│   ├── top.sv        # Módulo top: captura de entradas, instancia ALU, display 7-seg
│   ├── tb_alu.sv     # Testbench del módulo ALU (23 casos, autoverificado)
│   └── tb_top.sv     # Testbench de integración del top (11 casos, autoverificado)
└── constr/
    └── Basys3_Master.xdc  # Constraints de pines para la Basys3
```

---

## Operaciones soportadas

| Operación | Código (6 bits) | Descripción                             |
|-----------|----------------|-----------------------------------------|
| `ADD`     | `100000`       | Suma con signo: `A + B`                 |
| `SUB`     | `100010`       | Resta con signo: `A - B`               |
| `AND`     | `100100`       | AND bit a bit: `A & B`                 |
| `OR`      | `100101`       | OR bit a bit: `A \| B`                  |
| `XOR`     | `100110`       | XOR bit a bit: `A ^ B`                 |
| `SRA`     | `000011`       | Desplazamiento aritmético derecho: `A >>> B[4:0]` |
| `SRL`     | `000010`       | Desplazamiento lógico derecho: `A >> B[4:0]`      |
| `NOR`     | `100111`       | NOR bit a bit: `~(A \| B)`              |

> Los códigos de operación siguen la codificación del campo `funct` de MIPS-I.

---

## Flags

### Overflow (`o_overflow`)
Activo (1) únicamente para `ADD` y `SUB`, cuando el resultado no puede representarse correctamente en complemento a 2:

| Condición            | Operación | Ejemplo (16 bits)              |
|----------------------|-----------|--------------------------------|
| positivo + positivo = negativo | `ADD` | `0x7FFF + 0x0001 = 0x8000` |
| negativo + negativo = positivo | `ADD` | `0x8000 + 0x8000 = 0x0000` |
| positivo − negativo = negativo | `SUB` | `0x7FFF − 0xFFFF = 0x8000` |
| negativo − positivo = positivo | `SUB` | `0x8000 − 0x0001 = 0x7FFF` |

Para las operaciones lógicas y de desplazamiento, `o_overflow = 0` siempre.

### Zero (`o_zero`)
Activo (1) cuando el resultado es cero (`o_result == 0`). Aplica a todas las operaciones.

---

## Interfaz de usuario

### Switches (`sw[15:0]`)
Los 16 switches cargan el valor que se registrará al presionar el botón correspondiente.

### Botones

| Botón  | Función                                     |
|--------|---------------------------------------------|
| `btnU` | Captura `sw[15:0]` como **Operando A**      |
| `btnD` | Captura `sw[15:0]` como **Operando B**      |
| `btnC` | Captura `sw[5:0]`  como **Código de operación** |

La captura ocurre en el **flanco ascendente** del botón (detección de flanco de subida sincronizada con el reloj de 100 MHz).

### LEDs (`LED[15:0]`)
Muestran el resultado de la operación en binario.

### Display de 7 segmentos

```
  an[3]     an[2]     an[1]     an[0]
┌────────┬────────┬────────┬────────┐
│   o    │   0    │        │        │
│Overflow│  Zero  │  (off) │  (off) │
└────────┴────────┴────────┴────────┘
```

- **`an[3]` (dígito izquierdo)**: muestra la letra `o` cuando `o_overflow = 1`, apagado si no.
- **`an[2]`**: muestra el dígito `0` cuando `o_zero = 1`, apagado si no.
- **`an[1]`, `an[0]`**: siempre apagados.
- El punto decimal (`dp`) siempre está apagado.

El display utiliza multiplexado a ~381 Hz por dígito (contador de 18 bits dividiendo el clock de 100 MHz).

### Flujo de uso típico
1. Colocar los switches en el valor deseado para el **Operando A** y presionar `btnU`.
2. Colocar los switches en el valor deseado para el **Operando B** y presionar `btnD`.
3. Colocar los switches en el **código de operación** (en los 6 bits inferiores) y presionar `btnC`.
4. Leer el resultado en los **LEDs** y los flags en el **display**.

---

## Simulación

Se requiere [Icarus Verilog](http://iverilog.icarus.com/) (`iverilog` + `vvp`).

```bash
# Desde el directorio TP1/src/

# Testbench de la ALU (23 casos)
iverilog -g2005 -o tb_alu_sim tb_alu.sv alu.sv && vvp tb_alu_sim

# Testbench de integración del top (11 casos)
iverilog -g2005 -o tb_top_sim tb_top.sv top.sv alu.sv && vvp tb_top_sim
```

---

## Síntesis en Vivado

1. Crear un proyecto Vivado apuntando a la **Basys3** (`xc7a35tcpg236-1`).
2. Agregar los fuentes: `alu.sv` y `top.sv`.
3. Agregar el constraint: `Basys3_Master.xdc`.
4. Correr *Synthesis → Implementation → Generate Bitstream*.
5. Programar la placa con el `.bit` generado.
