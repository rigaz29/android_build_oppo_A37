# Changelog — LineageOS 17.1 UNOFFICIAL untuk OPPO A37

**Build:** `lineage-17.1-20260731-UNOFFICIAL-A37.zip`
**Tanggal:** 31 Juli 2026
**Base:** LineageOS 17.1 (Android 10) — MSM8916 (Snapdragon 410)

---

## Kernel (3.10.108)

Fork: [rigaz29/kernel_oppo_msm8939](https://github.com/rigaz29/kernel_oppo_msm8939) — branch `lz4-backport`

### Baru
- **LZ4 compression untuk zram** — backport library LZ4 dari kernel 3.18 LTS
  (`lib/lz4/`, `include/linux/lz4.h`). Driver zram sudah punya hook LZ4 sejak
  awal tapi library-nya tidak pernah disertakan. LZ4 2–3× lebih cepat dari LZO
  dengan rasio kompresi ~10–20% lebih rendah — tradeoff yang tepat untuk
  device low-end di mana CPU adalah bottleneck saat swap aktif.
- **LZ4 sebagai default compressor zram** — `default_compressor` di
  `zram_drv.c` diubah dari `"lzo"` ke `"lz4"`. Tidak perlu set manual lewat
  init script.
- **CONFIG_IPA + CONFIG_RMNET_IPA** — hardware data-path accelerator Qualcomm
  diaktifkan (sebelumnya hanya ada di defconfig arm, hilang di arm64).
  Meningkatkan throughput data seluler dan mengurangi beban CPU.
- **CONFIG_QPNP_COINCELL** — charging RTC backup battery diaktifkan.
- **CONFIG_NLS_UTF8** — dukungan filename UTF-8 di USB OTG dan SD card
  (sebelumnya hilang di defconfig arm64).
- **CONFIG_POWER_RESET** — parent config untuk `CONFIG_POWER_RESET_MSM`
  ditambahkan (sebelumnya hanya child-nya yang ada).

### Fix
- **v-cutoff-uv baterai 15399: 3.4V → 3.45V** (7 file batterydata DTS) —
  fix off-mode charging yang sebelumnya hanya diterapkan ke project 15109.
  Tanpa ini, A37f (15399) bisa **brick** setelah baterai habis total karena
  tegangan turun di bawah minimum bootloader.
- **Use-after-free di `fs/proc/base.c`** — hack app-killer mengakses
  `task->comm` setelah `put_task_struct()` melepas task struct. Diganti ke
  buffer `task_comm` yang sudah di-copy sebelumnya. Mencegah potensial
  kernel panic.
- **DTS: `status = "disable"` → `"disabled"`** (node `avago@39` di
  `msm8916-mtp-15399.dtsi`) — nilai `"disable"` tidak dikenali DT parser,
  sehingga node sensor APDS9900 tetap di-probe dan berpotensi konflik I2C.

### Cleanup
- Hapus 6 entri duplikat di arm defconfig (CPU freq governors + CPU_IDLE).
- Hapus `CONFIG_DEBUG_INFO` dari arm defconfig (mengurangi ukuran kernel
  image ~10–20 MB).

---

## Device Tree

Fork: [rigaz29/rb_device_oppo_A37](https://github.com/rigaz29/rb_device_oppo_A37) — branch `rb`

### Baru
- **Double-tap-to-wake (DT2W)** — integrasi driver gesture Synaptics OPPO
  (`/proc/touchpanel/double_tap_enable`), power HAL toggle, keylayout, dan
  SELinux policy.
- **Kompresi LZ4 untuk zram** — `write /sys/block/zram0/comp_algorithm lz4`
  di `init.target.rc` (sebagai fallback jika default compressor belum
  berubah).

### Fix
- **Tombol kapasitif mati setelah DT2W** — `synaptics-s3203.kl` hanya
  memetakan `key 62 WAKEUP`. Android memuat keylayout device-specific
  sebagai **pengganti** `Generic.kl` (bukan merge), sehingga BACK (158),
  HOME (172), dan APP_SWITCH (139) tidak terpetakan. Ditambahkan mapping
  yang sama dengan `ft5x06_ts.kl`.

### Sudah ada di fork (dari commit sebelumnya)
- Buang path toolchain hardcoded `/tmp/src/android/tc`
- Build `cryptfshw@1.0-service-qti.qsee` (bukan cuma `-base`)
- Fix sisa kang a6000 + file yang lupa disambungkan
- Buang tuning/fitur yang tidak diimplementasikan kernel
- Pasang `libwpa_client` untuk VoLTE
- Arahkan blob `stats_algorithm` ke shim yang benar
- Implementasikan `powerHint` + `setInteractive` di power HAL
- Fix zram: berhenti meminta compressor yang tidak ada
- Buang `latch_unsignaled` + 7 properti SF yang nol pembaca

---

## Build System

Repo: [rigaz29/android_build_oppo_A37](https://github.com/rigaz29/android_build_oppo_A37)

- Semua patch device tree (`patches/device-A37-*.patch`) dihapus — sudah
  menyatu di fork device tree.
- Fungsi `patch_device_tree()` dihapus dari `build.sh`.
- Kernel di-pin ke fork `rigaz29/kernel_oppo_msm8939` branch `lz4-backport`.
- Device tree di-pin ke fork `rigaz29/rb_device_oppo_A37` branch `rb`.

---

## Dikenal / Belum Difix

- Battery temperature hack -10°C di `oppo_adc.c` — blind offset tanpa
  dokumentasi root cause. Perlu investigasi ADC calibration.
- 18+ debug options masih aktif di defconfig (IKCONFIG, SCHEDSTATS,
  DYNAMIC_DEBUG, USB_MON, dll) — overhead runtime minor.
- `CONFIG_MSM_OCMEM` aktif tapi MSM8916 tidak punya OCMEM — dead code.
- IOMMU fault reporting di-disable di DTS — menyulitkan debugging DMA.
- exFAT kernel driver belum ada — microSD >32GB (exFAT) tidak bisa di-mount.
  Userspace tools (`mkfs.exfat`, `fsck.exfat`) sudah ada di ROM.
