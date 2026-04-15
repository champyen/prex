#include <sys/prex.h>
#include <ipc/sndio.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include "helix_mp3.h"

#define SNDIO_BUFFER_SIZE 16384
#define MAX_BUFFERS 2

static uint32_t rate_to_mask(uint32_t rate) {
    if (rate == 44100) return AUDIO_SAMP_RATE_44K;
    if (rate == 22050) return AUDIO_SAMP_RATE_22K;
    if (rate == 11025) return AUDIO_SAMP_RATE_11K;
    if (rate == 48000) return AUDIO_SAMP_RATE_48K;
    if (rate == 32000) return AUDIO_SAMP_RATE_32K;
    return AUDIO_SAMP_RATE_44K;
}

static int play_mp3(const char *path) {
    helix_mp3_t mp3;
    int err = helix_mp3_init_file(&mp3, path);
    if (err) {
        printf("Failed to init decoder for file '%s', error: %d\n", path, err);
        return err;
    }

    uint32_t sample_rate = helix_mp3_get_sample_rate(&mp3);
    uint32_t bitrate = helix_mp3_get_bitrate(&mp3);
    printf("MP3: %d Hz, %d kbps\n", sample_rate, bitrate / 1000);

    object_t sndio_obj;
    object_t cb_obj;
    char cb_name[32];
    int error;

    /* Sndio Setup */
    sprintf(cb_name, "scb_%x", (int)task_self());
    error = object_create(cb_name, &cb_obj);
    if (error == EEXIST) error = object_lookup(cb_name, &cb_obj);
    if (error) {
        printf("Error creating callback object: %d\n", error);
        helix_mp3_deinit(&mp3);
        return 1;
    }

    /* Wait for server */
    for (int i = 0; i < 100; i++) {
        error = object_lookup("!sndio", &sndio_obj);
        if (error == 0) break;
        timer_sleep(10, 0);
    }
    if (error) {
        printf("helixmp3: Error looking up !sndio: %d\n", error);
        helix_mp3_deinit(&mp3);
        return 1;
    }

    struct sndio_open_msg open_msg;
    open_msg.hdr.code = SNDIO_OPEN;
    open_msg.mode = AUMODE_PLAY;
    msg_send(sndio_obj, &open_msg, sizeof(open_msg));
    if (open_msg.hdr.status != 0) {
        printf("Error opening sndio: %d\n", open_msg.hdr.status);
        helix_mp3_deinit(&mp3);
        return 1;
    }

    struct sndio_params_msg params_msg;
    params_msg.hdr.code = SNDIO_SET_PARAMS;
    AUDIO_INITINFO(&params_msg.info);
    params_msg.info.play.sample_rate = rate_to_mask(sample_rate);
    params_msg.info.play.channels = 2; // Helix always outputs 2 channels
    params_msg.info.play.encoding = AUDIO_ENCODING_PCM_S16_LE;
    msg_send(sndio_obj, &params_msg, sizeof(params_msg));

    void *shm_addr;
    error = vm_allocate(task_self(), &shm_addr, SNDIO_BUFFER_SIZE * MAX_BUFFERS, 1);
    if (error) {
        printf("Failed to allocate shared memory\n");
        helix_mp3_deinit(&mp3);
        return 1;
    }

    struct sndio_buf_msg buf_msg;
    buf_msg.hdr.code = SNDIO_ALLOC_BUFS;
    buf_msg.count = MAX_BUFFERS;
    buf_msg.size = SNDIO_BUFFER_SIZE;
    buf_msg.shm_addr = shm_addr;
    msg_send(sndio_obj, &buf_msg, sizeof(buf_msg));
    if (buf_msg.count < MAX_BUFFERS) {
        printf("Failed to map buffers in server\n");
        vm_free(task_self(), shm_addr);
        helix_mp3_deinit(&mp3);
        return 1;
    }

    uint8_t *shm_base = (uint8_t *)shm_addr;
    struct sndio_queue_msg q_msg;
    q_msg.hdr.code = SNDIO_QUEUE_BUF;

    /* Initial queueing */
    for (int b = 0; b < MAX_BUFFERS; b++) {
        int16_t *target = (int16_t *)(shm_base + b * SNDIO_BUFFER_SIZE);
        size_t frames_to_read = SNDIO_BUFFER_SIZE / (2 * sizeof(int16_t));
        size_t read = helix_mp3_read_pcm_frames_s16(&mp3, target, frames_to_read);
        if (read == 0) break;
        if (read < frames_to_read) {
            memset(target + read * 2, 0, (frames_to_read - read) * 2 * sizeof(int16_t));
        }
        q_msg.buf_id = b;
        msg_send(sndio_obj, &q_msg, sizeof(q_msg));
        if (read < frames_to_read) break;
    }

    struct msg start_msg;
    start_msg.hdr.code = SNDIO_START;
    msg_send(sndio_obj, &start_msg, sizeof(start_msg));

    while (1) {
        struct msg notification;
        error = msg_receive(cb_obj, &notification, sizeof(notification));
        if (error) break;
        msg_reply(cb_obj, &notification, sizeof(notification));

        if (notification.hdr.code == SNDIO_BUF_READY) {
            int id = notification.data[0];
            int16_t *target = (int16_t *)(shm_base + id * SNDIO_BUFFER_SIZE);
            size_t frames_to_read = SNDIO_BUFFER_SIZE / (2 * sizeof(int16_t));
            size_t read = helix_mp3_read_pcm_frames_s16(&mp3, target, frames_to_read);
            if (read == 0) break;
            if (read < frames_to_read) {
                memset(target + read * 2, 0, (frames_to_read - read) * 2 * sizeof(int16_t));
            }

            q_msg.buf_id = id;
            msg_send(sndio_obj, &q_msg, sizeof(q_msg));
            if (read < frames_to_read) break;
        }
    }

    printf("helixmp3: Done.\n");
    helix_mp3_deinit(&mp3);
    vm_free(task_self(), shm_addr);
    return 0;
}

static int decode_mp3(const char *in_path, const char *out_path) {
    helix_mp3_t mp3;
    int err = helix_mp3_init_file(&mp3, in_path);
    if (err) {
        printf("Failed to init decoder for file '%s', error: %d\n", in_path, err);
        return err;
    }

    int16_t *pcm_buffer = malloc(1152 * 2 * sizeof(int16_t));
    if (!pcm_buffer) {
        printf("Failed to allocate pcm_buffer\n");
        helix_mp3_deinit(&mp3);
        return 1;
    }

        printf("Decoding '%s' to '%s'...\n", in_path, out_path);
        FILE *out_fp = fopen(out_path, "wb");
        if (!out_fp) {
            perror("fopen output");
            free(pcm_buffer);
            helix_mp3_deinit(&mp3);
            return 1;
        }

        while (1) {
            size_t read = helix_mp3_read_pcm_frames_s16(&mp3, pcm_buffer, 1152);
            if (read == 0) break;
            fwrite(pcm_buffer, sizeof(int16_t), read * 2, out_fp);
        }
        printf("Decoding finished.\n");
        fclose(out_fp);

    free(pcm_buffer);
    helix_mp3_deinit(&mp3);
    return 0;
}

int main(int argc, char *argv[]) {
    if (argc < 2) {
        printf("Usage: %s <input.mp3> [output.pcm]\n", argv[0]);
        return 1;
    }

    if (argc == 3) {
        printf("helixmp3: Decoding %s to %s\n", argv[1], argv[2]);
        return decode_mp3(argv[1], argv[2]);
    } else {
        return play_mp3(argv[1]);
    }
}
