#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../versions.env
source "${ROOT}/versions.env"

BUILD_DIR="${ROOT}/build"
DOWNLOAD_DIR="${BUILD_DIR}/downloads"
SOURCE_DIR="${BUILD_DIR}/sources"
OUTPUT_DIR="${BUILD_DIR}/buildroot-output-x86_64-musl"
DIST_DIR="${ROOT}/dist"
TOOLCHAIN_SIGNATURE="x86_64-musl-headers-6.12-v2"
TOOLCHAIN_SIGNATURE_FILE="${OUTPUT_DIR}/.lab-toolchain-signature"

mkdir -p "${HOME}" "${DOWNLOAD_DIR}" "${SOURCE_DIR}"

download() {
    local url="$1"
    local destination="$2"
    local expected_sha256="$3"

    if [[ ! -f "${destination}" ]] \
        || ! echo "${expected_sha256}  ${destination}" | sha256sum --check --status; then
        rm -f "${destination}"
        echo "[*] Downloading ${url}"
        curl --fail --location --retry 3 --output "${destination}" "${url}"
    fi

    echo "${expected_sha256}  ${destination}" | sha256sum --check --status
}

extract_once() {
    local archive="$1"
    local destination="$2"

    if [[ ! -d "${destination}" ]]; then
        tar -xf "${archive}" -C "${SOURCE_DIR}"
    fi
}

BUILDROOT_ARCHIVE="${DOWNLOAD_DIR}/buildroot-${BUILDROOT_VERSION}.tar.xz"
BUILDROOT_SOURCE="${SOURCE_DIR}/buildroot-${BUILDROOT_VERSION}"
TINYEMU_ARCHIVE="${DOWNLOAD_DIR}/tinyemu-${TINYEMU_VERSION}.tar.gz"
TINYEMU_SOURCE="${SOURCE_DIR}/tinyemu-${TINYEMU_VERSION}"
JSLINUX_BASE_URL="https://bellard.org/jslinux"

download \
    "https://buildroot.org/downloads/buildroot-${BUILDROOT_VERSION}.tar.xz" \
    "${BUILDROOT_ARCHIVE}" \
    "${BUILDROOT_SHA256}"
download \
    "https://bellard.org/tinyemu/tinyemu-${TINYEMU_VERSION}.tar.gz" \
    "${TINYEMU_ARCHIVE}" \
    "${TINYEMU_SHA256}"
download \
    "${JSLINUX_BASE_URL}/x86_64emu-wasm.js" \
    "${DOWNLOAD_DIR}/x86_64emu-wasm.js" \
    "${JSLINUX_X86_64_JS_SHA256}"
download \
    "${JSLINUX_BASE_URL}/x86_64emu-wasm.wasm" \
    "${DOWNLOAD_DIR}/x86_64emu-wasm.wasm" \
    "${JSLINUX_X86_64_WASM_SHA256}"
download \
    "${JSLINUX_BASE_URL}/kernel-x86_64-new.bin" \
    "${DOWNLOAD_DIR}/kernel-x86_64-new.bin" \
    "${JSLINUX_KERNEL_X86_64_SHA256}"
download \
    "${JSLINUX_BASE_URL}/jslinux.js" \
    "${DOWNLOAD_DIR}/jslinux.js" \
    "${JSLINUX_LOADER_SHA256}"
download \
    "${JSLINUX_BASE_URL}/term.js" \
    "${DOWNLOAD_DIR}/term.js" \
    "${JSLINUX_TERM_SHA256}"
download \
    "${JSLINUX_BASE_URL}/style.css" \
    "${DOWNLOAD_DIR}/jslinux.css" \
    "${JSLINUX_STYLE_SHA256}"

extract_once "${BUILDROOT_ARCHIVE}" "${BUILDROOT_SOURCE}"
extract_once "${TINYEMU_ARCHIVE}" "${TINYEMU_SOURCE}"

if [[ -d "${OUTPUT_DIR}/host" ]] &&
    [[ "$(cat "${TOOLCHAIN_SIGNATURE_FILE}" 2>/dev/null || true)" != \
        "${TOOLCHAIN_SIGNATURE}" ]]; then
    echo "[*] Toolchain settings changed; cleaning the active Buildroot output"
    make -C "${BUILDROOT_SOURCE}" O="${OUTPUT_DIR}" clean
fi
mkdir -p "${OUTPUT_DIR}"
printf '%s\n' "${TOOLCHAIN_SIGNATURE}" > "${TOOLCHAIN_SIGNATURE_FILE}"

echo "[*] Configuring Buildroot"
make -C "${BUILDROOT_SOURCE}" \
    O="${OUTPUT_DIR}" \
    BR2_EXTERNAL="${ROOT}/buildroot" \
    lab_x86_64_defconfig

# Buildroot does not automatically notice changes inside a local package after
# it has stamped that package as built. Always invalidate the scenario package
# so editing server.c and running `make image` is sufficient.
make -C "${BUILDROOT_SOURCE}" \
    O="${OUTPUT_DIR}" \
    BR2_EXTERNAL="${ROOT}/buildroot" \
    endpoint3-js-dirclean
make -C "${BUILDROOT_SOURCE}" \
    O="${OUTPUT_DIR}" \
    BR2_EXTERNAL="${ROOT}/buildroot" \
    lab-endpoints-dirclean

echo "[*] Building the x86_64 root filesystem"
make -C "${BUILDROOT_SOURCE}" \
    O="${OUTPUT_DIR}" \
    BR2_EXTERNAL="${ROOT}/buildroot"

echo "[*] Building TinyEMU image splitter"
mkdir -p "${BUILD_DIR}/bin"
cc -O2 -Wall -Wextra \
    -DCONFIG_VERSION="\"${TINYEMU_VERSION}\"" \
    -o "${BUILD_DIR}/bin/splitimg" \
    "${TINYEMU_SOURCE}/splitimg.c"

echo "[*] Assembling static web distribution"
rm -rf "${DIST_DIR}"
mkdir -p "${DIST_DIR}/root-x86_64-${LAB_IMAGE_VERSION}"

cp "${DOWNLOAD_DIR}/kernel-x86_64-new.bin" \
    "${DIST_DIR}/kernel-x86_64-lab-${LAB_IMAGE_VERSION}.bin"
cp "${DOWNLOAD_DIR}/x86_64emu-wasm.js" "${DIST_DIR}/"
cp "${DOWNLOAD_DIR}/x86_64emu-wasm.wasm" "${DIST_DIR}/"
cp "${DOWNLOAD_DIR}/term.js" "${DIST_DIR}/"
cp "${DOWNLOAD_DIR}/jslinux.js" "${DIST_DIR}/"
cp "${DOWNLOAD_DIR}/jslinux.css" "${DIST_DIR}/"
cp -R "${ROOT}/web/." "${DIST_DIR}/"
sed -i "s/__LAB_IMAGE_VERSION__/${LAB_IMAGE_VERSION}/g" \
    "${DIST_DIR}/challenge.html"
printf 'window.LAB_IMAGE_VERSION = "%s";\n' "${LAB_IMAGE_VERSION}" \
    > "${DIST_DIR}/image-version-${LAB_IMAGE_VERSION}.js"

"${BUILD_DIR}/bin/splitimg" \
    "${OUTPUT_DIR}/images/rootfs.ext2" \
    "${DIST_DIR}/root-x86_64-${LAB_IMAGE_VERSION}" \
    256

cat > "${DIST_DIR}/root-x86_64-${LAB_IMAGE_VERSION}.cfg" <<EOF
{
    version: 1,
    machine: "pc",
    memory_size: 512,
    kernel: "kernel-x86_64-lab-${LAB_IMAGE_VERSION}.bin",
    cmdline: "loglevel=3 console=hvc0 root=/dev/vda rw",
    drive0: { file: "root-x86_64-${LAB_IMAGE_VERSION}/blk.txt" },
}
EOF

cat > "${DIST_DIR}/build-info.txt" <<EOF
Lab image ${LAB_IMAGE_VERSION}
Buildroot ${BUILDROOT_VERSION} x86_64/musl
JSLinux x86_64 runtime ${JSLINUX_RELEASE}
TinyEMU ${TINYEMU_VERSION}
Scenarios endpoint1..endpoint4
EOF

echo "[+] Built ${DIST_DIR}"
echo "[+] Run: make serve"
