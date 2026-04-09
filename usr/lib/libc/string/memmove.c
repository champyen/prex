/*	$NetBSD: memmove.c,v 1.1 1998/08/04 04:48:17 perry Exp $	*/

#define MEMMOVE
#include "bcopy.c"

#ifdef __arm__
/*
 * ARM EABI memmove alias
 */
void __aeabi_memmove(void *dest, const void *src, size_t n)
{
	memmove(dest, src, n);
}

void __aeabi_memmove4(void *dest, const void *src, size_t n)
{
	memmove(dest, src, n);
}

void __aeabi_memmove8(void *dest, const void *src, size_t n)
{
	memmove(dest, src, n);
}
#endif

