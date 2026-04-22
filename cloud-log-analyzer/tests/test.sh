#!/usr/bin/env bash
# ============================================================
# tests/test.sh — Pruebas automáticas Variante B
# Determinar el código de estado HTTP más frecuente
# ============================================================
# El esperado se calcula dinámicamente desde el propio .txt,
# sin valores hardcodeados. Funciona con cualquier archivo
# de datos que se agregue a data/logs_*.txt
# ============================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# Compilar si no existe el binario
if [[ ! -x ./analyzer ]]; then
  echo "[INFO] Compilando binario..."
  make
fi

# ------------------------------------------------------------
# Función: ejecutar el analyzer según arquitectura del host
# ------------------------------------------------------------
run_analyzer() {
  local input="$1"
  if [[ $(uname -m) == "aarch64" ]]; then
    cat "$input" | ./analyzer
  elif command -v qemu-aarch64 >/dev/null 2>&1; then
    cat "$input" | qemu-aarch64 ./analyzer
  else
    echo "[WARN] Host no ARM64 y qemu-aarch64 no disponible; pruebas omitidas." >&2
    return 99
  fi
}

# ------------------------------------------------------------
# Función: calcular el código más frecuente desde el .txt
# Usa sort | uniq -c para contar, luego toma el mayor.
# En empate gana el código de menor valor numérico.
# ------------------------------------------------------------
calcular_esperado() {
  local file="$1"
  grep -E '^[0-9]{3}$' "$file" \
    | sort | uniq -c \
    | sort -k1,1rn -k2,2n \
    | awk 'NR==1 {print "Most frequent status code: " $2}'
}

# ------------------------------------------------------------
# Suite de pruebas
# ------------------------------------------------------------
echo "============================================================"
echo " Suite de pruebas — Variante B: código HTTP más frecuente"
echo "============================================================"
echo ""

status=0
test_num=0

for f in data/logs_*.txt; do
  test_num=$((test_num + 1))
  base="$(basename "$f")"

  echo "[TEST $test_num] $base"

  # Calcular esperado dinámicamente
  expected="$(calcular_esperado "$f")"

  if [[ -z "$expected" ]]; then
    expected="No valid codes found"
  fi

  # Ejecutar analyzer
  set +e
  output="$(run_analyzer "$f")"
  rc=$?
  set -e

  if [[ $rc -eq 99 ]]; then
    exit 0
  elif [[ $rc -ne 0 ]]; then
    echo "[FAIL] Error al ejecutar analyzer (rc=$rc)"
    status=1
    echo ""
    continue
  fi

  # Comparar
  if [[ "$output" == "$expected" ]]; then
    echo "[OK]   $output"
  else
    echo "[FAIL] Esperado : $expected"
    echo "[FAIL] Obtenido : $output"
    status=1
  fi
  echo ""
done

# -- Pruebas extra con entradas inline -----------------------

test_num=$((test_num + 1))
echo "[TEST $test_num] Entrada vacía"
set +e
output="$(printf '' | ./analyzer)"
set -e
if [[ "$output" == "No valid codes found" ]]; then
  echo "[OK]   No valid codes found"
else
  echo "[FAIL] Esperado : No valid codes found"
  echo "[FAIL] Obtenido : $output"
  status=1
fi
echo ""

test_num=$((test_num + 1))
echo "[TEST $test_num] Líneas inválidas mezcladas con válidas"
set +e
output="$(printf 'abc\n200\nXYZ\n200\n999\n' | ./analyzer)"
set -e
if [[ "$output" == "Most frequent status code: 200" ]]; then
  echo "[OK]   Most frequent status code: 200"
else
  echo "[FAIL] Esperado : Most frequent status code: 200"
  echo "[FAIL] Obtenido : $output"
  status=1
fi
echo ""

test_num=$((test_num + 1))
echo "[TEST $test_num] Un único código (503)"
set +e
output="$(printf '503\n' | ./analyzer)"
set -e
if [[ "$output" == "Most frequent status code: 503" ]]; then
  echo "[OK]   Most frequent status code: 503"
else
  echo "[FAIL] Esperado : Most frequent status code: 503"
  echo "[FAIL] Obtenido : $output"
  status=1
fi
echo ""

# ------------------------------------------------------------
echo "============================================================"
if [[ $status -eq 0 ]]; then
  echo "[RESULTADO] Todas las pruebas pasaron."
else
  echo "[RESULTADO] Hay pruebas fallidas."
fi
echo "============================================================"
exit $status
