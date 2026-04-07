/*
 * Simplified gzip for Prex
 * Based on LiteBSD gzip.c and zlib
 */

#include <sys/types.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include "libz/zlib.h"

#ifdef CMDBOX
#define main(argc, argv) gzip_main(argc, argv)
#endif

static int dflag; /* decompress */
static int cflag; /* stdout */
static int vflag; /* verbose */

static void usage(void)
{
    fprintf(stderr, "usage: gzip [-dcv] [file ...]\n");
    exit(1);
}

static int gz_compress(FILE *in, char *out_name)
{
    char buf[BUFSIZ];
    int len;
    gzFile gfile;

    if (out_name == NULL) {
        /* This case not fully supported by zlib gzopen for stdout usually, 
           but let's try fd 1 */
        gfile = gzdopen(1, "wb");
    } else {
        gfile = gzopen(out_name, "wb");
    }

    if (gfile == NULL) return -1;

    while ((len = (int)fread(buf, 1, sizeof(buf), in)) > 0) {
        if (gzwrite(gfile, buf, (unsigned)len) != len) {
            gzclose(gfile);
            return -1;
        }
    }

    gzclose(gfile);
    return 0;
}

static int gz_uncompress(char *in_name, FILE *out)
{
    char buf[BUFSIZ];
    int len;
    gzFile gfile;

    if (in_name == NULL) {
        gfile = gzdopen(0, "rb");
    } else {
        gfile = gzopen(in_name, "rb");
    }

    if (gfile == NULL) return -1;

    while ((len = gzread(gfile, buf, sizeof(buf))) > 0) {
        if (fwrite(buf, 1, (size_t)len, out) != (size_t)len) {
            gzclose(gfile);
            return -1;
        }
    }

    gzclose(gfile);
    return 0;
}

static void handle_file(char *file)
{
    FILE *in = NULL, *out = NULL;
    char out_name[256];
    int res;

    if (file == NULL) {
        if (dflag) gz_uncompress(NULL, stdout);
        else gz_compress(stdin, NULL);
        return;
    }

    if (dflag) {
        char *dot = strrchr(file, '.');
        if (dot && strcmp(dot, ".gz") == 0) {
            int len = (int)(dot - file);
            if (len > 255) len = 255;
            strncpy(out_name, file, (size_t)len);
            out_name[len] = '\0';
        } else {
            sprintf(out_name, "%s.out", file);
        }
        
        if (cflag) out = stdout;
        else if ((out = fopen(out_name, "wb")) == NULL) {
            perror(out_name);
            return;
        }

        res = gz_uncompress(file, out);
        if (res < 0) fprintf(stderr, "decompression failed\n");
        
        if (out != stdout) {
            fclose(out);
            if (res == 0) unlink(file);
        }
    } else {
        if ((in = fopen(file, "rb")) == NULL) {
            perror(file);
            return;
        }
        sprintf(out_name, "%s.gz", file);
        
        if (cflag) res = gz_compress(in, NULL);
        else res = gz_compress(in, out_name);

        if (res < 0) fprintf(stderr, "compression failed\n");
        
        fclose(in);
        if (!cflag && res == 0) unlink(file);
    }
}

int main(int argc, char **argv)
{
    int ch;

    dflag = cflag = vflag = 0;
    if (argc > 0) {
        char *p = strrchr(argv[0], '/');
        if (p) p++; else p = argv[0];
        if (strcmp(p, "gunzip") == 0) dflag = 1;
    }
    optind = 1;

    while ((ch = getopt(argc, argv, "dcv")) != -1) {
        switch (ch) {
        case 'd': dflag = 1; break;
        case 'c': cflag = 1; break;
        case 'v': vflag = 1; break;
        default: usage();
        }
    }
    argc -= optind;
    argv += optind;

    if (argc == 0) handle_file(NULL);
    else {
        while (argc--) handle_file(*argv++);
    }

    return 0;
}
