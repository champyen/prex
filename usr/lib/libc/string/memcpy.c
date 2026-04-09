/*	$NetBSD: memcpy.c,v 1.1 1998/08/04 04:48:17 perry Exp $	*/

#define MEMCOPY
#include "bcopy.c"

#ifdef __arm__
/*
 * ARM EABI memcpy alias
 */
void __aeabi_memcpy(void *dest, const void *src, size_t n)
{
	memcpy(dest, src, n);
}

void __aeabi_memcpy4(void *dest, const void *src, size_t n)
{
	memcpy(dest, src, n);
}

void __aeabi_memcpy8(void *dest, const void *src, size_t n)
{
	memcpy(dest, src, n);
}
#endif
