# Mini Cloud Log Analyzer — Variante B

**Autor:** Samuel Valentín Alvarado Valenzo  
**Materia:** Lenguajes de Interfaz  
**Institución:** Instituto Tecnológico de Tijuana  
**Entorno:** AWS Ubuntu 24 ARM64  

---

## Descripción

Implementación de un analizador de logs HTTP en **ARM64 Assembly puro**, capaz de procesar códigos de estado HTTP desde `stdin` y determinar cuál es el más frecuente, mostrando también el número de veces que aparece.

```bash
cat data/logs_B.txt | ./analyzer
```

Salida esperada:
```
================================
  Mini Cloud Log Analyzer
  Variante B - Mas frecuente
================================
Codigo mas frecuente : 404 (aparece 5 veces)
================================
```

---

## Objetivo

Demostrar cómo un problema de procesamiento de datos puede resolverse directamente a nivel de arquitectura, utilizando instrucciones ARM64, manejo de registros, acceso a memoria y syscalls de Linux — sin depender de ningún lenguaje de alto nivel.

---

## Tecnologías

- **ARM64 Assembly** (AArch64) — GNU Assembler (GAS)
- **Linux syscalls** — `read`, `write`, `exit`
- **GNU Binutils** — `as`, `ld`
- **GNU Make**
- **AWS Ubuntu 24 ARM64**

---

## 1. Introducción

### ¿Qué es ARM64?

ARM64 (también llamado AArch64) es la arquitectura de 64 bits de los procesadores ARM. Es la arquitectura base de dispositivos móviles, servidores en la nube (AWS Graviton), Apple Silicon y sistemas embebidos modernos. A diferencia de x86, ARM sigue un diseño RISC (Reduced Instruction Set Computer): pocas instrucciones simples, muchos registros de propósito general.

### ¿Por qué usar Assembly?

El ensamblador permite entender cómo funciona la computadora a nivel de registros y memoria. Cada instrucción escrita corresponde directamente a una operación del procesador: no hay compilador que interprete, no hay runtime que gestione memoria. Esto es útil para:

- Entender el modelo de ejecución real de un programa
- Optimizar rutinas críticas en rendimiento
- Comprender cómo los lenguajes de alto nivel se traducen a instrucciones de máquina

---

## 2. Marco Teórico

### Arquitectura ARM64

ARM64 opera con un modelo de carga/almacenamiento: las operaciones aritméticas solo trabajan con registros, y se usan instrucciones dedicadas (`ldr`, `str`) para acceder a memoria.

### Registros principales usados

| Registro | Uso en este proyecto |
|----------|----------------------|
| `x0–x2`  | Argumentos de syscall |
| `x8`     | Número de syscall |
| `x9–x15` | Variables temporales (parsing, conversión) |
| `x19`    | Iterador en búsqueda del máximo |
| `x20`    | Código HTTP ganador |
| `x21`    | Conteo máximo encontrado |
| `x22`    | Base de la tabla `counts` |
| `x25–x27`| Conversión de conteo a ASCII |

### Syscalls Linux ARM64 utilizadas

| Syscall | Número | Uso |
|---------|--------|-----|
| `read`  | 63     | Leer bloques de stdin |
| `write` | 64     | Escribir resultado en stdout |
| `exit`  | 93     | Terminar el proceso |

### ABI (Application Binary Interface)

En ARM64 (AAPCS64):
- Los argumentos de funciones van en `x0–x7`
- El valor de retorno va en `x0`
- El stack debe estar **alineado a 16 bytes** en todo momento
- Los registros `x19–x28` son callee-saved (deben preservarse)

---

## 3. Desarrollo

### Estructura del proyecto

```
cloud-log-analyzer/
├── src/
│   └── analyzer.s       # Código fuente ARM64
├── data/
│   ├── MOCK_DATA.txt    # Los 1000 datos generados con Mockaroo
│   ├── logs_A.txt       # Datos de prueba variante A
│   ├── logs_B.txt       # Datos de prueba variante B
│   └── ...
├── tests/
│   └── test.sh          # Suite de pruebas automáticas
├── Makefile             # Sistema de compilación
└── run.sh               # Script de ejecución
```

### Explicación del archivo `src/analyzer.s`

El programa se divide en 4 secciones y 3 fases de ejecución:

**Secciones:**

- `.rodata` — mensajes de texto para stdout
- `.bss` — tabla de conteos `counts[1000]` y buffer de lectura
- `.text` — código ejecutable

**Fase 1 — Lectura y conteo:**  
Se lee stdin en bloques de 4096 bytes y se procesa byte a byte. Se acumulan dígitos hasta encontrar `\n`. Cuando se completan exactamente 3 dígitos en rango 100–599, se incrementa `counts[código]`. El acceso es O(1) porque el índice del array ES el código HTTP.

**Fase 2 — Búsqueda del máximo:**  
Se itera `counts[100]` hasta `counts[599]` buscando el mayor valor. En caso de empate gana el código de menor valor numérico.

**Fase 3 — Salida:**  
Se convierte el código ganador (entero) a 3 dígitos ASCII mediante división y módulo. El conteo se convierte con división repetida más inversión de dígitos. Todo se escribe en stdout con la syscall `write`.

### Compilación

```bash
make
```

El `Makefile` detecta automáticamente la arquitectura:
- En **ARM64**: usa `as` + `ld` nativos
- En **x86_64**: usa `clang` con target `aarch64-linux-gnu`

---

## 4. Resultados

### Pruebas con `logs_B.txt` (1000 líneas)

```
================================
  Mini Cloud Log Analyzer
  Variante B - Mas frecuente
================================
Codigo mas frecuente : 404 (aparece X veces)
================================
```

### Tabla de pruebas

| Entrada | Esperado | Resultado |
|---------|----------|-----------|
| `logs_B.txt` | Código más frecuente | ✅ Correcto |
| Un solo código `503` | `503 (aparece 1 veces)` | ✅ Correcto |
| Entrada vacía | Sin códigos válidos | ✅ Correcto |
| Líneas inválidas mezcladas | Ignora inválidas | ✅ Correcto |

---

## 5. Análisis

- **Acceso O(1):** usar el código HTTP directamente como índice del array elimina cualquier búsqueda lineal durante el conteo.
- **Lectura por bloques:** leer 4096 bytes por syscall reduce el número de llamadas al sistema comparado con leer línea por línea.
- **Sin dependencias:** el binario resultante solo depende del kernel de Linux, sin libc ni runtime.
- **Alineación de stack:** ARM64 exige alineación a 16 bytes; ignorarlo produce Bus Error, como se comprobó durante el desarrollo.

---

## 6. Conclusiones

- El ensamblador ARM64 obliga a pensar en cada detalle: qué registro guarda qué valor, cómo se alinea el stack, cuándo se sobreescriben registros.
- Problemas como "el conteo siempre da 1" se originaron en que `read` leía todo el archivo pero solo se procesaban los primeros bytes — algo invisible en un lenguaje de alto nivel.
- Para tareas de procesamiento de texto simple, ARM64 Assembly es viable y eficiente, pero requiere disciplina en el manejo de registros.

---

## 7. Autorreflexión

- Mejoraría el manejo de errores: actualmente líneas malformadas se ignoran silenciosamente.
- Agregaría soporte para mostrar el top 3 de códigos más frecuentes.
- La conversión de entero a ASCII podría encapsularse como subrutina reutilizable usando `bl` y `ret`.

---

## 8. Evidencias

### Compilación

```bash
make clean && make
```

### Ejecución con archivo de 1000 líneas

```bash
cat data/MOCK_DATA.txt | ./analyzer
```

### Suite de pruebas

```bash
make test
```

### Git log

```bash
git log --oneline
```

---

## 🎬 Asciinema

[![Demo asciinema](https://asciinema.org/a/et0yz3obYbIdvtKM.svg)](https://asciinema.org/a/et0yz3obYbIdvtKM)

> Grabación de terminal mostrando compilación, pruebas y ejecución en AWS ARM64.

---

## Compilación y uso

```bash
# Compilar
make

# Ejecutar con archivo por defecto (logs_B.txt)
bash run.sh

# O tambien con el archivo de los 1000 datos (MOCK_DATA.txt)

# Ejecutar con cualquier archivo
bash run.sh data/logs_A.txt

# Pruebas automáticas
make test

# Limpiar binarios
make clean
```
