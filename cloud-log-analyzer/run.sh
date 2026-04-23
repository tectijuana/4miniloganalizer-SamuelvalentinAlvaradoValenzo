#!/usr/bin/env bash
# ============================================================
# run.sh — Ejecutar el analyzer con cualquier archivo de logs
# Uso: bash run.sh data/logs_B.txt
#      bash run.sh data/logs_A.txt
# Si no se pasa archivo, usa logs_B.txt por defecto (Variante B)
# ============================================================
set -euo pipefail

INPUT="${1:-data/logs_B.txt}"

if [[ ! -f "$INPUT" ]]; then
  echo "[ERROR] Archivo no encontrado: $INPUT" >&2
  exit 1
fi

if [[ ! -x ./analyzer ]]; then
  echo "[INFO] Compilando..."
  make
fi

if [[ $(uname -m) == "aarch64" ]]; then
  cat "$INPUT" | ./analyzer
elif command -v qemu-aarch64 >/dev/null 2>&1; then
  cat "$INPUT" | qemu-aarch64 ./analyzer
else
  echo "[ERROR] Host no ARM64 y qemu-aarch64 no disponible." >&2
  exit 1
fi
