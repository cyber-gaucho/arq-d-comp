# Máquinas de Estado Finitas - TP: UART

## Temario
Repaso de Máquinas de Estado
  ▪ Definiciones
  ▪ Representacion
  ▪ Ejemplo
  ▪ Consideraciones de Diseño

Trabajo Práctico
  ▪ UART

## Máquinas de Estado Finitas
 Las FSM se utilizan para modelar
  problemas que derivan en el diseño de
  lógica secuencial.
 Modelan sistemas abstractos que pueden
  estar en un único estado de un conjunto
  de estados finitos.
 Son usadas para modelar problemas en
  los que una secuencia de acciones
  depende de una secuencia de eventos.

### Representación
*Imagen*

### Representación en Hardware
*Imagen*

## Tipos de FSM

 Se identifican dos tipos de máquinas de
 estados, dependiendo de la lógica de salida:
 ▪ Máquina de Moore: La salida sólo depende del
   estado actual del circuito;
 ▪ Máquina de Mealy: La salida es función del
   estado actual del circuito Y de la entrada.

## Representación de Estados
 Binaria: Mínima cantidad de Flip-Flops
  ▪ 000, 001, 010, 011…

 One-Hot, One-Cold: Mas usadas en FPGA
  ▪ 0001, 0010, 0100, 1000
  ▪ 1110, 1101, 1011, 0111.

 Código Gray: Imposible en FSM con transiciones
  complejas.
  ▪ 000, 100, 110, 111…

 Output-Equals-State: Elimina lógica de salida

## Consideraciones de Diseño

 Máquinas de Estado Seguras
 ▪ Ante una entrada desconocida o ingreso a un
   estado inválido, en el siguiente ciclo se pasa a un
   estado de recuperación.

 Máquinas de Estado Rápidas
 ▪ Utilizan menos lógica debido a la ausencia de un
   estado de recuperación.
 Máxima Frecuencia: One-Hot o One-Cold
 Área: Binaria
 Min. Clock-To-Output delay: Output-Equals-
  State o Output con registro
 Glitch-Free Output: Output-Equals-State o
  Output con registro
 Mínimo Consumo: Estados con código Gray

## Máquinas de Estado en Verilog

 Usar un módulo para definir la máquina de
  estado.
 Usar una variable para representar el estado
  de la FSM llamada state
 Usar una variable para representar el posible
  próximo estado de la máquina, llamada
  next_state.
 Usar parameter o localparam para definir los
  estados.
 Para codificar los estados se pueden usar parámetros:

   parameter <state1> = 4'b0001;
   parameter <state2> = 4'b0010;
   parameter <state3> = 4'b0100;
   parameter <state4> = 4'b1000;

 Para representar las variables de estado actual y
  siguiente:
   reg [3:0] state = <state1>;
   reg [3:0] next_state = <state2>;

### Lógica de cambio de estado

always @(posedge <clock>) //Memory
  if (reset)        state <= <state1>;
  else              state <= next_state;


always @* // Next-state logic
  case (state)
      <state1>: begin
                    if (<condition>)
                           next_state = <state1>;
                    else
                           next_state = <state2>;
                  end
      <state2>:
                    .
                    .
                    .
      default: next_state = <state1>; // Fault Recovery
  endcase

### Lógica de las salidas

always @* // Output logic
  case (state)
     <state1>:
           <outputs> = <values>;
     <state2>:
                 .
                 .
                 .
     default:
           <outputs> = <values>; // Fault Recovery
  endcase

## TP: UART

 Universal Asynchronous Receiver and
 Transmitter


                                         Serial Out
       8 Bits           8 Bits

 ALU             INTF             UART
                                         Serial In
        8 bits           8 bits

                         Clock
 Genera un Tick 16 veces por Baud Rate
 Si baud rate es 19.200 ciclos por segundo, la
  frecuencia de muestreo debe ser 19.200 *16= 307.200
  ticks por segundo. Si el clock de la placa es 50 Mhz,
  hay que generar un tick cada 163 ciclos de reloj.

$$
\frac{\text{Clock}}{\text{Baud Rate} \times 16}
≅ 163
$$

 El Baud Rate Generator es un contador módulo 163.



### Secuencias de estados Rx

 Asumiendo N bits de datos, M bits de Stop.
  ▪ 1) Esperar a que la señal de entrada sea 0, momento en el
    que inicia el bit de Start. Iniciar el Tick Counter.
  ▪ 2) Cuando el contador llega a 7, la señal de entrada está en
    el punto medio del bit de Start. Reinicar el contador.
  ▪ 3) Cuando el contador llega a 15, la señal de entrada avanza
    1 bit, y alcanza la mitad del primer bit de datos. Tomar este
    valor e ingresarlo en un shift register. Reinicar el contador.
  ▪ 4) Repetir el paso 3 N-1 veces para tomar los bits restantes.
  ▪ 5) Si se usa bit de paridad, repetir el paso 3 una vez mas.
  ▪ 6) Reperir el paso 3 M veces, para obtener los bits de Stop.
RX                                                   r_data
                   rx           d_out
                                                       rd
                   clk        rx_done
            rate                                     rx_empty
                         Rx

      Baud Rate
      Generator

Clk                                      Interface
                                           Circuit              ALU
TX                 tx            d_in
                                                       w_data
                                                         wr
                   clk        tx_done
                                                      tx_full
                         Tx   tx_start


# De [Wikipedia](en.wikipedia.org/wiki/Universal_asynchronous_receiver-transmitter)

A UART frame consists of five elements:

- **Idle** (logic high (1))
- **Start bit** (logic low (0)): the start bit signals to the receiver that a new character is coming.
- **Data bits**: the next five to nine bits, depending on the code set employed, represent the character.
- **Parity bit**: if a parity bit is used, it would be placed after all of the data bits. The parity bit is a way for the receiving UART to tell if any data has changed during transmission.
- **Stop** (logic high (1)): the next one or two bits are always in the mark (logic high, i.e., 1) condition and called the stop bit(s). They signal to the receiver that the character is complete. Since the start bit is logic low (0) and the stop bit is logic high (1) there are always at least two guaranteed signal changes between characters. If the line is held in the logic low condition for longer than a character time, this is a break condition that can be detected by the UART.

In the most common settings of 8 data bits, no parity and 1 stop bit (i.e., **8N1**), the protocol efficiency is 8/10 = 80%. For comparison, Ethernet's protocol efficiency when using maximum throughput frames with a payload of 1500 bytes is up to 95% and up to 99% with 9000-byte jumbo frames. However, due to Ethernet's protocol overhead and minimum payload size of 42 bytes, if small messages of one or a few bytes are to be sent, Ethernet's protocol efficiency drops much lower than the UART's 8N1 constant efficiency of 80%.

The idle, no data state is high-voltage, or powered. This is a historic legacy from telegraphy, in which the line is held high to show that the line and transmitter are not damaged.

Each character is framed as a logic low start bit, data bits, possibly a parity bit and one or more stop bits. In most applications, the least significant data bit (the one on the left in this diagram) is transmitted first, but there are exceptions (such as the IBM 2741 printing terminal).

## Receiver

All operations of the UART hardware are controlled by an internal clock signal, which runs at a multiple of the data rate, typically 8 or 16 times the bit rate. The receiver tests the state of the incoming signal on each clock pulse, looking for the beginning of the start bit. If the apparent start bit lasts at least one-half of the bit time, it is valid and signals the start of a new character. If not, it is considered a spurious pulse and is ignored. After waiting a further bit time, the state of the line is again sampled and the resulting level clocked into a shift register. After the required number of bit periods for the character length (5 to 8 bits, typically) have elapsed, the contents of the shift register are made available (in parallel fashion) to the receiving system. The UART will set a flag indicating new data is available, and may also generate a processor interrupt to request that the host processor transfer the received data.

Communicating UARTs have no shared timing system apart from the communication signal. Typically, UARTs resynchronize their internal clocks on each change of the data line that is not considered a spurious pulse. Obtaining timing information in this manner, they reliably receive when the transmitter is sending at a slightly different speed than it should. Simplistic UARTs do not do this; instead, they resynchronize on the falling edge of the start bit only, and then read the center of each expected data bit, and this system works if the broadcast data rate is accurate enough to allow the stop bits to be sampled reliably.

It is a standard feature for a UART to store the most recent character while receiving the next. This "double buffering" gives a receiving computer an entire character transmission time to fetch a received character. Many UARTs have a small first-in, first-out FIFO buffer memory between the receiver shift register and the host system interface. This allows the host processor even more time to handle an interrupt from the UART and prevents loss of received data at high rates.

## Transmitter

Transmission operation is simpler as the timing does not have to be determined from the line state, nor is it bound to any fixed timing intervals. As soon as the sending system deposits a character in the shift register (after completion of the previous character), the UART generates a start bit, shifts the required number of data bits out to the line, generates and sends the parity bit (if used), and sends the stop bits. Since full-duplex operation requires characters to be sent and received at the same time, UARTs use two different shift registers for transmitted and received characters. High-performance UARTs could contain a transmit FIFO (first in, first out) buffer to allow a CPU or DMA controller to deposit multiple characters in a burst into the FIFO rather than have to deposit one character at a time into the shift register. Since transmission of a single or multiple characters may take a long time relative to CPU speeds, a UART maintains a flag showing busy status so that the host system knows if there is at least one character in the transmit buffer or shift register; "ready for next character(s)" may also be signaled with an interrupt.

## Application

Transmitting and receiving UARTs must be set for the same bit speed (Baud rate), character length, parity, and number of stop bits for proper operation. The receiving UART may detect some mismatched settings and set a "framing error" flag bit for the host system; in exceptional cases, the receiving UART will produce an erratic stream of mutilated characters and transfer them to the host system.

Typical serial ports used with personal computers connected to modems use one start bit, eight data bits, no parity, and one stop bit; for this configuration, the number of ASCII characters per second equals the bit rate divided by 10.

Some very low-cost home computers or embedded systems that lack a physical UART may instead emulate the protocol with software by sampling the state of an input port or directly manipulating an output port for data transmission. While very CPU-intensive (since the CPU timing is critical), the UART chip can thus be omitted, saving money and space. The technique is known as bit-banging.
