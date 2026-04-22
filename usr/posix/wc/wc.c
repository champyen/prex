/*
 * Copyright (c) 1980 Regents of the University of California.
 * All rights reserved.  The Berkeley software License Agreement
 * specifies the terms and conditions for redistribution.
 */

/* modified by Kohsuke Ohtani for Prex. */

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>

static long linect, wordct, charct;
static long tlinect, twordct, tcharct;
static char *wd = "lwc";

static void wcp(char *wd, long charct, long wordct, long linect);
static void ipr(long num);

int main(int argc, char **argv)
{
    int i, token;
    FILE *fp;
    int c;

    linect = wordct = charct = 0;
    tlinect = twordct = tcharct = 0;
    wd = "lwc";

    while (argc > 1 && *argv[1] == '-') {
        switch (argv[1][1]) {
        case 'l':
        case 'w':
        case 'c':
            wd = argv[1] + 1;
            break;
        default:
            fprintf(stderr, "Usage: wc [-lwc] [files]\n");
            exit(1);
        }
        argc--;
        argv++;
    }

    i = 1;
    fp = stdin;
    do {
        if (argc > 1) {
            if ((fp = fopen(argv[i], "r")) == NULL) {
                perror(argv[i]);
                continue;
            }
        }
        linect = 0;
        wordct = 0;
        charct = 0;
        token = 0;
        for (;;) {
            c = getc(fp);
            if (c == EOF)
                break;
            charct++;
            if (' ' < c && c < 0177) {
                if (!token) {
                    wordct++;
                    token++;
                }
                continue;
            }
            if (c == '\n') {
                linect++;
            } else if (c != ' ' && c != '\t')
                continue;
            token = 0;
        }
        /* print lines, words, chars */
        wcp(wd, charct, wordct, linect);
        if (argc > 1) {
            printf(" %s\n", argv[i]);
        } else
            printf("\n");
        if (fp != stdin)
            fclose(fp);
        tlinect += linect;
        twordct += wordct;
        tcharct += charct;
    } while (++i < argc);
    if (argc > 2) {
        wcp(wd, tcharct, twordct, tlinect);
        printf(" total\n");
    }
    exit(0);
}

static void wcp(char *wd, long charct, long wordct, long linect)
{
    while (*wd) {
        switch (*wd++) {
        case 'l':
            ipr(linect);
            break;

        case 'w':
            ipr(wordct);
            break;

        case 'c':
            ipr(charct);
            break;
        }
    }
}

static void ipr(long num)
{
    printf(" %7ld", num);
}
