#!/usr/bin/env bash
#
# build.sh - Build LineageOS 17.1 (Android 10) untuk OPPO A37 / A37f / A37fw
#
# Device : OPPO A37 (codename LineageOS: A37), Qualcomm MSM8916 / Snapdragon 410
# Source : https://github.com/LineageOS/android -b lineage-17.1
#
# Pemakaian:
#   ./build.sh                  # init + sync + build penuh
#   ./build.sh --no-sync        # langsung build, lewati repo sync
#   ./build.sh --sync-only      # cuma siapkan source, jangan build
#   ./build.sh --recovery       # build recovery.img saja
#   ./build.sh --clean          # hapus out/ device ini dulu, lalu build
#   BUILD_DIR=/mnt/ssd/los17 ./build.sh
#
# Host tanpa python2 (Ubuntu 24.04 dst.) otomatis dipatch: scripts/gcc-wrapper.py
# milik kernel 3.10 diganti versi python3 dari patches/gcc-wrapper.py.
#

set -euo pipefail

DEVICE="A37"
BRANCH="lineage-17.1"
MANIFEST_URL="https://github.com/LineageOS/android.git"
BUILD_DIR="${BUILD_DIR:-$HOME/los17}"
JOBS="${JOBS:-$(nproc --all)}"
CCACHE_SIZE="${CCACHE_SIZE:-50G}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_MANIFEST="$SCRIPT_DIR/A37.xml"
PY3_WRAPPER="$SCRIPT_DIR/patches/gcc-wrapper.py"
PY3_MARKER="LOS17-A37-PY3-WRAPPER"
KERNEL_PATH="kernel/oppo/msm8939"

# Diisi oleh check_host: "python2" (pakai wrapper asli) atau "python3" (perlu patch)
KERNEL_PY_MODE=""

DO_SYNC=1
DO_BUILD=1
DO_CLEAN=0
BUILD_TARGET="rom"

red()   { printf '\033[1;31m%s\033[0m\n' "$*"; }
green() { printf '\033[1;32m%s\033[0m\n' "$*"; }
info()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die()   { red "ERROR: $*"; exit 1; }

usage() {
    sed -n '3,18p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-sync)   DO_SYNC=0 ;;
        --sync-only) DO_BUILD=0 ;;
        --clean)     DO_CLEAN=1 ;;
        --recovery)  BUILD_TARGET="recovery" ;;
        --jobs|-j)   JOBS="$2"; shift ;;
        --dir)       BUILD_DIR="$2"; shift ;;
        --help|-h)   usage ;;
        *)           die "Opsi tidak dikenal: $1 (pakai --help)" ;;
    esac
    shift
done

# ---------------------------------------------------------------------------
# 1. Cek host
# ---------------------------------------------------------------------------
check_host() {
    info "Memeriksa host build"

    command -v git >/dev/null  || die "git belum terpasang"
    command -v repo >/dev/null || die "repo tool belum ada. Install:
    mkdir -p ~/bin && curl https://storage.googleapis.com/git-repo-downloads/repo > ~/bin/repo
    chmod a+x ~/bin/repo && export PATH=~/bin:\$PATH"

    # Kernel 3.10 memakai scripts/gcc-wrapper.py dengan shebang python2.
    # Tanpa binary python2 build kernel berhenti dengan:
    #   env: 'python2': No such file or directory
    # Kalau host tidak punya python2 (Ubuntu 24.04 sudah tidak menyediakannya),
    # wrapper itu diganti versi python3 dari patches/ oleh patch_kernel_python().
    if command -v python2 >/dev/null; then
        KERNEL_PY_MODE="python2"
        info "python2 tersedia — scripts/gcc-wrapper.py dipakai apa adanya"
    elif command -v python3 >/dev/null; then
        KERNEL_PY_MODE="python3"
        info "python2 tidak ada — wrapper kernel akan diganti versi python3"
    else
        die "Butuh python2 atau python3 di host. Install salah satu:
    sudo apt install python3
    Catatan: JANGAN pasang python-is-python2, itu merusak repo tool."
    fi

    git config --get user.email >/dev/null 2>&1 || die "git user.email belum diset:
    git config --global user.email \"kamu@example.com\"
    git config --global user.name  \"Nama Kamu\""

    local ram_gb disk_gb
    ram_gb=$(awk '/MemTotal/ {printf "%d", $2/1024/1024}' /proc/meminfo)
    if [[ "$ram_gb" -lt 8 ]]; then
        red "PERINGATAN: RAM ${ram_gb}GB. Di bawah 8GB linker sering kena OOM; tambah swap 16GB."
    fi

    mkdir -p "$BUILD_DIR"
    disk_gb=$(df -BG --output=avail "$BUILD_DIR" | tail -1 | tr -dc '0-9')
    if [[ "$disk_gb" -lt 200 ]]; then
        red "PERINGATAN: sisa disk ${disk_gb}GB di $BUILD_DIR. Source + out butuh ~200GB."
    fi

    if command -v ccache >/dev/null; then
        export USE_CCACHE=1
        export CCACHE_EXEC="$(command -v ccache)"
        export CCACHE_DIR="${CCACHE_DIR:-$HOME/.ccache}"
        ccache -M "$CCACHE_SIZE" >/dev/null
        info "ccache aktif (max $CCACHE_SIZE, dir $CCACHE_DIR)"
    else
        red "PERINGATAN: ccache tidak ada, build ulang akan jauh lebih lambat."
    fi

    green "Host OK (jobs=$JOBS, dir=$BUILD_DIR)"
}

# ---------------------------------------------------------------------------
# 2. Init source + local manifest
# ---------------------------------------------------------------------------
init_source() {
    cd "$BUILD_DIR"

    if [[ ! -d .repo ]]; then
        info "repo init $BRANCH (sekali saja, agak lama)"
        repo init -u "$MANIFEST_URL" -b "$BRANCH" --no-clone-bundle
    else
        info "Source tree sudah ada di $BUILD_DIR, lewati repo init"
    fi

    [[ -f "$LOCAL_MANIFEST" ]] || die "A37.xml tidak ditemukan di $SCRIPT_DIR"
    mkdir -p .repo/local_manifests
    cp "$LOCAL_MANIFEST" .repo/local_manifests/A37.xml
    info "Local manifest terpasang: .repo/local_manifests/A37.xml"
}

# ---------------------------------------------------------------------------
# 3. Sync
# ---------------------------------------------------------------------------
sync_source() {
    cd "$BUILD_DIR"
    info "repo sync (~60GB, sabar). Kalau putus, jalankan ulang script ini."
    repo sync -c --no-clone-bundle --no-tags --force-sync -j"$JOBS"
    green "Sync selesai"
}

# ---------------------------------------------------------------------------
# 4. Patch wrapper kernel untuk host tanpa python2
# ---------------------------------------------------------------------------
patch_kernel_python() {
    local wrapper="$BUILD_DIR/$KERNEL_PATH/scripts/gcc-wrapper.py"

    [[ "$KERNEL_PY_MODE" == "python3" ]] || return 0

    if [[ ! -f "$wrapper" ]]; then
        red "PERINGATAN: $KERNEL_PATH/scripts/gcc-wrapper.py belum ada, lewati patch (sync dulu?)"
        return 0
    fi

    if grep -q "$PY3_MARKER" "$wrapper"; then
        info "Wrapper kernel sudah versi python3"
        return 0
    fi

    [[ -f "$PY3_WRAPPER" ]] || die "patches/gcc-wrapper.py tidak ditemukan di $SCRIPT_DIR"

    [[ -f "${wrapper}.orig" ]] || cp "$wrapper" "${wrapper}.orig"
    cp "$PY3_WRAPPER" "$wrapper"
    chmod +x "$wrapper"
    green "scripts/gcc-wrapper.py diganti versi python3 (asli disimpan sebagai gcc-wrapper.py.orig)"
}

# ---------------------------------------------------------------------------
# 5. Build
# ---------------------------------------------------------------------------
build_rom() {
    cd "$BUILD_DIR"

    [[ -d "device/oppo/$DEVICE" ]] || die "device/oppo/$DEVICE tidak ada. Jalankan sync dulu."
    [[ -d "vendor/oppo/$DEVICE" ]] || die "vendor/oppo/$DEVICE tidak ada. Jalankan sync dulu."
    [[ -d "$KERNEL_PATH" ]]        || die "$KERNEL_PATH tidak ada. Jalankan sync dulu."

    export LC_ALL=C

    # envsetup.sh memakai variabel yang belum diset; matikan sementara `set -u`
    set +eu
    # shellcheck disable=SC1091
    source build/envsetup.sh
    breakfast "$DEVICE" || { red "breakfast gagal"; exit 1; }
    set -eu

    if [[ "$DO_CLEAN" == "1" ]]; then
        info "Menghapus out/target/product/$DEVICE"
        rm -rf "out/target/product/$DEVICE"
    fi

    local start_ts
    start_ts=$(date +%s)

    set +eu
    if [[ "$BUILD_TARGET" == "recovery" ]]; then
        info "Build recovery.img"
        mka recoveryimage -j"$JOBS"
    else
        info "Build ROM penuh (2-6 jam pada build pertama)"
        mka bacon -j"$JOBS"
    fi
    local rc=$?
    set -eu
    [[ $rc -eq 0 ]] || die "Build gagal. Lihat bagian Troubleshooting di README.md"

    local mins=$(( ($(date +%s) - start_ts) / 60 ))
    green "Build selesai dalam ${mins} menit"
    ls -lh "out/target/product/$DEVICE"/lineage-*.zip \
           "out/target/product/$DEVICE"/recovery.img 2>/dev/null || true
}

# ---------------------------------------------------------------------------
main() {
    check_host
    init_source
    if [[ "$DO_SYNC" == "1" ]]; then
        sync_source
    fi
    patch_kernel_python
    if [[ "$DO_BUILD" == "1" ]]; then
        build_rom
    else
        green "Source siap di $BUILD_DIR. Build dengan: $0 --no-sync"
    fi
}

# Hanya jalan kalau dieksekusi langsung, supaya fungsinya bisa di-source untuk tes
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
