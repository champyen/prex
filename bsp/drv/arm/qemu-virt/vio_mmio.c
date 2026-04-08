/*-
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

#include <driver.h>
#include <vio_mmio.h>
#include <conf/config.h>

#ifdef CONFIG_VIO_BLOCK
extern int vio_block_attach(vaddr_t base, int irq);
#endif

static int vio_mmio_init(struct driver* self)
{
    vaddr_t base;
    uint32_t magic;
    uint32_t dev_id;
    int irq;

    printf("VirtIO MMIO scan...\n");

    for (int i = 0; i < 32; i++) {
        base = CONFIG_VIO_MMIO_BASE + (i * 0x200);
        magic = bus_read_32(base + VIO_MMIO_MAGIC_ID);

        if (magic == VIO_MMIO_MAGIC_VALUE) {
            dev_id = bus_read_32(base + VIO_MMIO_DEV_ID);
            uint32_t ver = bus_read_32(base + VIO_MMIO_VER);
            irq = 48 + i; // QEMU virt SPI 16+i (48+i)

            switch (dev_id) {
#ifdef CONFIG_VIO_BLOCK
            case VIO_DEV_BLOCK:
                printf("Found VirtIO Block device at 0x%lx, irq %d, ver %d\n", base, irq, (int)ver);
                vio_block_attach(base, irq);
                break;
#endif
#ifdef CONFIG_VIO_NET
            case VIO_DEV_NET:
                printf("Found VirtIO Net device at 0x%lx, irq %d\n", base, irq);
                break;
#endif
            default:
                printf("Found unknown VirtIO device %d at 0x%lx\n", dev_id, base);
                break;
            }
        }
    }
    return 0;
}

struct driver vio_mmio_driver = {
    /* name */ "vio_mmio",
    /* devops */ NULL,
    /* devsz */ 0,
    /* flags */ 0,
    /* probe */ NULL,
    /* init */ vio_mmio_init,
    /* shutdown */ NULL,
};
