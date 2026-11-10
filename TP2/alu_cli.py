#!/usr/bin/env python3
"""
=============================================================================
Cliente CLI UART-ALU para Digilent Basys 3 (TP2 - Arquitectura de Computadoras)
=============================================================================
Permite interactuar en tiempo real con la ALU implementada en la FPGA a traves
del puerto serie USB-UART (8N1).

Caracteristicas:
  - Ingreso de operandos en decimal (con o sin signo) o hexadecimal (ej: 42, -5, 0x2A).
  - Seleccion de cualquiera de las 8 operaciones de la ALU (MIPS).
  - Desglose completo de campos: Operando A, Operando B, Operacion y Resultado.
  - Representacion en bits (binario) de cada campo.
  - Calculo y visualizacion de las banderas Zero y Overflow.
  - Comparacion visual directa con el mapa de LEDs fisico de la Basys 3:
      LED[15]   = Overflow
      LED[14]   = Zero
      LED[13:8] = Apagados (0)
      LED[7:0]  = Resultado
  - Modo interactivo y modo demo automatizado para exposicion frente al docente.
=============================================================================
"""

import sys
import time
import argparse
import glob

try:
    import serial
except ImportError:
    print("[ERROR] La libreria 'pyserial' no esta instalada.")
    print("        Instalala ejecutando: pip install pyserial")
    sys.exit(1)

# Diccionario de operaciones soportadas por la ALU
# Clave: Nombre corto -> (Opcode de 6 bits, Descripcion)
OPERACIONES = {
    "ADD": (0b100000, "Suma aritmetica (A + B)"),
    "SUB": (0b100010, "Resta aritmetica (A - B)"),
    "AND": (0b100100, "AND logico (A & B)"),
    "OR":  (0b100101, "OR logico (A | B)"),
    "XOR": (0b100110, "XOR logico (A ^ B)"),
    "SRA": (0b000011, "Desplazamiento aritmetico a derecha (A >>> B[2:0])"),
    "SRL": (0b000010, "Desplazamiento logico a derecha (A >> B[2:0])"),
    "NOR": (0b100111, "NOR logico (~(A | B))"),
}


class MockSerial:
    """Emulador de la ALU en hardware para pruebas sin placa conectada."""
    def __init__(self):
        self.buffer = bytearray()

    def write(self, data):
        if len(data) >= 3:
            a, b, op = data[0], data[1], data[2]
            res = 0
            if op == 0b100000:    # ADD
                res = (a + b) & 0xFF
            elif op == 0b100010:  # SUB
                res = (a - b) & 0xFF
            elif op == 0b100100:  # AND
                res = (a & b) & 0xFF
            elif op == 0b100101:  # OR
                res = (a | b) & 0xFF
            elif op == 0b100110:  # XOR
                res = (a ^ b) & 0xFF
            elif op == 0b000011:  # SRA
                sa = to_signed_8bit(a)
                res = (sa >> (b & 0x07)) & 0xFF
            elif op == 0b000010:  # SRL
                res = (a >> (b & 0x07)) & 0xFF
            elif op == 0b100111:  # NOR
                res = (~(a | b)) & 0xFF
            self.buffer.append(res)

    def read(self, n=1):
        if self.buffer:
            return bytes([self.buffer.pop(0)])
        return b""

    def reset_input_buffer(self):
        self.buffer.clear()

    def reset_output_buffer(self):
        pass

    def flush(self):
        pass

    def close(self):
        pass


def detectar_puerto_serie():
    """Detecta automaticamente el puerto serie de la Basys 3 en Linux/macOS/Windows."""
    # En Linux, la Basys 3 usualmente usa /dev/ttyUSB1 para la UART (ttyUSB0 es JTAG)
    preferidos = ["/dev/ttyUSB1", "/dev/ttyUSB0", "/dev/ttyACM0"]
    for p in preferidos:
        if glob.glob(p):
            return p

    # Si no, buscar cualquier ttyUSB o ttyACM
    candidatos = glob.glob("/dev/ttyUSB*") + glob.glob("/dev/ttyACM*")
    if candidatos:
        return candidatos[0]

    return "/dev/ttyUSB1"


def parsear_numero(texto):
    """
    Parsea un numero ingresado en decimal o hexadecimal y lo ajusta a 8 bits.
    Soporta:
      - Decimal positivo o negativo: '42', '-5'
      - Hexadecimal: '0x2A', '0X2A', '2A'
      - Binario: '0b00101010'
    """
    texto = texto.strip()
    try:
        # Intenta parsear con base automatica (0x para hex, 0b para binario, decimal puro)
        val = int(texto, 0)
    except ValueError:
        try:
            # Intenta parsear como hex directo sin prefijo '0x'
            val = int(texto, 16)
        except ValueError:
            raise ValueError(f"No se pudo interpretar el valor '{texto}'. Ingrese decimal o hex (ej: 25, -10, 0x1F).")

    # Ajustar a 8 bits (complemento a 2 para negativos)
    val_8bit = val & 0xFF
    return val_8bit, val


def calcular_banderas(op_a, op_b, opcode, resultado):
    """
    Calcula las banderas esperadas de Zero y Overflow con signo para contrastar con la FPGA.
    """
    # Bandera Zero: activa si el resultado de 8 bits es 0
    zero = 1 if resultado == 0 else 0

    # Bandera Overflow con signo (solo aplica para ADD y SUB)
    overflow = 0
    sign_a = (op_a >> 7) & 1
    sign_b = (op_b >> 7) & 1
    sign_r = (resultado >> 7) & 1

    if opcode == 0b100000:  # ADD: pos + pos = neg  OR  neg + neg = pos
        if (sign_a == sign_b) and (sign_r != sign_a):
            overflow = 1
    elif opcode == 0b100010:  # SUB: pos - neg = neg  OR  neg - pos = pos
        if (sign_a != sign_b) and (sign_r != sign_a):
            overflow = 1

    return zero, overflow


def to_signed_8bit(val):
    """Convierte un valor de 8 bits sin signo a entero con signo (-128 a 127)."""
    return val if val < 128 else val - 256


def renderizar_leds(resultado, zero, overflow):
    """Genera una representacion grafica de los 16 LEDs de la Basys 3."""
    # LED[15] = Overflow, LED[14] = Zero, LED[13:8] = 0, LED[7:0] = Resultado
    led_ovf  = "[●]" if overflow else "[○]"
    led_zero = "[●]" if zero else "[○]"

    leds_res = ""
    for bit in range(7, -1, -1):
        estado = (resultado >> bit) & 1
        leds_res += "[●] " if estado else "[○] "
    leds_res = leds_res.strip()

    linea = (
        f"  LED[15] (OVF)  : {led_ovf} ({overflow})\n"
        f"  LED[14] (ZERO) : {led_zero} ({zero})\n"
        f"  LED[13:8]      : [○] [○] [○] [○] [○] [○] (apagados)\n"
        f"  LED[7:0] (RES) : {leds_res}\n"
        f"                   b7  b6  b5  b4  b3  b2  b1  b0"
    )
    return linea


def ejecutar_operacion(ser, op_a, op_b, op_nombre, timeout=1.5):
    """
    Envia la trama de 3 bytes a la FPGA y lee el resultado de 8 bits.
    Trama PC -> FPGA:
      Byte 1: Operando A (8 bits)
      Byte 2: Operando B (8 bits)
      Byte 3: Codigo de operacion (6 bits)
    Respuesta FPGA -> PC:
      Byte de resultado (8 bits)
    """
    opcode_val, op_desc = OPERACIONES[op_nombre]

    # Limpiar buffers previos
    ser.reset_input_buffer()
    ser.reset_output_buffer()

    trama = bytes([op_a, op_b, opcode_val])
    ser.write(trama)
    ser.flush()

    # Esperar el byte de respuesta
    tiempo_inicio = time.time()
    resp = ser.read(1)
    tiempo_total = (time.time() - tiempo_inicio) * 1000  # en ms

    if not resp:
        print("\n[ERROR] Timeout: La FPGA no respondio dentro del tiempo limite.")
        print("        Verifique:")
        print("          1. Que la placa este encendida y programada (LED verde DONE encendido).")
        print("          2. Que el puerto serie sea el correcto (/dev/ttyUSB1).")
        print("          3. Pulse el boton de reset (btnR) en la placa para reiniciar las FSMs.")
        return None

    resultado = resp[0]
    zero, overflow = calcular_banderas(op_a, op_b, opcode_val, resultado)

    # Imprimir reporte detallado de la transaccion
    print("\n" + "=" * 65)
    print(f" OPERACION ALU: {op_nombre} - {op_desc}")
    print("=" * 65)

    print(f"{'CAMPO':<16} | {'DECIMAL':<10} | {'HEX':<8} | {'BINARIO (BITS)':<14} | {'NOTA'}")
    print("-" * 65)

    # Operando A
    s_a = to_signed_8bit(op_a)
    print(f"{'Operando A':<16} | {op_a:<3} (sign: {s_a:>4}) | 0x{op_a:02X}     | 0b{op_a:08b}     | Byte 1")

    # Operando B
    s_b = to_signed_8bit(op_b)
    print(f"{'Operando B':<16} | {op_b:<3} (sign: {s_b:>4}) | 0x{op_b:02X}     | 0b{op_b:08b}     | Byte 2")

    # Operacion
    print(f"{'Operacion':<16} | {opcode_val:<10} | 0x{opcode_val:02X}     | 0b{opcode_val:06b} (6 bits) | Byte 3")
    print("-" * 65)

    # Resultado
    s_res = to_signed_8bit(resultado)
    print(f"{'RESULTADO (FPGA)':<16} | {resultado:<3} (sign: {s_res:>4}) | 0x{resultado:02X}     | 0b{resultado:08b}     | Respuesta UART")
    print("=" * 65)

    # Banderas y LEDs
    print("\n[ESTADO DE BANDERAS Y MAPA DE LEDs EN LA BASYS 3]")
    print(renderizar_leds(resultado, zero, overflow))
    print(f"\n[INFO] Transaccion completada en {tiempo_total:.1f} ms.")

    return resultado


def menu_interactivo(ser):
    """Bucle principal de la interfaz interactiva."""
    ops_lista = list(OPERACIONES.keys())

    while True:
        print("\n" + "#" * 65)
        print(" SISTEMA UART-ALU BASYS 3 - PANEL DE CONTROL INTERACTIVO")
        print("#" * 65)
        print("Operaciones disponibles:")
        for idx, op in enumerate(ops_lista, start=1):
            codigo, desc = OPERACIONES[op]
            print(f"  {idx}. {op:<4} (0x{codigo:02X}) -> {desc}")
        print("  D. DEMO RAPIDA (Ejecuta bateria de pruebas para el profesor)")
        print("  Q. Salir")
        print("-" * 65)

        opcion = input("Seleccione una operacion (1-8, D, Q): ").strip().upper()

        if opcion == "Q":
            print("\nCerrando conexion. ¡Exitos en la presentacion!")
            break

        if opcion == "D":
            ejecutar_demo(ser)
            continue

        op_seleccionada = None
        if opcion.isdigit():
            num = int(opcion)
            if 1 <= num <= len(ops_lista):
                op_seleccionada = ops_lista[num - 1]
        elif opcion in OPERACIONES:
            op_seleccionada = opcion

        if not op_seleccionada:
            print("[AVISO] Opcion invalida. Intente de nuevo.")
            continue

        print(f"\n>> Operacion seleccionada: {op_seleccionada}")
        try:
            raw_a = input(" Ingrese Operando A (dec o hex, ej: 15, -10, 0x0F): ")
            val_a, _ = parsear_numero(raw_a)

            raw_b = input(" Ingrese Operando B (dec o hex, ej: 27, 0x1B): ")
            val_b, _ = parsear_numero(raw_b)
        except ValueError as err:
            print(f"[ERROR] {err}")
            continue

        ejecutar_operacion(ser, val_a, val_b, op_seleccionada)
        input("\nPresione ENTER para continuar...")


def ejecutar_demo(ser):
    """Ejecuta una serie de casos demostrativos de todas las operaciones y banderas."""
    casos = [
        ("ADD", 15, 27, "Suma normal sin banderas (15 + 27 = 42)"),
        ("SUB", 0x5A, 0x5A, "Resta con bandera ZERO activa (0x5A - 0x5A = 0)"),
        ("ADD", 0x7F, 0x01, "Suma con OVERFLOW con signo (127 + 1 = -128)"),
        ("SUB", 0x80, 0x01, "Resta con OVERFLOW con signo (-128 - 1 = +127)"),
        ("AND", 0xF0, 0xAA, "AND bit a bit (0xF0 & 0xAA = 0xA0)"),
        ("OR",  0x0F, 0xF0, "OR bit a bit (0x0F | 0xF0 = 0xFF)"),
        ("XOR", 0xAA, 0x55, "XOR bit a bit (0xAA ^ 0x55 = 0xFF)"),
        ("NOR", 0x0F, 0xF0, "NOR bit a bit con ZERO (~(0x0F | 0xF0) = 0x00)"),
        ("SRA", 0xF0, 2,    "Shift aritmetico a derecha (-16 >>> 2 = -4 / 0xFC)"),
        ("SRL", 0xF0, 2,    "Shift logico a derecha (0xF0 >> 2 = 0x3C)"),
    ]

    print("\n" + "=" * 65)
    print(" INICIANDO BATERIA DE DEMOSTRACION AUTOMATICA")
    print("=" * 65)

    for op, a, b, desc in casos:
        print(f"\n>>> DEMO: {desc}")
        res = ejecutar_operacion(ser, a, b, op)
        if res is None:
            break
        time.sleep(1.2)  # Pausa para poder observar los LEDs en la placa

    print("\n" + "=" * 65)
    print(" BATERIA DE DEMOSTRACION FINALIZADA")
    print("=" * 65)


def main():
    parser = argparse.ArgumentParser(
        description="Cliente de comunicacion UART para la ALU en Basys 3 (TP2 - Arq. de Computadoras)"
    )
    parser.add_argument("-p", "--port", default=None, help="Puerto serie (ej: /dev/ttyUSB1 o COM3). Auto-detectado por defecto.")
    parser.add_argument("-b", "--baud", type=int, default=9600, help="Velocidad de transmision en baudios (default: 9600)")
    parser.add_argument("--op", choices=list(OPERACIONES.keys()), help="Operacion para ejecucion directa no interactiva")
    parser.add_argument("-a", "--op-a", help="Operando A para ejecucion directa (ej: 15 o 0x0F)")
    parser.add_argument("-b_val", "--op-b", help="Operando B para ejecucion directa (ej: 27 o 0x1B)")
    parser.add_argument("--demo", action="store_true", help="Ejecutar la bateria de demostracion automatica directamente")
    parser.add_argument("--mock", action="store_true", help="Modo simulacion sin hardware (emula la respuesta de la Basys 3)")

    args = parser.parse_args()

    if args.mock:
        print("=" * 65)
        print(" MODO SIMULACION / EMULADOR ACTIVADO (Sin placa fisica)")
        print("=" * 65)
        ser = MockSerial()
    else:
        puerto = args.port or detectar_puerto_serie()

        print("=" * 65)
        print(" CONECTANDO CON DIGILENT BASYS 3 (UART-ALU)")
        print(f" Puerto  : {puerto}")
        print(f" Baudrate: {args.baud} (8N1)")
        print("=" * 65)

        try:
            ser = serial.Serial(
                port=puerto,
                baudrate=args.baud,
                bytesize=serial.EIGHTBITS,
                parity=serial.PARITY_NONE,
                stopbits=serial.STOPBITS_ONE,
                timeout=1.5
            )
        except Exception as err:
            print(f"\n[ERROR] No se pudo abrir el puerto serie '{puerto}': {err}")
            print("        Verifique permisos (sudo chmod 666 /dev/ttyUSB1) y que la placa este conectada.")
            print("        (Tip: Puede ejecutar con --mock para probar la CLI sin la placa conectada)")
            sys.exit(1)

    time.sleep(0.1)  # Estabilizacion

    try:
        # Modo directo por linea de comando
        if args.demo:
            ejecutar_demo(ser)
        elif args.op and args.op_a is not None and args.op_b is not None:
            val_a, _ = parsear_numero(args.op_a)
            val_b, _ = parsear_numero(args.op_b)
            ejecutar_operacion(ser, val_a, val_b, args.op)
        else:
            # Modo interactivo
            menu_interactivo(ser)
    finally:
        ser.close()


if __name__ == "__main__":
    main()
