#include "proc.h"

/* External handler declarations (exported from Zig) */
extern int proc_getpid(struct msg *);
extern int proc_getppid(struct msg *);
extern int proc_getpgid(struct msg *);
extern int proc_setpgid(struct msg *);
extern int proc_getsid(struct msg *);
extern int proc_setsid(struct msg *);
extern int proc_fork(struct msg *);
extern int proc_exit(struct msg *);
extern int proc_stop(struct msg *);
extern int proc_waitpid(struct msg *);
extern int proc_kill(struct msg *);
extern int proc_exec(struct msg *);
extern int proc_pstat(struct msg *);
extern int proc_register(struct msg *);
extern int proc_setinit(struct msg *);
extern int proc_trace(struct msg *);
extern int proc_boot(struct msg *);
extern int proc_shutdown(struct msg *);
extern int proc_debug(struct msg *);
extern int proc_noop(struct msg *);

#define ID_MAXBUCKETS 32

struct proc proc0;
struct pgrp pgrp0;
struct session session0;

struct proc initproc;
struct proc* curproc;
struct list allproc;

struct proc *get_proc0(void) { return &proc0; }
struct pgrp *get_pgrp0(void) { return &pgrp0; }
struct session *get_session0(void) { return &session0; }

struct proc *get_curproc(void) { return curproc; }
void set_curproc(struct proc *p) { curproc = p; }

struct proc *get_initproc(void) { return &initproc; }

struct list *get_allproc(void) { return &allproc; }

static pid_t last_pid = 1;
pid_t get_last_pid(void) { return last_pid; }
void set_last_pid(pid_t pid) { last_pid = pid; }

static device_t ttydev;

device_t get_ttydev(void)
{
	return ttydev;
}

void set_ttydev(device_t dev)
{
	ttydev = dev;
}

extern void exception_handler(int sig);
void setup_tty_exception(void)
{
	exception_setup(exception_handler);
}

const char *get_tty_name(void)
{
	return "tty";
}

const char *get_panic_msg(void)
{
	return "proc: can not terminate a task for exit";
}

const char *get_boot_msg(void) { return "Starting process server\n"; }
const char *get_create_obj_fail_msg(void) { return "proc: fail to create object"; }
const char *get_proc_obj_name(void) { return "!proc"; }
const char *get_exec_obj_name(void) { return "!exec"; }
const char *get_proc_path(void) { return "/boot/proc"; }
const char *get_no_exec_msg(void) { return "proc: no exec found"; }
const char *get_fail_register_msg(void) { return "proc: fail to register boot task"; }

struct list pid_table[ID_MAXBUCKETS];
struct list task_table[ID_MAXBUCKETS];
struct list pgid_table[ID_MAXBUCKETS];

struct list *get_pid_table(void)
{
	return pid_table;
}

struct list *get_task_table(void)
{
	return task_table;
}

struct list *get_pgid_table(void)
{
	return pgid_table;
}

void table_init(void)
{
	int i;
	for (i = 0; i < ID_MAXBUCKETS; i++) {
		list_init(&pid_table[i]);
		list_init(&task_table[i]);
		list_init(&pgid_table[i]);
	}
}

int
dispatch_msg(int code, struct msg *msg)
{
	if (code == PS_GETPID)
		return proc_getpid(msg);
	else if (code == PS_GETPPID)
		return proc_getppid(msg);
	else if (code == PS_GETPGID)
		return proc_getpgid(msg);
	else if (code == PS_SETPGID)
		return proc_setpgid(msg);
	else if (code == PS_SETSID)
		return proc_setsid(msg);
	else if (code == PS_GETSID)
		return proc_getsid(msg);
	else if (code == PS_FORK)
		return proc_fork(msg);
	else if (code == PS_EXIT)
		return proc_exit(msg);
	else if (code == PS_STOP)
		return proc_stop(msg);
	else if (code == PS_WAITPID)
		return proc_waitpid(msg);
	else if (code == PS_KILL)
		return proc_kill(msg);
	else if (code == PS_EXEC)
		return proc_exec(msg);
	else if (code == PS_PSTAT)
		return proc_pstat(msg);
	else if (code == PS_REGISTER)
		return proc_register(msg);
	else if (code == PS_SETINIT)
		return proc_setinit(msg);
	else if (code == PS_TRACE)
		return proc_trace(msg);
	else if (code == STD_BOOT)
		return proc_boot(msg);
	else if (code == STD_SHUTDOWN)
		return proc_shutdown(msg);
	else if (code == STD_DEBUG)
		return proc_debug(msg);
	else
		return proc_noop(msg);
}
