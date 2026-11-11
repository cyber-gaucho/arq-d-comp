#!/usr/bin/env python3
"""
=============================================================================
Cliente TUI / CLI UART-ALU para Digilent Basys 3 (TP2 - Arq. de Computadoras)
=============================================================================
Herramienta interactiva de terminal (TUI de ventana completa) y cliente de
linea de comandos (CLI) para comunicar la PC con el sistema UART-ALU en la
FPGA Digilent Basys 3 (Issue #11).

Caracteristicas principales:
  - Interfaz tipo aplicacion de terminal (TUI en pantalla alternativa ANSI)
    con navegacion por teclado en tiempo real.
  - Programa de demostracion pregrabado con ejecucion PASO A PASO (avanzando
    con ESPACIO / ENTER o navegando con flechas ↑/↓).
  - Modo Paso a Paso por Instruccion (3 bytes) o Paso a Paso por Byte
    individual (Byte 1: OpA -> Byte 2: OpB -> Byte 3: Opcode) para observar
    la evolucion de la FSM en hardware.
  - Ingreso de operaciones manuales (ADD, SUB, AND, OR, XOR, SRA, SRL, NOR)
    con operandos en decimal (con/sin signo), hexadecimal (0x..) o binario (0b..).
  - Visualizacion de valores enviados, byte recibido de la FPGA (en hex,
    binario, decimal sin signo y decimal en complemento a 2) y valor esperado
    calculado localmente para verificacion automatica (PASS / FAIL).
  - Representacion grafica en vivo de los 16 LEDs fisicos de la Basys 3.
  - Soporte de ejecucion directa por argumentos CLI y modo emulador (--mock).
=============================================================================
"""

import sys
import os
import time
import glob
import shutil
import argparse

try:
    import serial
except ImportError:
    serial = None


# =============================================================================
# DEFINICION DE OPERACIONES DE LA ALU (6 BITS)
# =============================================================================
OPERACIONES = {
    "ADD": (0b100000, "Suma con signo (A + B)"),
    "SUB": (0b100010, "Resta con signo (A - B)"),
    "AND": (0b100100, "AND logico bit a bit (A & B)"),
    "OR":  (0b100101, "OR logico bit a bit (A | B)"),
    "XOR": (0b100110, "XOR logico bit a bit (A ^ B)"),
    "SRA": (0b000011, "Shift aritmetico derecho (A >>> B[3:0])"),
    "SRL": (0b000010, "Shift logico derecho (A >> B[3:0])"),
    "NOR": (0b100111, "NOR logico bit a bit (~(A | B))"),
}

OPS_LISTA = list(OPERACIONES.keys())

# Programa pregrabado para la demostracion paso a paso frente a la catedra
PROGRAMA_DEMO_INICIAL = [
    ("ADD", 15,   27,   "Suma aritmetica basica (15 + 27 = 42)"),
    ("SUB", 0x5A, 0x5A, "Resta con bandera ZERO (90 - 90 = 0)"),
    ("ADD", 0x7F, 0x01, "Overflow positivo (+127 + 1 = -128)"),
    ("SUB", 0x80, 0x01, "Overflow negativo (-128 - 1 = +127)"),
    ("AND", 0xF0, 0xAA, "AND logico bit a bit (0xF0 & 0xAA = 0xA0)"),
    ("OR",  0x0F, 0xF0, "OR logico bit a bit (0x0F | 0xF0 = 0xFF)"),
    ("XOR", 0xAA, 0x55, "XOR logico bit a bit (0xAA ^ 0x55 = 0xFF)"),
    ("NOR", 0x0F, 0xF0, "NOR logico con ZERO (~(0x0F|0xF0) = 0x00)"),
    ("SRA", 0xF0, 2,    "Shift aritmetico der. (-16 >>> 2 = -4)"),
    ("SRL", 0xF0, 2,    "Shift logico derecho (240 >> 2 = 60)"),
]


# =============================================================================
# MODELO DE REFERENCIA LOCAL DE LA ALU (8 BITS) Y FUNCIONES AUXILIARES
# =============================================================================
def to_signed_8bit(val):
    """Convierte un byte sin signo (0..255) a entero en complemento a 2 (-128..127)."""
    val = val & 0xFF
    return val if val < 128 else val - 256


def format_bin8(val):
    """Formatea un byte de 8 bits como binario separado por nibbles (ej: 1111_0000)."""
    b = f"{val & 0xFF:08b}"
    return f"{b[:4]}_{b[4:]}"


def calcular_esperado_alu(op_a, op_b, opcode):
    """
    Calcula localmente el resultado esperado de 8 bits y las banderas (Zero, Overflow)
    replicando exactamente el comportamiento RTL de TP2/src/alu.v (NB_DATA = 8).
    """
    a = op_a & 0xFF
    b = op_b & 0xFF
    op = opcode & 0x3F

    if op == 0b100000:      # ADD
        res = (a + b) & 0xFF
    elif op == 0b100010:    # SUB
        res = (a - b) & 0xFF
    elif op == 0b100100:    # AND
        res = (a & b) & 0xFF
    elif op == 0b100101:    # OR
        res = (a | b) & 0xFF
    elif op == 0b100110:    # XOR
        res = (a ^ b) & 0xFF
    elif op == 0b000011:    # SRA (usa b[3:0] para NB_DATA=8, $clog2(8)=3)
        sa = to_signed_8bit(a)
        res = (sa >> (b & 0x0F)) & 0xFF
    elif op == 0b000010:    # SRL (usa b[3:0] para NB_DATA=8)
        res = (a >> (b & 0x0F)) & 0xFF
    elif op == 0b100111:    # NOR
        res = (~(a | b)) & 0xFF
    else:
        res = 0

    zero = 1 if res == 0 else 0

    # Overflow con signo (solo para ADD y SUB)
    overflow = 0
    sign_a = (a >> 7) & 1
    sign_b = (b >> 7) & 1
    sign_r = (res >> 7) & 1

    if op == 0b100000:      # ADD: (~a[7] & ~b[7] & r[7]) | (a[7] & b[7] & ~r[7])
        if (sign_a == sign_b) and (sign_r != sign_a):
            overflow = 1
    elif op == 0b100010:    # SUB: (~a[7] & b[7] & r[7]) | (a[7] & ~b[7] & ~r[7])
        if (sign_a != sign_b) and (sign_r != sign_a):
            overflow = 1

    return res, zero, overflow


def parsear_numero(texto):
    """
    Parsea un numero ingresado en decimal (con/sin signo), hexadecimal o binario
    y lo ajusta a 8 bits en complemento a 2.
    Soporta: '42', '-16', '0x2A', '0b00101010', '2A' (si tiene letras hex).
    """
    texto = texto.strip().replace("_", "")
    if not texto:
        raise ValueError("Valor vacio.")
    try:
        val = int(texto, 0)
    except ValueError:
        try:
            val = int(texto, 16)
        except ValueError:
            raise ValueError(
                f"No se pudo interpretar '{texto}'. Use decimal (ej: 15, -10), hex (0x0F) o bin (0b00001111)."
            )
    return val & 0xFF, val


# =============================================================================
# EMULADOR DE PUERTO SERIE (MOCK) Y DETECCION DE HARDWARE
# =============================================================================
class MockSerial:
    """
    Emulador fiel de la interfaz UART + FIFO + FSM alu_ctrl de la FPGA Basys 3.
    Soporta envio de los 3 bytes juntos o envio byte a byte (StWaitOpA -> StWaitOpB -> StWaitOpCode).
    """
    def __init__(self, port="MOCK-BASYS3", baudrate=9600):
        self.port = port
        self.baudrate = baudrate
        self.rx_fifo = bytearray()
        self.tx_fifo = bytearray()
        self.is_mock = True

    def write(self, data):
        self.rx_fifo.extend(data)
        while len(self.rx_fifo) >= 3:
            a = self.rx_fifo.pop(0)
            b = self.rx_fifo.pop(0)
            op = self.rx_fifo.pop(0) & 0x3F
            res, _, _ = calcular_esperado_alu(a, b, op)
            self.tx_fifo.append(res)

    def read(self, n=1):
        if self.tx_fifo:
            out = bytes(self.tx_fifo[:n])
            del self.tx_fifo[:n]
            return out
        return b""

    def reset_input_buffer(self):
        self.tx_fifo.clear()
        self.rx_fifo.clear()

    def reset_output_buffer(self):
        self.rx_fifo.clear()

    def flush(self):
        pass

    def close(self):
        pass


def detectar_puerto_serie():
    """Detecta automaticamente el puerto serie de la Basys 3 en Linux/macOS/Windows."""
    preferidos = ["/dev/ttyUSB1", "/dev/ttyUSB0", "/dev/ttyACM0"]
    for p in preferidos:
        if glob.glob(p):
            return p

    candidatos = sorted(glob.glob("/dev/ttyUSB*") + glob.glob("/dev/ttyACM*"))
    if candidatos:
        return candidatos[-1]

    return "/dev/ttyUSB1"


def abrir_puerto_serie(puerto, baudrate, timeout=1.5):
    """Intenta abrir el puerto serie fisico con pyserial."""
    if serial is None:
        raise RuntimeError("La libreria 'pyserial' no esta instalada (pip install pyserial).")
    ser = serial.Serial(
        port=puerto,
        baudrate=baudrate,
        bytesize=serial.EIGHTBITS,
        parity=serial.PARITY_NONE,
        stopbits=serial.STOPBITS_ONE,
        timeout=timeout,
    )
    ser.is_mock = False
    return ser


# =============================================================================
# CODIGOS DE COLOR ANSI Y UTILIDADES DE TERMINAL (TUI)
# =============================================================================
class Ansi:
    RESET     = "\033[0m"
    BOLD      = "\033[1m"
    DIM       = "\033[2m"
    ITALIC    = "\033[3m"
    UNDERLINE = "\033[4m"
    REVERSE   = "\033[7m"

    # Colores de texto
    FG_BLACK   = "\033[30m"
    FG_RED     = "\033[91m"
    FG_GREEN   = "\033[92m"
    FG_YELLOW  = "\033[93m"
    FG_BLUE    = "\033[94m"
    FG_MAGENTA = "\033[95m"
    FG_CYAN    = "\033[96m"
    FG_WHITE   = "\033[97m"
    FG_GRAY    = "\033[90m"

    # Colores de fondo
    BG_BLUE    = "\033[44m"
    BG_CYAN    = "\033[46m"
    BG_GREEN   = "\033[42m"
    BG_RED     = "\033[41m"
    BG_YELLOW  = "\033[43m"
    BG_DARK    = "\033[48;5;236m"
    BG_HEADER  = "\033[48;5;24m"
    BG_SEL     = "\033[48;5;238m"

    # Control de pantalla
    ALT_SCREEN_ON  = "\033[?1049h"
    ALT_SCREEN_OFF = "\033[?1049l"
    CURSOR_HIDE    = "\033[?25l"
    CURSOR_SHOW    = "\033[?25h"
    HOME           = "\033[H"
    CLEAR_EOS      = "\033[J"
    CLEAR_ALL      = "\033[2J\033[H"


def strip_ansi(text):
    """Elimina secuencias de escape ANSI para calcular el ancho visible real."""
    import re
    return re.sub(r"\033\[[0-9;?]*[A-Za-z]", "", text)


def pad_ansi(text, width, align="left"):
    """Ajusta un texto con codigos ANSI a un ancho visible exacto."""
    vis_len = len(strip_ansi(text))
    if vis_len >= width:
        return text
    pad = " " * (width - vis_len)
    if align == "right":
        return pad + text
    if align == "center":
        left = (width - vis_len) // 2
        right = width - vis_len - left
        return (" " * left) + text + (" " * right)
    return text + pad


def box_line(left, fill, right, width, color=Ansi.FG_BLUE):
    return f"{color}{left}{fill * (width - 2)}{right}{Ansi.RESET}"


def box_row(content, width, border_color=Ansi.FG_BLUE):
    padded = pad_ansi(content, width - 4)
    return f"{border_color}│{Ansi.RESET} {padded} {border_color}│{Ansi.RESET}"


def box_title(title, width, border_color=Ansi.FG_BLUE, title_color=Ansi.BOLD + Ansi.FG_CYAN):
    clean_title = f" {title} "
    vis_t = len(strip_ansi(clean_title))
    rem = max(0, width - 3 - vis_t)
    return (
        f"{border_color}╭─{Ansi.RESET}"
        f"{title_color}{clean_title}{Ansi.RESET}"
        f"{border_color}{'─' * rem}╮{Ansi.RESET}"
    )


def leer_tecla():
    """
    Lee una pulsacion de tecla cruda de la terminal (soporta flechas ↑/↓/←/→,
    ESPACIO, ENTER, ESC, Backspace y caracteres normales).
    """
    if not sys.stdin.isatty():
        linea = sys.stdin.readline()
        return linea.strip() if linea else "q"

    if os.name == "nt":
        import msvcrt
        ch = msvcrt.getwch()
        if ch in ("\x00", "\xe0"):
            ch2 = msvcrt.getwch()
            mapa = {"H": "UP", "P": "DOWN", "K": "LEFT", "M": "RIGHT"}
            return mapa.get(ch2, "")
        if ch == "\r":
            return "ENTER"
        if ch == " ":
            return "SPACE"
        if ch == "\x1b":
            return "ESC"
        return ch
    else:
        import tty
        import termios
        import select
        fd = sys.stdin.fileno()
        old_settings = termios.tcgetattr(fd)
        try:
            tty.setraw(fd)
            ch = os.read(fd, 1).decode("utf-8", errors="ignore")
            if ch == "\x1b":
                # Verificar si es secuencia de escape (flechas)
                rlist, _, _ = select.select([fd], [], [], 0.04)
                if rlist:
                    ch2 = os.read(fd, 1).decode("utf-8", errors="ignore")
                    if ch2 == "[":
                        rlist2, _, _ = select.select([fd], [], [], 0.04)
                        if rlist2:
                            ch3 = os.read(fd, 1).decode("utf-8", errors="ignore")
                            if ch3 == "A":
                                return "UP"
                            if ch3 == "B":
                                return "DOWN"
                            if ch3 == "C":
                                return "RIGHT"
                            if ch3 == "D":
                                return "LEFT"
                return "ESC"
            if ch in ("\r", "\n"):
                return "ENTER"
            if ch == " ":
                return "SPACE"
            if ch == "\x03":  # Ctrl+C
                raise KeyboardInterrupt
            if ch in ("\x7f", "\x08"):
                return "BACKSPACE"
            return ch
        finally:
            termios.tcsetattr(fd, termios.TCSADRAIN, old_settings)


# =============================================================================
# ESTADO Y LOGICA DE LA APLICACION TUI
# =============================================================================
class StepItem:
    """Representa una instruccion dentro del programa de demostracion."""
    def __init__(self, op, op_a, op_b, desc, es_manual=False):
        self.op = op
        self.op_a = op_a & 0xFF
        self.op_b = op_b & 0xFF
        self.desc = desc
        self.es_manual = es_manual
        self.estado = "PENDIENTE"  # PENDIENTE, EN_CURSO, PASS, FAIL, TIMEOUT
        self.rx_val = None
        self.exp_val, self.exp_zero, self.exp_ovf = calcular_esperado_alu(
            self.op_a, self.op_b, OPERACIONES[self.op][0]
        )
        self.latencia_ms = None
        self.bytes_enviados = 0  # 0, 1, 2, 3 (para modo byte a byte)

    def reset(self):
        self.estado = "PENDIENTE"
        self.rx_val = None
        self.latencia_ms = None
        self.bytes_enviados = 0


class AluTuiApp:
    """Aplicacion TUI interactiva para monitoreo y depuracion paso a paso."""
    def __init__(self, ser, puerto_nombre, baudrate):
        self.ser = ser
        self.puerto_nombre = puerto_nombre
        self.baudrate = baudrate

        self.programa = [
            StepItem(op, a, b, desc) for op, a, b, desc in PROGRAMA_DEMO_INICIAL
        ]
        self.cursor_idx = 0       # Instruccion apuntada por el selector ▶
        self.activa_idx = 0       # Instruccion mostrada en el Inspector de Transaccion
        self.modo_byte = False    # False = Paso por instruccion (3 bytes), True = Paso byte a byte

        self.total_enviadas = 0
        self.total_pass = 0
        self.total_fail = 0
        self.mensaje_barra = (
            "Presione [ESPACIO] o [ENTER] para ejecutar el paso actual y avanzar paso a paso."
        )
        self.mensaje_tipo = "INFO"  # INFO, OK, WARN, ERR

    def reiniciar_programa(self):
        """Reinicia todos los pasos del programa al estado pendiente."""
        for item in self.programa:
            item.reset()
        self.cursor_idx = 0
        self.activa_idx = 0
        if self.ser:
            try:
                self.ser.reset_input_buffer()
                self.ser.reset_output_buffer()
            except Exception:
                pass
        self.mensaje_barra = "Programa reiniciado al Paso #01. Listo para avanzar paso a paso."
        self.mensaje_tipo = "INFO"

    def alternar_mock(self):
        """Alterna entre conexion serie fisica y el emulador MockSerial."""
        if getattr(self.ser, "is_mock", False):
            # Intentar conectar al hardware real
            puerto = self.puerto_nombre if self.puerto_nombre != "MOCK-BASYS3" else detectar_puerto_serie()
            try:
                nuevo_ser = abrir_puerto_serie(puerto, self.baudrate)
                self.ser.close()
                self.ser = nuevo_ser
                self.puerto_nombre = puerto
                self.mensaje_barra = f"Conectado al hardware fisico en {puerto} @ {self.baudrate} baudios."
                self.mensaje_tipo = "OK"
            except Exception as err:
                self.mensaje_barra = f"No se pudo abrir {puerto}: {err}. Seguimos en modo Emulador (Mock)."
                self.mensaje_tipo = "WARN"
        else:
            try:
                if self.ser:
                    self.ser.close()
            except Exception:
                pass
            self.ser = MockSerial(baudrate=self.baudrate)
            self.mensaje_barra = "Modo Emulador Local (MockSerial) activado."
            self.mensaje_tipo = "INFO"

    def ejecutar_paso_actual(self, avanzar_cursor=True):
        """
        Ejecuta la instruccion seleccionada por cursor_idx.
        - Si modo_byte == False: envia los 3 bytes (OpA, OpB, Opcode), lee la respuesta
          y avanza el cursor al siguiente paso.
        - Si modo_byte == True: envia 1 byte por cada pulsacion (Byte 1 -> Byte 2 -> Byte 3 + RX).
        """
        item = self.programa[self.cursor_idx]
        self.activa_idx = self.cursor_idx
        opcode_val, _ = OPERACIONES[item.op]

        if not self.modo_byte:
            # Ejecucion de instruccion completa (3 bytes)
            item.bytes_enviados = 0
            try:
                self.ser.reset_input_buffer()
                self.ser.reset_output_buffer()

                trama = bytes([item.op_a, item.op_b, opcode_val])
                t0 = time.time()
                self.ser.write(trama)
                self.ser.flush()

                resp = self.ser.read(1)
                dt_ms = (time.time() - t0) * 1000.0
            except Exception as err:
                item.estado = "TIMEOUT"
                item.rx_val = None
                self.total_fail += 1
                self.mensaje_barra = f"Error de comunicacion serie: {err}"
                self.mensaje_tipo = "ERR"
                return

            item.bytes_enviados = 3
            item.latencia_ms = dt_ms
            self.total_enviadas += 1

            if not resp:
                item.estado = "TIMEOUT"
                item.rx_val = None
                self.total_fail += 1
                self.mensaje_barra = (
                    f"Paso #{self.cursor_idx + 1:02d}: TIMEOUT esperando respuesta de la FPGA. "
                    "Verifique conexion o pulse btnR en la Basys 3."
                )
                self.mensaje_tipo = "ERR"
                return

            item.rx_val = resp[0]
            if item.rx_val == item.exp_val:
                item.estado = "PASS"
                self.total_pass += 1
                self.mensaje_barra = (
                    f"Paso #{self.cursor_idx + 1:02d} [{item.op}] ejecutado -> "
                    f"FPGA devolvio 0x{item.rx_val:02X} ({to_signed_8bit(item.rx_val)}) == "
                    f"Esperado 0x{item.exp_val:02X} [✓ PASS]"
                )
                self.mensaje_tipo = "OK"
            else:
                item.estado = "FAIL"
                self.total_fail += 1
                self.mensaje_barra = (
                    f"Paso #{self.cursor_idx + 1:02d} [{item.op}] DISCREPANCIA -> "
                    f"FPGA: 0x{item.rx_val:02X} != Esperado: 0x{item.exp_val:02X} [✗ FAIL]"
                )
                self.mensaje_tipo = "ERR"

            if avanzar_cursor and self.cursor_idx < len(self.programa) - 1:
                self.cursor_idx += 1

        else:
            # Ejecucion Byte a Byte (1 byte por pulsacion)
            if item.bytes_enviados >= 3 or item.estado in ("PASS", "FAIL", "TIMEOUT"):
                # Reiniciar secuencia de 3 bytes para esta instruccion
                item.bytes_enviados = 0
                item.rx_val = None
                item.estado = "EN_CURSO"

            paso_byte = item.bytes_enviados + 1
            try:
                if paso_byte == 1:
                    self.ser.reset_input_buffer()
                    self.ser.reset_output_buffer()
                    self.ser.write(bytes([item.op_a]))
                    self.ser.flush()
                    item.bytes_enviados = 1
                    item.estado = "EN_CURSO"
                    self.mensaje_barra = (
                        f"[Byte 1/3 enviado] Operando A = 0x{item.op_a:02X} ({to_signed_8bit(item.op_a)}). "
                        "FSM FPGA en StWaitOpB. Presione [ESPACIO] para enviar Byte 2."
                    )
                    self.mensaje_tipo = "INFO"

                elif paso_byte == 2:
                    self.ser.write(bytes([item.op_b]))
                    self.ser.flush()
                    item.bytes_enviados = 2
                    item.estado = "EN_CURSO"
                    self.mensaje_barra = (
                        f"[Byte 2/3 enviado] Operando B = 0x{item.op_b:02X} ({to_signed_8bit(item.op_b)}). "
                        "FSM FPGA en StWaitOpCode. Presione [ESPACIO] para enviar Byte 3 (Opcode)."
                    )
                    self.mensaje_tipo = "INFO"

                elif paso_byte == 3:
                    t0 = time.time()
                    self.ser.write(bytes([opcode_val]))
                    self.ser.flush()
                    resp = self.ser.read(1)
                    dt_ms = (time.time() - t0) * 1000.0

                    item.bytes_enviados = 3
                    item.latencia_ms = dt_ms
                    self.total_enviadas += 1

                    if not resp:
                        item.estado = "TIMEOUT"
                        item.rx_val = None
                        self.total_fail += 1
                        self.mensaje_barra = "TIMEOUT al leer resultado tras enviar Byte 3."
                        self.mensaje_tipo = "ERR"
                        return

                    item.rx_val = resp[0]
                    if item.rx_val == item.exp_val:
                        item.estado = "PASS"
                        self.total_pass += 1
                        self.mensaje_barra = (
                            f"[Byte 3/3 enviado] Opcode {item.op} (0x{opcode_val:02X}) -> "
                            f"Resultado recibido: 0x{item.rx_val:02X} ({to_signed_8bit(item.rx_val)}) [✓ PASS]"
                        )
                        self.mensaje_tipo = "OK"
                    else:
                        item.estado = "FAIL"
                        self.total_fail += 1
                        self.mensaje_barra = (
                            f"[Byte 3/3 enviado] Discrepancia: FPGA=0x{item.rx_val:02X} vs "
                            f"Esperado=0x{item.exp_val:02X} [✗ FAIL]"
                        )
                        self.mensaje_tipo = "ERR"

                    if avanzar_cursor and self.cursor_idx < len(self.programa) - 1:
                        self.cursor_idx += 1

            except Exception as err:
                item.estado = "TIMEOUT"
                self.mensaje_barra = f"Error en envio byte a byte: {err}"
                self.mensaje_tipo = "ERR"

    def renderizar_pantalla(self):
        """Construye y dibuja toda la ventana de la aplicacion en el buffer de terminal."""
        cols, _ = shutil.get_terminal_size((108, 38))
        width = max(108, min(cols, 114))

        lineas = []

        # ---------------------------------------------------------------------
        # 1. CABECERA SUPERIOR DE LA VENTANA
        # ---------------------------------------------------------------------
        es_mock = getattr(self.ser, "is_mock", False)
        if es_mock:
            badge_conn = f"{Ansi.BOLD}{Ansi.FG_YELLOW}● EMULADOR LOCAL (MOCK){Ansi.RESET}"
        else:
            badge_conn = (
                f"{Ansi.BOLD}{Ansi.FG_GREEN}● HARDWARE: "
                f"{self.puerto_nombre} @ {self.baudrate} 8N1{Ansi.RESET}"
            )

        modo_str = (
            f"{Ansi.BOLD}{Ansi.FG_MAGENTA}BYTE A BYTE (1 Byte/paso){Ansi.RESET}"
            if self.modo_byte
            else f"{Ansi.BOLD}{Ansi.FG_CYAN}INSTRUCCIÓN (3 Bytes/paso){Ansi.RESET}"
        )

        titulo_top = (
            f"{Ansi.BG_HEADER}{Ansi.BOLD}{Ansi.FG_WHITE}"
            f"{pad_ansi('  DIGILENT BASYS 3 — MONITOR Y DEPURADOR UART-ALU (TP2 Arq. de Computadoras)', width)}"
            f"{Ansi.RESET}"
        )
        lineas.append(titulo_top)

        stats_str = (
            f"Conexión: {badge_conn}  │  Modo Paso: {modo_str}  │  "
            f"Tx: {Ansi.BOLD}{self.total_enviadas}{Ansi.RESET}  "
            f"{Ansi.FG_GREEN}PASS: {self.total_pass}{Ansi.RESET}  "
            f"{Ansi.FG_RED}FAIL: {self.total_fail}{Ansi.RESET}"
        )
        lineas.append(box_line("╭", "─", "╮", width, Ansi.FG_BLUE))
        lineas.append(box_row(stats_str, width, Ansi.FG_BLUE))
        lineas.append(box_line("╰", "─", "╯", width, Ansi.FG_BLUE))

        # ---------------------------------------------------------------------
        # 2. PANEL: PROGRAMA DE DEMOSTRACION PASO A PASO
        # ---------------------------------------------------------------------
        lineas.append(
            box_title(
                f"PROGRAMA DE DEMOSTRACIÓN PASO A PASO (Próximo ▶ #{self.cursor_idx + 1:02d}/{len(self.programa):02d} | En Inspector ● #{self.activa_idx + 1:02d})",
                width,
            )
        )
        hdr_prog = (
            f"{Ansi.BOLD}{Ansi.FG_WHITE}"
            f"{'PTR':<4} {'#':<3} {'OP':<4} {'OPERANDOS (DEC / HEX)':<22} "
            f"{'DESCRIPCIÓN DEL CASO DE PRUEBA':<42} {'ESTADO / RESULTADO FPGA'}"
            f"{Ansi.RESET}"
        )
        lineas.append(box_row(hdr_prog, width))
        lineas.append(box_line("├", "─", "┤", width, Ansi.FG_BLUE))

        for idx, item in enumerate(self.programa):
            es_cursor = (idx == self.cursor_idx)
            es_activa = (idx == self.activa_idx)

            if es_cursor and es_activa:
                puntero = f"{Ansi.BOLD}{Ansi.FG_YELLOW} ▶● {Ansi.RESET}"
            elif es_cursor:
                puntero = f"{Ansi.BOLD}{Ansi.FG_YELLOW} ▶  {Ansi.RESET}"
            elif es_activa:
                puntero = f"{Ansi.BOLD}{Ansi.FG_CYAN}  ● {Ansi.RESET}"
            else:
                puntero = "    "

            sa = to_signed_8bit(item.op_a)
            sb = to_signed_8bit(item.op_b)
            op_fmt = f"{sa:>4},{sb:>4} (0x{item.op_a:02X},0x{item.op_b:02X})"

            if item.estado == "PASS":
                sr = to_signed_8bit(item.rx_val)
                est_fmt = f"{Ansi.BOLD}{Ansi.FG_GREEN}✓ PASS{Ansi.RESET} 0x{item.rx_val:02X} ({sr:>+4d})"
            elif item.estado == "FAIL":
                rx_h = f"0x{item.rx_val:02X}" if item.rx_val is not None else "ERR"
                est_fmt = f"{Ansi.BOLD}{Ansi.FG_RED}✗ FAIL{Ansi.RESET} {rx_h}!=0x{item.exp_val:02X}"
            elif item.estado == "TIMEOUT":
                est_fmt = f"{Ansi.BOLD}{Ansi.FG_RED}✗ TIMEOUT{Ansi.RESET}"
            elif item.estado == "EN_CURSO":
                est_fmt = f"{Ansi.BOLD}{Ansi.FG_YELLOW}◐ Byte {item.bytes_enviados}/3 env.{Ansi.RESET}"
            else:
                est_fmt = f"{Ansi.DIM}· Pendiente (Esp:0x{item.exp_val:02X}){Ansi.RESET}"

            desc_corta = item.desc[:41]
            color_fila = Ansi.BOLD + Ansi.FG_WHITE if es_cursor else (Ansi.FG_CYAN if es_activa else "")
            reset_fila = Ansi.RESET if (es_cursor or es_activa) else ""

            fila_txt = (
                f"{puntero}{color_fila}{idx + 1:02d}  {item.op:<4} "
                f"{op_fmt:<22} {desc_corta:<42}{reset_fila} {est_fmt}"
            )
            lineas.append(box_row(fila_txt, width))

        lineas.append(box_line("╰", "─", "╯", width, Ansi.FG_BLUE))

        # ---------------------------------------------------------------------
        # 3. PANEL: INSPECTOR DE TRANSACCION Y VERIFICACION AUTOMATICA (ISSUE #11)
        # ---------------------------------------------------------------------
        act = self.programa[self.activa_idx]
        opcode_val, op_desc = OPERACIONES[act.op]

        lineas.append(
            box_title(
                f"INSPECTOR DE INSTRUCCIÓN ● #{self.activa_idx + 1:02d}: {act.op} — {op_desc}",
                width,
            )
        )

        # Indicador visual de los estados de la FSM alu_ctrl
        b_sent = act.bytes_enviados
        st1 = (
            f"{Ansi.BOLD}{Ansi.FG_GREEN}[1.OpA: 0x{act.op_a:02X} ✓]{Ansi.RESET}"
            if b_sent >= 1
            else f"{Ansi.BOLD}{Ansi.FG_YELLOW}[1.StWaitOpA ●]{Ansi.RESET}"
        )
        st2 = (
            f"{Ansi.BOLD}{Ansi.FG_GREEN}[2.OpB: 0x{act.op_b:02X} ✓]{Ansi.RESET}"
            if b_sent >= 2
            else (
                f"{Ansi.BOLD}{Ansi.FG_YELLOW}[2.StWaitOpB ●]{Ansi.RESET}"
                if b_sent == 1
                else f"{Ansi.DIM}[2.StWaitOpB]{Ansi.RESET}"
            )
        )
        st3 = (
            f"{Ansi.BOLD}{Ansi.FG_GREEN}[3.Op: 0x{opcode_val:02X} ✓]{Ansi.RESET}"
            if b_sent >= 3
            else (
                f"{Ansi.BOLD}{Ansi.FG_YELLOW}[3.StWaitOpCode ●]{Ansi.RESET}"
                if b_sent == 2
                else f"{Ansi.DIM}[3.StWaitOpCode]{Ansi.RESET}"
            )
        )
        st4 = (
            f"{Ansi.BOLD}{Ansi.FG_CYAN}[4.StSendResult: 0x{act.rx_val:02X} ✓]{Ansi.RESET}"
            if act.rx_val is not None
            else f"{Ansi.DIM}[4.StSendResult]{Ansi.RESET}"
        )
        lineas.append(
            box_row(f" {Ansi.BOLD}Protocolo FSM:{Ansi.RESET} {st1} ──► {st2} ──► {st3} ──► {st4}", width)
        )
        lineas.append(box_line("├", "─", "┤", width, Ansi.FG_BLUE))

        # Tabla de desglose de bytes (Hex, Binario, Decimal sin signo y Complemento a 2)
        hdr_insp = (
            f"{Ansi.BOLD}{Ansi.FG_WHITE}"
            f" {'CAMPO / TRAMA':<22} │ {'DIR':<9} │ {'DEC (SIN SIGNO)':<15} │ "
            f"{'DEC C2 (SIGNO)':<14} │ {'HEX':<6} │ {'BINARIO (BITS)'}"
            f"{Ansi.RESET}"
        )
        lineas.append(box_row(hdr_insp, width))
        lineas.append(box_line("├", "─", "┤", width, Ansi.FG_BLUE))

        # Byte 1: Operando A
        sa = to_signed_8bit(act.op_a)
        lineas.append(
            box_row(
                f" {'Byte 1: Operando A':<22} │ {'PC → FPGA':<9} │ {act.op_a:<15} │ "
                f"{sa:<+14d} │ 0x{act.op_a:02X}   │ 0b{format_bin8(act.op_a)}",
                width,
            )
        )
        # Byte 2: Operando B
        sb = to_signed_8bit(act.op_b)
        lineas.append(
            box_row(
                f" {'Byte 2: Operando B':<22} │ {'PC → FPGA':<9} │ {act.op_b:<15} │ "
                f"{sb:<+14d} │ 0x{act.op_b:02X}   │ 0b{format_bin8(act.op_b)}",
                width,
            )
        )
        # Byte 3: Codigo de Operacion
        lineas.append(
            box_row(
                f" {'Byte 3: Operación':<22} │ {'PC → FPGA':<9} │ {opcode_val:<3} ({act.op:<9}) │ "
                f"{'Opcode 6-bit':<14} │ 0x{opcode_val:02X}   │ 0b00_{opcode_val:06b}",
                width,
            )
        )
        lineas.append(box_line("├", "─", "┤", width, Ansi.FG_BLUE))

        # Respuesta recibida de la FPGA
        if act.rx_val is not None:
            sr = to_signed_8bit(act.rx_val)
            color_rx = Ansi.BOLD + (Ansi.FG_GREEN if act.rx_val == act.exp_val else Ansi.FG_RED)
            lineas.append(
                box_row(
                    f" {color_rx}{'Recibido (FPGA RX)':<22}{Ansi.RESET} │ {'FPGA → PC':<9} │ "
                    f"{color_rx}{act.rx_val:<15}{Ansi.RESET} │ "
                    f"{color_rx}{sr:<+14d}{Ansi.RESET} │ "
                    f"{color_rx}0x{act.rx_val:02X}{Ansi.RESET}   │ "
                    f"{color_rx}0b{format_bin8(act.rx_val)}{Ansi.RESET}",
                    width,
                )
            )
        else:
            lineas.append(
                box_row(
                    f" {'Recibido (FPGA RX)':<22} │ {'FPGA → PC':<9} │ "
                    f"{Ansi.DIM}{'--- (Pendiente de envío a la FPGA)':<52}{Ansi.RESET}",
                    width,
                )
            )

        # Valor esperado calculado localmente en la PC
        se = to_signed_8bit(act.exp_val)
        lineas.append(
            box_row(
                f" {Ansi.FG_CYAN}{'Esperado (Cálculo PC)':<22}{Ansi.RESET} │ {'Local Ref':<9} │ "
                f"{act.exp_val:<15} │ {se:<+14d} │ 0x{act.exp_val:02X}   │ 0b{format_bin8(act.exp_val)}",
                width,
            )
        )

        # Linea de verificacion automatica
        if act.estado == "PASS":
            lat_txt = f" ({act.latencia_ms:.1f} ms)" if act.latencia_ms is not None else ""
            verif_txt = (
                f" {Ansi.BOLD}{Ansi.FG_GREEN}✓ VERIFICACIÓN AUTOMÁTICA: PASS{Ansi.RESET} — "
                f"El byte recibido de la FPGA coincide con el esperado{lat_txt}."
            )
        elif act.estado == "FAIL":
            verif_txt = (
                f" {Ansi.BOLD}{Ansi.FG_RED}✗ VERIFICACIÓN AUTOMÁTICA: FAIL{Ansi.RESET} — "
                f"Recibido 0x{act.rx_val:02X} ({to_signed_8bit(act.rx_val)}) != "
                f"Esperado 0x{act.exp_val:02X} ({se})."
            )
        elif act.estado == "TIMEOUT":
            verif_txt = (
                f" {Ansi.BOLD}{Ansi.FG_RED}✗ ERROR: TIMEOUT{Ansi.RESET} — "
                "La FPGA no respondió. Verifique el puerto o presione Reset (btnR) en la Basys 3."
            )
        elif act.estado == "EN_CURSO":
            verif_txt = (
                f" {Ansi.BOLD}{Ansi.FG_YELLOW}◐ EN CURSO (Modo Byte a Byte):{Ansi.RESET} "
                f"{act.bytes_enviados}/3 bytes enviados a la FIFO RX de la FPGA."
            )
        else:
            verif_txt = (
                f" {Ansi.DIM}· Instrucción pendiente. Presione [ESPACIO] para ejecutar paso a paso.{Ansi.RESET}"
            )
        lineas.append(box_row(verif_txt, width))
        lineas.append(box_line("╰", "─", "╯", width, Ansi.FG_BLUE))

        # ---------------------------------------------------------------------
        # 4. PANEL: VISUALIZACION DE LEDS FISICOS DE LA DIGILENT BASYS 3
        # ---------------------------------------------------------------------
        val_leds = act.rx_val if act.rx_val is not None else act.exp_val
        zero_led, ovf_led = calcular_esperado_alu(act.op_a, act.op_b, opcode_val)[1:]
        if act.rx_val is not None:
            zero_led = 1 if act.rx_val == 0 else 0

        modo_led_lbl = (
            "ESTADO ACTUAL EN PLACA" if act.rx_val is not None else "VISTA PREVIA ESPERADA (Pre-envío)"
        )
        lineas.append(
            box_title(f"MAPA DE LEDs FÍSICOS DIGILENT BASYS 3 (LED[15:0]) — {modo_led_lbl}", width)
        )

        # Construir iconos de los 16 LEDs: LD15 (OVF), LD14 (ZERO), LD13..8 (0), LD7..0 (Resultado)
        ic_ovf = f"{Ansi.BOLD}{Ansi.FG_RED} ● {Ansi.RESET}" if ovf_led else f"{Ansi.DIM} ○ {Ansi.RESET}"
        ic_zro = f"{Ansi.BOLD}{Ansi.FG_CYAN} ● {Ansi.RESET}" if zero_led else f"{Ansi.DIM} ○ {Ansi.RESET}"
        ic_off = " ".join([f"{Ansi.DIM} ○ {Ansi.RESET}"] * 6)

        bits_res_icons = []
        bits_res_nums = []
        for bit in range(7, -1, -1):
            b_val = (val_leds >> bit) & 1
            if b_val:
                bits_res_icons.append(f"{Ansi.BOLD}{Ansi.FG_GREEN} ● {Ansi.RESET}")
                bits_res_nums.append(f"{Ansi.BOLD}{Ansi.FG_GREEN} 1 {Ansi.RESET}")
            else:
                bits_res_icons.append(f"{Ansi.DIM} ○ {Ansi.RESET}")
                bits_res_nums.append(f"{Ansi.DIM} 0 {Ansi.RESET}")

        fila_etiquetas = (
            f"  {Ansi.BOLD}OVF  ZERO{Ansi.RESET}   "
            f"{Ansi.DIM}┌───────── LED[13:8] Apagados ─────────┐{Ansi.RESET}   "
            f"{Ansi.BOLD}┌─────────── LED[7:0] Resultado ALU ───────────┐{Ansi.RESET}"
        )
        fila_leds = (
            f"  {ic_ovf}  {ic_zro}    "
            f"  {ic_off}            "
            f"{'   '.join(bits_res_icons)}"
        )
        fila_nombres = (
            f" {Ansi.DIM}LD15  LD14    LD13 LD12 LD11 LD10  LD9  LD8           "
            f"LD7   LD6   LD5   LD4   LD3   LD2   LD1   LD0{Ansi.RESET}"
        )
        fila_valores = (
            f"  ({ovf_led})   ({zero_led})     "
            f"{Ansi.DIM} 0    0    0    0    0    0{Ansi.RESET}            "
            f"{'   '.join(bits_res_nums)}"
        )

        lineas.append(box_row(fila_etiquetas, width))
        lineas.append(box_row(fila_leds, width))
        lineas.append(box_row(fila_nombres, width))
        lineas.append(box_row(fila_valores, width))
        lineas.append(box_line("╰", "─", "╯", width, Ansi.FG_BLUE))

        # ---------------------------------------------------------------------
        # 5. BARRA DE ESTADO Y CONTROLES DE TECLADO
        # ---------------------------------------------------------------------
        if self.mensaje_tipo == "OK":
            color_msg = Ansi.BOLD + Ansi.FG_GREEN
        elif self.mensaje_tipo == "WARN":
            color_msg = Ansi.BOLD + Ansi.FG_YELLOW
        elif self.mensaje_tipo == "ERR":
            color_msg = Ansi.BOLD + Ansi.FG_RED
        else:
            color_msg = Ansi.FG_CYAN

        lineas.append(f" {color_msg}▶ {self.mensaje_barra}{Ansi.RESET}")

        controles_1 = (
            f" {Ansi.REVERSE}{Ansi.BOLD} ESPACIO {Ansi.RESET} Paso ▶  "
            f"{Ansi.REVERSE}{Ansi.BOLD} ENTER {Ansi.RESET} Ejecutar actual  "
            f"{Ansi.REVERSE}{Ansi.BOLD} ↑/↓ {Ansi.RESET} Navegar  "
            f"{Ansi.REVERSE}{Ansi.BOLD} B {Ansi.RESET} Byte-a-Byte  "
            f"{Ansi.REVERSE}{Ansi.BOLD} I / 1-8 {Ansi.RESET} Op. Manual  "
            f"{Ansi.REVERSE}{Ansi.BOLD} A {Ansi.RESET} Auto  "
            f"{Ansi.REVERSE}{Ansi.BOLD} R {Ansi.RESET} Reiniciar  "
            f"{Ansi.REVERSE}{Ansi.BOLD} M {Ansi.RESET} Mock/HW  "
            f"{Ansi.REVERSE}{Ansi.BOLD} Q {Ansi.RESET} Salir"
        )
        lineas.append(controles_1)

        # Volcar todo al buffer de pantalla sin parpadeo
        salida = Ansi.HOME + "\n".join(lineas) + Ansi.CLEAR_EOS
        sys.stdout.write(salida)
        sys.stdout.flush()

    def dialogo_operacion_manual(self, op_preseleccionada=None):
        """
        Muestra un cuadro de entrada en la parte inferior de la ventana TUI
        para ingresar una instruccion personalizada y agregarla/ejecutarla.
        """
        sys.stdout.write(Ansi.CURSOR_SHOW)
        sys.stdout.flush()
        try:
            print("\n" + "─" * 84)
            print(f"{Ansi.BOLD}{Ansi.FG_CYAN} INGRESO DE INSTRUCCIÓN MANUAL{Ansi.RESET} (Deje vacío y presione ENTER para cancelar)")
            if op_preseleccionada:
                op_nombre = op_preseleccionada
                print(f" Operación seleccionada: {Ansi.BOLD}{op_nombre}{Ansi.RESET} ({OPERACIONES[op_nombre][1]})")
            else:
                ops_str = "  ".join([f"[{i+1}]{k}" for i, k in enumerate(OPS_LISTA)])
                print(f" Operaciones: {ops_str}")
                raw_op = input(" Seleccione Operación (1-8 o nombre, ej: ADD, SUB, SRA): ").strip().upper()
                if not raw_op:
                    self.mensaje_barra = "Ingreso manual cancelado."
                    self.mensaje_tipo = "INFO"
                    return
                if raw_op.isdigit() and 1 <= int(raw_op) <= len(OPS_LISTA):
                    op_nombre = OPS_LISTA[int(raw_op) - 1]
                elif raw_op in OPERACIONES:
                    op_nombre = raw_op
                else:
                    self.mensaje_barra = f"Operación '{raw_op}' inválida."
                    self.mensaje_tipo = "ERR"
                    return

            raw_a = input(" Operando A (decimal con/sin signo, hex o bin, ej: 15, -16, 0xF0): ").strip()
            if not raw_a:
                self.mensaje_barra = "Ingreso manual cancelado."
                self.mensaje_tipo = "INFO"
                return
            val_a, _ = parsear_numero(raw_a)

            raw_b = input(" Operando B (decimal con/sin signo, hex o bin, ej: 27, 2, 0x1B): ").strip()
            if not raw_b:
                self.mensaje_barra = "Ingreso manual cancelado."
                self.mensaje_tipo = "INFO"
                return
            val_b, _ = parsear_numero(raw_b)

            desc = f"[Manual] {op_nombre} ({to_signed_8bit(val_a)}, {to_signed_8bit(val_b)})"
            nuevo_paso = StepItem(op_nombre, val_a, val_b, desc, es_manual=True)
            self.programa.append(nuevo_paso)
            self.cursor_idx = len(self.programa) - 1
            self.ejecutar_paso_actual(avanzar_cursor=False)

        except ValueError as err:
            self.mensaje_barra = f"Error de formato: {err}"
            self.mensaje_tipo = "ERR"
        except (KeyboardInterrupt, EOFError):
            self.mensaje_barra = "Ingreso manual cancelado."
            self.mensaje_tipo = "INFO"
        finally:
            sys.stdout.write(Ansi.CURSOR_HIDE + Ansi.CLEAR_ALL)
            sys.stdout.flush()

    def ejecutar_auto_demo(self):
        """Recorre todos los pasos desde el cursor actual automaticamente con una breve pausa."""
        modo_previo = self.modo_byte
        self.modo_byte = False
        try:
            while self.cursor_idx < len(self.programa):
                idx_actual = self.cursor_idx
                self.ejecutar_paso_actual(avanzar_cursor=False)
                self.renderizar_pantalla()
                if self.programa[idx_actual].estado == "TIMEOUT":
                    break
                time.sleep(0.85)
                if self.cursor_idx < len(self.programa) - 1:
                    self.cursor_idx += 1
                else:
                    break
            self.mensaje_barra = "Recorrido automático completado. Puede navegar con [↑/↓] o reiniciar con [R]."
            self.mensaje_tipo = "OK"
        finally:
            self.modo_byte = modo_previo

    def run(self):
        """Bucle principal de eventos de la ventana TUI."""
        sys.stdout.write(Ansi.ALT_SCREEN_ON + Ansi.CURSOR_HIDE + Ansi.CLEAR_ALL)
        sys.stdout.flush()
        try:
            while True:
                self.renderizar_pantalla()
                tecla = leer_tecla()
                if not tecla:
                    continue

                t_upper = tecla.upper()

                if t_upper in ("Q", "ESC"):
                    break
                elif tecla in ("SPACE", "ENTER") or t_upper == "N":
                    self.ejecutar_paso_actual(avanzar_cursor=True)
                elif tecla == "UP" or t_upper == "K":
                    self.cursor_idx = (self.cursor_idx - 1) % len(self.programa)
                    self.activa_idx = self.cursor_idx
                    self.mensaje_barra = f"Seleccionado Paso #{self.cursor_idx + 1:02d}. Presione [ESPACIO/ENTER] para ejecutar."
                    self.mensaje_tipo = "INFO"
                elif tecla == "DOWN" or t_upper == "J":
                    self.cursor_idx = (self.cursor_idx + 1) % len(self.programa)
                    self.activa_idx = self.cursor_idx
                    self.mensaje_barra = f"Seleccionado Paso #{self.cursor_idx + 1:02d}. Presione [ESPACIO/ENTER] para ejecutar."
                    self.mensaje_tipo = "INFO"
                elif t_upper == "B":
                    self.modo_byte = not self.modo_byte
                    modo_txt = "BYTE A BYTE (1 byte por pulsación)" if self.modo_byte else "INSTRUCCIÓN COMPLETA (3 bytes)"
                    self.mensaje_barra = f"Modo de avance cambiado a: {modo_txt}."
                    self.mensaje_tipo = "INFO"
                elif t_upper == "R":
                    self.reiniciar_programa()
                elif t_upper == "A":
                    self.ejecutar_auto_demo()
                elif t_upper == "M":
                    self.alternar_mock()
                elif t_upper == "I":
                    self.dialogo_operacion_manual()
                elif tecla in ("1", "2", "3", "4", "5", "6", "7", "8"):
                    op_sel = OPS_LISTA[int(tecla) - 1]
                    self.dialogo_operacion_manual(op_preseleccionada=op_sel)

        except KeyboardInterrupt:
            pass
        finally:
            sys.stdout.write(Ansi.CURSOR_SHOW + Ansi.ALT_SCREEN_OFF)
            sys.stdout.flush()


# =============================================================================
# MODO LINEA DE COMANDOS (NO-TUI) PARA EJECUCION DIRECTA Y SCRIPTING (ISSUE #11)
# =============================================================================
def ejecutar_operacion_cli(ser, op_a, op_b, op_nombre):
    """
    Ejecuta una unica operacion desde la linea de comandos, imprime la tabla
    completa de valores enviados, byte recibido, valor esperado y verificacion
    automatica (Issue #11), junto con el estado de los LEDs de la Basys 3.
    """
    opcode_val, op_desc = OPERACIONES[op_nombre]
    exp_val, exp_zero, exp_ovf = calcular_esperado_alu(op_a, op_b, opcode_val)

    ser.reset_input_buffer()
    ser.reset_output_buffer()

    trama = bytes([op_a, op_b, opcode_val])
    t0 = time.time()
    ser.write(trama)
    ser.flush()
    resp = ser.read(1)
    dt_ms = (time.time() - t0) * 1000.0

    print("\n" + "=" * 78)
    print(f" OPERACIÓN UART-ALU: {op_nombre} — {op_desc}")
    print("=" * 78)
    print(f"{'CAMPO':<20} | {'SIN SIGNO':<9} | {'CON SIGNO (C2)':<14} | {'HEX':<6} | {'BINARIO (BITS)'}")
    print("-" * 78)

    sa = to_signed_8bit(op_a)
    sb = to_signed_8bit(op_b)
    se = to_signed_8bit(exp_val)

    print(f"{'Byte 1: Operando A':<20} | {op_a:<9} | {sa:<+14d} | 0x{op_a:02X}   | 0b{format_bin8(op_a)}")
    print(f"{'Byte 2: Operando B':<20} | {op_b:<9} | {sb:<+14d} | 0x{op_b:02X}   | 0b{format_bin8(op_b)}")
    print(f"{'Byte 3: Operación':<20} | {opcode_val:<9} | {op_nombre:<14} | 0x{opcode_val:02X}   | 0b00_{opcode_val:06b}")
    print("-" * 78)

    if not resp:
        print(f"{'Recibido (FPGA)':<20} | [TIMEOUT - Sin respuesta de la placa Basys 3]")
        print(f"{'Esperado (Local PC)':<20} | {exp_val:<9} | {se:<+14d} | 0x{exp_val:02X}   | 0b{format_bin8(exp_val)}")
        print("=" * 78)
        print("[FAIL] Timeout esperando respuesta por UART.")
        return None

    resultado = resp[0]
    sr = to_signed_8bit(resultado)
    coincide = (resultado == exp_val)
    estado_str = "PASS (Coincide)" if coincide else "FAIL (Discrepancia)"

    print(f"{'Recibido (FPGA)':<20} | {resultado:<9} | {sr:<+14d} | 0x{resultado:02X}   | 0b{format_bin8(resultado)}")
    print(f"{'Esperado (Local PC)':<20} | {exp_val:<9} | {se:<+14d} | 0x{exp_val:02X}   | 0b{format_bin8(exp_val)}")
    print("-" * 78)
    print(f" Verificación Automática : [{estado_str}] (Tiempo: {dt_ms:.1f} ms)")
    print(f" Banderas Esperadas      : Zero (LED[14]) = {exp_zero}  |  Overflow (LED[15]) = {exp_ovf}")
    print("=" * 78)

    leds_res = " ".join(["[●]" if ((resultado >> b) & 1) else "[○]" for b in range(7, -1, -1)])
    print(" Mapa de LEDs en Basys 3:")
    print(f"   LED[15] (OVF)  : {'[●]' if exp_ovf else '[○]'} ({exp_ovf})")
    print(f"   LED[14] (ZERO) : {'[●]' if exp_zero else '[○]'} ({exp_zero})")
    print(f"   LED[13:8]      : [○] [○] [○] [○] [○] [○] (apagados)")
    print(f"   LED[7:0] (RES) : {leds_res}")
    print("                    LD7 LD6 LD5 LD4 LD3 LD2 LD1 LD0")
    return resultado if coincide else None


def ejecutar_demo_cli_paso_a_paso(ser, auto=False):
    """Ejecuta el programa de demostracion en modo texto paso a paso."""
    print("\n" + "=" * 78)
    print(" PROGRAMA DE DEMOSTRACIÓN UART-ALU (MODO PASO A PASO)")
    print("=" * 78)
    for idx, (op, a, b, desc) in enumerate(PROGRAMA_DEMO_INICIAL, start=1):
        print(f"\n>>> PASO [{idx:02d}/{len(PROGRAMA_DEMO_INICIAL):02d}]: {desc}")
        if not auto and sys.stdin.isatty():
            resp_usr = input("    Presione [ENTER] para enviar instrucción (o 'q' para salir): ").strip().lower()
            if resp_usr == "q":
                break
        res = ejecutar_operacion_cli(ser, a, b, op)
        if res is None:
            break
        if auto:
            time.sleep(0.8)


# =============================================================================
# PUNTO DE ENTRADA PRINCIPAL
# =============================================================================
def main():
    parser = argparse.ArgumentParser(
        description="Monitor TUI y Cliente CLI UART-ALU para Digilent Basys 3 (TP2 - Issue #11)"
    )
    parser.add_argument(
        "-p", "--port", default=None,
        help="Puerto serie (ej: /dev/ttyUSB1 o COM3). Auto-detectado por defecto."
    )
    parser.add_argument(
        "--baud", type=int, default=9600,
        help="Velocidad de transmisión en baudios (default: 9600)."
    )
    parser.add_argument(
        "--op", choices=OPS_LISTA, type=str.upper,
        help="Operación para ejecución directa por línea de comandos (ADD, SUB, AND, OR, XOR, SRA, SRL, NOR)."
    )
    parser.add_argument(
        "-a", "--op-a", dest="op_a",
        help="Operando A para ejecución directa (ej: 15, -16, 0xF0)."
    )
    parser.add_argument(
        "-b", "-b_val", "--op-b", dest="op_b",
        help="Operando B para ejecución directa (ej: 27, 2, 0x1B)."
    )
    parser.add_argument(
        "--demo", action="store_true",
        help="Iniciar en modo demostración con el programa de pruebas pregrabado."
    )
    parser.add_argument(
        "--no-tui", action="store_true",
        help="Usar salida de texto estándar en lugar de la interfaz TUI de ventana completa."
    )
    parser.add_argument(
        "--mock", action="store_true",
        help="Modo emulador sin hardware físico (simula la respuesta de la Basys 3)."
    )

    args = parser.parse_args()

    # Inicializar conexion serie o emulador MockSerial
    puerto = args.port or detectar_puerto_serie()
    if args.mock:
        ser = MockSerial(port="MOCK-BASYS3", baudrate=args.baud)
    else:
        try:
            ser = abrir_puerto_serie(puerto, args.baud)
        except Exception as err:
            # Si estamos lanzando la TUI interactiva y no hay placa conectada,
            # ofrecemos iniciar en modo Emulador (Mock) o salir.
            if not args.op and not args.no_tui and sys.stdin.isatty():
                print(f"[AVISO] No se pudo abrir '{puerto}': {err}")
                print("        Iniciando interfaz TUI en Modo Emulador Local (--mock).")
                print("        (Puede reconectar al hardware en cualquier momento presionando [M]).")
                time.sleep(1.2)
                ser = MockSerial(port=puerto, baudrate=args.baud)
            else:
                print(f"\n[ERROR] No se pudo abrir el puerto serie '{puerto}': {err}")
                print("        Verifique permisos (sudo chmod 666 /dev/ttyUSB1) y que la Basys 3 esté conectada.")
                print("        Tip: Ejecute con --mock para probar sin placa física conectada.")
                sys.exit(1)

    try:
        # 1. Modo de ejecucion directa de una operacion por CLI (--op ADD -a 15 -b 27)
        if args.op and args.op_a is not None and args.op_b is not None:
            val_a, _ = parsear_numero(args.op_a)
            val_b, _ = parsear_numero(args.op_b)
            ok = ejecutar_operacion_cli(ser, val_a, val_b, args.op)
            sys.exit(0 if ok is not None else 1)

        # 2. Modo texto plano sin TUI (--no-tui)
        if args.no_tui or not sys.stdout.isatty():
            ejecutar_demo_cli_paso_a_paso(ser, auto=not sys.stdin.isatty())
            return

        # 3. Modo principal: Ventana de aplicacion interactiva en terminal (TUI)
        app = AluTuiApp(ser, puerto, args.baud)
        app.run()

    finally:
        ser.close()


if __name__ == "__main__":
    main()
