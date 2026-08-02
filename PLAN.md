# Rencana dan progres — OPPO A37

> ## ⛔ PROYEK 19.1 DIHENTIKAN — 2 Agustus 2026
>
> ROM berhasil dibangun dan di-flash, lalu **stuck di logo OPPO** — tidak sampai
> bootanimation, dan `adb` tidak terdeteksi sama sekali meski build varian `eng` dengan
> `ro.adb.secure=0`. Diagnosis berhenti di sini atas keputusan pemilik proyek.
>
> **Tidak ada yang dihapus.** `/root/los19` (130 GB) masih utuh, seluruh branch dan repo di
> GitHub masih ada, ROM 19.1 beserta boot/recovery tersimpan di `/root/a37-dl`. Dokumen ini
> tetap akurat sebagai catatan sejauh mana pekerjaan sampai — **jangan mulai ulang dari nol
> kalau suatu saat dilanjutkan.**
>
> `A37.xml` (17.1) sudah dikembalikan ke kernel `70ef81d` yang terbukti boot, supaya ROM 17.1
> yang jalan di perangkat tidak ikut tergantung pada pekerjaan yang belum teruji.
>
> Kalau dilanjutkan, titik lanjutnya ada di [Langkah diagnosis berikutnya](#langkah-diagnosis-berikutnya-belum-dijalankan).

Dokumen kerja untuk menaikkan OPPO A37 (MSM8916) dari LineageOS 17.1 ke versi yang lebih
baru. `README.md` mendokumentasikan ROM 17.1 yang sudah jalan.

**Target: LineageOS 19.1 (Android 12) — diputuskan 1 Agustus 2026.** 18.1 sempat jadi
kandidat karena eBPF di sana masih opsional, tapi pilihan jatuh ke 19.1 dan konsekuensinya
diterima: dua tambalan userspace yang harus dirawat. Urutan pengerjaannya ada di
[Rencana implementasi](#rencana-implementasi-191--wajib-dulu-mudah-ke-sulit).

Terakhir diperbarui: 1 Agustus 2026.

---

## Status hari ini

| Hal | Keadaan |
|---|---|
| ROM 17.1 di perangkat | **Boot normal tanpa bug** (dikonfirmasi 1 Agustus 2026) |
| Kernel `a12-prep` | 4 commit, sudah di-push, sudah di-pin di `A37.xml` |
| Kernel di perangkat | Masih `70ef81d` — `a12-prep` **belum pernah di-flash** |
| Tree 19.1 | **Ter-sync dan bisa `lunch`** di `/root/los19` — `lineage_A37-eng`, PLATFORM_VERSION=12 |
| Verifikasi 19.1 | Selesai — FDE aman, f2fs ringan, sdcardfs masih dipakai, **eBPF blocker** |
| Device tree 19.1 | `rigaz29/rb_device_oppo_A37` branch `a12-prep` — 15 commit dari `rb` di atas basis 19.1 |
| Manifest 19.1 | `A37-19.1.xml`, 10 project, terbukti lunch |
| W1 (bpfloader) | ✅ selesai — kode, kompilasi, biner, ter-pin |
| W2 (netd) | ✅ selesai — kode, kompilasi, biner, ter-pin |
| Properti pengaktif | ✅ `ro.kernel.ebpf.supported=false` ada di `build.prop` image |
| **Build ROM 19.1** | ✅ **berhasil 2 Agustus 2026** — `lineage-19.1-20260802-UNOFFICIAL-rigaz29-A37.zip`, 560 MB |
| ROM 19.1 di perangkat | ❌ **di-flash, stuck di logo OPPO** — tidak sampai bootanimation, `adb` nihil |
| Status proyek | ⛔ **dihentikan 2 Agustus 2026**, tanpa penghapusan apa pun |
| Pin kernel `A37.xml` (17.1) | dikembalikan ke `70ef81d` yang terbukti boot |

---

## Kenapa 19.1 dulu

Satu alasan bertahan, satu gugur setelah diverifikasi:

1. **FDE dihapus di A13, masih ada di A12.** ✅ Terkonfirmasi di tree 19.1. A37 memakai
   `TARGET_HW_DISK_ENCRYPTION` (dm-req-crypt + QSEE) dengan `encryptable=footer`, dan jalur
   itu utuh di 19.1. Enkripsi tidak perlu disentuh sama sekali. Di A13 harus pindah ke FBE —
   sedangkan fscrypt di kernel ini hanya v1 dan hanya ter-hook ke f2fs.
2. ~~eBPF baru wajib di A13; A11/A12 masih punya gerbang versi kernel.~~ ❌ **SALAH.**
   Diverifikasi terhadap sumber 19.1: gerbang itu tidak ada. eBPF sama wajibnya di Android
   12. Lihat [Blocker: eBPF](#blocker-ebpf-berlaku-juga-untuk-191).

Jadi 19.1 tetap lebih murah dari 20, tapi selisihnya jauh lebih tipis dari perkiraan awal —
bedanya tinggal enkripsi, bukan enkripsi *dan* jaringan.

---

## Fase 0 — defconfig murah · **SELESAI**

Branch [`a12-prep`](https://github.com/rigaz29/kernel_oppo_msm8939/tree/a12-prep), empat
commit di atas `70ef81d`. Dipilih karena semuanya hanya defconfig, nol baris C, dan tiga
dari empat sudah berguna di Android 10 — jadi bisa diuji di basis yang sudah terbukti.

| Commit | Perubahan | Alasan |
|---|---|---|
| `a363b5d` | `BLK_DEV_LOOP_MIN_COUNT` 8 → 32 | APEX butuh jauh lebih banyak loop device |
| `0420b77` | `QUOTA` + `QFMT_V2`, `PRINT_QUOTA_WARNING` off | statistik penyimpanan installd |
| `49766c1` | `MEMCG=y` | satu-satunya sumber event tekanan memori untuk lmkd tanpa PSI |
| `00fa451` | `ANDROID_LOW_MEMORY_KILLER` off | lmkd yang memutuskan, bukan driver kernel |

**Sudah diverifikasi:**

- Nama dan dependensi tiap simbol Kconfig dibaca langsung dari sumber, bukan diasumsikan.
- `.config` diekspansi di dua titik dan dibandingkan dengan baseline. Nol perubahan yang
  tidak diminta; `MM_OWNER`, `QUOTACTL`, `QUOTA_TREE` muncul karena `select`.
- `mm/memcontrol.o` dan lima objek `fs/quota/` kompilasi bersih (GCC 4.9 prebuilt).
- Build `Image` penuh exit 0, 16.592.888 byte, 0 error. Lima peringatan semuanya sudah ada
  sebelum perubahan ini.
- `System.map`: `mem_cgroup_init`, `dquot_initialize`, `sys_quotactl` ada; `lowmem_scan`
  dan `lowmem_shrink` hilang.
- ext4 di kernel ini mengenal `EXT4_FEATURE_RO_COMPAT_QUOTA` dan memasukkannya ke
  `RO_COMPAT_SUPP`, jadi userdata ber-`-O quota` tetap mountable read-write.

**Belum diverifikasi: apa pun di perangkat.** Zip AnyKernel3 sudah terbentuk tapi belum
di-flash.

### Cara flash bertahap

```bash
./build-kernel.sh --rev 49766c13971a161b362d08cc415fb2a51abeab2e   # commit 1-3
./build-kernel.sh --rev a12-prep                                   # tambah commit 4
```

Commit 4 satu-satunya yang bisa mengubah perilaku memori. Flash terpisah supaya regresi OOM
punya satu kandidat, bukan empat.

---

## Fase 1 — dua keputusan · **BELUM**

Biayanya nol kalau diambil benar, dan menghapus tiga backport besar sekaligus.

1. **`/data` pakai ext4, bukan f2fs.** `fstab.qcom` sudah punya barisnya. f2fs di kernel ini
   hanya mengenal `ENCRYPT|BLKZONED` (`fs/f2fs/f2fs.h:115`) sementara `mkfs.f2fs` modern
   menulis fitur superblock yang lebih baru. Memilih ext4 mencoret backport `fs/f2fs/`.
2. **Pertahankan FDE apa adanya.** Tidak ada pekerjaan kernel untuk enkripsi di 19.1.

*Cabang ke 20:* FDE tidak ada lagi → boot pertama tanpa enkripsi, FBE menyusul.

---

## Fase 2 — backport kecil · **BELUM**

Dikerjakan setelah 19.1 boot, bukan sebelumnya. Ketiganya berdiri sendiri.

| Item | Ukuran | Catatan |
|---|---|---|
| `uid_cputime` → `uid_sys_stats` | kecil | pendahulunya **sudah ada** (`drivers/misc/uid_cputime.c`, `CONFIG_UID_CPUTIME=y`), jadi ini menaikkan versi, bukan backport dari nol |
| `cpufreq_times` | kecil | perlu hook di `cpufreq.c` dan `kernel/sched/cputime.c` |
| syscall `membarrier` | ~100 baris | asuransi untuk JIT ART |

**Jebakan penomoran syscall:** tabel kernel ini berhenti di `memfd_create` = 279, sedangkan
`membarrier` = 283 di hulu. Nomor 280 (`bpf`), 281 (`execveat`), 282 (`userfaultfd`) harus
disisakan sebagai lubang atau `sys_ni_syscall`. Jangan dipadatkan — bionic memakai nomor
hulu.

---

## Fase 3 — mahal, hindari · **BELUM**

- **`fs/fuse` (7.23 → 4.9-an).** **Bukan syarat wajib** — koreksi atas klaim awal saya bahwa
  A12 membuang dukungan sdcardfs. `EmulatedVolume.cpp:269` di 19.1 justru berbunyi *"Mount
  sdcardfs regardless of FUSE"*, dan `Utils.cpp:1013` `IsSdcardfsUsed()` default `true` selama
  `sdcardfs` ada di `/proc/filesystems` — kernel ini punya `CONFIG_SDCARD_FS=y`. Kerjakan hanya
  kalau pengukuran menunjukkan storage lambat. Kalau memang perlu: salinan mentah dari 4.9 tidak
  akan kompilasi karena VFS 3.10 belum punya `->read_iter`/`iov_iter` modern — ambil 3.18 atau
  4.4 sebagai jembatan.
- **cgroup v2.** Tidak wajib: `cgroup_map_write.cpp:413` melewati controller yang gagal dengan
  `LOG(WARNING)` lalu lanjut, dan kegagalan builtin action di init hanya dicatat.
- **Backport eBPF ke kernel.** Ditolak sebagai jalur; yang dipakai adalah tambalan userspace di
  [Rencana implementasi](#rencana-implementasi-191--wajib-dulu-mudah-ke-sulit).
- **cgroup v2 demi app freezer.** Lewati; kegagalan mount cgroup2 hanya error log di init.
- **fscrypt untuk ext4.** Hanya perlu kalau mengejar FBE di ext4.

---

## Rencana implementasi 19.1 — wajib dulu, mudah ke sulit

Definisi **wajib** di sini sempit: tanpa itu ROM tidak boot, atau fungsi inti mati. Sisanya
masuk kategori nanti, betapapun menggodanya.

Hasil peninjauan: daftar wajib hanya berisi **tiga** hal. Tiga blocker yang sempat saya
sebut — FUSE, cgroup v2, f2fs — semuanya gugur setelah diperiksa ke sumber.

### W1 · bpfloader berhenti menggagalkan boot — **KODE SELESAI**

Dikerjakan 1 Agustus 2026 lewat cherry-pick dari `LineageOS-UL/android_system_bpf`
branch `lineage-19.1`, commit `8a936bb` "Ignore bpf errors for < 4.9 kernels"
(SagarMakhar/rajkale99). Ada di `/root/los19/system/bpf` branch `lineage-19.1-a37`
sebagai `5710a2b`; penulis asli, `Signed-off-by`, dan `Change-Id` terjaga.

**Metodenya berbeda dari rancangan awal di bawah, dan sengaja.** Rancangan awal memakai
`isAtLeastKernelVersion(4, 9, 0)`; yang dipakai adalah properti `ro.kernel.ebpf.supported`
(default `true`). Alasannya patch netd untuk W2 memakai properti yang sama persis — dua
komponen yang harus sepakat lebih baik dikendalikan satu sakelar daripada dua mekanisme
deteksi yang bisa berbeda pendapat. `bpf.progs_loaded=1` tetap diset walau pemuatan
dilewati, menjawab pertanyaan terbuka di rancangan.

Terverifikasi: `BpfLoader.cpp` hasilnya **byte-identik** dengan milik UL, dan
`#include <android-base/properties.h>` sudah ada di baris 41.

**Terverifikasi penuh 1 Agustus 2026 sore.** `m bpfloader` → exit 0; biner ARM 32-bit di
`out/target/product/A37/system/bin/bpfloader` memuat string `ro.kernel.ebpf.supported` dan
`bpf.progs_loaded`, sementara `DO NOT EXPECT SYSTEM TO BOOT` **tetap ada** — jalur gagal-keras
tidak dilumpuhkan, hanya digerbangi. Di-fork ke `rigaz29/android_system_bpf` dan di-pin
manifest lewat `remove-project` (wajib: `system/bpf` datang dari remote aosp).

Properti pengaktifnya ada di device tree sejak `fd0eae0`.

<details><summary>Rancangan awal (disimpan sebagai catatan)</summary>

Kembalikan gerbang yang dibuang AOSP di A12. Di `system/bpf/bpfloader/BpfLoader.cpp`, `main()`
langsung masuk loop `loadAllElfObjects()`; tambahkan keluar-awal di atasnya memakai
`android::bpf::isAtLeastKernelVersion(4, 9, 0)` yang **sudah ada** di
`libbpf_android/include/bpf/BpfUtils.h:44` (sekarang hanya dipakai makro GTest).

Acuan persis: AOSP `android-11.0.0_r48` `BpfLoader.cpp:83` — `if (!isBpfSupported()) return 0;`

Ukuran: ~5 baris. Yang harus diputuskan saat mengerjakan: apakah `bpf.progs_loaded=1` tetap
diset seperti perilaku A10 (`BpfLoader.cpp:100` di 17.1) — perlu dicek dulu apakah ada yang
menunggu properti itu; pencarian awal di `init.rc` dan netd tidak menemukan penunggu.

**Selesai bila:** `bpfloader` keluar 0 di kernel 3.10, tanpa baris `CRITICAL FAILURE`.

</details>

### Kompilasi terkunci di W3 — **SUDAH TERBUKA**

Hambatan di bawah berlaku 1 Agustus 2026 pagi dan **sudah tidak berlaku**: setelah
`A37-19.1.xml` disusun dan device tree `a12-prep` ter-sync, `lunch lineage_A37-eng`
berhasil. Catatan ini disimpan karena menjelaskan kenapa W1 sempat tidak bisa diuji.

<details><summary>Uraian hambatan yang sudah lewat</summary>

Uji kompilasi W1 dicoba dan **gagal karena lingkungan, bukan karena patch**:

```
error: vendor/lineage/build/soong/Android.bp:24:8: module "generated_kernel_includes":
       cmd: unknown variable '$(PATH_OVERRIDE_SOONG)'
```

`PATH_OVERRIDE_SOONG` didefinisikan di `vendor/lineage/config/BoardConfigSoong.mk`, yang
hanya ikut ter-include kalau target lunch-nya perangkat LineageOS. Soong mengurai
`vendor/lineage/build/soong/Android.bp` untuk **target apa pun**, termasuk `aosp_arm64`,
jadi tree ini tidak bisa membangun apa-apa selama belum ada device tree. Tidak ada target
lineage yang bisa dipakai: `device/lineage/car` dan `atv` adalah produk basis untuk
diwarisi, bukan perangkat.

**Konsekuensi:** W1 dan W2 hanya bisa diverifikasi sampai tingkat isi berkas sampai W3
menghasilkan device tree yang bisa di-lunch. Ini menaikkan prioritas W3 dari "terakhir"
menjadi "penghalang verifikasi" — kerangka device tree minimal yang cukup untuk `lunch`
sudah bernilai walau ROM-nya belum jalan.

</details>

Menaikkan prioritas W3 itu ternyata keputusan yang tepat, dan lebih murah dari dugaan:
tree 19.1-nya sudah ada, tinggal dipasang.

### W2 · netd berhenti crash loop — **SELESAI**

Dikerjakan 1 Agustus 2026 lewat cherry-pick `e3c9266d` dari
`LineageOS-UL/android_system_netd` branch `lineage-19.1`. Berbagi riwayat dengan LineageOS
19.1, jadi terpakai bersih; `server/Controllers.cpp` hasilnya identik dengan milik UL. Ada
di `rigaz29/android_system_netd` branch `lineage-19.1-a37` sebagai `5d5c71fa`, di-pin
manifest lewat `remove-project`.

Terverifikasi: `m netd` → exit 0, biner 505 KB memuat `ro.kernel.ebpf.supported`, dan string
`crash loop likely` **tetap ada** — bloknya utuh, hanya digerbangi.

**Jauh lebih kecil dari perkiraan awal.** Rancangan saya mengembalikan sepuluh penjaga
`mBpfEnabled` dengan 18.1 sebagai peta. Patch UL hanya empat baris: satu properti dan satu
`&& ebpf_supported` pada kondisi `exit(1)`.

**Batas yang harus disadari:** karena hanya titik fatal yang dijaga,
`TrafficController::start()` tetap gagal dan map bpf-nya tetap tidak terbuka — netd sekadar
tidak lagi bunuh diri karenanya. Apakah pemanggilan berikutnya (tag socket, firewall chain)
gagal dengan anggun **belum bisa dipastikan tanpa perangkat**. Yang menopang keputusan ini:
pendekatan tersebut sudah dipakai di lapangan pada perangkat MSM8916 oleh LineageOS-UL, dan
sisi framework punya jalan mundur sendiri — `NetworkStatsFactory.java:161` memilih jalurnya
dari keberadaan `/sys/fs/bpf/map_netd_app_uid_stats_map`, dan `xt_qtaguid` ada di kernel ini.

### W3 · device tree, vendor, dan VNDK 31 — **KERANGKA SELESAI**

Ternyata jauh lebih murah dari dugaan, karena tree-nya sudah ada:
**`meghs-playground/rb_device_oppo_A37` punya branch `lineage-19.1`** — penulis yang sama
dengan tree 17.1, perangkat yang sama, 1679 commit, dan sudah memuat penyesuaian era A12
(`manifest.xml` VINTF `target-level="legacy"`, `compatibility_matrix.xml`,
`PRODUCT_VENDOR_MOVE_ENABLED`). Gunung VNDK/treble yang saya perkirakan berminggu-minggu
sudah didaki di tree itu.

Yang dikerjakan 1 Agustus 2026: branch `a12-prep` di `rigaz29/rb_device_oppo_A37`, berisi
kelima belas commit dari branch `rb` di atas basis 19.1. Empat bentrok dan diselesaikan
dengan menyesuaikan niatnya, bukan menimpa — rinciannya ada di komentar `A37-19.1.xml`.
Efek samping: `5dd5150f` menambal rujukan putus di tree 19.1 (`device.mk:441` menyalin
`keylayout/synaptics-s3203.kl` padahal berkasnya tidak ada).

**`A37-19.1.xml`** menyusul, 10 project. Dua di antaranya tidak akan ketemu dari
`lineage.dependencies` dan baru terungkap lewat `meghs-playground/manifest_A37` dan
kegagalan `lunch`:

- **`hardware/qcom-caf/msm8916/{audio,display,media}`** — manifest 19.1 menyediakan
  qcom-caf untuk msm8953 sampai sm8350, tapi **tidak msm8916**
- **`device/qcom/sepolicy-legacy`** — `BoardConfig.mk:212` meng-include `sepolicy.mk` dari
  sana; repo resmi LineageOS mentok di `lineage-16.0`, jadi dipakai fork LineageOS-UL
  branch `lineage-19.1-legacy`

**`lunch lineage_A37-eng` berhasil** — `TARGET_PRODUCT=lineage_A37`, `PLATFORM_VERSION=12`.
Kunci verifikasi yang tadinya menahan W1 dan W2 kini terbuka.

**Tiga cacat bawaan tree 19.1** ditemukan saat mencoba `m bpfloader`, dan semuanya menghalangi
build sebelum satu berkas pun dikompilasi. Tidak satu pun berasal dari kelima belas commit
`rb` — diverifikasi ada di basis `d13d7ac`:

| Berhenti di | Masalah | Perbaikan |
|---|---|---|
| 26% kati | `libshims_ril` kembar antara `Android.mk` dan `Android.bp` | `c37b941` — buang yang di `.mk`; versi `.bp` punya `soc_specific: true` sehingga mendarat di `/vendor` bersama blob yang di-shim |
| 86% kati | `init.recovery.qcom.rc` kembar; satu blok salah nama dan akan menimpa init recovery dengan konfigurasi power | `7f90402` — ganti nama jadi `init.recovery.power.rc`, yaitu nama yang memang di-import `etc/init.recovery.qcom.rc` |
| 99% kati | `libbfqio` hilang — dibuang LineageOS setelah 17.1, masih dipakai `hwc_vsync.cpp:22` | `e37b138` — bawa tiga berkasnya ke device tree, jangan fork tree display demi dua baris |

Artinya tree 19.1 milik meghs memang **belum pernah dibangun oleh siapa pun** dalam kondisi
ini. Pantas diingat saat menemui kegagalan berikutnya: kemungkinan besar masih ada cacat
serupa yang baru muncul ketika modul lain ikut dibangun.

### Build ROM penuh — berhasil 2 Agustus 2026

```
lineage-19.1-20260802-UNOFFICIAL-rigaz29-A37.zip   560 MB
cf5a6d9d5753528014d3a65510abce119c3ba3db67a52f4caf7fdbddf618f983
```

Diarsipkan ke `/root/a37-dl` bersama `boot.img` (18 MB) dan `recovery.img` (25 MB), sha256
diverifikasi dan masuk `SHA256SUMS`.

Terverifikasi di dalam image: `ro.build.version.release=12`,
`ro.lineage.version=19.1-20260802-UNOFFICIAL-rigaz29-A37`,
`ro.kernel.ebpf.supported=false` di `build.prop`, dan kedua biner `system/bin/bpfloader`
serta `system/bin/netd` memuat string gerbang properti. Rantai W1–W2 utuh dari device tree
sampai biner terpasang.

**Sembilan kali gagal sebelum tuntas.** Delapan cacat nyata, nol berasal dari kelima belas
commit `rb`:

| # | Sumber | Masalah | Perbaikan |
|---|---|---|---|
| 1 | device tree | `libshims_ril` kembar `.mk`/`.bp` | `c37b941` |
| 2 | device tree | `init.recovery.qcom.rc` kembar, satu blok salah nama | `7f90402` |
| 3 | device tree | `libbfqio` dibuang LineageOS setelah 17.1, masih dipakai display HAL | `e37b138` |
| 4 | **kernel 3.10** | Makefile tidak membuat direktori output yang dihapus soong | `ec427db` |
| 5 | device tree | `power_profile.xml` diawali baris kosong sebelum `<?xml` | `5a9485e` |
| 6 | sepolicy-legacy | `sysfs_disk_stat` dibuang AOSP setelah 10, masih dilabeli | `46adbad` |
| 7 | device tree | spesifikasi gatekeeper kembar di vendor dan system_ext | `e69181f` |
| 8 | device tree | empat properti bentrok nilai antara `system.prop` dan `device.mk` | `dc3f3c9` |
| 9 | lingkungan | disk habis di tahap pengemasan (267 MB tersisa) | hapus `/root/los17` |

Cacat #4 lolos dari empat build kernel sebelumnya karena `build-kernel.sh` membuat
`$WORK/out` sendiri; jalur itu hanya tersentuh ketika soong yang memanggil `make` dengan
direktori yang sengaja dihapus lebih dulu.

### Hasil di perangkat: stuck di logo OPPO

Di-flash 2 Agustus 2026 dengan `/data` sudah diformat. **Berhenti di logo OPPO** — tidak
pernah sampai bootanimation — dan `adb devices` tidak mendeteksi apa pun, padahal build ini
varian `eng` dengan `ro.debuggable=1` dan `ro.adb.secure=0` sehingga `adbd` mestinya hidup
lebih awal dari biasanya. Artinya init mati sebelum `adbd` sempat start, atau kernel panic
lebih dulu.

Yang sempat dicoret sebelum diagnosis dihentikan:

- **`boot.img` sehat.** Header dibandingkan dengan `boot.img` 17.1 yang terbukti boot:
  pagesize 2048, base `0x80000000`, dan `dt_size` 210944 — sama persis, dan cocok dengan
  `dt.img` keluaran `dtbToolOppo`. Peringatan `unpack_bootimg` (`UnicodeDecodeError`) saat
  build memang benign: alat AOSP itu tidak mengenal field `dt_size` khas Qualcomm.
- **Bukan sisa enkripsi 17.1** — `/data` sudah diformat sebelum flash.

### Langkah diagnosis berikutnya (belum dijalankan)

Kalau proyek ini dilanjutkan, mulai dari sini — bukan dari nol:

1. **Boot ke recovery 19.1.** `recovery.img` memakai kernel yang sama persis dengan
   `boot.img`, hanya ramdisk-nya berbeda. Recovery boot normal → kernel sehat, masalah murni
   di system/init, dan kelima commit kernel bisa dicoret sekaligus tanpa flash apa pun.
   Recovery ikut stuck → kernel jadi tersangka.
2. **Ambil ramoops.** Kernel punya `CONFIG_PSTORE_RAM` dan cmdline membawa
   `ramoops.mem_address=0x9ff00000`; isinya bertahan melewati reboot hangat. Setelah stuck,
   tahan Power sampai reboot (jangan cabut baterai), masuk recovery, lalu
   `adb shell cat /sys/fs/pstore/console-ramoops-0`. Di situ akan terlihat apakah kernel
   panic atau init berhenti, dan di baris apa.
3. Tersangka teratas kalau ternyata userspace: cakupan W2 yang hanya menjaga titik `exit(1)`
   tanpa mengembalikan sepuluh penjaga `mBpfEnabled` — lihat
   [W2](#w2--netd-berhenti-crash-loop--selesai).

**Jangan kembali ke kernel `70ef81d` untuk 19.1.** `BLK_DEV_LOOP_MIN_COUNT` di sana masih
default 8, sedangkan A12 memasang puluhan APEX yang masing-masing butuh loop device;
`apexd` gagal adalah persis jenis kegagalan yang menghentikan init sebelum apa pun tampil.
Keempat commit kernel lebih mungkin menolong daripada menyebabkan masalah ini.

### Bukan wajib — kerjakan setelah boot pertama

| Item | Kenapa ditunda |
|---|---|
| `fs/fuse` | sdcardfs masih dipakai; ini soal kecepatan, bukan syarat |
| `uid_sys_stats`, `cpufreq_times` | statistik baterai per-aplikasi, tidak memblokir apa pun |
| syscall `membarrier` | ART punya jalur lain; ukur dulu lewat logcat |
| cgroup v2, backport eBPF kernel | ditolak sebagai jalur; W1+W2 menggantikannya |

## Prasyarat non-kernel

**Disk menggigit dua kali, persis seperti diperkirakan.** Per 1 Agustus 2026 sisa 154 GB
sementara `/root/los17` sendiri 131 GB, jadi `out/` 17.1 dihapus lebih dulu (+45 GB) setelah
zip-nya diarsipkan. Itu cukup untuk sync dan seluruh kompilasi, tapi **habis di tahap
pengemasan** — `add_img_to_target_files` menyalin seluruh SYSTEM ke direktori sementara soong
dan sisa 267 MB tidak cukup.

`/root/los17` akhirnya dihapus seluruhnya pada 2 Agustus 2026 (+87 GB). Aman karena keempat
project-nya bersih di SHA yang di-pin `A37.xml` sehingga bisa di-sync ulang persis, dan tiga
zip ROM 17.1 beserta boot/recovery sudah ada di `/root/a37-dl`.

Efek sampingnya: `build-kernel.sh` default `LOS_TREE=$HOME/los17` yang kini tidak ada.
Toolchain punya jalan mundur (clone prebuilt sendiri) tapi `dtbToolOppo` diambil dari
`$LOS_TREE/device/oppo/A37/dtbtool` dan akan gagal. Jalankan dengan `LOS_TREE=/root/los19`.

**Yang sebenarnya menentukan: treble dan VNDK 31.** Device tree A37 masih non-treble era
17.1 dengan blob CAF Android 6/8. Bobot kerja di situ jauh melebihi seluruh daftar kernel di
dokumen ini. Kernel realistis selesai dalam hitungan hari; sisi treble tidak.

---

## Hasil verifikasi terhadap sumber 19.1 · 1 Agustus 2026

Tree ter-sync di `/root/los19` (manifest `lineage-19.1`, HEAD `2202c15`, 994 project, 118 GB).

### 1. FDE — ✅ aman

| Bukti | Hasil |
|---|---|
| `hardware/lineage/interfaces/cryptfshw/` | ada, lengkap dengan `qsee/` |
| `system/vold/cryptfs.cpp` | ada, 123 KB |
| `system/core/fs_mgr/fs_mgr_fstab.cpp:189` | masih mem-parse `encryptable=` |

Keputusan "pertahankan FDE, nol pekerjaan kernel untuk enkripsi" tetap berlaku.

### 2. eBPF — ❌ ternyata wajib

Lihat [Blocker: eBPF](#blocker-ebpf-berlaku-juga-untuk-191).

### 3. f2fs — ⚠️ lebih ringan dari dugaan

`fs_mgr_format.cpp:139` memanggil `make_f2fs -g android`. Fitur tambahan hanya ditambahkan
bila diminta properti: `project_quota,extra_attr` (`external_storage.projid.enabled`),
`casefold` (`external_storage.casefold.enabled`), `compression` (flag fstab). Ketiganya mati
secara default.

`-g android` = `CONF_ANDROID` di `f2fs_format_main.c:109` menyalakan tiga bit: `ENCRYPT`
(0x0001), `QUOTA_INO` (0x0080), `VERITY` (0x0400). Kernel ini hanya mengenal `ENCRYPT` dan
`BLKZONED` — **tapi `sanity_check_raw_super()` di `fs/f2fs/super.c:1416` tidak memvalidasi
field `feature` terhadap daftar fitur yang dikenal**, jadi bit asing diabaikan, bukan
ditolak. Konsekuensinya inode kuota tersembunyi dibuat mkfs tapi tidak dipakai kernel.

Belum dibuktikan dengan mount sungguhan; yang dibaca baru jalur `sanity_check_raw_super`.
Kalau tetap ingin aman, ext4 untuk `/data` menghapus pertanyaan ini sepenuhnya.

---

## Blocker: eBPF (berlaku juga untuk 19.1)

Klaim saya sebelumnya — bahwa `bpfloader` dan `netd` di A11/A12 masih mundur dengan anggun
di kernel tanpa bpf — **tidak benar**. Rantai buktinya di tree 19.1:

| Berkas | Isi |
|---|---|
| `system/bpf/libbpf_android/include/bpf/BpfUtils.h:44` | `isAtLeastKernelVersion()` ada, tapi satu-satunya pemakainya adalah makro `SKIP_IF_*` untuk GTest. Bukan gerbang runtime. |
| `system/bpf/bpfloader/BpfLoader.cpp:114` | gagal muat → `"--- DO NOT EXPECT SYSTEM TO BOOT SUCCESSFULLY ---"`, `sleep(20)`, `return 2`. Tidak ada jalan keluar untuk kernel lama. |
| `system/netd/server/TrafficController.cpp:180` | `initMaps()` membuka enam map ter-pin dari `/sys/fs/bpf` lewat `RETURN_IF_NOT_OK`, tanpa fallback |
| `system/netd/server/Controllers.cpp:285` | `start()` gagal → `"CRITICAL: sleeping 60 seconds, netd exiting with failure, crash loop likely!"`, `sleep(60)`, `exit(1)` |

Sisi framework justru punya fallback: `NetworkStatsFactory()` (baris 161) menyetel
`useBpfStats` dari keberadaan `/sys/fs/bpf/map_netd_app_uid_stats_map`, dan jalur
`/proc/net/xt_qtaguid/stats` masih ada. **Tapi framework tidak menyelamatkan netd** — netd
mati lebih dulu.

Pilihan, tidak ada yang murah:

| Opsi | Bobot | Catatan |
|---|---|---|
| **Turun ke 18.1 (Android 11)** | **nol** | Gerbangnya masih utuh di A11 — lihat tabel di bawah. Tidak ada pekerjaan eBPF sama sekali. |
| Tambal `system/netd` + `system/bpf` untuk 19.1 | sedang, berkelanjutan | Buat `TrafficController::start()` mengembalikan ok saat map tidak ada, dan `bpfloader` keluar 0 di kernel lama — pada dasarnya mengembalikan kode yang dibuang AOSP di A12. Akuntansi trafik per-UID jatuh ke qtaguid yang sudah didukung framework. |
| Backport eBPF ke 3.10 | sangat besar | syscall + BPF_FS + verifier + `BPF_PROG_TYPE_CGROUP_SKB` + helper socket cookie + cgroup v2 untuk attach. Fitur kernel 4.4–4.12. |

### Kapan gerbang itu dibuang: A12

Diverifikasi terhadap sumber ketiga versi — 17.1 dari tree lokal, 18.1 dari
`LineageOS/android_system_netd` (`c013516`), 19.1 dari `/root/los19`, bpfloader A11 dari
AOSP `android-11.0.0_r48`.

| | 17.1 (A10) | 18.1 (A11) | 19.1 (A12) |
|---|---|---|---|
| `bpfloader` di kernel <4.9 | `BpfLoader.cpp:95` lewati `loadAllElfObjects()`, `return 0` | `BpfLoader.cpp:83` `if (!isBpfSupported()) return 0;` | **tidak ada** — langsung muat, gagal → `return 2` |
| `TrafficController::start()` | `:289` `if (mBpfLevel == NONE) return ok;` | `:252` `if (!mBpfEnabled) return ok;` — plus 9 penjaga lain | **tidak ada penjaga** |
| `Controllers.cpp` saat gagal | catat error, lanjut | catat error, lanjut | `:288` `sleep(60); exit(1);` — **netd crash loop** |

`ClatdController.cpp:77` di 18.1 bahkan mencetak alasannya terang-terangan: *"Pre-4.9 kernel
or pre-P api shipping level - disabling clat ebpf."* Jadi pemeriksaan versi 4.9 itu memang
jalur runtime yang disengaja, bukan sisa kode.

**Kesimpulan: 18.1 jalan di kernel tanpa eBPF; 19.1 tidak, kecuali ditambal.**

---

## Verifikasi 18.1 selengkapnya · 1 Agustus 2026

Diperiksa lewat clone dangkal `lineage-18.1` (`vold` `85ffd68`, `core` `d9e9c75`, `sepolicy`
`c590512`, `netd` `c013516`) dan AOSP `android-11.0.0_r48` untuk `system/bpf` dan
`system/memory/lmkd` — dua komponen yang tidak di-fork LineageOS di versi ini.

| Kebutuhan | Hasil | Bukti |
|---|---|---|
| eBPF | ✅ opsional | `BpfLoader.cpp:83`, `TrafficController.cpp:252` + 9 penjaga, `Controllers.cpp:286` hanya mencatat |
| FDE | ✅ ada | `vold/cryptfs.cpp`, 128 KB |
| **sdcardfs** | ✅ **masih dipakai** | `Utils.cpp:1010` `IsSdcardfsUsed()` = `IsFilesystemSupported("sdcardfs") && GetBoolProperty(..., true)` — default true, dan kernel punya `CONFIG_SDCARD_FS=y` |
| cgroup v2 | ✅ tidak fatal | `cgroup_map_write.cpp:386` gagal setup → `LOG(WARNING)`, "proceed with the next cgroup". Kegagalan builtin action di init hanya dicatat (`action.cpp:170`) |
| lmkd | ✅ luwes | `use_inkernel_interface = true` dan `use_psi_monitors = false` sebagai default — LMK in-kernel masih jalur yang sah, PSI tidak wajib |
| SELinux | ✅ cocok | `policy_version.mk:4` `POLICYVERS ?= 30`; kernel maksimal 30 |
| f2fs | ⚠️ sama seperti 19.1 | `fs_mgr_format.cpp:139` `make_f2fs -g android`; fitur ekstra hanya bila properti diminta |

**Efeknya pada rencana:** seluruh isi [Fase 3](#fase-3--mahal-hindari--belum) menguap untuk
18.1 — tidak perlu backport `fs/fuse` (sdcardfs masih dipakai), tidak perlu eBPF, tidak perlu
cgroup v2. [Fase 0](#fase-0--defconfig-murah--selesai) commit 4 pun jadi opsional, karena
lmkd A11 masih mau memakai LMK in-kernel.

**Belum diperiksa untuk 18.1:** VNDK 30 dan treble — dan justru di situlah bobot kerja
sesungguhnya, sama seperti untuk 19.1. Verifikasi di atas hanya menyangkut sisi kernel.

---

## Hasil audit kernel (referensi)

`kernel_oppo_msm8939` @ 3.10.108. Dibaca dari sumber, bukan dari ingatan tentang "kernel
3.10 umumnya".

**Sudah ada — jangan buang waktu:**

| Kebutuhan | Bukti |
|---|---|
| seccomp-bpf, termasuk zygote32 | `arch/arm64/Kconfig:38`, `syscall_get_arch()` mengembalikan `AUDIT_ARCH_ARM` untuk compat task |
| SELinux policy v30 (xperms) | `POLICYDB_VERSION_MAX = POLICYDB_VERSION_XPERMS_IOCTL` |
| kelas SELinux `binder` + hook LSM | `security/selinux/include/classmap.h:154` |
| `memfd_create` | syscall 279, `mm/shmem.c:2678` |
| binder multi-device (vndbinder) | `CONFIG_ANDROID_BINDER_DEVICES="binder,hwbinder,vndbinder"`, protokol v8 |
| USB gadget ConfigFS | `drivers/usb/gadget/configfs.c` |
| mount namespace (APEX) | `CONFIG_NAMESPACES=y` |
| dm-verity + loop (APEX) | keduanya `=y` |
| `xt_qtaguid` | `net/netfilter/xt_qtaguid.c`, ter-track |

**Tidak ada:**

cgroup v2 · overlayfs · incfs · erofs · dm-verity-fec · `statx` · `pidfd_open` ·
`membarrier` · `uid_sys_stats` · `cpufreq_times` · syscall `bpf` · PSI · fscrypt untuk ext4

**Setengah:** fscrypt ada tapi hanya API v1 dan hanya f2fs yang ter-hook · FUSE minor 7.23,
tanpa `FUSE_MAX_PAGES`/`PARALLEL_DIROPS`/writeback cache dan tanpa `FUSE_CANONICAL_PATH`
milik Android · f2fs hanya mengenal `ENCRYPT|BLKZONED`

---

## Log keputusan

| Tanggal | Keputusan | Alasan |
|---|---|---|
| 1 Ags 2026 | Target 19.1, bukan 20 | FDE dan eBPF, lihat [Kenapa 19.1 dulu](#kenapa-191-dulu) |
| 1 Ags 2026 | Backport eBPF + PSI yang setengah jadi dibuang | syscall `bpf` tidak pernah di-wire, hook PSI tidak pernah masuk `kernel/sched/core.c`; dan 19.1 kemungkinan tidak membutuhkannya |
| 1 Ags 2026 | `build-kernel.sh` menarik dari repo, bukan tree lokal | hasil build hanya bergantung pada apa yang sudah di-push, bisa direproduksi mesin lain |
| 1 Ags 2026 | `A37.xml` di-pin ke `a12-prep` | agar build ROM berikutnya memakai kernel ini; konsekuensinya ROM akan memuat keempat commit sekaligus, termasuk yang mematikan LMK |
| 1 Ags 2026 | Hapus `/root/los17/out` (45 GB) untuk memberi ruang tree 19.1 | zip `20260731` dan `20260801` beserta boot/recovery diarsipkan dulu ke `/root/a37-dl` — sebelumnya hanya `20260730` yang punya salinan |
| 1 Ags 2026 | Local manifest **tidak** dipasang di `/root/los19` | `A37.xml` berisi pin era 17.1 (device tree branch `rb`, vendor `lineage-17.1`); memasangnya akan menarik komponen yang tidak cocok |
| 1 Ags 2026 | **Koreksi:** eBPF wajib juga di 19.1 | diverifikasi ke sumber; asumsi "gerbang versi kernel" keliru. Menaikkan bobot 19.1 secara mendasar — lihat [Blocker: eBPF](#blocker-ebpf-berlaku-juga-untuk-191) |
| 1 Ags 2026 | Gerbang bpf ternyata dibuang tepat di A12; A11 masih punya | 18.1 jadi kandidat target terkuat karena biaya eBPF-nya nol. Target resmi belum diubah — menunggu keputusan |
| 1 Ags 2026 | Device tree 19.1 **diambil**, bukan dibuat sendiri | `meghs-playground/rb_device_oppo_A37` branch `lineage-19.1` berbagi riwayat dengan fork `rb`, jadi kelima belas perbaikan bisa di-cherry-pick, bukan ditulis ulang. Membuat dari nol berarti mengulang 1679 commit kerja spesifik-perangkat |
| 1 Ags 2026 | Semua 15 commit dipindahkan, tidak ada yang dilewati | permintaan pemilik proyek; pasangan zram (`13e89533`+`96f95213`) hasil akhirnya sama dengan kalau dilewati, tapi jejak riwayatnya utuh dan bisa di-bisect |
| 1 Ags 2026 | W1 di-fork ke `rigaz29/android_system_bpf` dan di-pin manifest | branch lokal yang tidak di-pin bisa hilang diam-diam saat `repo sync --force-sync`; `system/bpf` datang dari remote aosp sehingga perlu `remove-project` dulu |
| 2 Ags 2026 | Delapan cacat build diperbaiki di device tree/kernel kita, bukan dengan mem-fork tree bersama | `sepolicy-legacy` dan tree display dipakai banyak perangkat; menanggung fork besar demi satu-dua baris tidak sepadan. `libbfqio` dibawa ke device tree dengan alasan yang sama |
| 2 Ags 2026 | `/root/los17` dihapus seluruhnya | disk habis di tahap pengemasan. Aman: keempat project bersih di SHA yang di-pin, dan zip ROM 17.1 sudah diarsipkan |
| 2 Ags 2026 | **Proyek 19.1 dihentikan** setelah ROM stuck di logo OPPO | keputusan pemilik proyek. Tidak ada yang dihapus — tree, branch, repo, dan ROM tetap utuh supaya bisa dilanjutkan tanpa mengulang |
| 2 Ags 2026 | Pin kernel `A37.xml` (17.1) dikembalikan ke `70ef81d` | manifest 17.1 sempat menunjuk `a12-prep` yang belum pernah di-flash. ROM 17.1 yang jalan di perangkat tidak boleh bergantung pada pekerjaan yang belum teruji. Branch `a12-prep` tetap ada, zip AnyKernel3-nya di `/root/kbuild` |
| 1 Ags 2026 | **Tetap 19.1**, tidak turun ke 18.1 | keputusan pemilik proyek; konsekuensinya dua tambalan userspace (W1, W2) yang harus dirawat |
| 1 Ags 2026 | **Koreksi:** sdcardfs masih dipakai di 19.1 | `EmulatedVolume.cpp:269` + `Utils.cpp:1013`; klaim "A12 FUSE-only" keliru, jadi backport `fs/fuse` keluar dari daftar wajib |
