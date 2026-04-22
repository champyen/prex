/*
 * Simplified tar for Prex, iterative to save file descriptors.
 */

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <dirent.h>
#include <sys/param.h>
#include <sys/stat.h>
#include <sys/time.h>

#define TBLOCK 512
#define NAMSIZ 100

union hblock {
    char dummy[TBLOCK];
    struct header {
        char name[NAMSIZ];
        char mode[8];
        char uid[8];
        char gid[8];
        char size[12];
        char mtime[12];
        char chksum[8];
        char linkflag;
        char linkname[NAMSIZ];
    } dbuf;
};

static union hblock dblock;
static union hblock *tbuf;
static int vflag, cflag;
static int mt;
static int recno;
static int nblock = 20;

static void tomodes(struct stat *sp) {
    char buf[32];
    memset(dblock.dummy, 0, TBLOCK);
    sprintf(buf, "%6o ", (unsigned int)sp->st_mode & 0777);
    strncpy(dblock.dbuf.mode, buf, 8);
    sprintf(buf, "%6o ", (unsigned int)sp->st_uid);
    strncpy(dblock.dbuf.uid, buf, 8);
    sprintf(buf, "%6o ", (unsigned int)sp->st_gid);
    strncpy(dblock.dbuf.gid, buf, 8);
    sprintf(buf, "%11lo ", (unsigned long)sp->st_size);
    strncpy(dblock.dbuf.size, buf, 12);
    sprintf(buf, "%11lo ", (unsigned long)sp->st_mtime);
    strncpy(dblock.dbuf.mtime, buf, 12);
}

static int checksum(void) {
    int i = 0;
    unsigned char *cp;
    for (int j=0; j<8; j++) dblock.dbuf.chksum[j] = ' ';
    cp = (unsigned char *)dblock.dummy;
    for (int j = 0; j < TBLOCK; j++) i += cp[j];
    return i;
}

static void writetbuf(char *buffer, int n) {
    if (tbuf == NULL) tbuf = malloc((size_t)nblock * TBLOCK);
    while (n-- > 0) {
        memcpy((char *)&tbuf[recno++], buffer, TBLOCK);
        buffer += TBLOCK;
        if (recno >= nblock) {
            write(mt, (char *)tbuf, (size_t)(TBLOCK * nblock));
            recno = 0;
        }
    }
}

static void flushtape(void) {
    if (recno > 0) {
        memset((char *)&tbuf[recno], 0, (size_t)(TBLOCK * (nblock - recno)));
        write(mt, (char *)tbuf, (size_t)(TBLOCK * nblock));
    }
}

static void putfile(char *longname) {
    int infile;
    char buf[TBLOCK];
    struct stat st;

    if (stat(longname, &st) < 0) return;
    if (vflag) fprintf(stderr, "a %s\n", longname);

    if (S_ISREG(st.st_mode)) {
        tomodes(&st);
        strncpy(dblock.dbuf.name, longname, NAMSIZ);
        sprintf(dblock.dbuf.chksum, "%6o", checksum());
        writetbuf((char *)&dblock, 1);
        if ((infile = open(longname, O_RDONLY)) >= 0) {
            int i;
            while ((i = (int)read(infile, buf, TBLOCK)) > 0) {
                if (i < TBLOCK) memset(buf + i, 0, (size_t)(TBLOCK - i));
                writetbuf(buf, 1);
            }
            close(infile);
        }
    } else if (S_ISDIR(st.st_mode)) {
        tomodes(&st);
        strncpy(dblock.dbuf.name, longname, NAMSIZ);
        int len = (int)strlen(dblock.dbuf.name);
        if (len < NAMSIZ - 1 && dblock.dbuf.name[len-1] != '/') {
            dblock.dbuf.name[len] = '/';
            dblock.dbuf.name[len+1] = '\0';
        }
        sprintf(dblock.dbuf.chksum, "%6o", checksum());
        writetbuf((char *)&dblock, 1);
    }
}

int main(int argc, char **argv) {
    char *cp;
    char *usefile = NULL;

    vflag = cflag = 0;
    recno = 0;
    tbuf = NULL;

    if (argc < 2) return 1;
    argv++;
    while (*argv && **argv == '-') {
        for (cp = *argv++ + 1; *cp; cp++) {
            switch (*cp) {
            case 'f': if (*argv) usefile = *argv++; break;
            case 'c': cflag = 1; break;
            case 'v': vflag = 1; break;
            }
        }
    }

    if (cflag) {
        if (usefile) mt = open(usefile, O_RDWR|O_CREAT|O_TRUNC, 0666);
        else mt = dup(1);
        
        if (mt < 0) return 1;

        /* Iterative traversal for tar -c */
        char *stack[32];
        int depth = 0;
        while (*argv) {
            if (depth < 32) stack[depth++] = strdup(*argv++);
            else break;
        }
        
        while (depth > 0) {
            char *path = stack[--depth];
            putfile(path);
            struct stat st;
            if (stat(path, &st) == 0 && S_ISDIR(st.st_mode)) {
                DIR *dir = opendir(path);
                if (dir) {
                    struct dirent *de;
                    while ((de = readdir(dir))) {
                        if (strcmp(de->d_name, ".")==0 || strcmp(de->d_name, "..")==0) continue;
                        char newpath[256];
                        if (strlen(path) + strlen(de->d_name) + 2 < 256) {
                            sprintf(newpath, "%s/%s", path, de->d_name);
                            if (depth < 32) stack[depth++] = strdup(newpath);
                        }
                    }
                    closedir(dir);
                }
            }
            free(path);
        }
        memset(dblock.dummy, 0, TBLOCK);
        writetbuf(dblock.dummy, 1); /* empty */
        writetbuf(dblock.dummy, 1); /* empty */
        flushtape();
        close(mt);
    }
    if (tbuf) free(tbuf);
    return 0;
}
