# Rencana dan progres — OPPO A37

Dokumen kerja untuk menaikkan OPPO A37 (MSM8916) dari LineageOS 17.1 ke versi yang lebih
baru. `README.md` mendokumentasikan ROM 17.1 yang sudah jalan; file ini yang bergerak.

**Target utama: LineageOS 19.1 (Android 12).** LineageOS 20 (Android 13) dicatat sebagai
titik cabang di tiap bagian, bukan target yang dikejar sekarang — alasannya ada di
[Kenapa 19.1 dulu](#kenapa-191-dulu).

Terakhir diperbarui: 1 Agustus 2026.

---

## Status hari ini

| Hal | Keadaan |
|---|---|
| ROM 17.1 di perangkat | **Boot normal tanpa bug** (dikonfirmasi 1 Agustus 2026) |
| Kernel `a12-prep` | 4 commit, sudah di-push, sudah di-pin di `A37.xml` |
| Kernel di perangkat | Masih `70ef81d` — `a12-prep` **belum pernah di-flash** |
| Tree 19.1 | Belum di-sync |
| Fase berikutnya | Flash `a12-prep~1`, lalu `a12-prep` |

---

## Kenapa 19.1 dulu

Dua hal yang membuat Android 13 jauh lebih mahal untuk kernel 3.10, dan keduanya tidak
berlaku di Android 12:

1. **FDE dihapus di A13.** A37 memakai `TARGET_HW_DISK_ENCRYPTION` (dm-req-crypt + QSEE)
   dengan `encryptable=footer`. Jalur itu masih didukung di A12, jadi enkripsi tidak perlu
   disentuh sama sekali. Di A13 harus pindah ke FBE — dan fscrypt di kernel ini hanya v1
   dan hanya ter-hook ke f2fs, ext4 nol referensi.
2. **eBPF wajib di A13.** Akuntansi trafik pindah ke modul mainline Connectivity yang
   bpf-only. Kernel ini tidak punya syscall `bpf` sama sekali. Di A11/A12 `bpfloader` dan
   `netd` masih punya gerbang versi kernel, dan `xt_qtaguid` ada di kernel ini.
   **Perlu dibuktikan setelah sync** — lihat [Yang harus diverifikasi](#yang-harus-diverifikasi-setelah-sync-191).

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

- **`fs/fuse` (7.23 → 4.9-an).** Jangan dikerjakan di muka: boot dulu, pakai, ukur. Salinan
  mentah dari 4.9 tidak akan kompilasi karena VFS 3.10 belum punya `->read_iter`/`iov_iter`
  modern — ambil 3.18 atau 4.4 sebagai jembatan, patch `FUSE_CANONICAL_PATH` menyusul.
- **eBPF + cgroup v2.** Tidak relevan untuk 19.1. Untuk 20, jawabannya menambal userspace.
- **cgroup v2 demi app freezer.** Lewati; kegagalan mount cgroup2 hanya error log di init.
- **fscrypt untuk ext4.** Hanya perlu kalau mengejar FBE di ext4.

---

## Prasyarat non-kernel

**Disk akan menggigit lebih dulu daripada kernel.** Per 1 Agustus 2026: sisa 154 GB,
sementara `/root/los17` sendiri 131 GB (`out/` 45 GB, `.repo/` 37 GB). Tree kedua tidak muat
berdampingan begitu keduanya punya `out/`. Pilih salah satu sebelum `repo init`:

- hapus `/root/los17/out` setelah zip 17.1 diarsipkan (+45 GB)
- `repo init --reference=/root/los17` supaya objek git dipakai bersama (+~35 GB)
- kerjakan bergantian, jangan paralel

**Yang sebenarnya menentukan: treble dan VNDK 31.** Device tree A37 masih non-treble era
17.1 dengan blob CAF Android 6/8. Bobot kerja di situ jauh melebihi seluruh daftar kernel di
dokumen ini. Kernel realistis selesai dalam hitungan hari; sisi treble tidak.

---

## Yang harus diverifikasi setelah sync 19.1

Tiga klaim yang mendasari rencana ini tapi belum dibuktikan terhadap sumber `lineage-19.1`.
Jangan dianggap benar sampai dicek:

1. **`hardware/lineage/interfaces/cryptfshw` masih ada** dan `system/vold/cryptfs.cpp` masih
   utuh — dasar dari keputusan "pertahankan FDE".
2. **`netd` masih punya gerbang bpf.**
   `grep -rn isBpfSupported system/netd packages/modules/Connectivity`, dan apakah
   `NetworkStatsFactory` masih membaca `/proc/net/xt_qtaguid/stats`. Kalau ya, seluruh
   urusan eBPF bisa dicoret.
3. **Fitur superblock yang ditulis `mkfs.f2fs` A12.** Format kartu dengan `mkfs.f2fs` dari
   `out`, lalu `dump.f2fs`, bandingkan dengan bitmap fitur kernel.

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
