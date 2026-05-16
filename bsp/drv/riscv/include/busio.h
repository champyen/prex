/*-
 * Copyright (c) 2026, Champ Yen <champ.yen@gmail.com>
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * ...
 */

#ifndef _RISCV_BUSIO_H
#define _RISCV_BUSIO_H

#include <sys/cdefs.h>
#include <sys/types.h>

#define bus_read_8(addr) (*((volatile uint8_t*)(addr)))
#define bus_read_16(addr) (*((volatile uint16_t*)(addr)))
#define bus_read_32(addr) (*((volatile uint32_t*)(addr)))

#define bus_write_8(addr, val) (*((volatile uint8_t*)(addr)) = (val))
#define bus_write_16(addr, val) (*((volatile uint16_t*)(addr)) = (val))
#define bus_write_32(addr, val) (*((volatile uint32_t*)(addr)) = (val))

#endif /* !_RISCV_BUSIO_H */
