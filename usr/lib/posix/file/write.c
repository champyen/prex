/*
 * Copyright (c) 2007, Kohsuke Ohtani
 * Copyright (c) 2026, Champ Yen (champ.yen@gmail.com)
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 3. Neither the name of the author nor the names of any co-contributors
 *    may be used to endorse or promote products derived from this software
 *    without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 */

#include <sys/prex.h>
#include <sys/posix.h>
#include <ipc/fs.h>

#include <stddef.h>
#include <errno.h>
#include <string.h>

/*
 * VFS server uses vm_map() for zero-copy I/O.
 * This requires the user buffer to be page-aligned and within a single segment.
 * If mapping fails, we use a 4KB aligned bounce buffer.
 */
#define IO_BUF_SIZE 4096
static char io_buf[IO_BUF_SIZE] __attribute__((aligned(4096)));

int write(int fd, void* buf, size_t len)
{
    struct io_msg m;
    int error;
    size_t total = 0;
    const char* p = (const char*)buf;

    if (len == 0)
        return 0;

    /* 1. Try direct write (zero-copy) first for efficiency */
    m.hdr.code = FS_WRITE;
    m.fd = fd;
    m.buf = buf;
    m.size = len;
    error = __posix_call(__fs_obj, &m, sizeof(m), 0);

    if (error == 0)
        return (int)m.size;

    /* 2. Fallback to bounce-buffer if vm_map failed (EINVAL) or other mapping issues */
    if (error == EINVAL || error == EFAULT) {
        while (len > 0) {
            size_t chunk = (len > IO_BUF_SIZE) ? IO_BUF_SIZE : len;
            memcpy(io_buf, p, chunk);
            
            m.hdr.code = FS_WRITE;
            m.fd = fd;
            m.buf = io_buf;
            m.size = chunk;
            error = __posix_call(__fs_obj, &m, sizeof(m), 0);
            
            if (error != 0) {
                if (total > 0) return (int)total;
                errno = error;
                return -1;
            }
            
            total += m.size;
            p += m.size;
            len -= m.size;

            if (m.size < chunk) break;
        }
        return (int)total;
    }

    errno = error;
    return -1;
}
