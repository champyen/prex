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

#ifndef _AUDIO_H_
#define _AUDIO_H_

#include <sys/types.h>
#include <sys/audioio.h>
#include <ddi.h>

/*
 * Hardware parameters
 */
struct audio_params {
    uint32_t sample_rate;
    uint8_t  channels;
    uint8_t  encoding;
};

/*
 * Hardware interface callbacks
 */
struct audio_hw_if {
    int  (*open)(void *priv, int flags);
    void (*close)(void *priv);
    int  (*set_params)(void *priv, struct audio_params *params);
    int  (*start_output)(void *priv, void *buf, size_t size, void (*intr)(void *));
    int  (*stop_output)(void *priv);
    int  (*start_input)(void *priv, void *buf, size_t size, void (*intr)(void *));
    int  (*stop_input)(void *priv);
    int  (*set_volume)(void *priv, uint8_t volume);
};

/*
 * Driver registration
 */
__BEGIN_DECLS
device_t audio_attach(const char *name, struct audio_hw_if *hw_if, void *hw_priv);
__END_DECLS

#endif /* !_AUDIO_H_ */
