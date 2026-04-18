#ifndef PREX_GLUE_H
#define PREX_GLUE_H

#include <stdlib.h>

long long strtoll(const char *nptr, char **endptr, int base);
unsigned long long strtoull(const char *nptr, char **endptr, int base);
float strtof(const char *nptr, char **endptr);
double strtod(const char *nptr, char **endptr);
long double strtold(const char *nptr, char **endptr);
long double ldexpl(long double d, int exp);

extern char **environ;

#endif
