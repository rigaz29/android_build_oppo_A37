#!/usr/bin/env bash
#
# build-kernel-resukisu.sh - Bangun kernel OPPO A37/A37f/A37fw + ReSukiSU,
# lalu bungkus jadi zip flashable AnyKernel3.
#
# Kernel : 3.10.108 (msm8916), commit yang sama dengan ROM di A37.xml
# Root   : ReSukiSU (https://github.com/ReSukiSU/ReSukiSU) via manual hook
# Paket  : AnyKernel3 (https://github.com/osm0sis/AnyKernel3)
#
# Pemakaian:
#   ./build-kernel-resukisu.sh                  # semua tahap
#   ./build-kernel-resukisu.sh --no-clone       # pakai source yang sudah ada
#   ./build-kernel-resukisu.sh --zip-only       # rakit ulang zip tanpa kompilasi
#   ./build-kernel-resukisu.sh --clean          # hapus workdir dulu
#   WORK=/mnt/ssd/ksu ./build-kernel-resukisu.sh
#
# Perlu: git, curl, zip, make, gcc (host), dan toolchain aarch64-linux-android-4.9.
# Toolchain diambil dari tree LineageOS bila ada ($LOS_TREE, default ~/los17),
# kalau tidak ada akan di-clone dari prebuilt LineageOS.
#

set -euo pipefail

WORK="${WORK:-$HOME/ksu}"
LOS_TREE="${LOS_TREE:-$HOME/los17}"
JOBS="${JOBS:-$(nproc --all)}"

KERNEL_REPO="https://github.com/meghs-playground/kernel_oppo_msm8939.git"
KERNEL_BRANCH="0.0"
KERNEL_SHA="0efa2fea80994383a6d8e33a1ba87e990b52ec12"
DEFCONFIG="lineageos_a37f_defconfig"

RESUKISU_SETUP="https://raw.githubusercontent.com/ReSukiSU/ReSukiSU/main/kernel/setup.sh"
AK3_REPO="https://github.com/osm0sis/AnyKernel3.git"
GCC64_REPO="https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_aarch64_aarch64-linux-android-4.9.git"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_PATCH="$SCRIPT_DIR/patches/kernel-resukisu-hooks.patch"

DO_CLONE=1
DO_BUILD=1
DO_CLEAN=0

red()   { printf '\033[1;31m%s\033[0m\n' "$*"; }
green() { printf '\033[1;32m%s\033[0m\n' "$*"; }
info()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die()   { red "ERROR: $*"; exit 1; }

usage() { sed -n '3,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-clone) DO_CLONE=0 ;;
        --zip-only) DO_BUILD=0 ;;
        --clean)    DO_CLEAN=1 ;;
        --jobs|-j)  JOBS="$2"; shift ;;
        --help|-h)  usage ;;
        *)          die "Opsi tidak dikenal: $1 (pakai --help)" ;;
    esac
    shift
done

# ---------------------------------------------------------------------------
# 1. Cek host + siapkan toolchain
# ---------------------------------------------------------------------------
prepare() {
    info "Memeriksa host"
    for t in git curl zip make gcc; do
        command -v "$t" >/dev/null || die "$t belum terpasang"
    done

    [[ -f "$HOOKS_PATCH" ]] || die "patch tidak ditemukan: $HOOKS_PATCH"

    if [[ "$DO_CLEAN" == "1" ]]; then
        info "Menghapus $WORK"
        rm -rf "$WORK"
    fi
    mkdir -p "$WORK"

    # Toolchain: pinjam dari tree LineageOS kalau ada, kalau tidak clone prebuilt-nya
    TC64="$LOS_TREE/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9/bin"
    if [[ -x "$TC64/aarch64-linux-android-gcc" ]]; then
        info "Toolchain dari tree LineageOS: $TC64"
    else
        TC64="$WORK/tc-aarch64/bin"
        if [[ ! -x "$TC64/aarch64-linux-android-gcc" ]]; then
            info "Meng-clone toolchain GCC 4.9 aarch64 (~200 MB)"
            git clone -q --depth 1 "$GCC64_REPO" "$WORK/tc-aarch64"
        fi
        [[ -x "$TC64/aarch64-linux-android-gcc" ]] || die "toolchain aarch64 tidak tersedia"
        info "Toolchain: $TC64"
    fi

    TC32="$LOS_TREE/prebuilts/gcc/linux-x86/arm/arm-linux-androideabi-4.9/bin"
    export PATH="$TC64:$TC32:$PATH"
}

# ---------------------------------------------------------------------------
# 2. Source kernel pada commit yang sama dengan ROM
# ---------------------------------------------------------------------------
fetch_kernel() {
    KSRC="$WORK/kernel"

    if [[ "$DO_CLONE" == "1" && ! -d "$KSRC/.git" ]]; then
        info "Clone kernel $KERNEL_BRANCH (~1 GB)"
        git clone -q --depth 1 -b "$KERNEL_BRANCH" "$KERNEL_REPO" "$KSRC"
    fi
    [[ -d "$KSRC" ]] || die "source kernel tidak ada di $KSRC (jangan pakai --no-clone pada run pertama)"

    local head
    head="$(git -C "$KSRC" rev-parse HEAD)"
    if [[ "$head" != "$KERNEL_SHA" ]]; then
        red "PERINGATAN: HEAD kernel ${head:0:12}, bukan ${KERNEL_SHA:0:12} yang diuji."
        red "Patch hook bisa gagal diterapkan kalau source-nya bergerak jauh."
    fi
}

# ---------------------------------------------------------------------------
# 3. Pasang ReSukiSU + hook manual
# ---------------------------------------------------------------------------
integrate_resukisu() {
    cd "$KSRC"

    if [[ -d KernelSU && -L drivers/kernelsu ]]; then
        info "ReSukiSU sudah terpasang, lewati setup.sh"
    else
        info "Memasang ReSukiSU (setup.sh)"
        curl -LSs "$RESUKISU_SETUP" | bash
    fi

    # Hook manual + backport READ_ONCE + opsi defconfig.
    # Kernel 3.10 tidak bisa memakai tracepoint hook (butuh 5.10+), jadi enam
    # hook dipasang manual; ReSukiSU memeriksanya saat kompilasi.
    if patch -p1 --dry-run --silent < "$HOOKS_PATCH" >/dev/null 2>&1; then
        patch -p1 --silent < "$HOOKS_PATCH"
        green "Patch hook diterapkan"
    elif patch -p1 -R --dry-run --silent < "$HOOKS_PATCH" >/dev/null 2>&1; then
        info "Patch hook sudah terpasang"
    else
        die "patches/kernel-resukisu-hooks.patch tidak cocok dengan source ini"
    fi

    local n
    n=$(grep -c "ksu_handle_" fs/stat.c fs/exec.c fs/open.c kernel/sys.c | awk -F: '{s+=$2} END{print s}')
    [[ "$n" -ge 10 ]] || die "hook tidak lengkap setelah patch (ditemukan $n rujukan)"
    info "Hook terpasang: $n rujukan ksu_handle_* di 4 berkas"
}

# ---------------------------------------------------------------------------
# 4. Kompilasi kernel + DTB
# ---------------------------------------------------------------------------
build_kernel() {
    cd "$KSRC"
    mkdir -p out

    info "make $DEFCONFIG"
    make -s O=out ARCH=arm64 CROSS_COMPILE=aarch64-linux-android- \
         CROSS_COMPILE_ARM32=arm-linux-androideabi- "$DEFCONFIG"

    grep -q "^CONFIG_KSU=y" out/.config || die "CONFIG_KSU tidak aktif di .config"

    info "Kompilasi kernel (jobs=$JOBS)"
    make O=out ARCH=arm64 CROSS_COMPILE=aarch64-linux-android- \
         CROSS_COMPILE_ARM32=arm-linux-androideabi- -j"$JOBS" Image dtbs

    [[ -f out/arch/arm64/boot/Image ]] || die "Image tidak terbentuk"

    # Bukti hook benar-benar masuk kernel, bukan sekadar lolos kompilasi
    local missing=""
    for sym in ksu_handle_execve ksu_handle_faccessat ksu_handle_stat \
               ksu_handle_newfstat_ret ksu_handle_fstat64_ret ksu_handle_sys_reboot; do
        grep -q " $sym$" out/System.map || missing="$missing $sym"
    done
    [[ -z "$missing" ]] || die "simbol hook hilang dari System.map:$missing"
    green "Kernel siap — 6 simbol hook terverifikasi di System.map"
}

# ---------------------------------------------------------------------------
# 5. dt.img (QCDT) — device ini memakai DT terpisah
# ---------------------------------------------------------------------------
build_dtimg() {
    cd "$KSRC/out"
    local dtbtool="$LOS_TREE/out/host/linux-x86/bin/dtbToolOppo"

    if [[ ! -x "$dtbtool" ]]; then
        local src="$LOS_TREE/device/oppo/A37/dtbtool"
        [[ -d "$src" ]] || die "dtbToolOppo tidak ada dan sumbernya juga tidak ($src).
    Bangun ROM-nya dulu dengan build.sh, atau salin dtbToolOppo ke \$PATH."
        info "Mengompilasi dtbToolOppo dari device tree"
        g++ -O2 -o "$WORK/dtbToolOppo" "$src"/*.c* -I"$src"
        dtbtool="$WORK/dtbToolOppo"
    fi

    info "Membuat dt.img (QCDT)"
    "$dtbtool" -o "$WORK/dt.img" -s 2048 -p scripts/dtc/ arch/arm64/boot/dts/
    [[ -s "$WORK/dt.img" ]] || die "dt.img gagal dibuat"
    [[ "$(head -c 4 "$WORK/dt.img")" == "QCDT" ]] || die "dt.img bukan format QCDT"
    green "dt.img siap ($(stat -c%s "$WORK/dt.img") byte)"
}

# ---------------------------------------------------------------------------
# 6. Bungkus AnyKernel3
# ---------------------------------------------------------------------------
package_zip() {
    local ak3="$WORK/ak3" zipdir="$WORK/zip"

    [[ -d "$ak3/.git" ]] || { info "Clone AnyKernel3"; git clone -q --depth 1 "$AK3_REPO" "$ak3"; }

    rm -rf "$zipdir"
    cp -r "$ak3" "$zipdir"
    rm -rf "$zipdir/.git" "$zipdir/.github" "$zipdir/README.md" "$zipdir/modules" "$zipdir/patch"

    cp "$KSRC/out/arch/arm64/boot/Image" "$zipdir/Image"
    cp "$WORK/dt.img" "$zipdir/dt.img"
    chmod 644 "$zipdir/dt.img"

    # AnyKernel3 mencari dt/dt.img di root zip lalu memakainya sebagai --dt saat repack.
    cat > "$zipdir/anykernel.sh" <<'AKEOF'
### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers

### AnyKernel setup
# global properties
properties() { '
kernel.string=LineageOS 17.1 kernel 3.10.108 + ReSukiSU untuk OPPO A37/A37f/A37fw
do.devicecheck=1
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
device.name1=A37
device.name2=A37f
device.name3=A37fw
device.name4=a37f
device.name5=a37fw
supported.versions=
supported.patchlevels=
supported.vendorpatchlevels=
'; } # end properties

### AnyKernel install
## boot files attributes
boot_attributes() {
set_perm_recursive 0 0 755 644 $RAMDISK/*;
set_perm_recursive 0 0 750 750 $RAMDISK/init* $RAMDISK/sbin;
} # end attributes

# boot shell variables
BLOCK=/dev/block/bootdevice/by-name/boot;
IS_SLOT_DEVICE=0;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;

# import functions/variables and setup patching - see for reference (DO NOT REMOVE)
. tools/ak3-core.sh;

# boot install
# split_boot dipakai (bukan dump_boot) karena ramdisk tidak diubah sama sekali:
# hanya Image dan dt yang diganti, sisa boot.img dipakai ulang apa adanya.
split_boot;
flash_boot;
AKEOF

    local out="$WORK/ReSukiSU-A37f-$(date +%Y%m%d).zip"
    rm -f "$out"
    ( cd "$zipdir" && zip -qr9 "$out" . -x ".git*" )

    unzip -l "$out" | grep -q " Image$" || die "Image tidak masuk ke zip"
    unzip -l "$out" | grep -q " dt.img$" || die "dt.img tidak masuk ke zip"

    green "Zip siap: $out"
    ls -lh "$out"
    sha256sum "$out"
}

# ---------------------------------------------------------------------------
main() {
    prepare
    fetch_kernel
    if [[ "$DO_BUILD" == "1" ]]; then
        integrate_resukisu
        build_kernel
        build_dtimg
    else
        info "--zip-only: lewati integrasi & kompilasi"
        [[ -f "$KSRC/out/arch/arm64/boot/Image" ]] || die "belum ada Image hasil build"
        [[ -f "$WORK/dt.img" ]] || die "belum ada dt.img"
    fi
    package_zip

    cat <<EOF

Selesai. Sebelum memasang:
  - Backup boot.img lama sebagai jalan pulang kalau bootloop.
  - Modul ala Magisk TIDAK akan berfungsi: kernel 3.10 tanpa overlayfs.
  - Pasang aplikasi manager ReSukiSU untuk memberi izin root.
EOF
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
