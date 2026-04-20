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
#include <sys/socket.h>
#include <sys/endian.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>

int nc_main(int argc, char *argv[]) {
    int s;
    struct sockaddr_in remote;
    struct hostent *he;
    uint16_t port;
    char buf[2048];
    char send_buf[4096];
    int n, i, j;

    if (argc < 3) {
        printf("usage: nc <hostname> <port>\n");
        return 1;
    }

    he = gethostbyname(argv[1]);
    if (he == NULL) {
        printf("nc: unknown host %s\n", argv[1]);
        return 1;
    }
    port = (uint16_t)atoi(argv[2]);

    s = socket(AF_INET, SOCK_STREAM, 0);
    if (s < 0) {
        perror("nc: socket");
        return 1;
    }

    memset(&remote, 0, sizeof(remote));
    remote.sin_family = AF_INET;
    memcpy(&remote.sin_addr.s_addr, he->h_addr, 4);
    remote.sin_port = htons(port);

    if (connect(s, (struct sockaddr *)&remote, sizeof(remote)) < 0) {
        perror("nc: connect");
        close(s);
        return 1;
    }

    /* 
     * Scripting loop with LF -> CRLF conversion
     */
    while ((n = read(0, buf, sizeof(buf))) > 0) {
        j = 0;
        for (i = 0; i < n; i++) {
            if (buf[i] == '\n' && (i == 0 || buf[i-1] != '\r')) {
                send_buf[j++] = '\r';
            }
            send_buf[j++] = buf[i];
            if (j >= (int)sizeof(send_buf) - 2) {
                if (send(s, send_buf, j, 0) < 0) break;
                j = 0;
            }
        }
        if (j > 0) {
            if (send(s, send_buf, j, 0) < 0) break;
        }
        if (n < (int)sizeof(buf)) break;
    }

    shutdown(s, SHUT_WR);

    while ((n = recv(s, buf, sizeof(buf) - 1, 0)) > 0) {
        buf[n] = '\0';
        printf("%s", buf);
    }

    if (n < 0) perror("nc: recv");

    close(s);
    return 0;
}
