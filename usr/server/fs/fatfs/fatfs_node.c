/*
 * Copyright (c) 2005-2008, Kohsuke Ohtani
 * Copyright (c) 2021, Champ Yen (champ.yen@gmail.com)
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
#include <sys/buf.h>

#include <ctype.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <stdlib.h>

#include "fatfs.h"

/*
 * Generate checksum for LFN
 */
static uint8_t fat_chksum(char* name)
{
    uint8_t sum = 0;
    int i;

    for (i = 11; i > 0; i--)
        sum = ((sum & 1) ? 0x80 : 0) + (sum >> 1) + (uint8_t)*name++;
    return sum;
}

/*
 * Extract name from LFN entry
 */
static void fat_extract_lfn(struct fat_lfn_dirent* de, char* name)
{
    uint8_t* p = (uint8_t*)de;

    name[0] = p[1];
    name[1] = p[3];
    name[2] = p[5];
    name[3] = p[7];
    name[4] = p[9];
    name[5] = p[14];
    name[6] = p[16];
    name[7] = p[18];
    name[8] = p[20];
    name[9] = p[22];
    name[10] = p[24];
    name[11] = p[28];
    name[12] = p[30];
}

/*
 * Read directory entry to buffer, with cache.
 */
static int fat_read_dirent(struct fatfsmount* fmp, u_long sec)
{
    struct buf* bp;
    int error;

    if ((error = bread(fmp->dev, sec, &bp)) != 0)
        return error;
    memcpy(fmp->dir_buf, bp->b_data, SEC_SIZE);
    brelse(bp);
    return 0;
}

/*
 * Write directory entry from buffer.
 */
static int fat_write_dirent(struct fatfsmount* fmp, u_long sec)
{
    struct buf* bp;

    bp = getblk(fmp->dev, sec);
    memcpy(bp->b_data, fmp->dir_buf, SEC_SIZE);
    return bwrite(bp);
}

/*
 * Get directory entry for specified index.
 *
 * @dvp: vnode for directory.
 * @index: index of the entry
 * @np: pointer to fat node
 */
int fatfs_get_node(vnode_t dvp, int index, struct fatfs_node* np)
{
    struct fatfsmount* fmp;
    u_long cl, sec, sec_start, i, ent_idx;
    int cur_index, error;
    struct fat_dirent* de;
    char* lfn;
    uint8_t chksum = 0;
    int next_seq = -1;
    int accumulated_lfn = 0;

    lfn = malloc(512);
    if (lfn == NULL)
        return ENOMEM;
    memset(lfn, 0, 512);

    fmp = (struct fatfsmount*)dvp->v_mount->m_data;
    cl = dvp->v_blkno;
    cur_index = 0;

    DPRINTF(("fatfs_get_node: index=%d\n", index));

    if (cl == CL_ROOT && !(FAT32(fmp))) {
        /* Get entry from the root directory */
        sec_start = fmp->root_start;
        for (sec = sec_start; sec < fmp->data_start; sec++) {
            error = fat_read_dirent(fmp, sec);
            if (error) {
                free(lfn);
                return error;
            }
            de = (struct fat_dirent*)fmp->dir_buf;
            for (ent_idx = 0; ent_idx < DIR_PER_SEC; ent_idx++, de++) {
                if (IS_EMPTY(de)) {
                    free(lfn);
                    return ENOENT;
                }
                if (IS_DELETED(de)) {
                    next_seq = -1;
                    accumulated_lfn = 0;
                    continue;
                }
                if (IS_LFN(de)) {
                    struct fat_lfn_dirent* lfn_de = (struct fat_lfn_dirent*)de;
                    int seq = lfn_de->seq & LFN_SEQ_MASK;
                    if (lfn_de->seq & LFN_END) {
                        next_seq = seq;
                        chksum = lfn_de->checksum;
                        accumulated_lfn = seq;
                    }
                    if (seq != next_seq || lfn_de->checksum != chksum) {
                        next_seq = -1;
                        accumulated_lfn = 0;
                        continue;
                    }
                    fat_extract_lfn(lfn_de, &lfn[(seq - 1) * 13]);
                    next_seq--;
                    continue;
                }
                if (IS_VOL(de)) {
                    next_seq = -1;
                    accumulated_lfn = 0;
                    continue;
                }
                /* Valid SFN entry */
                if (cur_index == index) {
                    np->dirent = *de;
                    np->sector = sec;
                    np->offset = sizeof(struct fat_dirent) * ent_idx;
                    if (next_seq == 0 && chksum == fat_chksum((char*)de->name)) {
                        strlcpy(np->name, lfn, NAME_MAX);
                        np->num_lfn = accumulated_lfn;
                    } else {
                        fat_restore_name((char*)de->name, np->name);
                        np->num_lfn = 0;
                    }
                    free(lfn);
                    return 0;
                }
                cur_index++;
                next_seq = -1;
                accumulated_lfn = 0;
            }
        }
    } else {
        if (cl == CL_ROOT) /* CL_ROOT of FAT32 */
            cl = fmp->root_start;
        /* Get entry from the sub directory */
        while (!IS_EOFCL(fmp, cl)) {
            sec = cl_to_sec(fmp, cl);
            for (i = 0; i < fmp->sec_per_cl; i++) {
                error = fat_read_dirent(fmp, sec);
                if (error) {
                    free(lfn);
                    return error;
                }
                de = (struct fat_dirent*)fmp->dir_buf;
                for (ent_idx = 0; ent_idx < DIR_PER_SEC; ent_idx++, de++) {
                    if (IS_EMPTY(de)) {
                        free(lfn);
                        return ENOENT;
                    }
                    if (IS_DELETED(de)) {
                        next_seq = -1;
                        accumulated_lfn = 0;
                        continue;
                    }
                    if (IS_LFN(de)) {
                        struct fat_lfn_dirent* lfn_de = (struct fat_lfn_dirent*)de;
                        int seq = lfn_de->seq & LFN_SEQ_MASK;
                        if (lfn_de->seq & LFN_END) {
                            next_seq = seq;
                            chksum = lfn_de->checksum;
                            accumulated_lfn = seq;
                        }
                        if (seq != next_seq || lfn_de->checksum != chksum || seq == 0) {
                            next_seq = -1;
                            accumulated_lfn = 0;
                            continue;
                        }
                        fat_extract_lfn(lfn_de, &lfn[(seq - 1) * 13]);
                        next_seq--;
                        continue;
                    }
                    if (IS_VOL(de)) {
                        next_seq = -1;
                        accumulated_lfn = 0;
                        continue;
                    }
                    /* Valid SFN entry */
                    if (cur_index == index) {
                        np->dirent = *de;
                        np->sector = sec;
                        np->offset = sizeof(struct fat_dirent) * ent_idx;
                        if (next_seq == 0 && chksum == fat_chksum((char*)de->name)) {
                            strlcpy(np->name, lfn, NAME_MAX);
                            np->num_lfn = accumulated_lfn;
                        } else {
                            fat_restore_name((char*)de->name, np->name);
                            np->num_lfn = 0;
                        }
                        free(lfn);
                        return 0;
                    }
                    cur_index++;
                    next_seq = -1;
                    accumulated_lfn = 0;
                }
                sec++;
            }
            error = fat_next_cluster(fmp, cl, &cl);
            if (error) {
                free(lfn);
                return error;
            }
        }
    }
    free(lfn);
    return ENOENT;
}

/*
 * Find directory entry for specified name in directory.
 * The fat vnode data is filled if success.
 *
 * @dvp: vnode for directory.
 * @name: file name
 * @np: pointer to fat node
 */
int fatfs_lookup_node(vnode_t dvp, char* name, struct fatfs_node* np)
{
    struct fatfsmount* fmp;
    char fat_name[12];
    u_long cl, sec, sec_start, i, ent_idx;
    int error;
    struct fat_dirent* de;
    char* lfn;
    uint8_t chksum = 0;
    int next_seq = -1;
    int accumulated_lfn = 0;

    if (name == NULL)
        return ENOENT;

    lfn = malloc(512);
    if (lfn == NULL)
        return ENOMEM;
    memset(lfn, 0, 512);

    DPRINTF(("fat_lookup_node: cl=%d name=%s\n", dvp->v_blkno, name));

    fat_convert_name(name, fat_name);
    *(fat_name + 11) = '\0';

    fmp = (struct fatfsmount*)dvp->v_mount->m_data;
    cl = dvp->v_blkno;

    if (cl == CL_ROOT && !(FAT32(fmp))) {
        /* Search entry in root directory */
        sec_start = fmp->root_start;
        for (sec = sec_start; sec < fmp->data_start; sec++) {
            error = fat_read_dirent(fmp, sec);
            if (error) {
                free(lfn);
                return error;
            }
            de = (struct fat_dirent*)fmp->dir_buf;
            for (ent_idx = 0; ent_idx < DIR_PER_SEC; ent_idx++, de++) {
                if (IS_EMPTY(de)) {
                    free(lfn);
                    return ENOENT;
                }
                if (IS_DELETED(de)) {
                    next_seq = -1;
                    accumulated_lfn = 0;
                    continue;
                }
                if (IS_LFN(de)) {
                    struct fat_lfn_dirent* lfn_de = (struct fat_lfn_dirent*)de;
                    int seq = lfn_de->seq & LFN_SEQ_MASK;
                    if (lfn_de->seq & LFN_END) {
                        next_seq = seq;
                        chksum = lfn_de->checksum;
                        accumulated_lfn = seq;
                    }
                    if (seq != next_seq || lfn_de->checksum != chksum) {
                        next_seq = -1;
                        accumulated_lfn = 0;
                        continue;
                    }
                    fat_extract_lfn(lfn_de, &lfn[(seq - 1) * 13]);
                    next_seq--;
                    continue;
                }
                if (IS_VOL(de)) {
                    next_seq = -1;
                    accumulated_lfn = 0;
                    continue;
                }
                /* Valid SFN entry. Match name. */
                if ((next_seq == 0 && chksum == fat_chksum((char*)de->name) && !strcasecmp(lfn, name)) ||
                    !fat_compare_name((char*)de->name, fat_name)) {
                    np->dirent = *de;
                    np->sector = sec;
                    np->offset = sizeof(struct fat_dirent) * ent_idx;
                    if (next_seq == 0 && chksum == fat_chksum((char*)de->name)) {
                        strlcpy(np->name, lfn, NAME_MAX);
                        np->num_lfn = accumulated_lfn;
                    } else {
                        fat_restore_name((char*)de->name, np->name);
                        np->num_lfn = 0;
                    }
                    free(lfn);
                    return 0;
                }
                next_seq = -1;
                accumulated_lfn = 0;
            }
        }
    } else {
        if (cl == CL_ROOT) /* CL_ROOT of FAT32 */
            cl = fmp->root_start;
        /* Search entry in sub directory */
        while (!IS_EOFCL(fmp, cl)) {
            sec = cl_to_sec(fmp, cl);
            for (i = 0; i < fmp->sec_per_cl; i++) {
                error = fat_read_dirent(fmp, sec);
                if (error) {
                    free(lfn);
                    return error;
                }
                de = (struct fat_dirent*)fmp->dir_buf;
                for (ent_idx = 0; ent_idx < DIR_PER_SEC; ent_idx++, de++) {
                    if (IS_EMPTY(de)) {
                        free(lfn);
                        return ENOENT;
                    }
                    if (IS_DELETED(de)) {
                        next_seq = -1;
                        accumulated_lfn = 0;
                        continue;
                    }
                    if (IS_LFN(de)) {
                        struct fat_lfn_dirent* lfn_de = (struct fat_lfn_dirent*)de;
                        int seq = lfn_de->seq & LFN_SEQ_MASK;
                        if (lfn_de->seq & LFN_END) {
                            next_seq = seq;
                            chksum = lfn_de->checksum;
                            accumulated_lfn = seq;
                        }
                        if (seq != next_seq || lfn_de->checksum != chksum || seq == 0) {
                            next_seq = -1;
                            accumulated_lfn = 0;
                            continue;
                        }
                        fat_extract_lfn(lfn_de, &lfn[(seq - 1) * 13]);
                        next_seq--;
                        continue;
                    }
                    if (IS_VOL(de)) {
                        next_seq = -1;
                        accumulated_lfn = 0;
                        continue;
                    }
                    /* Valid SFN entry. Match name. */
                    if ((next_seq == 0 && chksum == fat_chksum((char*)de->name) && !strcasecmp(lfn, name)) ||
                        !fat_compare_name((char*)de->name, fat_name)) {
                        np->dirent = *de;
                        np->sector = sec;
                        np->offset = sizeof(struct fat_dirent) * ent_idx;
                        if (next_seq == 0 && chksum == fat_chksum((char*)de->name)) {
                            strlcpy(np->name, lfn, NAME_MAX);
                            np->num_lfn = accumulated_lfn;
                        } else {
                            fat_restore_name((char*)de->name, np->name);
                            np->num_lfn = 0;
                        }
                        free(lfn);
                        return 0;
                    }
                    next_seq = -1;
                    accumulated_lfn = 0;
                }
                sec++;
            }
            error = fat_next_cluster(fmp, cl, &cl);
            if (error) {
                free(lfn);
                return error;
            }
        }
    }
    free(lfn);
    return ENOENT;
}

/*
 * Generate 8.3 alias for long name
 */
static void fat_generate_alias(char* name, char* fat_name)
{
    int i, j;
    char* ext;

    memset(fat_name, ' ', 11);
    for (i = 0, j = 0; i < 6 && name[i] && name[i] != '.'; i++) {
        if (name[i] == ' ' || name[i] == '.')
            continue;
        fat_name[j++] = toupper((int)name[i]);
    }
    fat_name[j++] = '~';
    fat_name[j++] = '1';

    ext = strrchr(name, '.');
    if (ext && ext != name) {
        ext++;
        for (i = 0; i < 3 && ext[i]; i++) {
            fat_name[8 + i] = toupper((int)ext[i]);
        }
    }
}

/*
 * Set name part in LFN entry
 */
static void fat_set_lfn_part(struct fat_lfn_dirent* de, const char* name)
{
    uint8_t* p = (uint8_t*)de;
    int i;
    int end = 0;

    for (i = 0; i < 5; i++) {
        if (!end) {
            p[1 + i * 2] = *name;
            p[2 + i * 2] = 0;
            if (!*name)
                end = 1;
            else
                name++;
        } else {
            p[1 + i * 2] = 0xff;
            p[2 + i * 2] = 0xff;
        }
    }
    for (i = 0; i < 6; i++) {
        if (!end) {
            p[14 + i * 2] = *name;
            p[15 + i * 2] = 0;
            if (!*name)
                end = 1;
            else
                name++;
        } else {
            p[14 + i * 2] = 0xff;
            p[15 + i * 2] = 0xff;
        }
    }
    for (i = 0; i < 2; i++) {
        if (!end) {
            p[28 + i * 2] = *name;
            p[29 + i * 2] = 0;
            if (!*name)
                end = 1;
            else
                name++;
        } else {
            p[28 + i * 2] = 0xff;
            p[29 + i * 2] = 0xff;
        }
    }
}

/*
 * Find contiguous empty directory entries.
 */
static int fat_find_free_slots(struct fatfsmount* fmp, u_long cl, int num, u_long* out_sec, u_long* out_ent)
{
    u_long i, sec, ent_idx;
    int count = 0;
    struct fat_dirent* de;
    int error;

    while (!IS_EOFCL(fmp, cl)) {
        sec = cl_to_sec(fmp, cl);
        for (i = 0; i < fmp->sec_per_cl; i++) {
            error = fat_read_dirent(fmp, sec);
            if (error)
                return error;
            de = (struct fat_dirent*)fmp->dir_buf;
            for (ent_idx = 0; ent_idx < DIR_PER_SEC; ent_idx++, de++) {
                if (IS_EMPTY(de) || IS_DELETED(de)) {
                    if (count == 0) {
                        *out_sec = sec;
                        *out_ent = ent_idx;
                    }
                    count++;
                    if (count == num)
                        return 0;
                } else {
                    count = 0;
                }
            }
            sec++;
        }
        error = fat_next_cluster(fmp, cl, &cl);
        if (error)
            return error;
    }
    return ENOENT;
}

/*
 * Find empty directory entry and put new entry on it.
 * This search is done only in directory of specified cluster.
 * @dvp: vnode for directory.
 * @np: pointer to fat node
 */
int fatfs_add_node(vnode_t dvp, struct fatfs_node* np)
{
    struct fatfsmount* fmp;
    u_long cl, sec, next;
    int error;
    int num_lfn = 0;
    int total_entries;
    u_long start_sec = 0, start_ent = 0;
    struct fat_dirent* de;
    int i;
    uint8_t chksum;

    fmp = (struct fatfsmount*)dvp->v_mount->m_data;
    cl = dvp->v_blkno;

    if (!fat_valid_name(np->name)) {
        num_lfn = (strlen(np->name) + 12) / 13;
        fat_generate_alias(np->name, (char*)np->dirent.name);
    } else {
        fat_convert_name(np->name, (char*)np->dirent.name);
    }
    total_entries = num_lfn + 1;

    DPRINTF(("fatfs_add_node: cl=%d name=%s entries=%d\n", cl, np->name, total_entries));

    if (cl == CL_ROOT && !(FAT32(fmp))) {
        /* Search in root directory */
        int count = 0;
        for (sec = fmp->root_start; sec < fmp->data_start; sec++) {
            error = fat_read_dirent(fmp, sec);
            if (error)
                return error;
            de = (struct fat_dirent*)fmp->dir_buf;
            for (i = 0; i < DIR_PER_SEC; i++, de++) {
                if (IS_EMPTY(de) || IS_DELETED(de)) {
                    if (count == 0) {
                        start_sec = sec;
                        start_ent = (u_long)i;
                    }
                    if (++count == total_entries)
                        goto found;
                } else
                    count = 0;
            }
        }
        return ENOSPC;
    } else {
        if (cl == CL_ROOT)
            cl = fmp->root_start;
        error = fat_find_free_slots(fmp, cl, total_entries, &start_sec, &start_ent);
        if (error == ENOENT) {
            /* Expand directory */
            u_long last_cl = cl;
            while (!IS_EOFCL(fmp, last_cl)) {
                cl = last_cl;
                if (fat_next_cluster(fmp, cl, &last_cl))
                    break;
            }
            error = fat_expand_dir(fmp, cl, &next);
            if (error)
                return error;
            start_sec = cl_to_sec(fmp, next);
            start_ent = 0;
        } else if (error)
            return error;
    }

found:
    /* Write entries */
    chksum = fat_chksum((char*)np->dirent.name);
    sec = start_sec;
    for (i = 0; i < total_entries; i++) {
        error = fat_read_dirent(fmp, sec);
        if (error)
            return error;
        de = (struct fat_dirent*)fmp->dir_buf + start_ent;

        if (i < num_lfn) {
            /* LFN entry */
            struct fat_lfn_dirent* lfn_de = (struct fat_lfn_dirent*)de;
            int seq = num_lfn - i;
            memset(lfn_de, 0, sizeof(struct fat_lfn_dirent));
            lfn_de->seq = (uint8_t)seq;
            if (i == 0)
                lfn_de->seq |= LFN_END;
            lfn_de->attr = FA_LFN;
            lfn_de->checksum = chksum;
            fat_set_lfn_part(lfn_de, &np->name[(seq - 1) * 13]);
        } else {
            /* SFN entry */
            memcpy(de, &np->dirent, sizeof(struct fat_dirent));
        }

        error = fat_write_dirent(fmp, sec);
        if (error)
            return error;

        start_ent++;
        if (start_ent >= DIR_PER_SEC) {
            start_ent = 0;
            sec++;
            /* XXX: should handle cluster boundary if not root */
        }
    }
    return 0;
}

/*
 * Update directory entry for specified node.
 */
int fatfs_put_node(struct fatfsmount* fmp, struct fatfs_node* np)
{
    int error;
    struct fat_dirent* de;

    error = fat_read_dirent(fmp, np->sector);
    if (error)
        return error;

    de = (struct fat_dirent*)(fmp->dir_buf + np->offset);
    memcpy(de, &np->dirent, sizeof(struct fat_dirent));

    return fat_write_dirent(fmp, np->sector);
}

/*
 * Remove directory entry for specified node.
 */
int fatfs_remove_node(struct fatfsmount* fmp, struct fatfs_node* np)
{
    int error;
    struct fat_dirent* de;
    int i;
    u_long sec = np->sector;
    int ent_idx = (int)(np->offset / sizeof(struct fat_dirent));

    for (i = 0; i <= np->num_lfn; i++) {
        error = fat_read_dirent(fmp, sec);
        if (error)
            return error;
        de = (struct fat_dirent*)fmp->dir_buf + ent_idx;
        de->name[0] = SLOT_DELETED;
        error = fat_write_dirent(fmp, sec);
        if (error)
            return error;

        if (ent_idx == 0 && i < np->num_lfn) {
            /* XXX: Should handle cluster boundary if not root */
            sec--;
            ent_idx = DIR_PER_SEC - 1;
        } else {
            ent_idx--;
        }
    }
    return 0;
}
