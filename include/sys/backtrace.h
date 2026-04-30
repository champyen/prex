#ifndef _SYS_BACKTRACE_H
#define _SYS_BACKTRACE_H

#include <sys/cdefs.h>
#include <sys/types.h>

typedef struct backtrace
{
	void *function;   /* Address of the current address */
	void *address;    /* Calling site address */
	const char *name;
} backtrace_t;

__BEGIN_DECLS
int backtrace_unwind(backtrace_t *backtrace, int size);
int backtrace_unwind_frame(backtrace_t *buffer, int size, uint32_t pc, uint32_t lr, uint32_t sp, uint32_t r7, uint32_t r11);
const char *backtrace_function_name(uint32_t pc);
const char *backtrace_name(uint32_t address);
void backtrace_save(void);
void backtrace_save_frame(uint32_t pc, uint32_t lr, uint32_t sp, uint32_t r7, uint32_t r11);
__END_DECLS

#endif /* !_SYS_BACKTRACE_H */
