// ============================================================
// PRÁCTICA 4.2 — MINI CLOUD LOG ANALYZER
// ============================================================
// Variante   : B — Código de estado HTTP más frecuente
// Arquitectura: ARM64 (AArch64) — GNU Assembler (GAS)
// Sistema op. : Linux (Ubuntu ARM64)
// Entrada     : stdin — un código HTTP por línea
// Salida      : stdout — código con mayor frecuencia
//
// Uso:
//   cat data/logs_B.txt | ./analyzer
//
// Compilación:
//   as -g -o analyzer.o src/analyzer.s
//   ld -o analyzer analyzer.o
// ============================================================


// ============================================================
// SECCIÓN 1 — CONSTANTES DEL SISTEMA
// ============================================================
// Números de syscall para Linux ARM64 (AArch64).
// Se invocan con la instrucción  svc #0
// El número de syscall va en el registro x8.
// ============================================================

.equ SYS_READ,   63          // leer bytes desde un descriptor
.equ SYS_WRITE,  64          // escribir bytes a un descriptor
.equ SYS_EXIT,   93          // terminar el proceso

.equ STDIN,       0          // descriptor: entrada estándar
.equ STDOUT,      1          // descriptor: salida estándar

.equ BUF_SIZE,   16          // bytes máximos por lectura


// ============================================================
// SECCIÓN 2 — DATOS DE SÓLO LECTURA (.rodata)
// ============================================================
// Cadenas de texto que se imprimen en stdout.
// Se define también la longitud de cada mensaje usando
// la diferencia de posiciones ". - etiqueta" del ensamblador.
// No se incluye '\0' porque las syscalls usan longitud
// explícita, no terminador nulo.
// ============================================================

.section .rodata

msg_most:                               // prefijo del resultado
    .ascii  "Most frequent status code: "
msg_most_len = . - msg_most             // longitud calculada en ensamblado

msg_newline:                            // salto de línea final
    .ascii  "\n"

msg_none:                               // mensaje si no hay datos
    .ascii  "No valid codes found\n"
msg_none_len = . - msg_none


// ============================================================
// SECCIÓN 3 — DATOS NO INICIALIZADOS (.bss)
// ============================================================
// El sistema operativo garantiza que esta sección comienza
// en cero al cargar el programa, sin ocupar espacio en el
// binario en disco.
//
// counts[1000]:
//   Array de 1000 enteros de 64 bits (8 bytes cada uno).
//   El índice ES el código HTTP (100–599).
//   Acceso directo O(1): counts[código]++
//   Códigos fuera del rango simplemente nunca se tocan.
//
// buf[BUF_SIZE]:
//   Buffer temporal para leer cada línea de stdin.
// ============================================================

.section .bss

counts:  .skip  1000 * 8               // tabla de frecuencias
buf:     .skip  BUF_SIZE               // buffer de lectura


// ============================================================
// SECCIÓN 4 — CÓDIGO EJECUTABLE (.text)
// ============================================================

.section .text
.global _start


// ============================================================
// _start — punto de entrada del programa
// ============================================================
// No recibe argumentos. El flujo es:
//   1. Leer líneas de stdin en bucle → acumular en counts[]
//   2. Al llegar EOF, buscar el índice con mayor conteo
//   3. Imprimir el resultado y salir
// ============================================================

_start:


// ------------------------------------------------------------
// FASE 1 — BUCLE DE LECTURA Y CONTEO
// ------------------------------------------------------------
// Registros usados en esta fase:
//   x0  — fd / bytes leídos (syscall read)
//   x1  — puntero al buffer (syscall read)
//   x2  — cantidad de bytes a leer
//   x8  — número de syscall
//   x9  — puntero al buffer para parsing
//   w10 — dígito centenas → valor acumulado del código
//   w11 — dígito decenas
//   w12 — dígito unidades
//   w13 — multiplicador temporal (100 ó 10)
//   x11 — offset en la tabla counts (código × 8)
//   x12 — valor actual de counts[código]
// ------------------------------------------------------------

read_loop:

    // -- syscall read(STDIN, buf, BUF_SIZE) ------------------
    // Devuelve en x0 los bytes leídos.
    // x0 = 0  → EOF
    // x0 < 0  → error
    mov     x0, #STDIN
    adr     x1, buf
    mov     x2, #BUF_SIZE
    mov     x8, #SYS_READ
    svc     #0

    // Si no llegaron bytes, termina la fase de lectura
    cmp     x0, #0
    ble     find_max

    // Necesitamos mínimo 3 bytes (los 3 dígitos del código)
    cmp     x0, #3
    blt     read_loop


    // -- Parsing: ASCII → entero -----------------------------
    // Los primeros 3 bytes de buf son los dígitos del código.
    // Cada dígito ASCII tiene valor numérico = byte - '0' (48).
    // Validamos que cada byte esté en el rango '0'–'9'.
    adr     x9, buf                     // x9 apunta al buffer

    ldrb    w10, [x9]                   // leer dígito centenas
    sub     w10, w10, #'0'              // convertir ASCII → int
    cmp     w10, #9                     // ¿fuera de 0-9?
    bhi     read_loop                   // sí → línea inválida

    ldrb    w11, [x9, #1]              // leer dígito decenas
    sub     w11, w11, #'0'
    cmp     w11, #9
    bhi     read_loop

    ldrb    w12, [x9, #2]              // leer dígito unidades
    sub     w12, w12, #'0'
    cmp     w12, #9
    bhi     read_loop


    // -- Calcular valor entero: d0×100 + d1×10 + d2 ----------
    mov     w13, #100
    mul     w10, w10, w13              // w10 = centenas × 100
    mov     w13, #10
    mul     w11, w11, w13              // w11 = decenas × 10
    add     w10, w10, w11              // w10 += decenas
    add     w10, w10, w12             // w10 += unidades → código


    // -- Validar rango 100–599 --------------------------------
    // Códigos fuera de este rango se descartan silenciosamente.
    cmp     w10, #100
    blt     read_loop
    cmp     w10, #599
    bgt     read_loop


    // -- Incrementar counts[código] --------------------------
    // Dirección = base_counts + código × 8
    // (cada entrada ocupa 8 bytes = tamaño de un registro x)
    adr     x9, counts                 // x9 = base de la tabla
    uxtw    x10, w10                   // extender w10 → x10 (64 bits)
    lsl     x11, x10, #3              // x11 = código × 8 (offset)
    add     x11, x9, x11              // x11 = &counts[código]
    ldr     x12, [x11]                // x12 = valor actual
    add     x12, x12, #1              // incrementar
    str     x12, [x11]                // guardar

    b       read_loop                  // siguiente línea


// ------------------------------------------------------------
// FASE 2 — BÚSQUEDA DEL CÓDIGO MÁS FRECUENTE
// ------------------------------------------------------------
// Iteramos counts[100] hasta counts[599] buscando el máximo.
// En caso de empate gana el código de menor valor numérico
// (el primero encontrado con ese conteo).
//
// Registros usados en esta fase:
//   x19 — índice iterador (100 → 599)
//   x20 — índice del máximo encontrado (0 = ninguno aún)
//   x21 — valor máximo encontrado
//   x22 — base de la tabla counts
//   x23 — offset actual (x19 × 8)
//   x24 — counts[x19] leído
// ------------------------------------------------------------

find_max:
    mov     x19, #100                  // empezar desde código 100
    mov     x20, #0                    // max_code  = ninguno
    mov     x21, #0                    // max_count = 0
    adr     x22, counts                // base de la tabla

find_loop:
    cmp     x19, #599                  // ¿ya revisamos hasta 599?
    bgt     find_done

    // Leer counts[x19]
    lsl     x23, x19, #3              // offset = índice × 8
    ldr     x24, [x22, x23]           // x24 = counts[x19]

    // ¿Este conteo supera el máximo actual?
    cmp     x24, x21
    ble     find_next                  // no → siguiente

    // Actualizar máximo
    mov     x21, x24                   // max_count = counts[x19]
    mov     x20, x19                   // max_code  = x19

find_next:
    add     x19, x19, #1              // siguiente índice
    b       find_loop

find_done:
    // x20 = 0 significa que ningún código tuvo conteo > 0
    cmp     x20, #0
    beq     print_none


// ------------------------------------------------------------
// FASE 3 — SALIDA DEL RESULTADO
// ------------------------------------------------------------
// Convertimos el entero en x20 a 3 dígitos ASCII y lo
// escribimos en stdout junto con el mensaje prefijo.
//
// Conversión entero → ASCII (3 dígitos):
//   d2 (unidades) = código % 10
//   d1 (decenas)  = (código / 10) % 10
//   d0 (centenas) = código / 100
//
// Se usa el stack para almacenar temporalmente los 3 bytes.
// ARM64 requiere que el stack esté alineado a 16 bytes;
// reservamos 8 bytes que es suficiente para 3 bytes de dígitos.
//
// Registros usados:
//   x9  — valor a dividir en cada paso
//   x10 — divisor (10)
//   x11 — cociente de la división
//   x12 — dígito unidades (ASCII)
//   x13 — dígito decenas  (ASCII)
//   x14 — dígito centenas (ASCII)
// ------------------------------------------------------------

print_result:

    // Imprimir mensaje prefijo
    mov     x0, #STDOUT
    adr     x1, msg_most
    mov     x2, #(msg_most_len)
    mov     x8, #SYS_WRITE
    svc     #0

    // Reservar 8 bytes en el stack para los 3 dígitos ASCII
    sub     sp, sp, #8

    mov     x9,  x20                   // x9 = código a convertir
    mov     x10, #10                   // divisor

    // -- Unidades: código % 10 --------------------------------
    udiv    x11, x9, x10               // x11 = código / 10
    msub    x12, x11, x10, x9         // x12 = código - (x11 × 10)
    add     x12, x12, #'0'            // → ASCII

    // -- Decenas: (código / 10) % 10 -------------------------
    mov     x9,  x11                   // x9 = código / 10
    udiv    x11, x9, x10               // x11 = x9 / 10
    msub    x13, x11, x10, x9         // x13 = x9 % 10
    add     x13, x13, #'0'            // → ASCII

    // -- Centenas: código / 100 -------------------------------
    // x11 ya contiene código / 100 del paso anterior
    add     x14, x11, #'0'            // → ASCII

    // Guardar los 3 dígitos en orden d0 d1 d2
    strb    w14, [sp]                  // centenas
    strb    w13, [sp, #1]             // decenas
    strb    w12, [sp, #2]             // unidades

    // Escribir los 3 dígitos
    mov     x0, #STDOUT
    mov     x1, sp
    mov     x2, #3
    mov     x8, #SYS_WRITE
    svc     #0

    // Restaurar el stack
    add     sp, sp, #8

    // Imprimir salto de línea
    mov     x0, #STDOUT
    adr     x1, msg_newline
    mov     x2, #1
    mov     x8, #SYS_WRITE
    svc     #0

    b       exit_ok


// ------------------------------------------------------------
// SIN DATOS VÁLIDOS
// ------------------------------------------------------------
// Se llega aquí si ningún código tuvo frecuencia > 0,
// es decir, stdin estaba vacío o todas las líneas eran
// inválidas.
// ------------------------------------------------------------

print_none:
    mov     x0, #STDOUT
    adr     x1, msg_none
    mov     x2, #(msg_none_len)
    mov     x8, #SYS_WRITE
    svc     #0


// ------------------------------------------------------------
// SALIDA DEL PROCESO
// ------------------------------------------------------------
// syscall exit(0) — código 0 indica éxito al shell.
// ------------------------------------------------------------

exit_ok:
    mov     x0, #0
    mov     x8, #SYS_EXIT
    svc     #0
