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
# Versi python3 dari scripts/gcc-wrapper.py milik kernel MSM 3.10.
# Aslinya python2-only (memakai `print` statement), sehingga build kernel gagal
# dengan "env: 'python2': No such file or directory" pada distro modern
# (Ubuntu 24.04 sudah tidak punya paket python2 sama sekali).
#
# Perilaku dipertahankan: jalankan compiler, tampilkan stderr apa adanya, dan
# gagalkan build kalau muncul warning yang tidak ada di daftar allowed_warnings.
# Perubahan hanya soal python3: print() sebagai fungsi, stderr didekode dari
# bytes, dan iterasi baris memakai iter() agar output tetap streaming.

import errno
import os
import re
import subprocess
import sys

allowed_warnings = set([
    "return_address.c:63",
    "kprobes.c:1493",
    "rcutree.c:1614",
    "af_unix.c:893",
    "nl80211.c:58",
    "jhash.h:137",
    "cmpxchg.h:162",
    "ping.c:87",
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


def run_gcc():
    args = sys.argv[1:]
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
    status = run_gcc()
    sys.exit(status)
