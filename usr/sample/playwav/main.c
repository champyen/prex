/*
 * WAV Player for Prex+ using sndio
 */

#include <sys/prex.h>
#include <ipc/sndio.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>

#define BUFFER_SIZE 16384
#define MAX_BUFFERS 2

struct wav_header {

    char     riff_id[4];
    uint32_t riff_sz;
    char     wave_id[4];
    char     fmt_id[4];
    uint32_t fmt_sz;
    uint16_t audio_fmt;
    uint16_t num_chans;
    uint32_t sample_rate;
    uint32_t byte_rate;
    uint16_t block_align;
    uint16_t bits_per_samp;
    char     data_id[4];
    uint32_t data_sz;
};

static uint32_t rate_to_mask(uint32_t rate) {
    if (rate == 44100) return AUDIO_SAMP_RATE_44K;
    if (rate == 22050) return AUDIO_SAMP_RATE_22K;
    if (rate == 11025) return AUDIO_SAMP_RATE_11K;
    if (rate == 48000) return AUDIO_SAMP_RATE_48K;
    if (rate == 32000) return AUDIO_SAMP_RATE_32K;
    return AUDIO_SAMP_RATE_44K;
}

int main(int argc, char *argv[])
{
    if (argc < 2) {
        printf("Usage: %s <wav_file>\n", argv[0]);
        return 1;
    }

    FILE *fp = fopen(argv[1], "rb");
    if (!fp) {
        perror("fopen");
        return 1;
    }

    struct wav_header hdr;
    if (fread(&hdr, 1, sizeof(hdr), fp) != sizeof(hdr)) {
        printf("Failed to read WAV header\n");
        fclose(fp);
        return 1;
    }

    if (memcmp(hdr.riff_id, "RIFF", 4) != 0 || memcmp(hdr.wave_id, "WAVE", 4) != 0) {
        printf("Not a valid RIFF WAVE file\n");
        fclose(fp);
        return 1;
    }

    printf("WAV: %d channels, %d bits, %d Hz\n", hdr.num_chans, hdr.bits_per_samp, hdr.sample_rate);

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
        fclose(fp);
        return 1;
    }

    /* Wait for server */
    for (int i = 0; i < 100; i++) {
        error = object_lookup("!sndio", &sndio_obj);
        if (error == 0) break;
        timer_sleep(10, 0);
    }
    if (error) {
        printf("playwav: Error looking up !sndio: %d\n", error);
        fclose(fp);
        return 1;
    }

    struct sndio_open_msg open_msg;
    open_msg.hdr.code = SNDIO_OPEN;
    open_msg.mode = AUMODE_PLAY;
    msg_send(sndio_obj, &open_msg, sizeof(open_msg));
    if (open_msg.hdr.status != 0) {
        printf("Error opening sndio: %d\n", open_msg.hdr.status);
        fclose(fp);
        return 1;
    }

    struct sndio_params_msg params_msg;
    params_msg.hdr.code = SNDIO_SET_PARAMS;
    AUDIO_INITINFO(&params_msg.info);
    params_msg.info.play.sample_rate = rate_to_mask(hdr.sample_rate);
    params_msg.info.play.channels = hdr.num_chans;
    if (hdr.bits_per_samp == 16)
        params_msg.info.play.encoding = AUDIO_ENCODING_PCM_S16_LE;
    else
        params_msg.info.play.encoding = AUDIO_ENCODING_PCM_U8;
    msg_send(sndio_obj, &params_msg, sizeof(params_msg));

    void *shm_addr;
    error = vm_allocate(task_self(), &shm_addr, BUFFER_SIZE * MAX_BUFFERS, 1);
    if (error) {
        printf("Failed to allocate shared memory\n");
        fclose(fp);
        return 1;
    }

    struct sndio_buf_msg buf_msg;
    buf_msg.hdr.code = SNDIO_ALLOC_BUFS;
    buf_msg.count = MAX_BUFFERS;
    buf_msg.size = BUFFER_SIZE;
    buf_msg.shm_addr = shm_addr;
    msg_send(sndio_obj, &buf_msg, sizeof(buf_msg));
    if (buf_msg.count < MAX_BUFFERS) {
        printf("Failed to map buffers in server\n");
        vm_free(task_self(), shm_addr);
        fclose(fp);
        return 1;
    }

    uint8_t *shm_base = (uint8_t *)shm_addr;
    struct sndio_queue_msg q_msg;
    q_msg.hdr.code = SNDIO_QUEUE_BUF;

    /* Initial queueing */
    for (int b = 0; b < MAX_BUFFERS; b++) {
        uint8_t *target = shm_base + b * BUFFER_SIZE;
        size_t read = fread(target, 1, BUFFER_SIZE, fp);
        if (read < BUFFER_SIZE) memset(target + read, 0, BUFFER_SIZE - read);
        q_msg.buf_id = b;
        msg_send(sndio_obj, &q_msg, sizeof(q_msg));
        if (read < BUFFER_SIZE) break;
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
            uint8_t *target = shm_base + id * BUFFER_SIZE;
            size_t read = fread(target, 1, BUFFER_SIZE, fp);
            if (read == 0) break;
            if (read < BUFFER_SIZE) memset(target + read, 0, BUFFER_SIZE - read);

            q_msg.buf_id = id;
            msg_send(sndio_obj, &q_msg, sizeof(q_msg));
            if (read < BUFFER_SIZE) break;
        }
    }

    printf("playwav: Done.\n");
    fclose(fp);
    vm_free(task_self(), shm_addr);
    return 0;
}
