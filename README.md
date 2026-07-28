# LineageOS 17.1 untuk OPPO A37 / A37f / A37fw

Local manifest, patch, dan script build untuk membangun **LineageOS 17.1 (Android 10)**
pada OPPO A37 — codename LineageOS `A37`, Qualcomm **MSM8916 / Snapdragon 410**.

| | |
|---|---|
| SoC | Qualcomm MSM8916 (Snapdragon 410), 4× Cortex-A53 1.2 GHz, Adreno 306 |
| RAM / ROM | 2 GB / 16 GB |
| Layar | 5.0" 720×1280 |
| Nomor proyek OPPO | 15399 |
| Android bawaan | 5.1.1 (ColorOS 3.0) |

**Status: terbukti boot sampai homescreen** (28 Juli 2026). Lihat [Status pengujian](#status-pengujian)
untuk apa yang sudah dan belum diverifikasi.

## Isi repo

| File | Fungsi |
|---|---|
| `A37.xml` | Local manifest — device tree, vendor, kernel, dependency, semuanya di-pin ke SHA |
| `build.sh` | Script satu-jalan: cek host → init → sync → perbaiki LFS → patch → build |
| `patches/device-A37-cryptfshw.patch` | Menambah `cryptfshw@1.0-service-qti.qsee` ke `PRODUCT_PACKAGES` |
| `patches/device-A37-toolchain.patch` | Membuang path toolchain milik mesin pembuat device tree |
| `patches/gcc-wrapper.py` | Versi python3 dari wrapper kernel — hanya perlu untuk kernel selain yang di-pin |
| `README.md` | Dokumen ini |

## Konfigurasi yang terbukti boot

`A37.xml` mem-pin setiap project ke commit (`revision` = SHA 40 karakter, `upstream` = branch),
supaya `repo sync` kapan pun menghasilkan tree yang sama.

| Komponen | Repo | Commit | Branch | Path |
|---|---|---|---|---|
| device | [`meghs-playground/rb_device_oppo_A37`](https://github.com/meghs-playground/rb_device_oppo_A37) | `e03d9844ea01` | `rb` | `device/oppo/A37` |
| vendor | [`meghs-playground/rb-vendor_oppo_A37`](https://github.com/meghs-playground/rb-vendor_oppo_A37) | `6a644358bba6` | `lineage-17.1` | `vendor/oppo` |
| kernel | [`meghs-playground/kernel_oppo_msm8939`](https://github.com/meghs-playground/kernel_oppo_msm8939) | `0efa2fea8099` | `0.0` | `kernel/oppo/msm8939` |
| timekeep | [`LineageOS/android_hardware_sony_timekeep`](https://github.com/LineageOS/android_hardware_sony_timekeep) | `858c544d1ad1` | `lineage-17.1` | `hardware/sony/timekeep` |
| stlport | [`LineageOS/android_external_stlport`](https://github.com/LineageOS/android_external_stlport) | — | `lineage-15.1` | `external/stlport` |

Empat hal yang sering bikin salah pasang:

1. **Kernel bernama `msm8939` dan itu memang benar.** Repo tersebut adalah source drop
   gabungan OPPO untuk msm8916/msm8939 (R7s, R7Plus, F1f, A37f). Di dalamnya
   `arch/arm64/configs/lineageos_a37f_defconfig` berisi `CONFIG_ARCH_MSM8916=y` dan
   `CONFIG_MACH_15399=y` — nomor proyek OPPO untuk A37.
2. **Vendor dipasang ke `vendor/oppo`, bukan `vendor/oppo/A37`.** Root repo vendor berisi
   folder `A37/`, jadi path project-nya satu tingkat di atas.
3. **Device tree dan vendor harus sepasang.** Vendor ini membawa prebuilt
   `bluetooth@1.0-service-qti`, `perf@1.0-service`, dan `iop@1.0/2.0`; mencampur dengan
   device tree lain berisiko dua service memperebutkan instance `default` HAL yang sama.
4. **SHA di manifest harus lengkap 40 karakter.** `repo` memperlakukan SHA singkat sebagai
   nama branch dan gagal dengan `fatal: couldn't find remote ref refs/heads/<sha>`.

Varian kernel [`kernel_oppo_msm8939_`](https://github.com/meghs-playground/kernel_oppo_msm8939_)
(akhiran garis bawah) adalah versi ber-root KernelSU — pakai itu hanya kalau memang ingin root.

Ingin mengikuti perkembangan terbaru alih-alih commit yang di-pin? Ganti `revision` dengan
nama branch pada atribut `upstream` masing-masing.

## Syarat host

- **Ubuntu 20.04 LTS** paling aman, tapi konfigurasi ini berhasil dibangun di
  **Ubuntu 24.04.4** (12 core, 11 GB RAM). Kernel yang di-pin tidak butuh `python2`, dan
  ketiadaan `lib32ncurses5-dev` di 24.04 ternyata tidak menghalangi build.
- RAM ≥ 8 GB (16 GB ideal; kalau 8 GB tambahkan swap 16 GB)
- Disk kosong ≥ 200 GB — source ~90 GB, `out/` ~60 GB
- Kuota internet ~60 GB untuk sync pertama

```bash
sudo apt update
sudo apt install -y bc bison build-essential ccache curl flex g++-multilib gcc-multilib \
  git git-lfs gnupg gperf imagemagick lib32readline-dev lib32z1-dev libelf-dev \
  liblz4-tool libncurses5 libncurses5-dev libsdl1.2-dev libssl-dev libxml2 libxml2-utils \
  lzop pngcrush rsync schedtool squashfs-tools xsltproc zip zlib1g-dev openjdk-8-jdk

# di Ubuntu 20.04/22.04 tambahkan juga: lib32ncurses5-dev

mkdir -p ~/bin
curl https://storage.googleapis.com/git-repo-downloads/repo > ~/bin/repo
chmod a+x ~/bin/repo
export PATH=~/bin:$PATH

git config --global user.name  "Nama Kamu"
git config --global user.email "kamu@example.com"
```

> **Jangan pasang `python-is-python2`.** `repo` butuh python3 dan symlink itu merusaknya.

---

# Jalur A — build dengan `build.sh`

Cara yang disarankan. Script menangani semua jebakan yang dijelaskan di
[Catatan teknis](#catatan-teknis).

```bash
git clone https://github.com/rigaz29/android_build_oppo_A37 a37-build
cd a37-build
chmod +x build.sh
./build.sh
```

Itu saja. Sekali jalan: `repo init` → sync → perbaiki LFS → terapkan patch → build.
Hasilnya di `~/los17/out/target/product/A37/`.

## Opsi

| Perintah | Guna |
|---|---|
| `./build.sh` | init + sync + build penuh |
| `./build.sh --no-sync` | build ulang tanpa sync — dipakai untuk hampir semua iterasi |
| `./build.sh --sync-only` | siapkan source saja, jangan build |
| `./build.sh --recovery` | bangun `recovery.img` saja |
| `./build.sh --installclean` | buang file terpasang yang basi, lalu build — **wajib setelah ganti device tree/vendor** |
| `./build.sh --clean` | hapus `out/target/product/A37` dulu, lalu build |
| `./build.sh --jobs 4` | batasi paralelisme untuk host ber-RAM kecil |
| `./build.sh --dir /mnt/ssd/los17` | pilih lokasi source (default `~/los17`) |
| `./build.sh --help` | ringkasan opsi |

Variabel lingkungan: `BUILD_DIR`, `JOBS`, `CCACHE_SIZE` (default 50G), `LFS_ARCHS`
(default `arm`), `BUILD_LABEL` (`none` untuk membuang label pada nama zip).

## Yang dikerjakan otomatis

| Tahap | Isi |
|---|---|
| Cek host | `git`, `repo`, `git config user.email`, python2/python3, peringatan RAM & disk, aktifkan ccache |
| Init | `repo init … --git-lfs` (juga pada tree lama yang sudah ada) |
| Sync | `repo sync -c --no-clone-bundle --no-tags --force-sync` |
| LFS | deteksi `webview.apk` yang masih pointer 133 byte, lalu `git lfs pull` di project yang tepat |
| Patch kernel | ganti `scripts/gcc-wrapper.py` dengan versi python3 **hanya** kalau kernel memakainya dan host tanpa python2 |
| Patch device tree | terapkan semua `patches/device-A37-*.patch` secara idempoten |
| Label | peringatan kalau `TARGET_UNOFFICIAL_BUILD_ID` terwarisi dari environment |
| Build | `breakfast A37` lalu `mka bacon` (atau `mka recoveryimage`) |

---

# Jalur B — build manual

Kalau ingin mengerjakan sendiri tanpa script, atau perlu menyisipkan langkah lain di
tengah. Semua perintah di bawah setara dengan yang dilakukan `build.sh`.

### 1. Siapkan source

```bash
mkdir -p ~/los17 && cd ~/los17
repo init -u https://github.com/LineageOS/android.git -b lineage-17.1 \
          --no-clone-bundle --git-lfs
```

`--git-lfs` wajib, jangan dilewat — lihat [Prebuilt webview dan Git LFS](#prebuilt-webview-dan-git-lfs).

### 2. Pasang local manifest

```bash
mkdir -p .repo/local_manifests
cp /path/ke/a37-build/A37.xml .repo/local_manifests/
```

### 3. Sync

```bash
repo sync -c --no-clone-bundle --no-tags --force-sync -j$(nproc --all)
```

### 4. Pastikan prebuilt LFS benar-benar terunduh

```bash
ls -l external/chromium-webview/prebuilt/arm/webview.apk    # harus ~91 MB, bukan 133 byte
```

Kalau masih pointer:

```bash
cd external/chromium-webview/prebuilt/arm
git lfs install --local && git lfs pull
cd ~/los17
```

### 5. Terapkan patch device tree

```bash
patch -p1 -d device/oppo/A37 < /path/ke/a37-build/patches/device-A37-cryptfshw.patch
patch -p1 -d device/oppo/A37 < /path/ke/a37-build/patches/device-A37-toolchain.patch
```

Verifikasi:

```bash
grep -c 'cryptfshw@1.0-service-qti.qsee' device/oppo/A37/device.mk   # → 1
grep -c '^KERNEL_TOOLCHAIN := /tmp'      device/oppo/A37/BoardConfig.mk   # → 0
```

### 6. Kernel: hanya kalau memakai kernel lain

Kernel yang di-pin sudah membuang `scripts/gcc-wrapper.py` (`CC = $(CROSS_COMPILE)gcc`),
jadi langkah ini **tidak perlu**. Untuk kernel lain yang masih memakainya, di host tanpa
python2:

```bash
cp /path/ke/a37-build/patches/gcc-wrapper.py kernel/oppo/msm8939/scripts/gcc-wrapper.py
chmod +x kernel/oppo/msm8939/scripts/gcc-wrapper.py
```

### 7. Bersihkan label warisan

```bash
unset TARGET_UNOFFICIAL_BUILD_ID    # kalau tidak, nama zip ikut label build device lain
```

### 8. Build

```bash
source build/envsetup.sh
breakfast A37

m installclean      # hanya kalau device tree/vendor baru saja diganti

mka bacon           # ROM lengkap
# atau
mka recoveryimage   # recovery.img saja
```

Tidak perlu menyiapkan toolchain kernel: pada LineageOS 17.1 `TARGET_KERNEL_CLANG_COMPILE`
default-nya `false`, jadi kernel dibangun dengan GCC 4.9 prebuilt
(`prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9`) yang sudah ada di source.
Device tree juga membawa `dtbtool/` sendiri untuk `dtbToolOppo`.

### 9. Periksa hasilnya sebelum flash

Pastikan tidak ada dua service untuk satu HAL:

```bash
ls out/target/product/A37/system/vendor/bin/hw/
```

Kalau muncul pasangan seperti `light@2.0-service.a6000` bersama
`light@2.0-service.oppo_msm8916`, berarti ada sisa build lama — jalankan `m installclean`
lalu `mka bacon` ulang.

## Manual vs `build.sh`

| Langkah | `build.sh` | Manual |
|---|---|---|
| `--git-lfs` saat init | otomatis | harus diingat sendiri |
| Objek LFS yang masih pointer | dideteksi & ditarik | cek & `git lfs pull` sendiri |
| Patch device tree | idempoten, otomatis | `patch -p1` dua berkas |
| Wrapper kernel python3 | dipasang bila perlu saja | salin manual bila perlu |
| Label zip | `BUILD_LABEL=none` | `unset TARGET_UNOFFICIAL_BUILD_ID` |
| ccache | diaktifkan otomatis | `export USE_CCACHE=1 CCACHE_EXEC=$(which ccache)` |
| Cek RAM/disk | ada peringatan | — |
| `installclean` | `--installclean` | `m installclean` |

---

## Hasil build

```
out/target/product/A37/lineage-17.1-<tanggal>-UNOFFICIAL-A37.zip   ~450 MB
out/target/product/A37/recovery.img
out/target/product/A37/boot.img
```

## Pasang ke HP

1. **Backup dulu** — semua data akan hilang.
2. Unlock bootloader, lalu flash recovery hasil build ini (jangan pakai recovery dari build
   device tree lain):
   ```bash
   fastboot flash recovery recovery.img
   ```
   Langsung masuk recovery (Vol− + Power), jangan boot ke sistem dulu.
3. Di recovery: **Factory reset → Format data/factory reset**. Data stock terenkripsi FDE,
   wajib diformat.
4. Pasang ROM:
   ```bash
   adb sideload lineage-17.1-*-UNOFFICIAL-A37.zip
   ```
5. GApps (opsional): **Open GApps ARM 10.0 varian `pico` saja** — RAM cuma 2 GB. Pasang
   sebelum boot pertama.
6. **Jangan pernah format partisi `firmware` dan `persist`** — di situ ada modem, kalibrasi
   sensor, dan MAC WiFi (`BOARD_ROOT_EXTRA_FOLDERS := firmware persist`).

Zip aman untuk semua varian:
`TARGET_OTA_ASSERT_DEVICE := a37f,A37f,A37fw,a37fw,msm8916,msm8939`.

## Troubleshooting

| Gejala | Sebab & solusi |
|---|---|
| `ccache: error: execute_noreturn of /tmp/src/android/tc/bin/aarch64-linux-android-gcc` | `KERNEL_TOOLCHAIN` hardcoded di device tree — terapkan `patches/device-A37-toolchain.patch` |
| `failed opening zip: Invalid file` pada target `webview` | Objek Git LFS belum ditarik — lihat [Prebuilt webview dan Git LFS](#prebuilt-webview-dan-git-lfs) |
| `fatal: couldn't find remote ref refs/heads/<sha>` | SHA di manifest tidak lengkap; harus 40 karakter |
| `repo sync` gagal pada `external/stlport` | Repo itu tidak punya branch `lineage-17.1`; `A37.xml` sudah mem-pin ke `lineage-15.1` |
| `env: 'python2': No such file or directory` saat build kernel | Kernel lain yang masih memakai wrapper — salin `patches/gcc-wrapper.py`, atau jalankan lewat `build.sh` |
| `error, forbidden warning: <file>:<baris>` | Gate warning wrapper Qualcomm; `patches/gcc-wrapper.py` default-nya pass-through |
| `breakfast A37` → device not found | Path harus persis `device/oppo/A37`, dan sync harus jalan setelah local manifest dipasang |
| Bootloop di bootanimation | Cek dua service untuk satu HAL (`ls .../vendor/bin/hw/`) dan `m installclean`; lihat [Bootloop dan cryptfshw](#bootloop-dan-cryptfshw) |
| Ninja terbunuh / host kehabisan RAM | Tambah swap 16 GB atau `--jobs 4` |
| `unsupported reloc 43` / error linker 32-bit | Paket multilib kurang: `gcc-multilib g++-multilib lib32z1-dev` |
| Build berhenti tanpa pesan jelas | Error asli ada di `out/error.log`, bukan di ~20 baris terakhir terminal |

---

## Catatan teknis

Kenapa patch dan langkah tambahan di atas ada. Semuanya berasal dari kegagalan nyata saat
membangun ROM ini.

### Bootloop dan cryptfshw

ROM build pertama boot sampai bootanimation lalu reboot berulang. Membandingkan isinya
dengan ROM 17.1 yang terbukti jalan menunjukkan selisihnya bukan blob kamera/GPS,
melainkan **service HAL**: `manifest.xml` mendeklarasikan HAL sebagai `hwbinder` tanpa ada
proses yang melayaninya.

Tersangka utamanya `vendor.qti.hardware.cryptfshw` — `vold` membutuhkannya karena
`BoardConfig.mk` menyalakan `TARGET_HW_DISK_ENCRYPTION := true`, tapi `device.mk` hanya
memuat `vendor.qti.hardware.cryptfshw@1.0-base` dan vendor tree tidak membawa prebuilt
service-nya. `patches/device-A37-cryptfshw.patch` menambahkan
`vendor.qti.hardware.cryptfshw@1.0-service-qti.qsee`, yang sumbernya sudah ada di
`hardware/lineage/interfaces/cryptfshw/1.0/qsee`.

Perbaikan itu masuk bersamaan dengan pindah ke pasangan device tree + vendor `rb` dan
`installclean`, jadi mana yang paling menentukan tidak pernah dipisahkan.

### Toolchain hardcoded di device tree

`BoardConfig.mk` device tree menyimpan path mesin pembuatnya:

```makefile
TARGET_KERNEL_CROSS_COMPILE_PREFIX := aarch64-linux-android-
KERNEL_TOOLCHAIN := /tmp/src/android/tc/bin
```

Menurut `vendor/lineage/config/BoardConfigKernel.mk`, menyetel
`TARGET_KERNEL_CROSS_COMPILE_PREFIX` justru **membatalkan** default
`KERNEL_TOOLCHAIN_arm64`, jadi kedua baris harus dibuang — itu isi
`patches/device-A37-toolchain.patch`.

### Sisa build lama setelah ganti tree

Build inkremental AOSP tidak membuang file yang tidak lagi diminta `PRODUCT_PACKAGES`,
sehingga sisa device tree lama tetap masuk image:

```
android.hardware.light@2.0-service.a6000          ← sisa tree lama
android.hardware.light@2.0-service.oppo_msm8916   ← yang benar
android.hardware.bluetooth@1.0-service            ← sisa
android.hardware.bluetooth@1.0-service-qti        ← yang benar
```

Dua service memperebutkan instance `default` HAL yang sama adalah resep bootloop
tersendiri. Karena itu `m installclean` (atau `--installclean`) wajib sekali setiap ganti
device tree/vendor.

### Prebuilt webview dan Git LFS

`external/chromium-webview/prebuilt/arm/webview.apk` (~91 MB) disimpan lewat Git LFS. Tanpa
`--git-lfs` saat `repo init`, yang tersync hanya pointer 133 byte berisi
`version https://git-lfs.github.com/spec/v1`, dan build baru gagal di ~98%:

```
FAILED: target Prebuilt: webview (out/.../webview_intermediates/package.apk)
out/.../package.apk: error: failed opening zip: Invalid file.
```

Tiap arsitektur adalah project repo terpisah (`prebuilt/arm`, `arm64`, `x86`, `x86_64`);
direktori induk `external/chromium-webview` bukan git repo, jadi `git lfs pull` di sana
menjawab *"Not in a Git repository"*. A37 hanya butuh `arm`.

### Wrapper python2 pada kernel MSM 3.10

Tidak relevan untuk kernel yang di-pin, tapi berlaku untuk kebanyakan kernel msm8916/8939
lain. Kernel 3.10 memanggil compiler lewat `Makefile`:

```make
CC = $(srctree)/scripts/gcc-wrapper.py $(REAL_CC)
```

`gcc-wrapper.py` ber-shebang `python2` dan memakai `print` statement, sementara Ubuntu 24.04
sudah tidak menyediakan paket python2. AOSP juga tidak menyuplainya untuk tahap ini:
`kernel.mk` LineageOS 17.1 menambahkan `$(TOOLS_PATH_OVERRIDE)`, tapi variabel itu tidak
didefinisikan di `build/core/config.mk` branch tersebut.

`patches/gcc-wrapper.py` adalah port python3-nya, dengan satu perubahan perilaku:
**warning tidak lagi menggagalkan build**. Daftar `allowed_warnings` bawaan hanya 8 baris
dari 2011 dan menabrak source OPPO, misalnya `unused variable 'suspend_abort'` di
`kernel/irq/pm.c:103`. Wrapper meneruskan proses lewat `os.execvp`, jadi exit status
compiler tetap utuh — error kompilasi asli tetap menggagalkan build. Untuk mengembalikan
gerbang lama: `GCC_WRAPPER_FATAL_WARNINGS=1`.

### Label pada nama zip

LineageOS menyusun nama zip dari `TARGET_UNOFFICIAL_BUILD_ID`, yang gampang terwarisi dari
`~/.bashrc` sisa build device lain — misalnya zip A37 keluar bernama
`lineage-17.1-…-UNOFFICIAL-microG-ReSukiSU-A37.zip` padahal isinya vanilla tanpa microG
maupun KernelSU. Label ini juga masuk ke `ro.lineage.version` di `build.prop`, jadi
mengubahnya berarti build ulang tahap packaging, bukan sekadar `mv`.

---

## Yang harus diterima apa adanya

- **SELinux permissive** — dihardcode di device tree
  (`BOARD_KERNEL_CMDLINE += androidboot.selinux=permissive`, `SELINUX_IGNORE_NEVERALLOWS := true`).
  Play Integrity/SafetyNet gagal; sebagian aplikasi bank/dompet digital menolak jalan.
- **`VENDOR_SECURITY_PATCH := 2016-01-01`** — blob dari ColorOS 5.1.1. Patch level Android
  boleh baru, blob vendornya tidak.
- **Kamera HAL1 legacy + shim** (`TARGET_HAS_LEGACY_CAMERA_HAL1`, `libshim_camera`).
  Aplikasi Camera2 API / GCam jangan diharap mulus.
- **Userspace 32-bit** (`TARGET_ARCH := arm`, kernel `arm64`) — aplikasi arm64-only tidak
  bisa dipasang.
- **LineageOS 17.1 sudah EOL di hulu** — tidak ada patch keamanan baru untuk branch ini.
  Kalau ingin lebih baru: device tree
  [`udyneos-prjkt/android_device_oppo_A37`](https://github.com/udyneos-prjkt/android_device_oppo_A37)
  branch `lineage-18.1`, kernel tetap sama.

## Status pengujian

Sudah diverifikasi:

- Build penuh selesai dan menghasilkan zip 450 MB (`#### build completed successfully ####`).
- **ROM terpasang di perangkat dan boot sampai homescreen.**
- Tidak ada duplikat service HAL di `vendor/bin/hw/` setelah `installclean`.
- Semua HAL yang tadinya kosong kini terisi: `cryptfshw@1.0-service-qti.qsee`,
  `bluetooth@1.0-service-qti`, `perf@1.0-service`, `light@2.0-service.oppo_msm8916`,
  `wifi@1.0-service.legacy`, `livedisplay` (legacymm + sysfs), `drm@1.1-service.widevine`,
  `vendor/bin/timekeep`.
- `repo sync` ulang dengan manifest ber-pin mengembalikan keempat HEAD ke commit yang benar.
- `patches/gcc-wrapper.py` diuji langsung dengan gcc: kompilasi bersih exit 0; warning tidak
  menggagalkan build dan object tetap ada; `GCC_WRAPPER_FATAL_WARNINGS=1` mengembalikan
  perilaku lama; error kompilasi asli tetap exit 1.

Belum diverifikasi:

- Fungsi per-perangkat keras setelah boot: WiFi, Bluetooth, kamera, GPS, panggilan/sinyal,
  audio, sensor, pemutaran video.
- Masih ada **43 berkas** yang berbeda dari ROM 17.1 pembanding, antara lain
  `libshims_flp.so`, `libshims_get_process_name.so`, dan `libantradio.so`. Sebagian memang
  wajar berbeda antar-build (`bin/healthd`, `etc/firmware/modem.b*`), sebagian bisa jadi
  penyebab fitur tertentu mati.

Menemukan error? Sertakan ~50 baris terakhir `out/error.log` di Issues.

## Kredit

- [@meghs-playground](https://github.com/meghs-playground) — device tree `rb`, vendor, dan kernel yang dipakai di sini
- [@DeepakChaurasia30](https://github.com/DeepakChaurasia30) — tree `rb` hulu dan vendor A37
- [@yashraj22](https://github.com/yashraj22), [@sheikhshahnawaz41299](https://github.com/sheikhshahnawaz41299) — device tree & kernel A37 generasi sebelumnya
- Tim LineageOS dan kontributor msm8916/msm8939

Build ini **UNOFFICIAL**. Pakai dengan risiko sendiri — salah flash bisa membuat perangkat brick.
