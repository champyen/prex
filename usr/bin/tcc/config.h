/* usr/bin/tcc/config.h */
#ifndef CONFIG_TCC_H
#define CONFIG_TCC_H

#define TCC_VERSION "0.9.27"

/* TCC expects these to be defined to select the target architecture */
#if defined(__arm__)
# ifndef TCC_TARGET_ARM
#  define TCC_TARGET_ARM
# endif
# ifndef CONFIG_TCC_ASM
#  define CONFIG_TCC_ASM
# endif
#elif defined(__i386__)
# ifndef TCC_TARGET_I386
#  define TCC_TARGET_I386
# endif
# ifndef CONFIG_TCC_ASM
#  define CONFIG_TCC_ASM
# endif
#endif

/* Use the one-source build style for simplicity in the Prex build tree */
#ifndef ONE_SOURCE
# define ONE_SOURCE 1
#endif

#ifndef CONFIG_TCC_STATIC
# define CONFIG_TCC_STATIC 1
#endif

/* Disable features not yet supported or needed on Prex */
#ifndef CONFIG_TCC_SEMLOCK
# define CONFIG_TCC_SEMLOCK 0
#endif

/* We don't want TCC to try to be native since Prex is missing many host headers */
#undef TCC_IS_NATIVE

/* Prex libc stubs for missing long long/long double functions */
#define strtoll(s, e, b)  strtol(s, e, b)
#define strtoull(s, e, b) strtoul(s, e, b)
#define ldexpl(v, e)      ldexp(v, e)

/* Missing globals/headers */
extern char **environ;

#endif
