/*
 * Copyright (c) 2010-2021, Champ Yen (champ.yen@gmail.com)
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

#ifndef _VIO_MMIO_H_
#define _VIO_MMIO_H_

#include <sys/cdefs.h>
#include <sys/ioctl.h>
#include <ddi.h>

#define VIO_MMIO_MAGIC_ID               0x000
// "virt" string
#define VIO_MMIO_MAGIC_VALUE            0x74726976

// Device version number
#define VIO_MMIO_VER                    0x004
// Virtio Subsystem Device ID
#define VIO_MMIO_DEV_ID                 0x008
// Virtio Subsystem Vendor ID
#define VIO_MMIO_VEND_ID                0x00c

// Flags representing features the device supports
#define VIO_MMIO_DEV_FEATURE            0x010
// Device (host) features word selection
#define VIO_MMIO_DEV_FEATURE_SEL        0x014

// Flags representing device features understood and activated by the driver
#define VIO_MMIO_DRV_FEATURE            0x020

// Activated (guest) features word selection
#define VIO_MMIO_DRV_FEATURE_SEL        0x024

#define VIO_MMIO_PAGE_SIZE              0X028

// Virtual queue index
#define VIO_MMIO_QUEUE_SEL              0x030

// Maximum virtual queue size
#define VIO_MMIO_QUEUE_NUM_MAX          0x034

// Virtual queue size
#define VIO_MMIO_QUEUE_SIZE             0x038

#define VIO_MMIO_QUEUE_ALIGN            0x03c
#define VIO_MMIO_QUEUE_PFN              0x040

// Virtual queue ready bit
#define VIO_MMIO_QUEUE_READY            0x044

// Queue notifier
#define VIO_MMIO_QUEUE_NOTIFY           0x050

// Interrupt status
#define VIO_MMIO_IRQ_STATUS             0x060

// Interrupt acknowledge
#define VIO_MMIO_IRQ_ACK                0x064
#define VIO_MMIO_IRQ_VRING              (1 << 0)
#define VIO_MMIO_IRQ_CFG                (1 << 1)

// Device status
#define VIO_MMIO_STATUS                 0x070

// Virtual queue’s Descriptor Area 64 bit long physical address
#define VIO_MMIO_QUEUE_DESC_LOW         0x080
#define VIO_MMIO_QUEUE_DESC_HIGH        0x084

// Virtual queue’s Driver Area 64 bit long physical address
#define VIO_MMIO_QUEUE_DRV_LOW          0x090
#define VIO_MMIO_QUEUE_DRV_HIGH         0x094

// Virtual queue’s Device Area 64 bit long physical address
#define VIO_MMIO_QUEUE_DEV_LOW          0x0a0
#define VIO_MMIO_QUEUE_DEV_HIGH         0x0a4

// Shared memory id
#define VIO_MMIO_SHM_SEL                0x0ac

// Shared memory region 64 bit long length
#define VIO_MMIO_SHM_LEN_LOW            0x0b0
#define VIO_MMIO_SHM_LEN_HIGH           0x0b4

// Shared memory region 64 bit long physical address
#define VIO_MMIO_SHM_BASE_LOW           0x0b8
#define VIO_MMIO_SHM_BASE_HIGH          0x0bc

#define VIO_MMIO_QUEUE_RESET            0x0c0

// Configuration atomicity value
#define VIO_MMIO_CFG_GEN                0x0fc

// Configuration space
#define VIO_MMIO_CFG                    0x100


typedef enum {
    VIO_DEV_NET = 1,
    VIO_DEV_BLOCK = 2,
    VIO_DEV_VSOCK = 19,
    VIO_DEV_AUDIO = 25,
    VIO_DEV_FS = 26,
} vio_dev_type;

#endif // _VIO_MMIO_H_
