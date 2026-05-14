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

#ifndef _SYS_DKI_TABLE_H
#define _SYS_DKI_TABLE_H

/*
 * Driver-Kernel Interface (DKI) function list.
 * Syntax: DO(index, public_name, internal_kernel_symbol)
 */
#define FOR_EACH_DKI(DO)                                                                                               \
    DO(0, copyin, copyin)                                                                                              \
    DO(1, copyout, copyout)                                                                                            \
    DO(2, copyinstr, copyinstr)                                                                                        \
    DO(3, kmem_alloc, kmem_alloc)                                                                                      \
    DO(4, kmem_free, kmem_free)                                                                                        \
    DO(5, kmem_map, kmem_map)                                                                                          \
    DO(6, page_alloc, page_alloc)                                                                                      \
    DO(7, page_free, page_free)                                                                                        \
    DO(8, page_reserve, page_reserve)                                                                                  \
    DO(9, irq_attach, irq_attach)                                                                                      \
    DO(10, irq_detach, irq_detach)                                                                                     \
    DO(11, spl0, spl0)                                                                                                 \
    DO(12, splhigh, splhigh)                                                                                           \
    DO(13, splx, splx)                                                                                                 \
    DO(14, timer_callout, timer_callout)                                                                               \
    DO(15, timer_stop, timer_stop)                                                                                     \
    DO(16, timer_delay, timer_delay)                                                                                   \
    DO(17, timer_ticks, timer_ticks)                                                                                   \
    DO(18, sched_lock, sched_lock)                                                                                     \
    DO(19, sched_unlock, sched_unlock)                                                                                 \
    DO(20, sched_tsleep, sched_tsleep)                                                                                 \
    DO(21, sched_wakeup, sched_wakeup)                                                                                 \
    DO(22, sched_dpc, sched_dpc)                                                                                       \
    DO(23, task_capable, task_capable)                                                                                 \
    DO(24, exception_post, exception_post)                                                                             \
    DO(25, device_create, device_create)                                                                               \
    DO(26, device_destroy, device_destroy)                                                                             \
    DO(27, device_lookup, device_lookup)                                                                               \
    DO(28, device_control, device_control)                                                                             \
    DO(29, device_broadcast, device_broadcast)                                                                         \
    DO(30, device_private, device_private)                                                                             \
    DO(31, machine_bootinfo, machine_bootinfo)                                                                         \
    DO(32, machine_powerdown, machine_powerdown)                                                                       \
    DO(33, sysinfo, sysinfo)                                                                                           \
    DO(34, uart_lock, hal_uart_lock)                                                                                   \
    DO(35, uart_unlock, hal_uart_unlock)                                                                               \
    DO(36, panic, DKI_INT_PANIC)                                                                                       \
    DO(37, printf, DKI_INT_PRINTF)                                                                                     \
    DO(38, dbgctl, DKI_INT_DBGCTL)

#define MAX_DKI 39

#endif /* !_SYS_DKI_TABLE_H */
