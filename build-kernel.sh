#!/usr/bin/env bash
#
# build-kernel.sh - Bangun kernel murni OPPO A37/A37f/A37fw dari tree lokal,
# lalu bungkus jadi zip flashable AnyKernel3. Tanpa root, tanpa ReSukiSU.
#
# Sumber : repo git (default) atau tree lokal (--local)
# Kernel : 3.10.108 (msm8916)
# Paket  : AnyKernel3 (https://github.com/osm0sis/AnyKernel3)
#
# Secara default skrip menarik sendiri dari $KERNEL_REPO ke $WORK/kernel, jadi
# hasilnya hanya bergantung pada apa yang sudah di-push - bukan pada keadaan
# repo sync Anda. Objek git dipinjam dari tree lokal bila ada, jadi clone
# pertama tidak perlu menarik ~1 GB dari jaringan.
#
# Kompilasi selalu out-of-tree (O=$WORK/out), jadi tree kernel tidak pernah
# dikotori oleh hasil build.
#
# Pemakaian:
#   ./build-kernel.sh                     # tarik dari repo, bangun branch a12-prep
#   ./build-kernel.sh --rev lz4-backport  # branch, tag, atau SHA lain di remote
#   ./build-kernel.sh --local             # pakai tree lokal apa adanya, tanpa jaringan
#   ./build-kernel.sh --local --checkout  # izinkan skrip memindahkan HEAD tree lokal
#   ./build-kernel.sh --zip-only          # rakit ulang zip tanpa kompilasi
#   ./build-kernel.sh --clean             # hapus workdir dulu
#   KERNEL_REPO=... WORK=/mnt/ssd/kbuild ./build-kernel.sh
#
# Verifikasi simbol opsional - gagalkan build kalau simbol tidak sesuai harapan:
#   EXPECT_SYMS="mem_cgroup_init dquot_initialize" \
#   EXPECT_NO_SYMS="lowmem_scan lowmem_shrink" ./build-kernel.sh
#
# Perlu: git, zip, unzip, make, gcc/g++ (host), dan toolchain
# aarch64-linux-android-4.9 dari tree LineageOS ($LOS_TREE, default ~/los17).
#

set -euo pipefail

LOS_TREE="${LOS_TREE:-$HOME/los17}"
LOCAL_KSRC="${KSRC:-$LOS_TREE/kernel/oppo/msm8939}"
WORK="${WORK:-$HOME/kbuild}"
JOBS="${JOBS:-$(nproc --all)}"

KERNEL_REPO="${KERNEL_REPO:-https://github.com/rigaz29/kernel_oppo_msm8939.git}"
REV="${REV:-a12-prep}"
DEFCONFIG="${DEFCONFIG:-lineageos_a37f_defconfig}"

EXPECT_SYMS="${EXPECT_SYMS:-}"
EXPECT_NO_SYMS="${EXPECT_NO_SYMS:-}"

AK3_REPO="https://github.com/osm0sis/AnyKernel3.git"
GCC64_REPO="https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_aarch64_aarch64-linux-android-4.9.git"

DO_BUILD=1
DO_CLEAN=0
DO_CHECKOUT=0
SOURCE=repo

red()   { printf '\033[1;31m%s\033[0m\n' "$*"; }
green() { printf '\033[1;32m%s\033[0m\n' "$*"; }
info()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die()   { red "ERROR: $*"; exit 1; }

usage() { sed -n '3,33p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --rev|-r)     REV="$2"; shift ;;
        --defconfig)  DEFCONFIG="$2"; shift ;;
        --local)      SOURCE=local ;;
        --repo)       KERNEL_REPO="$2"; SOURCE=repo; shift ;;
        --checkout)   DO_CHECKOUT=1 ;;
        --zip-only)   DO_BUILD=0 ;;
        --clean)      DO_CLEAN=1 ;;
        --jobs|-j)    JOBS="$2"; shift ;;
        --help|-h)    usage ;;
        *)            die "Opsi tidak dikenal: $1 (pakai --help)" ;;
    esac
    shift
done

OUT="$WORK/out"

# ---------------------------------------------------------------------------
# 1. Cek host + siapkan toolchain
# ---------------------------------------------------------------------------
prepare() {
    info "Memeriksa host"
    for t in git zip unzip make gcc g++; do
        command -v "$t" >/dev/null || die "$t belum terpasang"
    done

    if [[ "$SOURCE" == "local" && ! -d "$LOCAL_KSRC/.git" ]]; then
        die "tree kernel tidak ditemukan di $LOCAL_KSRC
    Set KSRC=/path/ke/kernel, atau LOS_TREE=/path/ke/tree-lineageos."
    fi

    if [[ "$DO_CLEAN" == "1" ]]; then
        info "Menghapus $WORK"
        rm -rf "$WORK"
    fi
    mkdir -p "$WORK" "$OUT"

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
# 2a. Sumber = repo git (default)
#
# Workdir $WORK/kernel milik skrip sepenuhnya, jadi HEAD-nya boleh dipindah
# tanpa bertanya. Tree lokal Anda tidak disentuh sama sekali - kalau ada, ia
# hanya dipinjam objeknya supaya clone pertama tidak menarik ~1 GB.
# ---------------------------------------------------------------------------
fetch_kernel() {
    KSRC="$WORK/kernel"

    if [[ ! -d "$KSRC/.git" ]]; then
        if [[ -d "$LOCAL_KSRC/.git" ]]; then
            info "Clone $KERNEL_REPO (meminjam objek dari $LOCAL_KSRC)"
        else
            info "Clone $KERNEL_REPO (~1 GB, tidak ada tree lokal untuk dipinjam)"
        fi
        git clone -q --reference-if-able "$LOCAL_KSRC" --dissociate \
            "$KERNEL_REPO" "$KSRC" || die "clone gagal"
    fi

    info "Fetch $KERNEL_REPO"
    git -C "$KSRC" remote set-url origin "$KERNEL_REPO"
    git -C "$KSRC" fetch -q --tags --prune origin || die "fetch gagal"

    local want
    want="$(git -C "$KSRC" rev-parse --verify --quiet "origin/${REV}^{commit}" \
         || git -C "$KSRC" rev-parse --verify --quiet "${REV}^{commit}")" || true
    [[ -n "$want" ]] || die "revisi '$REV' tidak ada di $KERNEL_REPO.
    Branch lokal yang belum di-push tidak terlihat dari sini. Pilih salah satu:
      git -C $LOCAL_KSRC push -u gh $REV
      $0 --local --rev $REV"

    git -C "$KSRC" checkout -q --detach "$want"
    git -C "$KSRC" clean -qfd

    SHA="$(git -C "$KSRC" rev-parse --short=12 HEAD)"
    BRANCH="$REV"
    DIRTY=""

    info "Sumber: $KERNEL_REPO @ $REV ($SHA)"
    git -C "$KSRC" log -1 --format='    %s' | cat
}

# ---------------------------------------------------------------------------
# 2b. Sumber = tree lokal (--local)
#
# Skrip tidak pernah memindahkan HEAD diam-diam di sini: tanpa --checkout, HEAD
# yang tidak cocok adalah error, bukan sesuatu yang diperbaiki sendiri. Tree itu
# milik Anda, dan repo sync memperlakukan HEAD sebagai keadaan yang sah.
# ---------------------------------------------------------------------------
select_revision() {
    KSRC="$LOCAL_KSRC"
    local want head
    want="$(git -C "$KSRC" rev-parse --verify --quiet "${REV}^{commit}")" \
        || die "revisi '$REV' tidak ada di $KSRC"
    head="$(git -C "$KSRC" rev-parse HEAD)"

    if [[ "$want" != "$head" ]]; then
        if [[ "$DO_CHECKOUT" == "1" ]]; then
            [[ -z "$(git -C "$KSRC" status --porcelain)" ]] \
                || die "tree kotor, tidak aman untuk checkout. Commit atau stash dulu."
            info "Checkout $REV (${want:0:12})"
            git -C "$KSRC" checkout -q "$REV"
        else
            die "HEAD tree lokal ${head:0:12}, sedangkan --rev '$REV' menunjuk ${want:0:12}.
    Pilih salah satu:
      git -C $KSRC checkout $REV
      $0 --rev $REV --checkout"
        fi
    fi

    SHA="$(git -C "$KSRC" rev-parse --short=12 HEAD)"
    BRANCH="$(git -C "$KSRC" rev-parse --abbrev-ref HEAD)"
    DIRTY=""
    if [[ -n "$(git -C "$KSRC" status --porcelain)" ]]; then
        DIRTY="-dirty"
        red "PERINGATAN: tree kernel kotor — hasil build tidak mewakili commit $SHA."
        git -C "$KSRC" status --short | sed 's/^/    /'
    fi

    info "Sumber: $KSRC @ $BRANCH ($SHA$DIRTY)"
    git -C "$KSRC" log -1 --format='    %s' | cat
}

# ---------------------------------------------------------------------------
# 3. Kompilasi kernel + DTB
# ---------------------------------------------------------------------------
build_kernel() {
    local mk=(make -C "$KSRC" O="$OUT" ARCH=arm64
              CROSS_COMPILE=aarch64-linux-android-
              CROSS_COMPILE_ARM32=arm-linux-androideabi-)

    info "make $DEFCONFIG"
    "${mk[@]}" -s "$DEFCONFIG"

    KVER="$("${mk[@]}" -s kernelversion 2>/dev/null | tail -1)"
    info "Versi kernel: $KVER"

    info "Kompilasi kernel + dtbs (jobs=$JOBS)"
    "${mk[@]}" -j"$JOBS" Image dtbs

    [[ -f "$OUT/arch/arm64/boot/Image" ]] || die "Image tidak terbentuk"
    green "Image siap ($(stat -c%s "$OUT/arch/arm64/boot/Image") byte)"

    verify_symbols
}

# Bukti bahwa konfigurasi benar-benar mendarat di biner, bukan cuma di .config.
verify_symbols() {
    [[ -n "$EXPECT_SYMS$EXPECT_NO_SYMS" ]] || return 0
    [[ -f "$OUT/System.map" ]] || die "System.map tidak ada, tidak bisa verifikasi simbol"

    local missing="" present="" sym
    for sym in $EXPECT_SYMS; do
        grep -q " $sym\$" "$OUT/System.map" || missing="$missing $sym"
    done
    for sym in $EXPECT_NO_SYMS; do
        ! grep -q " $sym\$" "$OUT/System.map" || present="$present $sym"
    done

    [[ -z "$missing" ]] || die "simbol yang diharapkan tidak ada di System.map:$missing"
    [[ -z "$present" ]] || die "simbol yang seharusnya hilang masih ada di System.map:$present"
    green "Verifikasi simbol lolos — ada: ${EXPECT_SYMS:-(tidak diminta)} · tidak ada: ${EXPECT_NO_SYMS:-(tidak diminta)}"
}

# ---------------------------------------------------------------------------
# 4. dt.img (QCDT) — device ini memakai DT terpisah dari boot.img
# ---------------------------------------------------------------------------
build_dtimg() {
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
    "$dtbtool" -o "$WORK/dt.img" -s 2048 -p "$OUT/scripts/dtc/" "$OUT/arch/arm64/boot/dts/"
    [[ -s "$WORK/dt.img" ]] || die "dt.img gagal dibuat"
    [[ "$(head -c 4 "$WORK/dt.img")" == "QCDT" ]] || die "dt.img bukan format QCDT"
    green "dt.img siap ($(stat -c%s "$WORK/dt.img") byte)"
}

# ---------------------------------------------------------------------------
# 5. Bungkus AnyKernel3
# ---------------------------------------------------------------------------
package_zip() {
    local ak3="$WORK/ak3" zipdir="$WORK/zip"

    [[ -d "$ak3/.git" ]] || { info "Clone AnyKernel3"; git clone -q --depth 1 "$AK3_REPO" "$ak3"; }

    rm -rf "$zipdir"
    cp -r "$ak3" "$zipdir"
    rm -rf "$zipdir/.git" "$zipdir/.github" "$zipdir/README.md" "$zipdir/modules" "$zipdir/patch"

    cp "$OUT/arch/arm64/boot/Image" "$zipdir/Image"
    cp "$WORK/dt.img" "$zipdir/dt.img"
    chmod 644 "$zipdir/dt.img"

    # AnyKernel3 mencari dt/dt.img di root zip lalu memakainya sebagai --dt saat repack.
    cat > "$zipdir/anykernel.sh" <<AKEOF
### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers

### AnyKernel setup
# global properties
properties() { '
kernel.string=Kernel ${KVER:-3.10.108} (${BRANCH} ${SHA}${DIRTY}) untuk OPPO A37/A37f/A37fw
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
set_perm_recursive 0 0 755 644 \$RAMDISK/*;
set_perm_recursive 0 0 750 750 \$RAMDISK/init* \$RAMDISK/sbin;
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

    local out="$WORK/A37f-kernel-${KVER:-3.10.108}-${SHA}${DIRTY}-$(date +%Y%m%d).zip"
    rm -f "$out"
    ( cd "$zipdir" && zip -qr9 "$out" . -x ".git*" )

    unzip -l "$out" | grep -q " Image$"  || die "Image tidak masuk ke zip"
    unzip -l "$out" | grep -q " dt.img$" || die "dt.img tidak masuk ke zip"

    green "Zip siap: $out"
    ls -lh "$out"
    sha256sum "$out"
    ZIP="$out"
}

# ---------------------------------------------------------------------------
main() {
    prepare
    if [[ "$SOURCE" == "repo" ]]; then
        fetch_kernel
    else
        select_revision
    fi
    if [[ "$DO_BUILD" == "1" ]]; then
        build_kernel
        build_dtimg
    else
        info "--zip-only: lewati kompilasi"
        [[ -f "$OUT/arch/arm64/boot/Image" ]] || die "belum ada Image hasil build di $OUT"
        [[ -f "$WORK/dt.img" ]] || die "belum ada dt.img di $WORK"
        KVER="$(make -C "$KSRC" O="$OUT" -s kernelversion 2>/dev/null | tail -1)"
    fi
    package_zip

    cat <<EOF

Selesai. Sebelum memasang:
  - Backup boot.img lama (fastboot boot / dd) sebagai jalan pulang kalau bootloop.
  - Zip ini hanya mengganti Image + dt, ramdisk boot.img yang ada dipakai ulang.
    Jadi zip ini terikat pada ROM yang sedang terpasang, bukan pengganti boot.img.
  - Kernel murni tanpa root: aplikasi manager KernelSU/ReSukiSU tidak akan
    menemukan apa pun. Untuk yang ber-root pakai build-kernel-resukisu.sh.

  adb sideload $ZIP
EOF
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
