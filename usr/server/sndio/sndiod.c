/*
 * Copyright (c) 2026, Champ Yen (champ.yen@gmail.com)
 * All rights reserved.
 *
 * This is an original implementation inspired by the OpenBSD sndio project.
 *
 * Implementation of sndio server for Prex+
 */

#include <sys/prex.h>
#include <sys/audioio.h>
#include <ipc/sndio.h>
#include <ipc/exec.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>

#define MAX_CLIENTS 8
#define MAX_BUFFERS_PER_CLIENT 4
#define MIX_BUFFER_SIZE 16384

#ifdef DEBUG_SNDIOD
#define DPRINTF(a) dprintf a
#else
#define DPRINTF(a)
#endif

struct client {
    task_t task;
    object_t cb_obj;
    int active;
    int playing;
    struct audio_info info;
    struct sndio_buf_info bufs[MAX_BUFFERS_PER_CLIENT];
    int num_bufs;
    void *shm_base;
};

static struct client clients[MAX_CLIENTS];
static mutex_t client_mutex = MUTEX_INITIALIZER;
static cond_t mix_cond = COND_INITIALIZER;
static object_t sndio_obj;
static device_t sound_dev;

static int16_t mix_buffer[MIX_BUFFER_SIZE / 2];

/*
 * Wait until specified server starts.
 */
static void wait_server(const char* name, object_t* pobj)
{
    int i, error = 0;

    /* Give chance to run other servers. */
    thread_yield();

    /*
     * Wait for server loading. timeout is 1 sec.
     */
    for (i = 0; i < 100; i++) {
        error = object_lookup(name, pobj);
        if (error == 0)
            break;

        /* Wait 10msec */
        timer_sleep(10, 0);
        thread_yield();
    }
    if (error) {
        DPRINTF(("sndiod: server %s not found\n", name));
        sys_panic("sndiod: server not found");
    }
}

/*
 * Mixing thread: Sums client buffers and writes to hardware
 */
static void mixing_thread(void)
{
    size_t size;
    int i, b, s, error;
    int16_t *src;
    int active_play;

    DPRINTF(("sndiod: Mixing thread started\n"));

    while (1) {
        mutex_lock(&client_mutex);
        
        /* Clear mix buffer */
        memset(mix_buffer, 0, sizeof(mix_buffer));
        active_play = 0;

        /* Mix active clients */
        for (i = 0; i < MAX_CLIENTS; i++) {
            if (!clients[i].active || !clients[i].playing)
                continue;

            for (b = 0; b < clients[i].num_bufs; b++) {
                if (clients[i].bufs[b].state == SNDIO_BUF_QUEUED_STATE) {
                    clients[i].bufs[b].state = SNDIO_BUF_BUSY_STATE;
                    src = (int16_t *)clients[i].bufs[b].addr;
                    
                    /* Simple linear mixing (addition) */
                    for (s = 0; s < (MIX_BUFFER_SIZE / 2); s++) {
                        int32_t mixed = (int32_t)mix_buffer[s] + (int32_t)src[s];
                        /* Clipping */
                        if (mixed > 32767) mixed = 32767;
                        if (mixed < -32768) mixed = -32768;
                        mix_buffer[s] = (int16_t)mixed;
                    }
                    active_play = 1;
                    break; 
                }
            }
        }

        if (!active_play) {
            /* If nothing to play, wait for a client to queue a buffer */
            cond_wait(&mix_cond, &client_mutex);
            mutex_unlock(&client_mutex);
            continue;
        }
        mutex_unlock(&client_mutex);

        /* Write to hardware (blocks if driver is working) */
        size = MIX_BUFFER_SIZE;
        error = device_write(sound_dev, mix_buffer, &size, 0);

        /* Post-playback: Release buffers back to clients */
        mutex_lock(&client_mutex);
        for (i = 0; i < MAX_CLIENTS; i++) {
            if (!clients[i].active)
                continue;

            for (b = 0; b < clients[i].num_bufs; b++) {
                if (clients[i].bufs[b].state == SNDIO_BUF_BUSY_STATE) {
                    clients[i].bufs[b].state = SNDIO_BUF_READY_STATE;
                    
                    /* Notify client that buffer is ready */
                    if (clients[i].cb_obj != 0) {
                        struct msg notification;
                        object_t cb_obj = clients[i].cb_obj;
                        notification.hdr.code = SNDIO_BUF_READY;
                        notification.data[0] = clients[i].bufs[b].id;
                        
                        /* 
                         * CRITICAL: Unlock mutex before msg_send to avoid deadlock
                         * with client blocked on msg_send to us.
                         */
                        mutex_unlock(&client_mutex);
                        msg_send(cb_obj, &notification, sizeof(notification));
                        mutex_lock(&client_mutex);
                    }
                }
            }
        }
        mutex_unlock(&client_mutex);
    }
}

/*
 * Control thread: Handles IPC requests from clients
 */
static void control_thread(void)
{
    uint8_t msg_buf[MAX_SNDIOMSG];
    struct msg_header *hdr = (struct msg_header *)msg_buf;
    int error;
    int i, b;
    task_t client_task;

    DPRINTF(("sndiod: Control thread started\n"));

    while (1) {
        error = msg_receive(sndio_obj, msg_buf, MAX_SNDIOMSG);
        if (error)
            continue;

        client_task = hdr->task;
        mutex_lock(&client_mutex);

        switch (hdr->code) {
        case SNDIO_OPEN: {
            int found = -1;
            char cb_name[32];
            for (i = 0; i < MAX_CLIENTS; i++) {
                if (!clients[i].active) {
                    found = i;
                    break;
                }
            }
            if (found != -1) {
                clients[found].active = 1;
                clients[found].task = client_task;
                clients[found].playing = 0;
                clients[found].num_bufs = 0;
                clients[found].shm_base = NULL;
                
                /* Look up client callback object */
                sprintf(cb_name, "scb_%x", (int)client_task);
                if (object_lookup(cb_name, &clients[found].cb_obj) != 0) {
                    clients[found].cb_obj = 0;
                }
                
                hdr->status = 0;
            } else {
                hdr->status = ENOMEM;
            }
            break;
        }

        case SNDIO_CLOSE:
            for (i = 0; i < MAX_CLIENTS; i++) {
                if (clients[i].active && clients[i].task == client_task) {
                    clients[i].active = 0;
                    /* Free buffers if any */
                    if (clients[i].shm_base) {
                        vm_free(task_self(), clients[i].shm_base);
                        clients[i].shm_base = NULL;
                    }
                    break;
                }
            }
            hdr->status = 0;
            break;

        case SNDIO_SET_PARAMS: {
            struct sndio_params_msg *m = (struct sndio_params_msg *)msg_buf;
            for (i = 0; i < MAX_CLIENTS; i++) {
                if (clients[i].active && clients[i].task == client_task) {
                    clients[i].info = m->info;
                    break;
                }
            }
            hdr->status = 0;
            break;
        }

        case SNDIO_ALLOC_BUFS: {
            struct sndio_buf_msg *m = (struct sndio_buf_msg *)msg_buf;
            for (i = 0; i < MAX_CLIENTS; i++) {
                if (clients[i].active && clients[i].task == client_task) {
                    int count = m->count;
                    if (count > MAX_BUFFERS_PER_CLIENT) count = MAX_BUFFERS_PER_CLIENT;
                    
                    void *server_addr;
                    int err;
                    err = vm_map(client_task, m->shm_addr, m->size * count, &server_addr);
                    if (err == 0) {
                        clients[i].shm_base = server_addr;
                        for (b = 0; b < count; b++) {
                            clients[i].bufs[b].id = b;
                            clients[i].bufs[b].addr = (void*)((uint8_t*)server_addr + b * m->size);
                            clients[i].bufs[b].size = m->size;
                            clients[i].bufs[b].state = SNDIO_BUF_READY_STATE;
                        }
                        clients[i].num_bufs = count;
                        m->count = count;
                    } else {
                        DPRINTF(("sndiod: vm_map failed with error %d\n", err));
                        m->count = 0;
                    }
                    break;
                }
            }
            hdr->status = 0;
            break;
        }

        case SNDIO_START:
            for (i = 0; i < MAX_CLIENTS; i++) {
                if (clients[i].active && clients[i].task == client_task) {
                    clients[i].playing = 1;
                    DPRINTF(("sndiod: Starting playback for client %x\n", (int)client_task));
                    cond_signal(&mix_cond);
                    break;
                }
            }
            hdr->status = 0;
            break;

        case SNDIO_STOP:
            for (i = 0; i < MAX_CLIENTS; i++) {
                if (clients[i].active && clients[i].task == client_task) {
                    clients[i].playing = 0;
                    DPRINTF(("sndiod: Stopping playback for client %x\n", (int)client_task));
                    break;
                }
            }
            hdr->status = 0;
            break;

        case SNDIO_QUEUE_BUF: {
            struct sndio_queue_msg *m = (struct sndio_queue_msg *)msg_buf;
            for (i = 0; i < MAX_CLIENTS; i++) {
                if (clients[i].active && clients[i].task == client_task) {
                    int id = m->buf_id;
                    if (id >= 0 && id < clients[i].num_bufs) {
                        clients[i].bufs[id].state = SNDIO_BUF_QUEUED_STATE;
                        DPRINTF(("sndiod: Queued buffer %d for client %x\n", id, (int)client_task));
                        cond_signal(&mix_cond);
                    }
                    break;
                }
            }
            hdr->status = 0;
            break;
        }

        default:
            hdr->status = EINVAL;
            break;
        }

        mutex_unlock(&client_mutex);
        msg_reply(sndio_obj, msg_buf, MAX_SNDIOMSG);
    }
}

static char mix_stack[8192];

int main(int argc, char *argv[])
{
    thread_t t;
    int error;
    object_t execobj;
    struct bind_msg bm;

    DPRINTF(("sndiod: Starting...\n"));

    /*
     * Wait for exec server and request capability binding
     */
    wait_server("!exec", &execobj);

    bm.hdr.code = EXEC_BINDCAP;
    strlcpy(bm.path, "/boot/sndiod", sizeof(bm.path));
    msg_send(execobj, &bm, sizeof(bm));

    /* Open audio device */
    error = device_open("audio", DO_WRONLY, &sound_dev);
    if (error) {
        sys_panic("sndiod: Error opening /dev/audio");
    }

    /* Create sndio object */
    error = object_create("!sndio", &sndio_obj);
    if (error) {
        sys_panic("sndiod: Error creating !sndio object");
    }

    /* Start mixing thread */
    error = thread_create(task_self(), &t);
    if (error) return 1;
    thread_load(t, mixing_thread, mix_stack + 8192);
    thread_setpri(t, 100); /* Standard priority */
    thread_resume(t);

    /* Run control thread in main */
    control_thread();

    return 0;
}
