#!/usr/bin/env bash
set -euo pipefail

# Usage: ./tools/build-rust.sh <VERSION> <ARCH>
#   VERSION: e.g. v2
#   ARCH:    amd64 | arm64

SVC="${1}"
VER="${2:-v2}"
ARCH_IN="${3:-amd64}"

ROOT="$(git rev-parse --show-toplevel)"
SRC="${ROOT}/src/endpoints/${SVC}-rs"
OUT="${ROOT}/artifacts/${VER}"
BIN_NAME="${SVC}"

# Map ARCH -> Rust target triples (musl preferred, glibc as fallback)
case "${ARCH_IN}" in
  amd64)
    MUSL_TARGET="x86_64-unknown-linux-musl"
    GNU_TARGET="x86_64-unknown-linux-gnu"
    ART_ARCH="amd64"
    ;;
  arm64|aarch64)
    export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=aarch64-linux-gnu-gcc
    export CC_aarch64_unknown_linux_gnu=aarch64-linux-gnu-gcc
    MUSL_TARGET="unavailable"
    GNU_TARGET="aarch64-unknown-linux-gnu"
    ART_ARCH="arm64"
    ;;
  *)
    echo "[!] Unsupported ARCH: ${ARCH_IN}. Use amd64 or arm64."
    exit 1
    ;;
esac

mkdir -p "${OUT}"

need_rust_target() {
  local tgt="$1"
  if ! rustup target list --installed | grep -qx "${tgt}"; then
    echo "[*] Adding Rust target ${tgt}"
    rustup target add "${tgt}" || return 1
  fi
}

build_for_target() {
  local tgt="$1"
  echo "[*] Building ${BIN_NAME} for ${tgt}"

  # For musl, try to encourage fully-static linking where possible.
  local rustflags_backup="${RUSTFLAGS-}"
  if [[ "${tgt}" == *"-musl" ]]; then
    export RUSTFLAGS="${RUSTFLAGS-} -C target-feature=+crt-static"
  fi

  ( cd "${SRC}" && cargo build --release --target "${tgt}" ) || {
    # restore RUSTFLAGS before returning failure
    export RUSTFLAGS="${rustflags_backup-}"
    return 1
  }

  # restore RUSTFLAGS after success, to avoid contaminating other builds
  export RUSTFLAGS="${rustflags_backup-}"
  return 0
}

ART_BIN="${OUT}/${BIN_NAME}_linux_${ART_ARCH}"
ART_TAR="${OUT}/${BIN_NAME}_linux_${ART_ARCH}.tar.gz"

# Try MUSL first, then GLIBC
TARGET_USED=""
if [[ "$MUSL_TARGET" != "unavailable" ]] && need_rust_target "${MUSL_TARGET}" && build_for_target "${MUSL_TARGET}"; then
  TARGET_USED="${MUSL_TARGET}"
  SRC_BIN="${SRC}/target/${MUSL_TARGET}/release/${BIN_NAME}"
  echo "[*] Built successfully with MUSL target: ${TARGET_USED}"
else
  echo "[!] MUSL build failed or target unavailable. Falling back to glibc (${GNU_TARGET})"
  need_rust_target "${GNU_TARGET}" || true
  build_for_target "${GNU_TARGET}"
  TARGET_USED="${GNU_TARGET}"
  SRC_BIN="${SRC}/target/${GNU_TARGET}/release/${BIN_NAME}"
  echo "[*] Built successfully with glibc target: ${TARGET_USED}"
fi

# Stage and package
cp -f "${SRC_BIN}" "${ART_BIN}"
chmod +x "${ART_BIN}"
tar -C "${OUT}" -czf "${ART_TAR}" "$(basename "${ART_BIN}")"
rm -f "${ART_BIN}"

# Recompute checksums for the entire artifacts version dir
( cd "${OUT}" && sha256sum *.tar.gz > sha256sums.txt )

echo "[*] Artifact: ${ART_TAR}"
echo "[*] Target used: ${TARGET_USED}"
echo "[*] Checksums: ${OUT}/sha256sums.txt"

