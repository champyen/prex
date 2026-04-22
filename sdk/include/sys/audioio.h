/*
 * Copyright (c) 2026, Champ Yen (champ.yen@gmail.com)
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

#ifndef _SYS_AUDIOIO_H_
#define _SYS_AUDIOIO_H_

#include <sys/types.h>
#include <sys/ioctl.h>

/*
 * Audio encoding types - Expanded to include signed/unsigned and endianness
 */
#define AUDIO_ENCODING_NONE             0
#define AUDIO_ENCODING_ULAW             1
#define AUDIO_ENCODING_ALAW             2
#define AUDIO_ENCODING_PCM_S8           3
#define AUDIO_ENCODING_PCM_U8           4
#define AUDIO_ENCODING_PCM_S16_LE       5
#define AUDIO_ENCODING_PCM_S16_BE       6
#define AUDIO_ENCODING_PCM_U16_LE       7
#define AUDIO_ENCODING_PCM_U16_BE       8

/* Alias for compatibility */
#define AUDIO_ENCODING_LINEAR           AUDIO_ENCODING_PCM_S16_LE

/*
 * Sampling Rates Macros (Bitmask for capabilities)
 */
#define AUDIO_SAMP_RATE_8K              0x0001
#define AUDIO_SAMP_RATE_11K             0x0002
#define AUDIO_SAMP_RATE_12K             0x0004
#define AUDIO_SAMP_RATE_16K             0x0008
#define AUDIO_SAMP_RATE_22K             0x0010
#define AUDIO_SAMP_RATE_24K             0x0020
#define AUDIO_SAMP_RATE_32K             0x0040
#define AUDIO_SAMP_RATE_44K             0x0080
#define AUDIO_SAMP_RATE_48K             0x0100
#define AUDIO_SAMP_RATE_96K             0x0200

/*
 * Audio Feature Controls (NuttX style)
 */
#define AUDIO_FU_MUTE                   0x0001
#define AUDIO_FU_VOLUME                 0x0002
#define AUDIO_FU_BASS                   0x0004
#define AUDIO_FU_TREBLE                 0x0008
#define AUDIO_FU_BALANCE                0x0010

/*
 * Audio state structure for play or record
 */
struct audio_prinfo {
    u_int   sample_rate;    /* predefined sampling rate (AUDIO_SAMP_RATE_xxx) */
    u_int   channels;       /* number of channels (1 or 2) */
    u_int   encoding;       /* encoding type */
    u_int   gain;           /* volume (0-255) */
    u_int   port;           /* selected I/O port */
    u_long  seek;           /* current byte offset in stream */
    u_int   samples;        /* total samples processed */
    u_int   eof;            /* EOF count */
    u_char  pause;          /* non-zero to pause the stream */
    u_char  error;          /* non-zero if an underrun/overrun occurred */
    u_char  waiting;        /* non-zero if a process is waiting for I/O */
    u_char  open;           /* non-zero if the stream is open */
    u_char  active;         /* non-zero if hardware is actively moving data */
};

/*
 * Top-level audio state structure
 */
struct audio_info {
    struct  audio_prinfo play;   /* Playback state */
    struct  audio_prinfo record; /* Recording state */
    u_int   monitor_gain;        /* Input to output loopback gain */
    u_int   blocksize;           /* Preferred I/O block size */
    u_int   hiwat;               /* High water mark */
    u_int   lowat;               /* Low water mark */
    u_int   backlog;             /* Samples of output backlog to generate */
};

/*
 * IOCTLs for /dev/audio and /dev/sound
 */
#define AUDIO_GETINFO   _IOR('A', 1, struct audio_info)
#define AUDIO_SETINFO   _IOWR('A', 2, struct audio_info)
#define AUDIO_DRAIN     _IO('A', 3)
#define AUDIO_FLUSH     _IO('A', 4)

/*
 * Playback/record modes
 */
#define AUMODE_PLAY     0x0001
#define AUMODE_RECORD   0x0002

#define AUDIO_INITINFO(p) \
    do { \
        memset((p), 0xff, sizeof(struct audio_info)); \
    } while (0)

#endif /* !_SYS_AUDIOIO_H_ */
