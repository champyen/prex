#include <stdlib.h>
#include <math.h>
#include <string.h>
#include <sys/prex.h>
#include <sys/posix.h>
#include <ipc/fs.h>
#include <errno.h>
#include <stdio.h>
#include <unistd.h>

long long strtoll(const char *nptr, char **endptr, int base) {
    return (long long)strtol(nptr, endptr, base);
}

unsigned long long strtoull(const char *nptr, char **endptr, int base) {
    return (unsigned long long)strtoul(nptr, endptr, base);
}

float strtof(const char *nptr, char **endptr) { return (float)atof(nptr); }
double strtod(const char *nptr, char **endptr) { return atof(nptr); }
long double strtold(const char *nptr, char **endptr) { return (long double)atof(nptr); }

long double ldexpl(long double d, int exp) {
    while (exp > 0) { d *= 2.0; exp--; }
    while (exp < 0) { d /= 2.0; exp++; }
    return d;
}

void *dlopen(const char *filename, int flag) { return NULL; }
void dlclose(void *p) {}
void *dlsym(void *handle, const char *symbol) { return NULL; }
const char *dlerror(void) { return NULL; }
int tcc_run(void *s, int argc, char **argv) { return -1; }
void tcc_run_free(void *s) {}
