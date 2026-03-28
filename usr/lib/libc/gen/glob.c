/*
 * Copyright (c) 1989, 1993
 *	The Regents of the University of California.  All rights reserved.
 *
 * This code is derived from software contributed to Berkeley by
 * Guido van Rossum.
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

/*
 * glob(3) -- a superset of the one defined in POSIX 1003.2.
 *
 * The [!...] convention to negate a range is supported (SysV, Posix, ksh).
 *
 * Optional extra services, controlled by flags not defined by POSIX:
 *
 * GLOB_QUOTE:
 *	Escaping convention: \ inhibits any special meaning the following
 *	character might have (except \ at end of string is retained).
 * GLOB_MAGCHAR:
 *	Set in gl_flags if pattern contained a globbing character.
 * GLOB_NOMAGIC:
 *	Same as GLOB_NOCHECK, but it will only append pattern if it did
 *	not contain any magic characters.  [Used in csh style globbing]
 * GLOB_ALTDIRFUNC:
 *	Use alternately specified directory access functions.
 * GLOB_TILDE:
 *	expand ~user/foo to the /home/dir/of/user/foo
 * GLOB_BRACE:
 *	expand {1,2}{a,b} to 1a 1b 2a 2b 
 * gl_matchc:
 *	Number of matches in the current invocation of glob.
 */

#include <sys/param.h>
#include <sys/stat.h>

#include <ctype.h>
#include <dirent.h>
#include <errno.h>
#include <glob.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define	DOLLAR		'$'
#define	DOT		'.'
#define	EOS		'\0'
#define	LBRACKET	'['
#define	NOT		'!'
#define	QUESTION	'?'
#define	QUOTE		'\\'
#define	RANGE		'-'
#define	RBRACKET	']'
#define	SEP		'/'
#define	STAR		'*'
#define	TILDE		'~'
#define	UNDERSCORE	'_'
#define	LBRACE		'{'
#define	RBRACE		'}'
#define	SLASH		'/'
#define	COMMA		','

#ifndef DEBUG

#define	M_QUOTE		0x8000
#define	M_PROTECT	0x4000
#define	M_MASK		0xffff
#define	M_ASCII		0x00ff

typedef u_short Char;

#else

#define	M_QUOTE		0x80
#define	M_PROTECT	0x40
#define	M_MASK		0xff
#define	M_ASCII		0x7f

typedef char Char;

#endif


#define	CHAR(c)		((Char)((c)&M_ASCII))
#define	META(c)		((Char)((c)|M_QUOTE))
#define	M_ALL		META('*')
#define	M_END		META(']')
#define	M_NOT		META('!')
#define	M_ONE		META('?')
#define	M_RNG		META('-')
#define	M_SET		META('[')
#define	ismeta(c)	(((c)&M_QUOTE) != 0)


static int	 compare(const void *, const void *);
static void	 g_Ctoc(const Char *, char *);
static int	 g_lstat(Char *, struct stat *, glob_t *);
static DIR	*g_opendir(Char *, glob_t *);
static Char	*g_strchr(Char *, int);
static int	 g_stat(Char *, struct stat *, glob_t *);
static int	 glob0(const Char *, glob_t *);
static int	 glob1(Char *, glob_t *);
static int	 glob2(Char *, Char *, Char *, glob_t *);
static int	 glob3(Char *, Char *, Char *, Char *, glob_t *);
static int	 globextend(const Char *, glob_t *);
static const Char *	 globtilde(const Char *, Char *, glob_t *);
static int	 globexp1(const Char *, glob_t *);
static int	 globexp2(const Char *, const Char *, glob_t *, int *);
static int	 match(Char *, Char *, Char *);

int
glob(const char *pattern, int flags, int (*errfunc)(const char *, int), glob_t *pglob)
{
	const u_char *patnext;
	int c;
	Char *bufnext, *bufend, patbuf[MAXPATHLEN+1];

	patnext = (const u_char *) pattern;
	if (!(flags & GLOB_APPEND)) {
		pglob->gl_pathc = 0;
		pglob->gl_pathv = NULL;
		if (!(flags & GLOB_DOOFFS))
			pglob->gl_offs = 0;
	}
	pglob->gl_flags = flags & ~GLOB_MAGCHAR;
	pglob->gl_errfunc = errfunc;
	pglob->gl_matchc = 0;

	bufnext = patbuf;
	bufend = bufnext + MAXPATHLEN;
	if (flags & GLOB_QUOTE) {
		/* Protect the quoted characters. */
		while (bufnext < bufend && (c = *patnext++) != EOS) 
			if (c == QUOTE) {
				if ((c = *patnext++) == EOS) {
					c = QUOTE;
					--patnext;
				}
				*bufnext++ = c | M_PROTECT;
			}
			else
				*bufnext++ = c;
	}
	else 
	    while (bufnext < bufend && (c = *patnext++) != EOS) 
		    *bufnext++ = c;
	*bufnext = EOS;

	if (flags & GLOB_BRACE)
	    return globexp1(patbuf, pglob);
	else
	    return glob0(patbuf, pglob);
}

static int globexp1(const Char *pattern, glob_t *pglob)
{
	const Char* ptr = pattern;
	int rv;

	if (pattern[0] == LBRACE && pattern[1] == RBRACE && pattern[2] == EOS)
		return glob0(pattern, pglob);

	while ((ptr = (const Char *) g_strchr((Char *) ptr, LBRACE)) != NULL)
		if (!globexp2(ptr, pattern, pglob, &rv))
			return rv;

	return glob0(pattern, pglob);
}

static int globexp2(const Char *ptr, const Char *pattern, glob_t *pglob, int *rv)
{
	int     i;
	Char   *lm, *ls;
	const Char *pe, *pm, *pl;
	Char    patbuf[MAXPATHLEN + 1];

	for (lm = patbuf, pm = pattern; pm != ptr; *lm++ = *pm++)
		continue;
	ls = lm;

	for (i = 0, pe = ++ptr; *pe; pe++)
		if (*pe == LBRACKET) {
			for (pm = pe++; *pe != RBRACKET && *pe != EOS; pe++)
				continue;
			if (*pe == EOS)
				pe = pm;
		}
		else if (*pe == LBRACE)
			i++;
		else if (*pe == RBRACE) {
			if (i == 0)
				break;
			i--;
		}

	if (i != 0 || *pe == EOS) {
		*rv = glob0(patbuf, pglob);
		return 0;
	}

	for (i = 0, pl = pm = ptr; pm <= pe; pm++)
		switch (*pm) {
		case LBRACKET:
			for (pl = pm++; *pm != RBRACKET && *pm != EOS; pm++)
				continue;
			if (*pm == EOS)
				pm = pl;
			break;
		case LBRACE:
			i++;
			break;
		case RBRACE:
			if (i) {
			    i--;
			    break;
			}
		case COMMA:
			if (i && *pm == COMMA)
				break;
			else {
				for (lm = ls; (pl < pm); *lm++ = *pl++)
					continue;
				for (pl = pe + 1; (*lm++ = *pl++) != EOS;)
					continue;
				*rv = globexp1(patbuf, pglob);
				pl = pm + 1;
			}
			break;
		default:
			break;
		}
	*rv = 0;
	return 0;
}

static const Char *
globtilde(const Char *pattern, Char *patbuf, glob_t *pglob)
{
	return pattern;
}
	
static int
glob0(const Char *pattern, glob_t *pglob)
{
	const Char *qpatnext;
	int c, err, oldpathc;
	Char *bufnext, patbuf[MAXPATHLEN+1];

	qpatnext = globtilde(pattern, patbuf, pglob);
	oldpathc = pglob->gl_pathc;
	bufnext = patbuf;

	while ((c = *qpatnext++) != EOS) {
		switch (c) {
		case LBRACKET:
			c = *qpatnext;
			if (c == NOT)
				++qpatnext;
			if (*qpatnext == EOS ||
			    g_strchr((Char *) qpatnext+1, RBRACKET) == NULL) {
				*bufnext++ = LBRACKET;
				if (c == NOT)
					--qpatnext;
				break;
			}
			*bufnext++ = M_SET;
			if (c == NOT)
				*bufnext++ = M_NOT;
			c = *qpatnext++;
			do {
				*bufnext++ = CHAR(c);
				if (*qpatnext == RANGE &&
				    (c = qpatnext[1]) != RBRACKET) {
					*bufnext++ = M_RNG;
					*bufnext++ = CHAR(c);
					qpatnext += 2;
				}
			} while ((c = *qpatnext++) != RBRACKET);
			pglob->gl_flags |= GLOB_MAGCHAR;
			*bufnext++ = M_END;
			break;
		case QUESTION:
			pglob->gl_flags |= GLOB_MAGCHAR;
			*bufnext++ = M_ONE;
			break;
		case STAR:
			pglob->gl_flags |= GLOB_MAGCHAR;
			if (bufnext == patbuf || bufnext[-1] != M_ALL)
			    *bufnext++ = M_ALL;
			break;
		default:
			*bufnext++ = CHAR(c);
			break;
		}
	}
	*bufnext = EOS;

	if ((err = glob1(patbuf, pglob)) != 0)
		return(err);

	if (pglob->gl_pathc == oldpathc && 
	    ((pglob->gl_flags & GLOB_NOCHECK) || 
	      ((pglob->gl_flags & GLOB_NOMAGIC) &&
	       !(pglob->gl_flags & GLOB_MAGCHAR))))
		return(globextend(pattern, pglob));
	else if (!(pglob->gl_flags & GLOB_NOSORT)) 
		qsort(pglob->gl_pathv + pglob->gl_offs + oldpathc,
		    pglob->gl_pathc - oldpathc, sizeof(char *), compare);
	return(0);
}

static int
compare(const void *p, const void *q)
{
	return(strcmp(*(char * const *)p, *(char * const *)q));
}

static int
glob1(Char *pattern, glob_t *pglob)
{
	Char pathbuf[MAXPATHLEN+1];

	if (*pattern == EOS)
		return(0);
	return(glob2(pathbuf, pathbuf, pattern, pglob));
}

static int
glob2(Char *pathbuf, Char *pathend, Char *pattern, glob_t *pglob)
{
	struct stat sb;
	Char *p, *q;
	int anymeta;

	for (anymeta = 0;;) {
		if (*pattern == EOS) {
			*pathend = EOS;
			if (g_lstat(pathbuf, &sb, pglob))
				return(0);
		
			if (((pglob->gl_flags & GLOB_MARK) &&
			    pathend[-1] != SEP) && (S_ISDIR(sb.st_mode)
			    || (S_ISLNK(sb.st_mode) &&
			    (g_stat(pathbuf, &sb, pglob) == 0) &&
			    S_ISDIR(sb.st_mode)))) {
				*pathend++ = SEP;
				*pathend = EOS;
			}
			++pglob->gl_matchc;
			return(globextend(pathbuf, pglob));
		}

		q = pathend;
		p = pattern;
		while (*p != EOS && *p != SEP) {
			if (ismeta(*p))
				anymeta = 1;
			*q++ = *p++;
		}

		if (!anymeta) {
			pathend = q;
			pattern = p;
			while (*pattern == SEP)
				*pathend++ = *pattern++;
		} else
			return(glob3(pathbuf, pathend, pattern, p, pglob));
	}
}

static int
glob3(Char *pathbuf, Char *pathend, Char *pattern, Char *restpattern, glob_t *pglob)
{
	struct dirent *dp;
	DIR *dirp;
	int err;
	char buf[MAXPATHLEN];

	*pathend = EOS;
	errno = 0;
	    
	if ((dirp = g_opendir(pathbuf, pglob)) == NULL) {
		if (pglob->gl_errfunc) {
			g_Ctoc(pathbuf, buf);
			if (pglob->gl_errfunc(buf, errno) ||
			    pglob->gl_flags & GLOB_ERR)
				return (GLOB_ABEND);
		}
		return(0);
	}

	err = 0;

	while ((dp = readdir(dirp))) {
		const u_char *sc;
		Char *dc;

		if (dp->d_name[0] == DOT && *pattern != DOT)
			continue;
		for (sc = (const u_char *) dp->d_name, dc = pathend; 
		     (*dc++ = *sc++) != EOS;)
			continue;
		if (!match(pathend, pattern, restpattern)) {
			*pathend = EOS;
			continue;
		}
		err = glob2(pathbuf, --dc, restpattern, pglob);
		if (err)
			break;
	}

	closedir(dirp);
	return(err);
}

static int
globextend(const Char *path, glob_t *pglob)
{
	char **pathv;
	int i;
	u_int newsize;
	char *copy;
	const Char *p;

	newsize = sizeof(*pathv) * (2 + pglob->gl_pathc + pglob->gl_offs);
	pathv = pglob->gl_pathv ? 
		    realloc((char *)pglob->gl_pathv, newsize) :
		    malloc(newsize);
	if (pathv == NULL)
		return(GLOB_NOSPACE);

	if (pglob->gl_pathv == NULL && pglob->gl_offs > 0) {
		pathv += pglob->gl_offs;
		for (i = pglob->gl_offs; --i >= 0; )
			*--pathv = NULL;
	}
	pglob->gl_pathv = pathv;

	for (p = path; *p++;)
		continue;
	if ((copy = malloc(p - path)) != NULL) {
		g_Ctoc(path, copy);
		pathv[pglob->gl_offs + pglob->gl_pathc++] = copy;
	}
	pathv[pglob->gl_offs + pglob->gl_pathc] = NULL;
	return(copy == NULL ? GLOB_NOSPACE : 0);
}

static int
match(Char *name, Char *pat, Char *patend)
{
	int ok, negate_range;
	Char c, k;

	while (pat < patend) {
		c = *pat++;
		switch (c & M_MASK) {
		case M_ALL:
			if (pat == patend)
				return(1);
			do 
			    if (match(name, pat, patend))
				    return(1);
			while (*name++ != EOS);
			return(0);
		case M_ONE:
			if (*name++ == EOS)
				return(0);
			break;
		case M_SET:
			ok = 0;
			if ((k = *name++) == EOS)
				return(0);
			if ((negate_range = ((*pat & M_MASK) == M_NOT)) != EOS)
				++pat;
			while (((c = *pat++) & M_MASK) != M_END)
				if ((*pat & M_MASK) == M_RNG) {
					if (c <= k && k <= pat[1])
						ok = 1;
					pat += 2;
				} else if (c == k)
					ok = 1;
			if (ok == negate_range)
				return(0);
			break;
		default:
			if (*name++ != c)
				return(0);
			break;
		}
	}
	return(*name == EOS);
}

void
globfree(glob_t *pglob)
{
	int i;
	char **pp;

	if (pglob->gl_pathv != NULL) {
		pp = pglob->gl_pathv + pglob->gl_offs;
		for (i = pglob->gl_pathc; i--; ++pp)
			if (*pp)
				free(*pp);
		free(pglob->gl_pathv);
	}
}

static DIR *
g_opendir(Char *str, glob_t *pglob)
{
	char buf[MAXPATHLEN];

	if (!*str)
		strcpy(buf, ".");
	else
		g_Ctoc(str, buf);

	if (pglob->gl_flags & GLOB_ALTDIRFUNC)
		return((*pglob->gl_opendir)(buf));

	return(opendir(buf));
}

static int
g_lstat(Char *fn, struct stat *sb, glob_t *pglob)
{
	char buf[MAXPATHLEN];

	g_Ctoc(fn, buf);
	if (pglob->gl_flags & GLOB_ALTDIRFUNC)
		return((*pglob->gl_lstat)(buf, sb));
	return(lstat(buf, sb));
}

static int
g_stat(Char *fn, struct stat *sb, glob_t *pglob)
{
	char buf[MAXPATHLEN];

	g_Ctoc(fn, buf);
	if (pglob->gl_flags & GLOB_ALTDIRFUNC)
		return((*pglob->gl_stat)(buf, sb));
	return(stat(buf, sb));
}

static Char *
g_strchr(Char *str, int ch)
{
	do {
		if (*str == ch)
			return (str);
	} while (*str++);
	return (NULL);
}

static void
g_Ctoc(const Char *str, char *buf)
{
	char *dc;

	for (dc = buf; (*dc++ = *str++) != EOS;)
		continue;
}
