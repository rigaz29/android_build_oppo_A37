# LineageOS 17.1 untuk OPPO A37 / A37f / A37fw

Local manifest + script build untuk membangun **LineageOS 17.1 (Android 10)** pada
OPPO A37 (codename LineageOS: `A37`), Qualcomm **MSM8916 / Snapdragon 410**.

| | |
|---|---|
| SoC | Qualcomm MSM8916 (Snapdragon 410), 4× Cortex-A53 1.2 GHz, Adreno 306 |
| RAM / ROM | 2 GB / 16 GB |
| Layar | 5.0" 720×1280 |
| Nomor proyek OPPO | 15399 |
| Android bawaan | 5.1.1 (ColorOS 3.0) |

## Isi repo

| File | Fungsi |
|---|---|
| `A37.xml` | Local manifest — device tree, vendor blobs, kernel, dependency |
| `build.sh` | Script satu-jalan: cek host → `repo init` → `repo sync` → perbaiki LFS → patch kernel → build |
| `patches/gcc-wrapper.py` | Versi python3 dari `scripts/gcc-wrapper.py` kernel, untuk host tanpa python2 |
| `README.md` | Dokumen ini |

## Source yang dipakai

| Komponen | Repo | Branch | Path |
|---|---|---|---|
| device | [`yashraj22/device_oppo_A37`](https://github.com/yashraj22/device_oppo_A37) | `lineage-17.1` | `device/oppo/A37` |
| vendor | [`DeepakChaurasia30/android-vendor_oppo_A37`](https://github.com/DeepakChaurasia30/android-vendor_oppo_A37) | `ten` | `vendor/oppo/A37` |
| kernel | [`OPPO-A37/kernel_oppo_msm8939`](https://github.com/OPPO-A37/kernel_oppo_msm8939) | `0.0` | `kernel/oppo/msm8939` |
| dependency | [`LineageOS/android_external_stlport`](https://github.com/LineageOS/android_external_stlport) | `lineage-15.1` | `external/stlport` |

Dua hal yang sering bikin orang salah pilih:

1. **Kernel-nya bernama `msm8939`, dan itu memang benar.** Repo itu adalah source drop
   gabungan OPPO untuk msm8916/msm8939 (R7s, R7Plus, F1f, A37f). Di dalamnya
   `arch/arm64/configs/lineageos_a37f_defconfig` berisi `CONFIG_ARCH_MSM8916=y` dan
   `CONFIG_MACH_15399=y`. Tiga device tree A37 yang berbeda (17.1, 18.1, 20)
   semuanya menunjuk ke `kernel/oppo/msm8939` + defconfig yang sama.
2. **Vendor `yashraj22/vendor_oppo_A37f` jangan dipakai** untuk 17.1 — branch-nya hanya
   `lineage-15.1` dan satu branch dump stock 5.1.1. Yang cocok untuk Android 10 adalah
   branch `ten` milik DeepakChaurasia30, karena `device.mk` baris 527 memanggil
   `$(call inherit-product, vendor/oppo/A37/A37-vendor.mk)`.

## Syarat host

- **Ubuntu 20.04 LTS** paling aman. 22.04 umumnya masih bisa. **24.04 belum tentu** —
  paket 32-bit legacy seperti `lib32ncurses5-dev` sudah tidak ada kandidatnya di sana.
- RAM ≥ 8 GB (16 GB ideal; kalau 8 GB tambahkan swap 16 GB)
- Disk kosong ≥ 200 GB
- Kuota internet ~60 GB untuk sync pertama

```bash
sudo apt update
sudo apt install -y bc bison build-essential ccache curl flex g++-multilib gcc-multilib \
  git gnupg gperf imagemagick lib32ncurses5-dev lib32readline-dev lib32z1-dev libelf-dev \
  liblz4-tool libncurses5 libncurses5-dev libsdl1.2-dev libssl-dev libxml2 libxml2-utils \
  lzop pngcrush rsync schedtool squashfs-tools xsltproc zip zlib1g-dev openjdk-8-jdk python2

mkdir -p ~/bin
curl https://storage.googleapis.com/git-repo-downloads/repo > ~/bin/repo
chmod a+x ~/bin/repo
export PATH=~/bin:$PATH

git config --global user.name  "Nama Kamu"
git config --global user.email "kamu@example.com"
```

> **Kalau `python2` tidak tersedia di distromu, itu tidak masalah** — lihat bagian berikut.
> Yang penting: **jangan pasang `python-is-python2`**, karena `repo` butuh python3 dan
> symlink itu akan merusaknya.

### Soal python2 pada distro modern

Kernel 3.10 memanggil compiler lewat wrapper python2 — `Makefile` baris 345:

```make
CC = $(srctree)/scripts/gcc-wrapper.py $(REAL_CC)
```

dan `scripts/gcc-wrapper.py` shebang-nya `#!/usr/bin/env python2` serta masih memakai
`print` statement gaya python2. Di host tanpa python2 build kernel berhenti dengan
`env: 'python2': No such file or directory`. Ubuntu 24.04 sudah tidak menyediakan paket
python2 sama sekali (`apt-cache policy python2` → *Candidate: (none)*).

`build.sh` menangani ini otomatis:

- kalau `python2` ada → wrapper asli dipakai apa adanya;
- kalau tidak ada tapi `python3` ada → `patches/gcc-wrapper.py` disalin ke
  `kernel/oppo/msm8939/scripts/gcc-wrapper.py`, aslinya disimpan sebagai
  `gcc-wrapper.py.orig`. Idempoten, aman dijalankan berulang;
- kalau dua-duanya tidak ada → script berhenti dengan pesan jelas.

### Warning tidak lagi menggagalkan build

Wrapper asli juga menggagalkan build begitu gcc mengeluarkan warning yang tidak ada di
daftar `allowed_warnings` — daftar berisi 8 baris yang ditulis tahun 2011. Pada source
OPPO ini gate tersebut menabrak, misalnya:

```
kernel/irq/pm.c:103:7: warning: unused variable 'suspend_abort' [-Wunused-variable]
error, forbidden warning: pm.c:103
make[3]: *** [scripts/Makefile.build:309: kernel/irq/pm.o] Error 1
```

Warning-nya sendiri benar — `suspend_abort` di `check_wakeup_irqs()` memang tidak pernah
dipakai karena `log_suspend_abort_reason()` dipanggil dengan format string langsung. Tapi
sebagai gerbang QA internal Qualcomm hal itu tidak relevan untuk membangun ROM, dan
menyisirnya satu per satu berarti puluhan iterasi build (~14 menit per iterasi).

Karena itu `patches/gcc-wrapper.py` **default-nya pass-through**: warning tetap tercetak
apa adanya, tapi tidak menggagalkan build. Error kompilasi asli tetap menggagalkan build
seperti biasa, karena exit status compiler diteruskan utuh (wrapper memakai `os.execvp`,
jadi tanpa overhead pipe dan urutan output persis seperti memanggil gcc langsung).

Kalau kamu ingin gerbang lama itu kembali:

```bash
GCC_WRAPPER_FATAL_WARNINGS=1 ./build.sh --no-sync
```

### Prebuilt webview dan Git LFS

`repo init` **wajib** memakai `--git-lfs`. Prebuilt `external/chromium-webview/prebuilt/arm/webview.apk`
(~91 MB) disimpan lewat Git LFS; tanpa flag itu yang tersync hanya file pointer 133 byte
berisi teks `version https://git-lfs.github.com/spec/v1`. Build tetap jalan sampai ~98%
lalu gagal di ujung:

```
FAILED: target Prebuilt: webview (out/.../webview_intermediates/package.apk)
out/.../package.apk: error: failed opening zip: Invalid file.
veridex E ... Expected valid zip or dex file
```

`build.sh` sekarang memakai `--git-lfs` saat init, dan `fix_lfs_pointers()` mendeteksi
pointer yang tersisa pada tree lama lalu menarik objeknya. Perbaikan manual:

```bash
cd ~/los17/external/chromium-webview/prebuilt/arm
git lfs install --local && git lfs pull
```

Perhatikan tiap arsitektur adalah project repo terpisah (`prebuilt/arm`, `prebuilt/arm64`,
`prebuilt/x86`, `prebuilt/x86_64`) — direktori induk `external/chromium-webview` sendiri
bukan git repo, jadi `git lfs pull` di sana akan menjawab *"Not in a Git repository"*.
A37 hanya butuh `arm`; atur lewat `LFS_ARCHS="arm arm64"` kalau perlu yang lain.

AOSP tidak menyediakan python2 sendiri untuk tahap ini: di `kernel.mk` LineageOS 17.1 ada
`PATH_OVERRIDE += $(TOOLS_PATH_OVERRIDE)`, tapi `TOOLS_PATH_OVERRIDE` tidak didefinisikan
di `build/core/config.mk` branch tersebut — jadi wrapper memang mengambil python dari host.

## Cara pakai

```bash
git clone <repo-ini> a37-build && cd a37-build
chmod +x build.sh
./build.sh
```

Opsi lain:

```bash
./build.sh --sync-only          # siapkan source saja
./build.sh --no-sync            # build ulang tanpa sync
./build.sh --recovery           # bangun recovery.img saja
./build.sh --clean              # bersihkan out/ device ini dulu
./build.sh --installclean       # buang file terpasang yang basi (setelah ganti tree)
./build.sh --jobs 4             # batasi paralelisme (host RAM kecil)
BUILD_DIR=/mnt/ssd/los17 ./build.sh
BUILD_LABEL=none ./build.sh     # buang label pada nama zip
BUILD_LABEL=vanilla ./build.sh  # lineage-17.1-<tgl>-UNOFFICIAL-vanilla-A37.zip
```

Default lokasi source: `~/los17` (ubah lewat `BUILD_DIR` atau `--dir`).

### Kalau mau manual

```bash
mkdir -p ~/los17 && cd ~/los17
repo init -u https://github.com/LineageOS/android.git -b lineage-17.1 --no-clone-bundle --git-lfs
mkdir -p .repo/local_manifests && cp /path/ke/A37.xml .repo/local_manifests/
repo sync -c --no-clone-bundle --no-tags --force-sync -j$(nproc --all)

# Hanya kalau host tidak punya python2:
cp /path/ke/patches/gcc-wrapper.py kernel/oppo/msm8939/scripts/gcc-wrapper.py

source build/envsetup.sh
breakfast A37
mka bacon
```

Tidak perlu menyiapkan toolchain kernel sendiri: pada LineageOS 17.1
`TARGET_KERNEL_CLANG_COMPILE` default-nya `false`, jadi kernel dibangun dengan GCC 4.9
prebuilt (`prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9`) yang sudah ada di
dalam source — persis yang dibutuhkan kernel 3.10. Device tree juga sudah membawa
`dtbtool/` sendiri untuk `dtbToolOppo`.

### Label pada nama zip

LineageOS menyusun nama zip dari `TARGET_UNOFFICIAL_BUILD_ID`. Variabel itu gampang
terwarisi dari `~/.bashrc` sisa build device lain, dan hasilnya zip A37 keluar dengan nama
yang menyesatkan, misalnya `lineage-17.1-20260728-UNOFFICIAL-microG-ReSukiSU-A37.zip`
padahal isinya LineageOS vanilla tanpa microG maupun KernelSU sama sekali.

`build.sh` memperingatkan kalau variabel itu diwarisi dari environment. Untuk mengendalikannya:

```bash
BUILD_LABEL=none ./build.sh --no-sync      # hapus label
BUILD_LABEL=vanilla ./build.sh --no-sync   # ganti label
```

Perlu diingat label ini bukan sekadar nama file — ia masuk ke `ro.lineage.version` di
`build.prop`, jadi mengubahnya berarti build ulang tahap image + packaging (beberapa menit
saja karena inkremental), bukan sekadar `mv`.

### Setelah mengganti device tree atau vendor

Wajib `--installclean` sekali. Build inkremental AOSP tidak membuang file yang tidak lagi
diminta `PRODUCT_PACKAGES`, jadi sisa tree lama tetap ikut ke dalam image. Contoh nyata saat
pindah ke tree `rb` — dua service memperebutkan instance `default` HAL yang sama:

```
android.hardware.light@2.0-service.a6000          ← sisa tree lama
android.hardware.light@2.0-service.oppo_msm8916   ← yang benar
android.hardware.bluetooth@1.0-service            ← sisa
android.hardware.bluetooth@1.0-service-qti        ← yang benar
```

## Hasil build

```
out/target/product/A37/lineage-17.1-<tanggal>-UNOFFICIAL-A37.zip
out/target/product/A37/recovery.img
```

## Pasang ke HP

1. **Backup dulu** — semua data akan hilang.
2. Unlock bootloader, lalu flash recovery:
   ```bash
   fastboot flash recovery recovery.img
   ```
   Langsung masuk recovery (Vol− + Power), jangan boot ke sistem dulu.
3. Di recovery: **Factory reset → Format data/factory reset** (data stock terenkripsi FDE,
   wajib diformat).
4. Pasang ROM:
   ```bash
   adb sideload lineage-17.1-*-UNOFFICIAL-A37.zip
   ```
5. GApps (opsional): **Open GApps ARM 10.0 varian `pico` saja** — RAM cuma 2 GB.
   Pasang sebelum boot pertama.
6. **Jangan pernah format partisi `firmware` dan `persist`** — di situ ada modem, kalibrasi
   sensor, dan MAC WiFi (`BOARD_ROOT_EXTRA_FOLDERS := firmware persist`).

Zip aman untuk semua varian: `TARGET_OTA_ASSERT_DEVICE := a37f,A37f,A37fw,a37fw,msm8916,msm8939`.

## Troubleshooting

| Gejala | Sebab & solusi |
|---|---|
| `env: 'python2': No such file or directory` saat build kernel | Jalankan lewat `build.sh` (wrapper otomatis dipatch ke python3), atau manual: `cp patches/gcc-wrapper.py ~/los17/kernel/oppo/msm8939/scripts/gcc-wrapper.py` |
| Build kernel gagal dengan `error, forbidden warning: <file>:<baris>` | Muncul kalau kamu memakai wrapper asli atau `GCC_WRAPPER_FATAL_WARNINGS=1`. Default `patches/gcc-wrapper.py` sudah pass-through, jadi jalankan lewat `build.sh` tanpa env itu |
| `repo sync` gagal pada `external/stlport` | Repo itu tidak punya branch `lineage-17.1`; `A37.xml` sudah mem-pin ke `lineage-15.1` |
| `breakfast A37` → device not found | Path harus persis `device/oppo/A37` (huruf besar), dan `repo sync` harus jalan setelah local manifest dipasang |
| Ninja terbunuh / host kehabisan RAM | Tambah swap 16 GB atau `./build.sh --jobs 4` |
| `unsupported reloc 43` / error linker 32-bit | Paket multilib kurang: `gcc-multilib g++-multilib lib32z1-dev` |
| `failed opening zip: Invalid file` pada target `webview` | Objek Git LFS belum ditarik — lihat bagian "Prebuilt webview dan Git LFS" |
| Build berhenti tanpa pesan jelas | Ulangi `./build.sh --no-sync`; error asli biasanya muncul di ~200 baris terakhir |

## Yang harus diterima apa adanya

- **SELinux permissive** — sudah dihardcode di device tree
  (`BOARD_KERNEL_CMDLINE += androidboot.selinux=permissive`, `SELINUX_IGNORE_NEVERALLOWS := true`).
  Akibatnya Play Integrity/SafetyNet gagal dan sebagian aplikasi bank/dompet digital menolak jalan.
- **`VENDOR_SECURITY_PATCH := 2016-01-01`** — blob-nya dari ColorOS 5.1.1. Patch level Android
  boleh baru, blob vendornya tidak.
- **Kamera HAL1 legacy + shim** (`TARGET_HAS_LEGACY_CAMERA_HAL1`, `libshim_camera`).
  Jangan berharap aplikasi Camera2 API / GCam berjalan mulus.
- **Userspace 32-bit** (`TARGET_ARCH := arm`, kernel `arm64`). Normal untuk device ini, tapi
  aplikasi arm64-only tidak bisa dipasang.
- **LineageOS 17.1 sudah EOL di hulu** — tidak ada patch keamanan baru untuk branch ini.
  Kalau ingin lebih baru: device tree [`udyneos-prjkt/android_device_oppo_A37`](https://github.com/udyneos-prjkt/android_device_oppo_A37)
  branch `lineage-18.1`, vendor branch `lineage-19.1`, kernel tetap sama.

## Status pengujian

Yang sudah diuji:

- `build.sh` lolos `bash -n`, parsing argumen dan `--help` benar.
- Guard host bekerja: pada Ubuntu 24.04 tanpa python2 script berhenti rapi, dan setelah
  patch ditambahkan ia lanjut ke mode python3.
- `patches/gcc-wrapper.py` diuji langsung dengan gcc dalam tiga skenario: kompilasi bersih
  lolos (exit 0); warning tidak menggagalkan build pada mode default dan object file tetap
  ada; `GCC_WRAPPER_FATAL_WARNINGS=1` mengembalikan perilaku lama (`error, forbidden
  warning:`, object dihapus, exit 1); error kompilasi asli tetap exit 1.
- `patch_kernel_python()` diuji pada tree tiruan: backup `.orig` dibuat, pemanggilan kedua
  tidak mengubah apa pun (idempoten), dan pembaruan isi `patches/gcc-wrapper.py` ikut
  tersalin ke tree kernel.
- `repo sync` penuh (~90 GB di disk) dan build kernel berjalan sampai
  `LD drivers/built-in.o` pada Ubuntu 24.04.

Yang **belum** diuji:

- Build penuh sampai menghasilkan zip. Kernel sudah lewat jauh, tapi tahap ROM
  (HAL, `dtbToolOppo`, packaging) belum tuntas dibuktikan.
- Hasil flashing ke perangkat fisik.

Kalau kamu menabrak error, tempel ~50 baris terakhir log-nya di Issues.

## Kredit

- [@yashraj22](https://github.com/yashraj22), [@sheikhshahnawaz41299](https://github.com/sheikhshahnawaz41299) — device tree & kernel A37
- [@DeepakChaurasia30](https://github.com/DeepakChaurasia30) — vendor tree & device tree 19.1
- Tim LineageOS dan kontributor msm8916/msm8939

Build ini **UNOFFICIAL**. Pakai dengan risiko sendiri — salah flash bisa membuat perangkat brick.
