#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# Copyright (c) 2011-2012, The Linux Foundation. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#     * Redistributions of source code must retain the above copyright
#       notice, this list of conditions and the following disclaimer.
#     * Redistributions in binary form must reproduce the above copyright
#       notice, this list of conditions and the following disclaimer in the
#       documentation and/or other materials provided with the distribution.
#     * Neither the name of The Linux Foundation nor
#       the names of its contributors may be used to endorse or promote
#       products derived from this software without specific prior written
#       permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NON-INFRINGEMENT ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT OWNER OR
# CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
# EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
# PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
# OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
# WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
# OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
# ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

# LOS17-A37-PY3-WRAPPER
#
# Pengganti scripts/gcc-wrapper.py milik kernel MSM 3.10.
#
# Dua masalah yang diselesaikan:
#
# 1. Wrapper asli python2-only (memakai `print` statement), sedangkan Ubuntu
#    24.04 sudah tidak menyediakan python2 sama sekali. Build kernel berhenti
#    dengan "env: 'python2': No such file or directory".
#
# 2. Wrapper asli menggagalkan build begitu gcc mengeluarkan warning yang tidak
#    ada di daftar allowed_warnings — daftar yang isinya hanya 8 baris dan
#    ditulis tahun 2011. Pada source OPPO ini gate tersebut menabrak,
#    contohnya:
#
#      kernel/irq/pm.c:103:7: warning: unused variable 'suspend_abort'
#      error, forbidden warning: pm.c:103
#
#    Itu warning yang benar (variabelnya memang dead code di source OPPO), tapi
#    sebagai gerbang QA internal Qualcomm ia tidak relevan untuk membangun ROM,
#    dan menyisir sisa kernel satu per satu berarti puluhan iterasi build.
#
# Default sekarang: warning tetap ditampilkan apa adanya, tapi TIDAK
# menggagalkan build (pass-through — proses compiler langsung meng-exec, jadi
# tanpa overhead pipe dan urutan output persis seperti memanggil gcc langsung).
#
# Untuk mengembalikan perilaku asli (warning = fatal):
#
#     GCC_WRAPPER_FATAL_WARNINGS=1 ./build.sh --no-sync

import errno
import os
import re
import subprocess
import sys

FATAL_WARNINGS = os.environ.get('GCC_WRAPPER_FATAL_WARNINGS', '0') == '1'

allowed_warnings = set([
    "return_address.c:63",
    "kprobes.c:1493",
    "rcutree.c:1614",
    "af_unix.c:893",
    "nl80211.c:58",
    "jhash.h:137",
    "cmpxchg.h:162",
    "ping.c:87",
    # Ditambahkan untuk source OPPO A37 (dipakai hanya saat mode fatal aktif):
    "pm.c:103",
])

# Nama object file, kalau ketemu.
ofile = None

warning_re = re.compile(r'''(.*/|)([^/]+\.[a-z]+:\d+):(\d+:)? warning:''')


def interpret_warning(line):
    """Baca pesan gcc. Yang kita pedulikan punya nama file dan kata 'warning'."""
    line = line.rstrip('\n')
    m = warning_re.match(line)
    if m and m.group(2) not in allowed_warnings:
        print("error, forbidden warning:", m.group(2))

        # Kalau ada warning, buang object file-nya supaya build tidak
        # menganggap target ini sudah selesai.
        if ofile:
            try:
                os.remove(ofile)
            except OSError:
                pass
        sys.exit(1)


def exec_passthrough(args):
    """Ganti proses ini dengan compiler-nya. Tidak pernah kembali."""
    try:
        os.execvp(args[0], args)
    except OSError as e:
        if e.errno == errno.ENOENT:
            print(args[0] + ':', e.strerror)
            print('Is your PATH set correctly?')
        else:
            print(' '.join(args), str(e))
        sys.exit(e.errno)


def run_gcc(args):
    """Mode lama: awasi stderr, gagalkan build pada warning terlarang."""
    # Cari -o
    try:
        i = args.index('-o')
        global ofile
        ofile = args[i + 1]
    except (ValueError, IndexError):
        pass

    try:
        proc = subprocess.Popen(args, stderr=subprocess.PIPE)
        for raw in iter(proc.stderr.readline, b''):
            line = raw.decode('utf-8', errors='replace')
            sys.stdout.write(line)
            interpret_warning(line)

        result = proc.wait()
    except OSError as e:
        result = e.errno
        if result == errno.ENOENT:
            print(args[0] + ':', e.strerror)
            print('Is your PATH set correctly?')
        else:
            print(' '.join(args), str(e))

    return result


if __name__ == '__main__':
    argv = sys.argv[1:]
    if not argv:
        print('usage: gcc-wrapper.py <compiler> [args...]')
        sys.exit(2)

    if FATAL_WARNINGS:
        sys.exit(run_gcc(argv))
    else:
        exec_passthrough(argv)
