#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../versions.env
source "${ROOT}/versions.env"

BUILD_DIR="${ROOT}/build"
DOWNLOAD_DIR="${BUILD_DIR}/downloads"
SOURCE_DIR="${BUILD_DIR}/sources"
SYSTEM_OUTPUT_DIR="${BUILD_DIR}/buildroot-output-x86_64-musl"
DATABASE_OUTPUT_DIR="${BUILD_DIR}/buildroot-output-x86_64-musl-database"
DIST_DIR="${ROOT}/dist"

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

prepare_output() {
    local output_dir="$1"
    local toolchain_signature="$2"
    local defconfig="$3"
    shift 3
    local signature_file="${output_dir}/.lab-toolchain-signature"
    local package

    if [[ -d "${output_dir}/host" ]] &&
        [[ "$(cat "${signature_file}" 2>/dev/null || true)" != \
            "${toolchain_signature}" ]]; then
        echo "[*] Toolchain settings changed; cleaning ${output_dir}"
        make -C "${BUILDROOT_SOURCE}" O="${output_dir}" clean
    fi
    mkdir -p "${output_dir}"
    printf '%s\n' "${toolchain_signature}" > "${signature_file}"

    echo "[*] Configuring ${defconfig}"
    make -C "${BUILDROOT_SOURCE}" \
        O="${output_dir}" \
        BR2_EXTERNAL="${ROOT}/buildroot" \
        "${defconfig}"

    # Local packages are not automatically rebuilt after their source changes.
    for package in "$@"; do
        make -C "${BUILDROOT_SOURCE}" \
            O="${output_dir}" \
            BR2_EXTERNAL="${ROOT}/buildroot" \
            "${package}-dirclean"
    done

    echo "[*] Building ${defconfig}"
    make -C "${BUILDROOT_SOURCE}" \
        O="${output_dir}" \
        BR2_EXTERNAL="${ROOT}/buildroot"
}

prepare_output \
    "${SYSTEM_OUTPUT_DIR}" \
    "x86_64-musl-headers-6.12-v2" \
    lab_x86_64_defconfig \
    endpoint3-js \
    lab-endpoints

prepare_output \
    "${DATABASE_OUTPUT_DIR}" \
    "x86_64-musl-cxx-headers-6.12-v1" \
    lab_database_x86_64_defconfig \
    database-challenge

echo "[*] Building TinyEMU image splitter"
mkdir -p "${BUILD_DIR}/bin"
cc -O2 -Wall -Wextra \
    -DCONFIG_VERSION="\"${TINYEMU_VERSION}\"" \
    -o "${BUILD_DIR}/bin/splitimg" \
    "${TINYEMU_SOURCE}/splitimg.c"

echo "[*] Assembling static web distribution"
rm -rf "${DIST_DIR}"
mkdir -p "${DIST_DIR}/root-x86_64-${LAB_IMAGE_VERSION}"
mkdir -p \
    "${DIST_DIR}/root-x86_64-database-${LAB_DATABASE_IMAGE_VERSION}"

cp "${DOWNLOAD_DIR}/kernel-x86_64-new.bin" \
    "${DIST_DIR}/kernel-x86_64-lab-${JSLINUX_RELEASE}.bin"
cp "${DOWNLOAD_DIR}/x86_64emu-wasm.js" "${DIST_DIR}/"
cp "${DOWNLOAD_DIR}/x86_64emu-wasm.wasm" "${DIST_DIR}/"
cp "${DOWNLOAD_DIR}/term.js" "${DIST_DIR}/"
cp "${DOWNLOAD_DIR}/jslinux.js" "${DIST_DIR}/"
cp "${DOWNLOAD_DIR}/jslinux.css" "${DIST_DIR}/"
cp -R "${ROOT}/web/." "${DIST_DIR}/"
sed -i "s/__LAB_IMAGE_VERSION__/${LAB_IMAGE_VERSION}/g" \
    "${DIST_DIR}/challenge.html"
sed -i "s/__LAB_DATABASE_IMAGE_VERSION__/${LAB_DATABASE_IMAGE_VERSION}/g" \
    "${DIST_DIR}/challenge.html"
cat > \
    "${DIST_DIR}/image-versions-${LAB_IMAGE_VERSION}-${LAB_DATABASE_IMAGE_VERSION}.js" <<EOF
window.LAB_IMAGE_VERSIONS = {
  system: "${LAB_IMAGE_VERSION}",
  database: "${LAB_DATABASE_IMAGE_VERSION}"
};
EOF

"${BUILD_DIR}/bin/splitimg" \
    "${SYSTEM_OUTPUT_DIR}/images/rootfs.ext2" \
    "${DIST_DIR}/root-x86_64-${LAB_IMAGE_VERSION}" \
    256
"${BUILD_DIR}/bin/splitimg" \
    "${DATABASE_OUTPUT_DIR}/images/rootfs.ext2" \
    "${DIST_DIR}/root-x86_64-database-${LAB_DATABASE_IMAGE_VERSION}" \
    256

cat > "${DIST_DIR}/root-x86_64-${LAB_IMAGE_VERSION}.cfg" <<EOF
{
    version: 1,
    machine: "pc",
    memory_size: 512,
    kernel: "kernel-x86_64-lab-${JSLINUX_RELEASE}.bin",
    cmdline: "loglevel=3 console=hvc0 root=/dev/vda rw",
    drive0: { file: "root-x86_64-${LAB_IMAGE_VERSION}/blk.txt" },
}
EOF

cat > \
    "${DIST_DIR}/root-x86_64-database-${LAB_DATABASE_IMAGE_VERSION}.cfg" <<EOF
{
    version: 1,
    machine: "pc",
    memory_size: 512,
    kernel: "kernel-x86_64-lab-${JSLINUX_RELEASE}.bin",
    cmdline: "loglevel=3 console=hvc0 root=/dev/vda rw",
    drive0: { file: "root-x86_64-database-${LAB_DATABASE_IMAGE_VERSION}/blk.txt" },
}
EOF

cat > "${DIST_DIR}/build-info.txt" <<EOF
System image ${LAB_IMAGE_VERSION}
Database image ${LAB_DATABASE_IMAGE_VERSION}
Buildroot ${BUILDROOT_VERSION} x86_64/musl
JSLinux x86_64 runtime ${JSLINUX_RELEASE}
TinyEMU ${TINYEMU_VERSION}
System scenarios endpoint1..endpoint4
Database scenarios database1
EOF

echo "[+] Built ${DIST_DIR}"
echo "[+] Run: make serve"
