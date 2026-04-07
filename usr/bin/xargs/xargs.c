/*-
 * Copyright (c) 1990, 1993
 *	The Regents of the University of California.  All rights reserved.
 *
 * This code is derived from software contributed to Berkeley by
 * John B. Roll Jr.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 3. All advertising materials mentioning features or use of this software
 *    must display the following acknowledgement:
 *	This product includes software developed by the University of
 *	California, Berkeley and its contributors.
 * 4. Neither the name of the University nor the names of its contributors
 *    may be used to endorse or promote products derived from this software
 *    without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE REGENTS AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE REGENTS OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 */

/* modified by Kohsuke Ohtani for Prex. */

#include <sys/param.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <paths.h>
#include <stdarg.h>

#ifdef CMDBOX
#define main(argc, argv) xargs_main(argc, argv)
#endif

#ifndef _PATH_ECHO
#define _PATH_ECHO "/bin/echo"
#endif

static int tflag, rval;

static void fatal(const char *fmt, ...)
{
	va_list ap;
	va_start(ap, fmt);
	(void)fprintf(stderr, "xargs: ");
	(void)vfprintf(stderr, fmt, ap);
	va_end(ap);
	(void)fprintf(stderr, "\n");
	exit(1);
}

static void run(char **argv)
{
	int noinvoke;
	char **p;
	pid_t pid;
	int status;

	if (tflag) {
		(void)fprintf(stderr, "%s", *argv);
		for (p = argv + 1; *p; ++p)
			(void)fprintf(stderr, " %s", *p);
		(void)fprintf(stderr, "\n");
		(void)fflush(stderr);
	}
	noinvoke = 0;
	switch(pid = vfork()) {
	case -1:
		fatal("vfork: %s", strerror(errno));
	case 0:
		execvp(argv[0], argv);
		(void)fprintf(stderr,
		    "xargs: %s: %s\n", argv[0], strerror(errno));
		noinvoke = 1;
		_exit(1);
	}
	pid = waitpid(pid, &status, 0);
	if (pid == -1)
		fatal("waitpid: %s", strerror(errno));
	if (noinvoke)
		exit(127);
	if (WIFSIGNALED(status) || (WIFEXITED(status) && WEXITSTATUS(status) == 255))
		exit(1);
	if (WIFEXITED(status) && WEXITSTATUS(status))
		rval = 1;
}

static void usage(void)
{
	(void)fprintf(stderr,
"usage: xargs [-t] [-n number [-x]] [-s size] [utility [argument ...]]\n");
	exit(1);
}

int main(int argc, char **argv)
{
	int ch;
	char *p, *bbp, *ebp, **bxp, **exp, **xp;
	int cnt, indouble, insingle, nargs, nflag, nline, xflag;
	char **av, *argp;

	tflag = rval = 0;
	optind = 1; /* Reset for cmdbox */

	/*
	 * Prex has very small ARG_MAX (255).
	 */
	nargs = 5000;
	nline = ARG_MAX - 64; 
	if (nline <= 0) nline = 100;

	nflag = xflag = 0;
	while ((ch = getopt(argc, argv, "n:s:tx")) != EOF)
		switch(ch) {
		case 'n':
			nflag = 1;
			if ((nargs = atoi(optarg)) <= 0)
				fatal("illegal argument count");
			break;
		case 's':
			nline = atoi(optarg);
			break;
		case 't':
			tflag = 1;
			break;
		case 'x':
			xflag = 1;
			break;
		case '?':
		default:
			usage();
	}
	argc -= optind;
	argv += optind;

	if (xflag && !nflag)
		usage();

	if (!(av = bxp =
	    (char **)malloc((size_t)(1 + argc + nargs + 1) * sizeof(char **))))
		fatal("%s", strerror(errno));

	if (!*argv) {
		*bxp = _PATH_ECHO;
		cnt = strlen(*bxp++);
	} else {
		cnt = 0;
		do {
			*bxp = *argv;
			cnt += strlen(*bxp++) + 1;
		} while (*++argv);
	}

	exp = (xp = bxp) + nargs;

	nline -= cnt;
	if (nline <= 0)
		fatal("insufficient space for command");

	if (!(bbp = (char *)malloc((size_t)nline + 1)))
		fatal("%s", strerror(errno));
	ebp = (argp = p = bbp) + nline - 1;

	for (insingle = indouble = 0;;) {
		switch(ch = getchar()) {
		case EOF:
			if (p == bbp)
				exit(rval);
			if (argp == p) {
				*xp = NULL;
				run(av);
				exit(rval);
			}
			goto arg1;
		case ' ':
		case '\t':
			if (insingle || indouble)
				goto addch;
			goto arg2;
		case '\n':
			if (argp == p)
				continue;
arg1:			if (insingle || indouble)
				 fatal("unterminated quote");

arg2:			*p = '\0';
			*xp++ = argp;

			if (xp == exp || p == ebp || ch == EOF) {
				if (xflag && xp != exp && p == ebp)
					fatal("insufficient space for arguments");
				*xp = NULL;
				run(av);
				if (ch == EOF)
					exit(rval);
				p = bbp;
				xp = bxp;
			} else
				++p;
			argp = p;
			break;
		case '\'':
			if (indouble)
				goto addch;
			insingle = !insingle;
			break;
		case '"':
			if (insingle)
				goto addch;
			indouble = !indouble;
			break;
		case '\\':
			if (!insingle && !indouble && (ch = getchar()) == EOF)
				fatal("backslash at EOF");
		default:
addch:			if (p < ebp) {
				*p++ = (char)ch;
				break;
			}
			if (bxp == xp)
				fatal("insufficient space for argument");
			if (xflag)
				fatal("insufficient space for arguments");

			*xp = NULL;
			run(av);
			xp = bxp;
			cnt = (int)(ebp - argp);
			memcpy(bbp, argp, (size_t)cnt);
			p = (argp = bbp) + cnt;
			*p++ = (char)ch;
			break;
		}
        }
}
