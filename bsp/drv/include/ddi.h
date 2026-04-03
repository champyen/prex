/*
 * Copyright (c) 2009, Kohsuke Ohtani
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

/*
 * ddi.h - Device Driver Interface
 */

#ifndef _DDI_H
#define _DDI_H

#include <types.h>
#include <sys/cdefs.h>
#include <sys/types.h>
#include <machine/stdarg.h>
#include <dki.h>
#include <busio.h> /* bus_read/bus_write */

#ifdef DEBUG
#define ASSERT(exp)                                                                                                    \
    do {                                                                                                               \
        if (!(exp))                                                                                                    \
            assert(__FILE__, __LINE__, #exp);                                                                          \
    } while (0)
#else
#define ASSERT(exp) ((void)0)
#endif

/*
 * I/O request packet
 */
struct irp
{
    int cmd;             /* I/O command */
    int blkno;           /* block number */
    u_long blksz;        /* block size */
    void* buf;           /* I/O buffer */
    int ntries;          /* retry count */
    int error;           /* error status */
    struct event iocomp; /* I/O completion event */
};

/*
 * I/O command
 */
#define IO_NONE 0
#define IO_READ 1
#define IO_WRITE 2
#define IO_FORMAT 3 /* not supported */
#define IO_CANCEL 4

__BEGIN_DECLS
void driver_shutdown(void);
void calibrate_delay(void);
void delay_usec(u_long usec);

int enodev(void);
int nullop(void);

/*
 * DMA transfer request
 */
struct dma_xfer_req
{
    void*   addr;       /* memory address */
    paddr_t dev_addr;   /* device address */
    u_long  size;       /* transfer size */
    int     dir;        /* direction */
    int     dreq;       /* dreq line */
};

/* DMA directions */
#define DMA_READ  0 /* device -> memory */
#define DMA_WRITE 1 /* memory -> device */
#define DMA_COPY  2 /* memory -> memory */

dma_t dma_attach(int chan);
void dma_detach(dma_t handle);
void dma_xfer(dma_t handle, struct dma_xfer_req* req);
void dma_stop(dma_t handle);
void dma_wait(dma_t handle, int32_t timeout_ms);
void* dma_alloc(size_t size);

long atol(const char* str);
char* strncpy(char* dest, const char* src, size_t count);
int strncmp(const char* src, const char* tgt, size_t count);
size_t strlcpy(char* dest, const char* src, size_t count);
size_t strnlen(const char* str, size_t max);
void* memcpy(void* dest, const void* src, size_t count);
void* memset(void* dest, int ch, size_t count);

u_long strtoul(const char* nptr, char** endptr, int base);

int isalnum(int c);
int isalpha(int c);
int isblank(int c);
int isupper(int c);
int islower(int c);
int isspace(int c);
int isdigit(int c);
int isxdigit(int c);
int isprint(int c);

#ifdef DEBUG
void assert(const char*, int, const char*);
#endif
__END_DECLS

#endif /* !_DDI_H */
