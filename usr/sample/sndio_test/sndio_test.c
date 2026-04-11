/*
 * Copyright (c) 2026, Champ Yen (champ.yen@gmail.com)
 * All rights reserved.
 *
 * This is an original implementation inspired by the OpenBSD sndio project.
 *
 * Test client for sndiod
 */

#include <sys/prex.h>
#include <ipc/sndio.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <errno.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

#define SAMPLE_RATE 44100
#define CHANNELS 2
#define BUFFER_SIZE 16384 /* Must match server MIX_BUFFER_SIZE for now */

#ifdef DEBUG_SNDIO_TEST
#define DPRINTF(a) printf a
#else
#define DPRINTF(a)
#endif

static void fill_buffer(int16_t *buf, int count, int *phase)
{
    int i;
    for (i = 0; i < count / 2; i += 2) {
        int16_t val = (int16_t)(10000 * sin(2 * M_PI * 440 * (*phase) / SAMPLE_RATE));
        buf[i] = val;     /* Left */
        buf[i + 1] = val; /* Right */
        (*phase)++;
    }
}

int main(int argc, char *argv[])
{
    object_t sndio_obj;
    object_t cb_obj;
    char cb_name[32];
    int error;
    int phase = 0;

    DPRINTF(("sndio_test: Starting...\n"));

    /* Create callback object */
    sprintf(cb_name, "scb_%x", (int)task_self());
    error = object_create(cb_name, &cb_obj);
    if (error == EEXIST) {
        error = object_lookup(cb_name, &cb_obj);
    }
    if (error) {
        printf("sndio_test: Error creating/looking up callback object: %d\n", error);
        return 1;
    }

    /* Find sndiod object */
    error = object_lookup("!sndio", &sndio_obj);
    if (error) {
        printf("sndio_test: Error looking up !sndio: %d\n", error);
        return 1;
    }

    /* Open sndio */
    struct sndio_open_msg open_msg;
    open_msg.hdr.code = SNDIO_OPEN;
    open_msg.mode = AUMODE_PLAY;
    msg_send(sndio_obj, &open_msg, sizeof(open_msg));
    if (open_msg.hdr.status != 0) {
        printf("sndio_test: Error opening sndio: %d\n", open_msg.hdr.status);
        return 1;
    }

    /* Set params */
    struct sndio_params_msg params_msg;
    params_msg.hdr.code = SNDIO_SET_PARAMS;
    AUDIO_INITINFO(&params_msg.info);
    params_msg.info.play.sample_rate = AUDIO_SAMP_RATE_44K;
    params_msg.info.play.channels = CHANNELS;
    params_msg.info.play.encoding = AUDIO_ENCODING_PCM_S16_LE;
    msg_send(sndio_obj, &params_msg, sizeof(params_msg));

    /* Allocate shared memory */
    void *shm_addr;
    error = vm_allocate(task_self(), &shm_addr, BUFFER_SIZE * 2, 1);
    if (error) {
        printf("sndio_test: Failed to allocate shared memory\n");
        return 1;
    }

    /* Set up buffers */
    struct sndio_buf_msg buf_msg;
    buf_msg.hdr.code = SNDIO_ALLOC_BUFS;
    buf_msg.count = 2;
    buf_msg.size = BUFFER_SIZE;
    buf_msg.shm_addr = shm_addr;
    msg_send(sndio_obj, &buf_msg, sizeof(buf_msg));
    if (buf_msg.count < 2) {
        printf("sndio_test: Failed to map 2 buffers in server\n");
        return 1;
    }

    int16_t *shm_base = (int16_t *)shm_addr;
    int16_t *buf0 = shm_base;
    int16_t *buf1 = (int16_t *)((uint8_t *)shm_base + BUFFER_SIZE);

    DPRINTF(("sndio_test: Allocated buffers at %p and %p\n", buf0, buf1));

    /* Start playback */
    struct msg msg;
    msg.hdr.code = SNDIO_START;
    msg_send(sndio_obj, &msg, sizeof(msg));

    /* Initial queueing */
    fill_buffer(buf0, BUFFER_SIZE, &phase);
    struct sndio_queue_msg q_msg;
    q_msg.hdr.code = SNDIO_QUEUE_BUF;
    q_msg.buf_id = 0;
    msg_send(sndio_obj, &q_msg, sizeof(q_msg));

    fill_buffer(buf1, BUFFER_SIZE, &phase);
    q_msg.buf_id = 1;
    msg_send(sndio_obj, &q_msg, sizeof(q_msg));

    DPRINTF(("sndio_test: Playing tone (10 seconds)...\n"));
    int loops = (SAMPLE_RATE * 10) / (BUFFER_SIZE / 4);
    while (loops-- > 0) {
        struct msg notification;
        error = msg_receive(cb_obj, &notification, sizeof(notification));
        if (error) {
            printf("sndio_test: msg_receive error %d\n", error);
            break;
        }
        msg_reply(cb_obj, &notification, sizeof(notification));

        if (notification.hdr.code == SNDIO_BUF_READY) {
            int id = notification.data[0];
            int16_t *target = (id == 0) ? buf0 : buf1;
            fill_buffer(target, BUFFER_SIZE, &phase);

            q_msg.buf_id = id;
            error = msg_send(sndio_obj, &q_msg, sizeof(q_msg));
            if (error) {
                printf("sndio_test: msg_send error %d\n", error);
                break;
            }
        }
        if (loops % 10 == 0) {
            DPRINTF(("sndio_test: loops left %d\n", loops));
        }
    }
    /* Stop playback */
    msg.hdr.code = SNDIO_STOP;
    msg_send(sndio_obj, &msg, sizeof(msg));

    /* Close */
    msg.hdr.code = SNDIO_CLOSE;
    msg_send(sndio_obj, &msg, sizeof(msg));

    vm_free(task_self(), shm_addr);

    DPRINTF(("sndio_test: Done.\n"));
    return 0;
}
