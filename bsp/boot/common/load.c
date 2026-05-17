/*-
 * Copyright (c) 2005-2009, Kohsuke Ohtani
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
 * load.c - OS image loader
 */

#include <boot.h>
#include <load.h>
#include <sys/ar.h>

/* forward declarations */
static int load_module(struct ar_hdr*, struct module*);
static void setup_bootdisk(struct ar_hdr*);

paddr_t load_base;
paddr_t load_start;
int nr_img = 0;

/*
 * Load all modules.
 * The boot image contains the kernel, drivers and boot tasks.
 * It is an archive file in AR format.
 */
void load_os(void)
{
    char* magic;
    struct ar_hdr* hdr;
    struct module* m;
    char* base;
    size_t size;

    DPRINTF(("loading: ...\n"));

    /*
     *  Sanity check of archive image.
     */
    magic = (char*)kvtop(CONFIG_BOOTIMG_BASE);
    if (strncmp(magic, ARMAG, SARMAG)) {
        char* scan = (char*)0x80000000;
        int j;
        DPRINTF(("Searching 16MB RAM for magic...\n"));
        for (j = 0; j < 0x1000000; j += 4) {
            if (scan[j] == '!' && scan[j+1] == '<' && scan[j+2] == 'a') {
                DPRINTF(("FOUND magic at %lx!\n", (long)(scan + j)));
            }
        }
        panic("Invalid OS image");
    }

    /*
     * Load kernel module.
     */
    hdr = (struct ar_hdr*)(magic + SARMAG);
    if (load_module(hdr, &bootinfo->kernel) != 0) {
        panic("Invalid kernel module");
    }

    /*
     * Load driver module.
     */
    size = (size_t)atol((char*)&hdr->ar_size);
    hdr = (struct ar_hdr*)((paddr_t)hdr + sizeof(struct ar_hdr) + roundup(size, 2));
    if (load_module(hdr, &bootinfo->driver) != 0) {
        panic("Invalid driver module");
    }

    /*
     * Load boot tasks.
     */
    for (;;) {
        size = (size_t)atol((char*)&hdr->ar_size);
        hdr = (struct ar_hdr*)((paddr_t)hdr + sizeof(struct ar_hdr) + roundup(size, 2));
        m = &bootinfo->tasks[bootinfo->nr_tasks];
        if (load_module(hdr, m) != 0) {
            break;
        }
        bootinfo->nr_tasks++;
    }

    /*
     *  Reserve memory for image modules
     */
    base = (char*)kvtop(CONFIG_BOOTIMG_BASE);
    size = (size_t)round_page((paddr_t)hdr - (paddr_t)base);
    bootinfo->ram[bootinfo->nr_rams].base = (paddr_t)base;
    bootinfo->ram[bootinfo->nr_rams].size = size;
    bootinfo->ram[bootinfo->nr_rams].type = MT_RESERVED;
    bootinfo->nr_rams++;

#ifdef CONFIG_BOOTDISK
    setup_bootdisk(hdr);
#endif
}

/*
 * Load module.
 * Return 0 on success, -1 on failure.
 */
static int load_module(struct ar_hdr* hdr, struct module* m)
{
    char* c;

    if (strncmp((char*)&hdr->ar_fmag, ARFMAG, 2)) {
        return -1;
    }
    c = (char*)&hdr->ar_name[0];
    strlcpy(m->name, c, sizeof(m->name));
    for (c = m->name; *c != '\0'; c++) {
        if (*c == ' ' || *c == '/') {
            *c = '\0';
            break;
        }
    }
    DPRINTF(("loading: hdr=%lx module=%lx name=%s\n", (long)hdr, (long)m, m->name));

    if (load_elf((char*)hdr + sizeof(struct ar_hdr), m) != 0) {
        return -1;
    }
    return 0;
}

#ifdef CONFIG_BOOTDISK
/*
 * Setup boot disk
 */
static void setup_bootdisk(struct ar_hdr* hdr)
{
    struct bootinfo* bi = bootinfo;
    paddr_t base;
    size_t size;

    if (strncmp((char*)&hdr->ar_fmag, ARFMAG, 2)) {
        return;
    }

    base = (paddr_t)round_page((paddr_t)hdr + sizeof(struct ar_hdr));
    size = (size_t)atol((char*)&hdr->ar_size);

    bi->bootdisk.base = base;
    bi->bootdisk.size = size;

    /*  Reserve memory for boot disk */
    bi->ram[bi->nr_rams].base = base;
    bi->ram[bi->nr_rams].size = (size_t)round_page(size);
    bi->ram[bi->nr_rams].type = MT_BOOTDISK;
    bi->nr_rams++;
#endif
    DPRINTF(("bootdisk base=%lx size=%lx\n", bi->bootdisk.base, bi->bootdisk.size));
}
