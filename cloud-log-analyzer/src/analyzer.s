// ============================================================
// PRÁCTICA 4.2 — MINI CLOUD LOG ANALYZER
// ============================================================
// Variante   : B — Código de estado HTTP más frecuente
// Arquitectura: ARM64 (AArch64) — GNU Assembler (GAS)
// Sistema op. : Linux (Ubuntu ARM64)
// Entrada     : stdin — un código HTTP por línea
// Salida      : stdout — código con mayor frecuencia y conteo
//
//Nombre: Samuel Valentin Alvarado Valenzo
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
// Se invocan con la instrucción svc #0
// El número de syscall va en el registro x8.
// ============================================================

.equ SYS_READ,   63          // leer bytes desde un descriptor
.equ SYS_WRITE,  64          // escribir bytes a un descriptor
.equ SYS_EXIT,   93          // terminar el proceso

.equ STDIN,       0          // descriptor: entrada estándar
.equ STDOUT,      1          // descriptor: salida estándar

.equ BUF_SIZE,  4096         // buffer grande para leer bloques


// ============================================================
// SECCIÓN 2 — DATOS DE SÓLO LECTURA (.rodata)
// ============================================================

.section .rodata

msg_header:
    .ascii  "================================\n"
    .ascii  "  Mini Cloud Log Analyzer\n"
    .ascii  "  Variante B - Mas frecuente\n"
    .ascii  "================================\n"
msg_header_len = . - msg_header

msg_code:
    .ascii  "Codigo mas frecuente : "
msg_code_len = . - msg_code

msg_aparece:
    .ascii  " (aparece "
msg_aparece_len = . - msg_aparece

msg_veces:
    .ascii  " veces)\n"
msg_veces_len = . - msg_veces

msg_footer:
    .ascii  "================================\n"
msg_footer_len = . - msg_footer

msg_none:
    .ascii  "Sin codigos validos en la entrada.\n"
msg_none_len = . - msg_none


// ============================================================
// SECCIÓN 3 — DATOS NO INICIALIZADOS (.bss)
// ============================================================
// counts[1000]: array indexado por código HTTP (100-599).
//   El índice ES el código → acceso O(1).
//   El SO garantiza que inicia en cero.
// buf[BUF_SIZE]: buffer de lectura de stdin.
// ============================================================

.section .bss

counts:  .skip  1000 * 8
buf:     .skip  BUF_SIZE


// ============================================================
// SECCIÓN 4 — CÓDIGO EJECUTABLE (.text)
// ============================================================

.section .text
.global _start


// ============================================================
// _start — punto de entrada del programa
// ============================================================
// Flujo:
//   1. Leer bloques de stdin → procesar byte a byte
//   2. Acumular dígitos por línea → cuando llega '\n' o EOF
//      convertir y contar el código
//   3. Buscar el índice con mayor conteo
//   4. Imprimir resultado formateado
// ============================================================

_start:

// ------------------------------------------------------------
// FASE 1 — LECTURA Y CONTEO
// ------------------------------------------------------------
// Se lee stdin en bloques de BUF_SIZE bytes.
// Se itera byte a byte acumulando dígitos.
// Cuando se encuentra '\n' o fin de buffer se procesa
// la línea acumulada.
//
// Registros usados:
//   x19 — bytes leídos en el bloque actual
//   x20 — índice del byte actual en el buffer
//   x21 — acumulador de dígitos de la línea actual
//   x22 — cantidad de dígitos acumulados
//   x23 — byte actual leído
//   x24 — puntero base al buffer
// ------------------------------------------------------------

    // Inicializar acumuladores de línea
    mov     x21, #0                // acumulador de valor
    mov     x22, #0                // contador de dígitos

read_block:
    // -- syscall read(STDIN, buf, BUF_SIZE) ------------------
    mov     x0, #STDIN
    adr     x1, buf
    mov     x2, #BUF_SIZE
    mov     x8, #SYS_READ
    svc     #0

    // x0 = bytes leídos
    cmp     x0, #0
    ble     flush_last             // EOF → procesar última línea

    mov     x19, x0               // x19 = bytes leídos
    mov     x20, #0               // x20 = índice en buffer
    adr     x24, buf              // x24 = base del buffer

byte_loop:
    cmp     x20, x19
    bge     read_block             // procesamos todo el bloque

    // Leer byte actual
    ldrb    w23, [x24, x20]
    add     x20, x20, #1

    // ¿Es salto de línea o retorno de carro?
    cmp     w23, #'\n'
    beq     process_line
    cmp     w23, #'\r'
    beq     process_line

    // ¿Es dígito ASCII '0'–'9'?
    sub     w23, w23, #'0'
    cmp     w23, #9
    bhi     byte_loop              // no es dígito, ignorar

    // Acumular dígito: valor = valor * 10 + dígito
    mov     x9, #10
    mul     x21, x21, x9
    add     x21, x21, x23
    add     x22, x22, #1

    b       byte_loop

process_line:
    // Solo procesar si acumulamos exactamente 3 dígitos
    cmp     x22, #3
    bne     reset_line

    // Validar rango 100–599
    cmp     x21, #100
    blt     reset_line
    cmp     x21, #599
    bgt     reset_line

    // -- Incrementar counts[código] --------------------------
    // Dirección = &counts + código × 8
    adr     x9, counts
    lsl     x10, x21, #3          // offset = código × 8
    add     x10, x9, x10          // &counts[código]
    ldr     x11, [x10]            // valor actual
    add     x11, x11, #1
    str     x11, [x10]            // counts[código]++

reset_line:
    // Reiniciar acumuladores para la siguiente línea
    mov     x21, #0
    mov     x22, #0
    b       byte_loop

flush_last:
    // Procesar última línea si no terminó con '\n'
    cmp     x22, #3
    bne     find_max
    cmp     x21, #100
    blt     find_max
    cmp     x21, #599
    bgt     find_max

    adr     x9, counts
    lsl     x10, x21, #3
    add     x10, x9, x10
    ldr     x11, [x10]
    add     x11, x11, #1
    str     x11, [x10]


// ------------------------------------------------------------
// FASE 2 — BÚSQUEDA DEL CÓDIGO MÁS FRECUENTE
// ------------------------------------------------------------
// Itera counts[100..599] y guarda el índice con mayor valor.
// En empate gana el código de menor valor numérico.
//
// Registros usados:
//   x19 — iterador (100 → 599)
//   x20 — índice del máximo (0 = ninguno encontrado)
//   x21 — conteo máximo encontrado
//   x22 — base de la tabla counts
//   x23 — offset actual (x19 × 8)
//   x24 — counts[x19] leído
// ------------------------------------------------------------

find_max:
    mov     x19, #100
    mov     x20, #0
    mov     x21, #0
    adr     x22, counts

find_loop:
    cmp     x19, #599
    bgt     find_done

    lsl     x23, x19, #3
    ldr     x24, [x22, x23]

    cmp     x24, x21
    ble     find_next

    mov     x21, x24               // max_count = counts[x19]
    mov     x20, x19               // max_code  = x19

find_next:
    add     x19, x19, #1
    b       find_loop

find_done:
    cmp     x20, #0
    beq     print_none


// ------------------------------------------------------------
// FASE 3 — IMPRIMIR RESULTADO
// ------------------------------------------------------------
// x20 = código ganador
// x21 = conteo del ganador
//
// Conversión int → ASCII:
//   Código  : 3 dígitos fijos (centenas, decenas, unidades)
//   Conteo  : dígitos variables con división repetida + inversión
//
// Registros usados:
//   x9–x14 — conversión del código
//   x15    — puntero al stack para dígitos del conteo
//   x25    — contador de dígitos del conteo
//   x26    — índice izquierdo para inversión
//   x27    — índice derecho para inversión
// ------------------------------------------------------------

print_result:

    // -- Header ----------------------------------------------
    mov     x0, #STDOUT
    adr     x1, msg_header
    mov     x2, #(msg_header_len)
    mov     x8, #SYS_WRITE
    svc     #0

    // -- "Codigo mas frecuente : " ---------------------------
    mov     x0, #STDOUT
    adr     x1, msg_code
    mov     x2, #(msg_code_len)
    mov     x8, #SYS_WRITE
    svc     #0

    // -- Convertir código (x20) → 3 dígitos ASCII ------------
    // Stack alineado a 16 bytes (requisito ARM64)
    sub     sp, sp, #16

    mov     x9,  x20
    mov     x10, #10

    udiv    x11, x9, x10
    msub    x12, x11, x10, x9     // unidades
    add     x12, x12, #'0'

    mov     x9,  x11
    udiv    x11, x9, x10
    msub    x13, x11, x10, x9     // decenas
    add     x13, x13, #'0'

    add     x14, x11, #'0'        // centenas

    strb    w14, [sp]
    strb    w13, [sp, #1]
    strb    w12, [sp, #2]

    mov     x0, #STDOUT
    mov     x1, sp
    mov     x2, #3
    mov     x8, #SYS_WRITE
    svc     #0

    add     sp, sp, #16

    // -- " (aparece " ----------------------------------------
    mov     x0, #STDOUT
    adr     x1, msg_aparece
    mov     x2, #(msg_aparece_len)
    mov     x8, #SYS_WRITE
    svc     #0

    // -- Convertir conteo (x21) → ASCII ----------------------
    // División repetida: extrae dígitos en orden inverso,
    // luego se invierten para imprimir correctamente.
    // x25 se usa (no x19) para no pisar registros de fase 2.
    sub     sp, sp, #16

    mov     x9,  x21
    mov     x10, #10
    mov     x15, sp
    mov     x25, #0

count_digits_loop:
    udiv    x11, x9, x10
    msub    x12, x11, x10, x9     // dígito = x9 % 10
    add     x12, x12, #'0'
    strb    w12, [x15, x25]
    add     x25, x25, #1
    mov     x9,  x11
    cmp     x9,  #0
    bne     count_digits_loop

    // Invertir dígitos
    mov     x26, #0
    sub     x27, x25, #1

reverse_loop:
    cmp     x26, x27
    bge     reverse_done
    ldrb    w11, [x15, x26]
    ldrb    w12, [x15, x27]
    strb    w12, [x15, x26]
    strb    w11, [x15, x27]
    add     x26, x26, #1
    sub     x27, x27, #1
    b       reverse_loop

reverse_done:
    mov     x0, #STDOUT
    mov     x1, x15
    mov     x2, x25
    mov     x8, #SYS_WRITE
    svc     #0

    add     sp, sp, #16

    // -- " veces)\n" -----------------------------------------
    mov     x0, #STDOUT
    adr     x1, msg_veces
    mov     x2, #(msg_veces_len)
    mov     x8, #SYS_WRITE
    svc     #0

    // -- Footer ----------------------------------------------
    mov     x0, #STDOUT
    adr     x1, msg_footer
    mov     x2, #(msg_footer_len)
    mov     x8, #SYS_WRITE
    svc     #0

    b       exit_ok


// ------------------------------------------------------------
// SIN DATOS VÁLIDOS
// ------------------------------------------------------------

print_none:
    mov     x0, #STDOUT
    adr     x1, msg_header
    mov     x2, #(msg_header_len)
    mov     x8, #SYS_WRITE
    svc     #0

    mov     x0, #STDOUT
    adr     x1, msg_none
    mov     x2, #(msg_none_len)
    mov     x8, #SYS_WRITE
    svc     #0

    mov     x0, #STDOUT
    adr     x1, msg_footer
    mov     x2, #(msg_footer_len)
    mov     x8, #SYS_WRITE
    svc     #0


// ------------------------------------------------------------
// SALIDA DEL PROCESO
// ------------------------------------------------------------

exit_ok:
    mov     x0, #0
    mov     x8, #SYS_EXIT
    svc     #0
