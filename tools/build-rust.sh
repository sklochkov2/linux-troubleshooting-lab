#!/usr/bin/env bash
set -euo pipefail

VER="${1:-v2}"
ARCH="${2:-amd64}"      # x86_64
ROOT="$(git rev-parse --show-toplevel)"
SRC="${ROOT}/src/endpoints/endpoint2-rs"
OUT="${ROOT}/artifacts/${VER}"
mkdir -p "${OUT}"

# Build static-ish with musl if available; else fall back to glibc
TARGET="x86_64-unknown-linux-musl"
if ! rustup target list --installed | grep -q "${TARGET}"; then
  echo "[*] Adding musl target ${TARGET}"
  rustup target add "${TARGET}"
fi

echo "[*] Building endpoint2 (Rust) for ${TARGET}"
( cd "${SRC}" && cargo build --release --target "${TARGET}" )

BIN="${SRC}/target/${TARGET}/release/endpoint2"
OUTBIN="${OUT}/endpoint2_linux_${ARCH}"
cp "${BIN}" "${OUTBIN}"

echo "[*] Packaging ${OUTBIN}"
tar -C "${OUT}" -czf "${OUT}/endpoint2_linux_${ARCH}.tar.gz" "$(basename "${OUTBIN}")"
rm -f "${OUTBIN}"

# If you also build Go artifacts, ensure sha file includes all tarballs
( cd "${OUT}" && sha256sum *.tar.gz > sha256sums.txt )
echo "[*] Artifacts in ${OUT}"
