#!/usr/bin/env bash
set -euo pipefail

VER="${1:-v1}"
ARCH="${2:-amd64}"
ROOT="$(git rev-parse --show-toplevel)"
OUT="${ROOT}/artifacts/${VER}"
mkdir -p "$OUT"

build_one () {
  local name="$1" src="$2"
  local bin="${OUT}/${name}_linux_${ARCH}"
  echo "[*] $name → ${bin}"
  CGO_ENABLED=0 GOOS=linux GOARCH="${ARCH}" \
    go build -trimpath -ldflags="-s -w" -o "${bin}" "${src}"
  tar -C "${OUT}" -czf "${OUT}/${name}_linux_${ARCH}.tar.gz" "$(basename "${bin}")"
  rm -f "${bin}"
}

build_one dashboard  "${ROOT}/src/dashboard/main.go"
#build_one endpoint2  "${ROOT}/src/endpoints/endpoint2/main.go"
#build_one endpoint3  "${ROOT}/src/endpoints/endpoint3/main.go"
#build_one endpoint4  "${ROOT}/src/endpoints/endpoint4/main.go"

( cd "${OUT}" && sha256sum *.tar.gz > sha256sums.txt )
echo "[*] artifacts -> ${OUT}"
