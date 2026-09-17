# TP1 — ALU Simple con Flags en Basys3

Implementación de una ALU (Unidad Aritmético-Lógica) de 8 bits sobre la placa **Digilent Basys3**. Soporta 8 operaciones, marca los flags de **Overflow** y **Zero** y trabaja con captura por flanco de botón y reset activo en el botón derecho.

---

## Estructura del proyecto

```
TP1/
├── src/
│   ├── alu.sv        # Módulo ALU: operaciones y flags
│   ├── btn_reg.sv    # Registro de captura por flanco de botón
│   ├── top.sv        # Integración del sistema y conexión con la Basys3
│   ├── tb_alu.sv     # Testbench de la ALU
│   ├── tb_top.sv     # Testbench de integración
│   └── tb_btn_reg.sv # Testbench de btn_reg
├── constr/
│   └── Basys3_Master.xdc # Constraints de pines para la Basys3
├── assets/           # Imágenes utilizadas en el informe
├── informe.md        # Informe completo del trabajo práctico
├── test.sh           # Script de ejecución de los testbench
└── README.md         # Documentación resumida del proyecto
```

---

## Operaciones soportadas

| Operación | Código (6 bits) | Descripción                             |
|-----------|----------------|-----------------------------------------|
| `ADD`     | `100000`       | Suma con signo: `A + B`                 |
| `SUB`     | `100010`       | Resta con signo: `A - B`               |
| `AND`     | `100100`       | AND bit a bit: `A & B`                 |
| `OR`      | `100101`       | OR bit a bit: `A \| B`                 |
| `XOR`     | `100110`       | XOR bit a bit: `A ^ B`                 |
| `SRA`     | `000011`       | Desplazamiento aritmético derecho: `A >>> B[$clog2(NB_DATA):0]` |
| `SRL`     | `000010`       | Desplazamiento lógico derecho: `A >> B[$clog2(NB_DATA):0]`      |
| `NOR`     | `100111`       | NOR bit a bit: `~(A \| B)`             |

---

## Flags

### Overflow (`o_overflow`)
Se activa en `ADD` y `SUB` cuando el resultado matemático excede el rango representable en complemento a dos para el ancho configurado.

Ejemplos:
- `0x7F + 0x01 = 0x80` → overflow activo
- `0x80 - 0x01 = 0x7F` → overflow activo

### Zero (`o_zero`)
Se activa cuando el resultado de la operación es cero.

---

## Interfaz de usuario

### Switches (`sw[15:0]`)
Los switches cargan el valor en la entrada `sw`, pero solo los 8 bits inferiores se usan como dato del operando o del código de operación.

### Botones

| Botón  | Función                                     |
|--------|---------------------------------------------|
| `btnU` | Captura `sw[7:0]` como Operando A           |
| `btnD` | Captura `sw[7:0]` como Operando B           |
| `btnC` | Captura `sw[5:0]` como código de operación  |
| `btnR` | Reset síncrono del sistema                 |

La captura ocurre en el flanco ascendente del botón y se mantiene estable mientras el botón permanece presionado.

### LEDs (`LED[15:0]`)
La distribución es la siguiente:
- `LED[7:0]` = resultado de la ALU
- `LED[13:8]` = apagados
- `LED[14]` = flag de `Zero`
- `LED[15]` = flag de `Overflow`

---

## Flujo de uso típico
1. Colocar los switches en el valor deseado para el Operando A y presionar `btnU`.
2. Colocar el valor del Operando B y presionar `btnD`.
3. Colocar el código de operación en los 6 bits inferiores de `sw` y presionar `btnC`.
4. Observar el resultado en `LED[7:0]` y los flags en `LED[14]` y `LED[15]`.
5. Usar `btnR` para limpiar los registros y dejar el sistema en cero.

---

## Simulación

Se requiere [Icarus Verilog](http://iverilog.icarus.com/) (`iverilog` + `vvp`).

El script `test.sh` permite compilar y ejecutar los testbench de forma individual o todos en conjunto. Debe ejecutarse desde el directorio raíz de `TP1/`:

```bash
./test.sh
```

Por defecto, se ejecutan todos los testbench:

* `tb_alu.sv` — Pruebas del módulo ALU.
* `tb_btn_reg.sv` — Pruebas del módulo de registro de captura.
* `tb_top.sv` — Pruebas de integración del sistema.

También es posible ejecutar un testbench específico indicando como argumento el módulo a probar:

```bash
./test.sh alu
./test.sh btn
./test.sh top
```

Para ejecutar explícitamente todos los testbench:

```bash
./test.sh all
```

Si alguna compilación o prueba falla, el script finaliza inmediatamente e indica el error correspondiente.

---

## Síntesis en Vivado

1. Crear un proyecto Vivado apuntando a la **Basys3** (`xc7a35tcpg236-1`).
2. Agregar todos los fuentes: `alu.sv`, `btn_reg.sv` y `top.sv`.
3. Agregar el constraint: `Basys3_Master.xdc`.
4. Ejecutar *Synthesis → Implementation → Generate Bitstream*.
5. Programar la placa con el `.bit` generado.
