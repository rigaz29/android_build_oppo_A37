# Kernel OPPO A37 + ReSukiSU → zip AnyKernel3

Panduan membangun kernel 3.10.108 untuk OPPO A37/A37f/A37fw dengan root
[ReSukiSU](https://github.com/ReSukiSU/ReSukiSU), dibungkus jadi zip flashable
[AnyKernel3](https://github.com/osm0sis/AnyKernel3).

Basis kernelnya commit yang sama dengan ROM di [`A37.xml`](A37.xml)
(`0efa2fea` di `meghs-playground/kernel_oppo_msm8939`), jadi satu-satunya variabel baru
adalah ReSukiSU itu sendiri.

| | |
|---|---|
| Kernel | Linux 3.10.108, arm64, msm8916 — **non-GKI** |
| Metode hook | Manual hook (`CONFIG_KSU_MANUAL_HOOK`) — tracepoint hook butuh kernel 5.10+ |
| Format DT | QCDT terpisah (`dt.img`), bukan appended dtb |
| Partisi | `/dev/block/bootdevice/by-name/boot`, non-A/B |
| Modul ala Magisk | **Tidak berfungsi** — 3.10 tidak punya overlayfs (baru ada di 3.18) |

---

# Jalur A — otomatis

```bash
./build-kernel-resukisu.sh
```

Sekali jalan: clone kernel → pasang ReSukiSU → terapkan hook → kompilasi → `dt.img` →
zip AnyKernel3. Hasilnya `~/ksu/ReSukiSU-A37f-<tanggal>.zip`.

| Opsi | Guna |
|---|---|
| `--no-clone` | pakai source kernel yang sudah ada |
| `--zip-only` | rakit ulang zip tanpa mengompilasi lagi |
| `--clean` | hapus workdir lalu mulai dari nol |
| `--jobs N` | batasi paralelisme |
| `WORK=/mnt/ssd/ksu` | pindahkan workdir (default `~/ksu`) |
| `LOS_TREE=/path/los17` | tree LineageOS untuk meminjam toolchain & `dtbToolOppo` |

Toolchain: kalau `$LOS_TREE` (default `~/los17`) berisi
`prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9`, script memakainya. Kalau
tidak, prebuilt GCC 4.9 LineageOS di-clone otomatis (~200 MB).

Script berhenti dengan pesan jelas kalau: patch hook tidak cocok, `CONFIG_KSU` tidak aktif
di `.config`, ada simbol hook yang hilang dari `System.map`, `dt.img` bukan QCDT, atau
`Image`/`dt.img` tidak masuk ke zip.

---

# Jalur B — manual

## 1. Siapkan toolchain

```bash
# dari tree LineageOS yang sudah ada:
export PATH=~/los17/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9/bin:$PATH
export PATH=~/los17/prebuilts/gcc/linux-x86/arm/arm-linux-androideabi-4.9/bin:$PATH

# atau clone prebuilt-nya sendiri:
git clone --depth 1 \
  https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_aarch64_aarch64-linux-android-4.9 \
  ~/ksu/tc-aarch64
export PATH=~/ksu/tc-aarch64/bin:$PATH
```

## 2. Ambil source kernel

```bash
mkdir -p ~/ksu && cd ~/ksu
git clone --depth 1 -b 0.0 \
  https://github.com/meghs-playground/kernel_oppo_msm8939.git kernel
cd kernel
git rev-parse HEAD    # harus 0efa2fea80994383a6d8e33a1ba87e990b52ec12
```

## 3. Pasang ReSukiSU

```bash
curl -LSs "https://raw.githubusercontent.com/ReSukiSU/ReSukiSU/main/kernel/setup.sh" | bash
```

Hasilnya: direktori `KernelSU/`, symlink `drivers/kernelsu`, plus baris tambahan di
`drivers/Makefile` dan `drivers/Kconfig`.

## 4. Terapkan hook manual

```bash
patch -p1 < /path/ke/a37-build/patches/kernel-resukisu-hooks.patch
```

Patch itu berisi enam hook, backport `READ_ONCE`, dan opsi defconfig. Isinya dijelaskan di
[Rincian hook](#rincian-hook) — baca kalau kamu ingin memasangnya sendiri alih-alih pakai
patch.

Verifikasi:

```bash
grep -c "ksu_handle_" fs/stat.c fs/exec.c fs/open.c kernel/sys.c
grep -E "^CONFIG_KSU" arch/arm64/configs/lineageos_a37f_defconfig
```

## 5. Kompilasi

```bash
mkdir -p out
make -s O=out ARCH=arm64 CROSS_COMPILE=aarch64-linux-android- \
     CROSS_COMPILE_ARM32=arm-linux-androideabi- lineageos_a37f_defconfig

grep -E "^CONFIG_KSU=y|^CONFIG_KSU_MANUAL_HOOK=y|^CONFIG_KALLSYMS_ALL=y" out/.config

make O=out ARCH=arm64 CROSS_COMPILE=aarch64-linux-android- \
     CROSS_COMPILE_ARM32=arm-linux-androideabi- -j$(nproc) Image dtbs
```

Hasil: `out/arch/arm64/boot/Image` (~19 MB) dan satu DTB di
`out/arch/arm64/boot/dts/msm8916-mtp-15399.dtb`.

Bukti hook benar-benar masuk — kompilasi yang lolos saja belum cukup meyakinkan, meski
ReSukiSU memang menggagalkan build bila ada hook yang hilang:

```bash
grep -E " ksu_handle_(execve|faccessat|stat|newfstat_ret|fstat64_ret|sys_reboot)$" out/System.map
```

Harus muncul keenamnya sebagai simbol `T`.

## 6. Buat `dt.img` (QCDT)

Device ini memakai DT terpisah, jadi Image saja tidak cukup.

```bash
cd out
dtbToolOppo -o ~/ksu/dt.img -s 2048 -p scripts/dtc/ arch/arm64/boot/dts/
head -c 4 ~/ksu/dt.img    # harus: QCDT
```

`dtbToolOppo` ada di `~/los17/out/host/linux-x86/bin/` setelah ROM pernah dibangun. Kalau
belum, kompilasi dari sumbernya di device tree:

```bash
g++ -O2 -o ~/ksu/dtbToolOppo ~/los17/device/oppo/A37/dtbtool/*.c* -I ~/los17/device/oppo/A37/dtbtool
```

## 7. Bungkus AnyKernel3

```bash
cd ~/ksu
git clone --depth 1 https://github.com/osm0sis/AnyKernel3.git ak3
cp -r ak3 zip && cd zip
rm -rf .git .github README.md modules patch

cp ~/ksu/kernel/out/arch/arm64/boot/Image Image
cp ~/ksu/dt.img dt.img && chmod 644 dt.img
```

Ganti isi `anykernel.sh` dengan:

```sh
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

boot_attributes() {
set_perm_recursive 0 0 755 644 $RAMDISK/*;
set_perm_recursive 0 0 750 750 $RAMDISK/init* $RAMDISK/sbin;
}

BLOCK=/dev/block/bootdevice/by-name/boot;
IS_SLOT_DEVICE=0;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;

. tools/ak3-core.sh;

split_boot;
flash_boot;
```

Lalu bungkus:

```bash
zip -r9 ~/ksu/ReSukiSU-A37f-$(date +%Y%m%d).zip . -x ".git*"
unzip -l ~/ksu/ReSukiSU-A37f-*.zip | grep -E " Image$| dt.img$"
```

Dua catatan soal AnyKernel3 di device ini:

- **`split_boot` + `flash_boot`, bukan `dump_boot` + `write_boot`.** Ramdisk tidak diubah
  sama sekali; hanya `Image` dan `dt` yang diganti, sisa boot.img dipakai ulang.
- **Nama berkas `dt.img` penting.** `tools/ak3-core.sh` mencari `dt`, `dt.img`,
  `recovery_dtbo`, lalu `dtb` di root zip, dan memakainya sebagai `--dt` saat repack. Kalau
  tidak disertakan, dt lama dari boot.img yang dipakai — kernel baru dengan DT lama bisa
  tidak boot.

---

## Rincian hook

ReSukiSU **memeriksa setiap hook saat kompilasi** dan sengaja menggagalkan build kalau ada
yang hilang (`tools/manual_hook_check.mk`). Untuk kernel 3.10 ada enam yang wajib, dengan
varian versi yang berbeda dari contoh di dokumentasi resmi:

| Hook | Berkas | Kenapa varian ini |
|---|---|---|
| `ksu_handle_execve` | `fs/exec.c` | 3.14− memakai `execve`, bukan `execveat`; dipasang di `do_execve` dan `compat_do_execve` |
| `ksu_handle_faccessat` | `fs/open.c` | varian 4.19− |
| `ksu_handle_stat` | `fs/stat.c` | dipasang di `newfstatat` dan `fstatat64` |
| `ksu_handle_newfstat_ret` | `fs/stat.c` | sebelum `return error` di `newfstat` |
| `ksu_handle_fstat64_ret` | `fs/stat.c` | sebelum `return error` di `fstat64` |
| `ksu_handle_sys_reboot` | `kernel/sys.c` | 3.10 belum punya `kernel/reboot.c` (baru ada di 3.11) |

Yang **tidak** perlu dipasang manual, karena default `y` di Kconfig ReSukiSU:
`KSU_MANUAL_HOOK_AUTO_SETUID_HOOK`, `..._AUTO_INITRC_HOOK`, `..._AUTO_INPUT_HOOK` — jadi
`kernel/sys.c` setresuid, `fs/read_write.c`, dan `drivers/input/input.c` tidak disentuh.

Export simbol SELinux (`write_op`, `sel_handle_status_ops`, `policy_rwlock`, dst.) juga
tidak perlu, karena `CONFIG_KALLSYMS_ALL=y` membuat `Kbuild` melewati
`static_export_check.mk`.

### Backport `READ_ONCE`

Tanpa ini, link gagal:

```
drivers/built-in.o: In function `ksu_install_sulog_fd':
lsm_hooks.c:(.text+0x63ec20): undefined reference to `READ_ONCE'
```

`READ_ONCE()` baru masuk kernel 3.19; di 3.10 hanya ada `ACCESS_ONCE()`. ReSukiSU
menyediakan definisi kompatibilitasnya di `compat/kernel_compat.h`, tapi `sulog/fd.c`
memakainya tanpa meng-include header itu — bug hulu yang hanya menggigit kernel <3.19.

Patch menambahkan `READ_ONCE`/`WRITE_ONCE` ke `include/linux/compiler.h` **kernel**, bukan
menyunting `KernelSU/`, karena direktori itu dikelola `setup.sh` dan suntingan lokal akan
hilang begitu di-update.

---

## Pasang ke HP

1. **Backup boot.img dulu** — ini jalan pulang kalau bootloop:
   ```bash
   adb shell su -c "dd if=/dev/block/bootdevice/by-name/boot of=/sdcard/boot-backup.img"
   ```
   Atau ambil `boot.img` dari hasil build ROM (`out/target/product/A37/boot.img`).
2. Pastikan ROM sudah boot normal lebih dulu — jangan menumpuk dua perubahan sekaligus.
3. Flash lewat recovery: **Apply update → ADB sideload**, lalu
   `adb sideload ReSukiSU-A37f-<tanggal>.zip`.
4. Reboot, lalu pasang aplikasi manager ReSukiSU untuk memberi izin root.

Kalau bootloop: masuk recovery, flash ulang `boot-backup.img`, atau sideload zip ROM.

## Batasan

- **Modul ala Magisk tidak akan berfungsi.** `CONFIG_OVERLAY_FS` tidak ada sama sekali di
  3.10 (overlayfs masuk 3.18). Root, `su`, manager, dan profil aplikasi tetap jalan.
- Kernel ini **belum diuji boot di perangkat** — lihat catatan status di bagian bawah
  [README](README.md).
- Root memperlemah model keamanan perangkat. ROM ini sudah `SELinux permissive` sejak awal,
  jadi jangan pakai untuk aplikasi perbankan atau data sensitif.

## Rujukan

- [ReSukiSU](https://github.com/ReSukiSU/ReSukiSU) — [panduan build](https://resukisu.github.io/guide/build.html), [integrasi manual](https://resukisu.github.io/guide/manual-integrate.html)
- [AnyKernel3](https://github.com/osm0sis/AnyKernel3) oleh osm0sis
