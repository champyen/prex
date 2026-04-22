/*
 * Copyright (c) 2026, Champ Yen (champ.yen@gmail.com)
 * All rights reserved.
 *
 * This is an original implementation inspired by the OpenBSD sndio project.
 *
 * Implementation of sndio-style IPC for Prex+
 */

#ifndef _IPC_SNDIO_H
#define _IPC_SNDIO_H

#include <sys/types.h>
#include <ipc/ipc.h>
#include <sys/audioio.h>

/*
 * Messages for sndio object
 */
#define SNDIO_OPEN        0x00000300
#define SNDIO_CLOSE       0x00000301
#define SNDIO_SET_PARAMS  0x00000302
#define SNDIO_GET_PARAMS  0x00000303
#define SNDIO_ALLOC_BUFS  0x00000304
#define SNDIO_FREE_BUFS   0x00000305
#define SNDIO_START       0x00000306
#define SNDIO_STOP        0x00000307
#define SNDIO_QUEUE_BUF   0x00000308
#define SNDIO_BUF_READY   0x00000309 /* Callback from server to client */

/*
 * Buffer states
 */
#define SNDIO_BUF_READY_STATE   0
#define SNDIO_BUF_QUEUED_STATE  1
#define SNDIO_BUF_BUSY_STATE    2

/*
 * Buffer info
 */
struct sndio_buf_info {
    int id;
    void *addr;     /* Shared memory address in client space */
    size_t size;
    int state;
};

/*
 * Open message
 */
struct sndio_open_msg {
    struct msg_header hdr;
    int mode;       /* AUMODE_PLAY, AUMODE_RECORD */
};

/*
 * Parameter message
 */
struct sndio_params_msg {
    struct msg_header hdr;
    struct audio_info info;
};

/*
 * Buffer allocation message
 */
struct sndio_buf_msg {
    struct msg_header hdr;
    int count;      /* Number of buffers */
    size_t size;    /* Size of each buffer */
    void *shm_addr; /* Base address of shared memory in client space */
};

/*
 * Queue message
 */
struct sndio_queue_msg {
    struct msg_header hdr;
    int buf_id;     /* ID of the buffer to queue */
};

/* Max size of sndio message */
#define MAX_SNDIOMSG sizeof(struct sndio_params_msg)

#endif /* !_IPC_SNDIO_H */
