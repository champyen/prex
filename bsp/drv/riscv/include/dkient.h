/*
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

/*
 * Stub to call kernel device interface
 */
#define STUB(index, func)         \
    .global func;                 \
    ENTRY(func)                   \
    la t0, dki_table;             \
    lw t0, 0(t0);                 \
    lw t0, (index * 4)(t0);       \
    jr t0
