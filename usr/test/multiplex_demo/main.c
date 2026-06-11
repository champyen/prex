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

#include <sys/prex.h>
#include <sys/select.h>
#include <sys/poll.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>

int main(int argc, char **argv) {
    int fd1, fd2;
    fd_set readfds;
    char buf[128];
    int n;

    printf("Starting multiplex_demo...\n");

    /* Create named pipes */
    unlink("/mnt/fifo/pipe1");
    unlink("/mnt/fifo/pipe2");
    if (mkfifo("/mnt/fifo/pipe1", 0666) < 0) {
        perror("mkfifo /mnt/fifo/pipe1");
        return 1;
    }
    if (mkfifo("/mnt/fifo/pipe2", 0666) < 0) {
        perror("mkfifo /mnt/fifo/pipe2");
        return 1;
    }

    /* Open pipes in non-blocking mode */
    fd1 = open("/mnt/fifo/pipe1", O_RDONLY | O_NONBLOCK);
    fd2 = open("/mnt/fifo/pipe2", O_RDONLY | O_NONBLOCK);
    if (fd1 < 0 || fd2 < 0) {
        perror("open pipes");
        return 1;
    }

    printf("Waiting for data on /mnt/fifo/pipe1, /mnt/fifo/pipe2, or stdin (fd 0)...\n");

    for (;;) {
        FD_ZERO(&readfds);
        FD_SET(0, &readfds);
        FD_SET(fd1, &readfds);
        FD_SET(fd2, &readfds);

        int max_fd = fd2 > fd1 ? fd2 : fd1;

        int nready = select(max_fd + 1, &readfds, NULL, NULL, NULL);
        if (nready < 0) {
            perror("select");
            break;
        }

        if (FD_ISSET(0, &readfds)) {
            n = read(0, buf, sizeof(buf) - 1);
            if (n > 0) {
                buf[n] = '\0';
                printf("Input from stdin: %s", buf);
                if (strncmp(buf, "exit", 4) == 0) break;
            }
        }

        if (FD_ISSET(fd1, &readfds)) {
            n = read(fd1, buf, sizeof(buf) - 1);
            if (n > 0) {
                buf[n] = '\0';
                printf("Input from /mnt/fifo/pipe1: %s", buf);
            }
        }

        if (FD_ISSET(fd2, &readfds)) {
            n = read(fd2, buf, sizeof(buf) - 1);
            if (n > 0) {
                buf[n] = '\0';
                printf("Input from /mnt/fifo/pipe2: %s", buf);
            }
        }
    }

    close(fd1);
    close(fd2);
    unlink("/mnt/fifo/pipe1");
    unlink("/mnt/fifo/pipe2");

    return 0;
}
