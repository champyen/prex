#include <string.h>
#include <stdlib.h>

/* ARM AEABI stubs */
void __aeabi_memclr(void *dest, size_t n) {
    memset(dest, 0, n);
}

void __aeabi_memclr4(void *dest, size_t n) {
    memset(dest, 0, n);
}

void __aeabi_memclr8(void *dest, size_t n) {
    memset(dest, 0, n);
}

/* Float string conversion stubs for Prex */
double strtod(const char *nptr, char **endptr) {
    if (endptr) *endptr = (char *)nptr;
    return 0.0;
}

float strtof(const char *nptr, char **endptr) {
    if (endptr) *endptr = (char *)nptr;
    return 0.0f;
}

long double strtold(const char *nptr, char **endptr) {
    if (endptr) *endptr = (char *)nptr;
    return 0.0L;
}
