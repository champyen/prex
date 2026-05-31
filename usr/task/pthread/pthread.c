/*-
 * Copyright (c) 2026, Champ Yen <champ.yen@gmail.com>
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
 * 3. Neither the name of the author nor the names of any co-contributors
 *    may be used to endorse or promote products derived from this software
 *    without specific prior written permission.
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

/*
 * pthread.c - sample program to create three threads using POSIX threads.
 */

#include <stdio.h>
#include <pthread.h>
#include <unistd.h>

static void* thread_A(void* arg)
{
    int i;
    printf("\nThread A is starting\n");
    for (i = 0; i < 1024; i++) {
        putchar('A');
        if ((i & 0xff) == 0)
            pthread_yield();
    }
    printf("\nThread A is terminated\n");
    return NULL;
}

static void* thread_B(void* arg)
{
    int i;
    printf("\nThread B is starting\n");
    for (i = 0; i < 2048; i++) {
        putchar('B');
        if ((i & 0xff) == 0)
            pthread_yield();
    }
    printf("\nThread B is terminated\n");
    return NULL;
}

static void* thread_C(void* arg)
{
    int i;
    printf("\nThread C is starting\n");
    for (i = 0; i < 4096; i++) {
        putchar('C');
        if ((i & 0xff) == 0)
            pthread_yield();
    }
    printf("\nThread C is terminated\n");
    return NULL;
}

int main(int argc, char* argv[])
{
    pthread_t ta, tb, tc;

    printf("POSIX Thread sample program\n");

    if (pthread_create(&ta, NULL, thread_A, NULL) != 0)
        printf("Error creating thread A\n");
    if (pthread_create(&tb, NULL, thread_B, NULL) != 0)
        printf("Error creating thread B\n");
    if (pthread_create(&tc, NULL, thread_C, NULL) != 0)
        printf("Error creating thread C\n");

    printf("Waiting for threads to finish...\n");

    pthread_join(ta, NULL);
    pthread_join(tb, NULL);
    pthread_join(tc, NULL);

    printf("\nAll threads joined - OK!\n");
    return 0;
}
