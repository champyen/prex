/*-
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

#include <sys/ioctl.h>
#include <sys/audioio.h>
#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <math.h>
#include <stdint.h>
#include <string.h>

#define SAMPLE_RATE 44100
#define FREQ        440
#define CHANNELS    2
#define DURATION    3 // seconds
#define AMPLITUDE   16383 // Max 32767 for S16

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

int main(int argc, char *argv[])
{
    int fd;
    struct audio_info info;
    int16_t *buf;
    int duration = DURATION;
    
    if (argc > 1) {
        duration = atoi(argv[1]);
        if (duration <= 0) duration = DURATION;
    }

    int num_samples = SAMPLE_RATE * duration;
    size_t buf_size = num_samples * CHANNELS * sizeof(int16_t);

    fd = open("/dev/audio", O_WRONLY);
    if (fd < 0) {
        perror("open /dev/audio");
        return 1;
    }

    AUDIO_INITINFO(&info);
    info.play.sample_rate = AUDIO_SAMP_RATE_44K;
    info.play.channels = CHANNELS;
    info.play.encoding = AUDIO_ENCODING_PCM_S16_LE;

    if (ioctl(fd, AUDIO_SETINFO, &info) < 0) {
        perror("AUDIO_SETINFO");
        close(fd);
        return 1;
    }

    buf = malloc(buf_size);
    if (buf == NULL) {
        perror("malloc");
        close(fd);
        return 1;
    }

    printf("Generating 440Hz sine wave for %d seconds...\n", duration);
    for (int i = 0; i < num_samples; i++) {
        int16_t val = (int16_t)(AMPLITUDE * sin(2.0 * M_PI * FREQ * i / SAMPLE_RATE));
        buf[i * 2] = val;     // Left
        buf[i * 2 + 1] = val; // Right
    }

    printf("Playing beep...\n");
    size_t second_size = SAMPLE_RATE * CHANNELS * sizeof(int16_t);
    for (int s = 0; s < duration; s++) {
        if (write(fd, buf + (s * SAMPLE_RATE * CHANNELS), second_size) < 0) {
            perror("write /dev/audio");
            break;
        }
    }

    printf("Beep complete.\n");

    close(fd);
    free(buf);
    return 0;
}
