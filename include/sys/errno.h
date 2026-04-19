/*
 * Copyright (c) 1982, 1986, 1989, 1993
 *	The Regents of the University of California.  All rights reserved.
 * (c) UNIX System Laboratories, Inc.
 * All or some portions of this file are derived from material licensed
 * to the University of California by American Telephone and Telegraph
 * Co. or Unix System Laboratories, Inc. and are reproduced herein with
 * the permission of UNIX System Laboratories, Inc.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 3. Neither the name of the University nor the names of its contributors
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
 *
 *	@(#)errno.h	8.5 (Berkeley) 1/21/94
 */

#ifndef _SYS_ERRNO_H_
#define _SYS_ERRNO_H_

#define EPERM 1    /* Operation not permitted */
#define ENOENT 2   /* No such file or directory */
#define ESRCH 3    /* No such process */
#define EINTR 4    /* Interrupted system call */
#define EIO 5      /* Input/output error */
#define ENXIO 6    /* Device not configured */
#define E2BIG 7    /* Argument list too long */
#define ENOEXEC 8  /* Exec format error */
#define EBADF 9    /* Bad file descriptor */
#define ECHILD 10  /* No child processes */
#define EDEADLK 11 /* Resource deadlock avoided */
/* 11 was EAGAIN */
#define ENOMEM 12  /* Cannot allocate memory */
#define EACCES 13  /* Permission denied */
#define EFAULT 14  /* Bad address */
#define ENOTBLK 15 /* Block device required */
#define EBUSY 16   /* Device busy */
#define EEXIST 17  /* File exists */
#define EXDEV 18   /* Cross-device link */
#define ENODEV 19  /* Operation not supported by device */
#define ENOTDIR 20 /* Not a directory */
#define EISDIR 21  /* Is a directory */
#define EINVAL 22  /* Invalid argument */
#define ENFILE 23  /* Too many open files in system */
#define EMFILE 24  /* Too many open files */
#define ENOTTY 25  /* Inappropriate ioctl for device */
#define ETXTBSY 26 /* Text file busy */
#define EFBIG 27   /* File too large */
#define ENOSPC 28  /* No space left on device */
#define ESPIPE 29  /* Illegal seek */
#define EROFS 30   /* Read-only file system */
#define EMLINK 31  /* Too many links */
#define EPIPE 32   /* Broken pipe */

/* math software */
#define EDOM 33   /* Numerical argument out of domain */
#define ERANGE 34 /* Result too large */

/* non-blocking and interrupt i/o */
#define EAGAIN 35          /* Resource temporarily unavailable */
#define EWOULDBLOCK EAGAIN /* Operation would block */

#define ETIMEDOUT 36    /* Operation timed out */
#define ENAMETOOLONG 37 /* File name too long */
#define ENOTEMPTY 38    /* Directory not empty */

/* quotas & mush */
#define EPROCLIM 39 /* Too many processes */
#define ENOSYS 40   /* Function not implemented */

#endif /* !_SYS_ERRNO_H_ */

/* Networking errnos */
#define EADDRINUSE      48
#define EADDRNOTAVAIL   49
#define ENETDOWN        50
#define ENETUNREACH     51
#define ENETRESET       52
#define ECONNABORTED    53
#define ECONNRESET      54
#define ENOBUFS         55
#define EISCONN         56
#define ENOTCONN        57
#define ESHUTDOWN       58
#define ETOOMANYREFS    59
#define ECONNREFUSED    61
#define ELOOP           62
#define EHOSTDOWN       64
#define EHOSTUNREACH    65
#define EUSERS          68
#define EDQUOT          69
#define ESTALE          70
#define EREMOTE         71
#define EBADRPC         72
#define ERPCMISMATCH    73
#define EPROGUNAVAIL    74
#define EPROGMISMATCH   75
#define EPROCUNAVAIL    76
#define ENOLCK          77
#define EFTYPE          79
#define EAUTH           80
#define ENEEDAUTH       81
#define EINPROGRESS     82
#define EALREADY        83
#define EMSGSIZE        84
#define ENOPROTOOPT     85
#define EAFNOSUPPORT    86
#define EOPNOTSUPP      87
