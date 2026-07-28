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
| `build.sh` | Script satu-jalan: cek host → `repo init` → `repo sync` → build |
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

- **Ubuntu 20.04 LTS** (di 22.04+ paket `lib32ncurses5-dev` / `libncurses5` sudah dibuang)
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

> **`python2` wajib, tapi jangan pasang `python-is-python2`.**
> Kernel 3.10 ini memakai `scripts/gcc-wrapper.py` yang shebang-nya `#!/usr/bin/env python2`
> (lihat `Makefile` baris 345: `CC = $(srctree)/scripts/gcc-wrapper.py $(REAL_CC)`),
> sementara `repo` butuh python3. Cukup sediakan binary `python2`; jangan ubah symlink `python`.

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
./build.sh --jobs 4             # batasi paralelisme (host RAM kecil)
BUILD_DIR=/mnt/ssd/los17 ./build.sh
```

Default lokasi source: `~/los17` (ubah lewat `BUILD_DIR` atau `--dir`).

### Kalau mau manual

```bash
mkdir -p ~/los17 && cd ~/los17
repo init -u https://github.com/LineageOS/android.git -b lineage-17.1 --no-clone-bundle
mkdir -p .repo/local_manifests && cp /path/ke/A37.xml .repo/local_manifests/
repo sync -c --no-clone-bundle --no-tags --force-sync -j$(nproc --all)

source build/envsetup.sh
breakfast A37
mka bacon
```

Tidak perlu menyiapkan toolchain kernel sendiri: pada LineageOS 17.1
`TARGET_KERNEL_CLANG_COMPILE` default-nya `false`, jadi kernel dibangun dengan GCC 4.9
prebuilt (`prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9`) yang sudah ada di
dalam source — persis yang dibutuhkan kernel 3.10. Device tree juga sudah membawa
`dtbtool/` sendiri untuk `dtbToolOppo`.

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
| `env: 'python2': No such file or directory` saat build kernel | `sudo apt install python2` (bukan `python-is-python2`) |
| `repo sync` gagal pada `external/stlport` | Repo itu tidak punya branch `lineage-17.1`; `A37.xml` sudah mem-pin ke `lineage-15.1` |
| `breakfast A37` → device not found | Path harus persis `device/oppo/A37` (huruf besar), dan `repo sync` harus jalan setelah local manifest dipasang |
| Ninja terbunuh / host kehabisan RAM | Tambah swap 16 GB atau `./build.sh --jobs 4` |
| `unsupported reloc 43` / error linker 32-bit | Paket multilib kurang: `gcc-multilib g++-multilib lib32z1-dev` |
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

## Kredit

- [@yashraj22](https://github.com/yashraj22), [@sheikhshahnawaz41299](https://github.com/sheikhshahnawaz41299) — device tree & kernel A37
- [@DeepakChaurasia30](https://github.com/DeepakChaurasia30) — vendor tree & device tree 19.1
- Tim LineageOS dan kontributor msm8916/msm8939

Build ini **UNOFFICIAL**. Pakai dengan risiko sendiri — salah flash bisa membuat perangkat brick.
