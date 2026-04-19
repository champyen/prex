/*
 * Copyright 2018 Phoenix Systems
 * Copyright (c) 2026, Champ Yen (champ.yen@gmail.com)
 * All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include <stdlib.h>
#include <time.h>
#include <sys/prex.h>
#include "lwip/sys.h"

u32_t sys_jiffies(void)
{
    u_long ticks;
    sys_time(&ticks);
	return (u32_t)ticks;
}

u32_t sys_now(void)
{
    u_long ticks;
    sys_time(&ticks);
    return (u32_t)(ticks * 10); /* Assuming HZ=100 */
}
