# Prex POSIX Compliance

*For Prex version 0.9.0, 2009/10/01*



### Table of Contents

- [Introduction](http://prex.sourceforge.net/doc/posix.html#intro)
- [POSIX APIs](http://prex.sourceforge.net/doc/posix.html#api)

## Introduction

In order to reduce the development time of mobilie applications, Prex is providing developers with POSIX system call interface and standard C libraries.

## POSIX APIs

### File and Directories - <unistd.h>

| Name      | Synopsis                                               | Description                                         | Support?                        |
| --------- | ------------------------------------------------------ | --------------------------------------------------- | ------------------------------- |
| getcwd    | char *getcwd(char *buf, size_t size);                  | get current working directory                       | ![Yes](img/posix/checkmark.png) |
| mkdir     | int mkdir(const char *pathname, mode_t mode);          | create a directory                                  | ![Yes](img/posix/checkmark.png) |
| rmdir     | int rmdir(const char *pathname);                       | delete a directory                                  | ![Yes](img/posix/checkmark.png) |
| chdir     | int chdir(const char *path);                           | change working directory                            | ![Yes](img/posix/checkmark.png) |
| link      | int link(const char *oldpath, const char *newpath);    | make a new name for a file                          | X                               |
| unlink    | int unlink(const char *pathname);                      | delete a name and possibly the file it refers to    | ![Yes](img/posix/checkmark.png) |
| rename    | int rename(const char *oldpath, const char *newpath);  | change the name or location of a file               | ![Yes](img/posix/checkmark.png) |
| stat      | int stat(const char *file_name, struct stat *buf);     | get file status                                     | ![Yes](img/posix/checkmark.png) |
| chmod     | int chmod(const char *path, mode_t mode);              | change permissions of a file                        | X                               |
| chown     | int chown(const char *path, uid_t owner, gid_t group); | change ownership of a file                          | X                               |
| utime     | int utime(const char *filename, struct utimbuf *buf);  | change access and/or modification times of an inode | X                               |
| opendir   | DIR *opendir(const char *name);                        | open a directory                                    | ![Yes](img/posix/checkmark.png) |
| readdir   | struct dirent *readdir(DIR *dir);                      | read directory entry                                | ![Yes](img/posix/checkmark.png) |
| closedir  | int closedir(DIR *dir);                                | close a directory                                   | ![Yes](img/posix/checkmark.png) |
| rewinddir | void rewinddir(DIR *dir);                              | reset directory stream                              | ![Yes](img/posix/checkmark.png) |

### Advanced File Operations - <unistd.h>

| Name   | Synopsis                                              | Description                                         | Support?                                                  |
| ------ | ----------------------------------------------------- | --------------------------------------------------- | --------------------------------------------------------- |
| access | int access(const char *pathname, int mode);           | check user's permissions for a file                 | ![Yes](img/posix/checkmark.png)                           |
| open   | int open(const char *pathname, int flags);            | open and possibly create a file or device           | ![Yes](img/posix/checkmark.png)                           |
| creat  | int creat(const char *pathname, mode_t mode);         | open and possibly create a file or device           | ![Yes](img/posix/checkmark.png) |
| close  | int close(int fd);                                    | close a file descriptor                             | ![Yes](img/posix/checkmark.png) |
| read   | ssize_t read(int fd, void *buf, size_t count);        | read from a file descriptor                         | ![Yes](img/posix/checkmark.png) |
| write  | ssize_t write(int fd, const void *buf, size_t count); | write to a file descriptor                          | ![Yes](img/posix/checkmark.png) |
| fcntl  | int fcntl(int fd, int cmd);                           | manipulate file descriptor                          | ![Yes](img/posix/checkmark.png) |
| fstat  | int fstat(int filedes, struct stat *buf);             | get file status                                     | ![Yes](img/posix/checkmark.png) |
| lseek  | off_t lseek(int fildes, off_t offset, int whence);    | reposition read/write file offset                   | ![Yes](img/posix/checkmark.png) |
| dup    | int dup(int oldfd);                                   | duplicate a file descriptor                         | ![Yes](img/posix/checkmark.png) |
| dup2   | int dup2(int oldfd, int newfd);                       | duplicate a file descriptor                         | ![Yes](img/posix/checkmark.png) |
| pipe   | int pipe(int filedes[2]);                             | create pipe                                         | ![Yes](img/posix/checkmark.png) |
| mkfifo | int mkfifo(const char *pathname, mode_t mode);        | make a FIFO special file (a named pipe)             | plan                                                      |
| umask  | mode_t umask(mode_t mask);                            | set file creation mask                              | X                                                         |
| fdopen | FILE *fdopen(int fildes, const char *mode);           | associate a stream with an existing file descriptor | ![Yes](img/posix/checkmark.png) |
| fileno | int fileno(FILE *stream);                             | return file descriptor of stream                    | ![Yes](img/posix/checkmark.png) |

### Processes - <unistd.h>

| Name    | Synopsis                                                     | Description                                 | Support?                                                     |
| ------- | ------------------------------------------------------------ | ------------------------------------------- | ------------------------------------------------------------ |
| fork    | pid_t fork(void);                                            | create a child process                      | ![Yes](img/posix/checkmark.png)    |
| execl   | int execl(const char *path, const char *arg, ...);           | execute a file                              | ![Yes](img/posix/checkmark.png)    |
| execle  | int execle(const char *path, const char *arg, ...)           | execute a file                              | ![Yes](img/posix/checkmark.png)    |
| execlp  | int execlp(const char *file, const char *arg, ...);          | execute a file                              | ![Yes](img/posix/checkmark.png)    |
| execv   | int execv(const char *path, char *const argv[]);             | execute a file                              | ![Yes](img/posix/checkmark.png)    |
| execve  | int execve(const char *path, char *const argv[], char *const envp[])) | execute program                             | ![Yes](img/posix/checkmark.png)    |
| execvp  | int execvp(const char *file, char *const argv[]);            | execute a file                              | ![Yes](img/posix/checkmark.png)    |
| wait    | pid_t wait(int *status);                                     | wait for process termination                | ![Yes](img/posix/checkmark.png)    |
| waitpid | pid_t waitpid(pid_t pid, int *status, int options);          | wait for process termination                | ![Yes](img/posix/checkmark.png)    |
| _exit   | void _exit(int status);                                      | terminate the current process               | ![Yes](img/posix/checkmark.png)    |
| kill    | int kill(pid_t pid, int sig);                                | send signal to a process                    | ![Yes](img/posix/checkmark.png)    |
| sleep   | unsigned int sleep(unsigned int seconds);                    | Sleep for the specified number of seconds   | ![Yes](img/posix/checkmark.png)    |
| pause   | int pause(void);                                             | wait for signal                             | ![Yes](img/posix/checkmark.png)    |
| alarm   | unsigned int alarm(unsigned int seconds);                    | set an alarm clock for delivery of a signal | ![Yes](img/posix/checkmark.png)    |
| setuid  | int setuid(uid_t uid);                                       | set user identity                           | ![Yes](img/posix/checkmark.png)(Limited Support) |
| setgid  | int setgid(gid_t gid);                                       | set group identity                          | ![Yes](img/posix/checkmark.png)(Limited Support) |

### Long Jumps - <setjmp.h>

| Name       | Synopsis                                     | Description                             | Support?                                                  |
| ---------- | -------------------------------------------- | --------------------------------------- | --------------------------------------------------------- |
| setjmp     | int setjmp(jmp_buf env);                     | save stack context for non-local goto   | ![Yes](img/posix/checkmark.png) |
| sigsetjmp  | int sigsetjmp(sigjmp_buf env, int savesigs); | save stack context for non-local goto   | X                                                         |
| longjmp    | void longjmp(jmp_buf env, int val);          | non-local jump to a saved stack context | ![Yes](img/posix/checkmark.png) |
| siglongjmp | void siglongjmp(sigjmp_buf env, int val);    | non-local jump to a saved stack context | X                                                         |

### Signal Handling - <signal.h>

| Name        | Synopsis                                                     | Description                             | Support?                                                  |
| ----------- | ------------------------------------------------------------ | --------------------------------------- | --------------------------------------------------------- |
| sigaction   | int sigaction(int sig, const struct sigaction *act, struct sigaction *oldact); | examine and change signal action        | ![Yes](img/posix/checkmark.png) |
| sigemptyset | int sigemptyset(sigset_t *set);                              | create an empty signal set              | X                                                         |
| sigfillset  | int sigfillset(sigset_t *set);                               | create a full set of signals            | X                                                         |
| sigaddset   | int sigaddset(sigset_t *set, int signum);                    | add a signal to a signal set            | X                                                         |
| sigdelset   | int sigdelset(sigset_t *set, int signum);                    | remove a signal from a signal set       | X                                                         |
| sigismember | int sigismember(const sigset_t *set, int signum);            | test a signal set for a selected member | X                                                         |
| sigprocmask | int sigprocmask(int how, const sigset_t *set, sigset_t *oset); | examine and change blocked signals      | ![Yes](img/posix/checkmark.png) |
| sigpending  | int sigpending(sigset_t *set);                               | examine pending signals                 | ![Yes](img/posix/checkmark.png) |
| sigsuspend  | int sigsuspend(const sigset_t *mask);                        | wait for a signal                       | ![Yes](img/posix/checkmark.png) |

### Obtaining Information at Runtime - <unistd.h><pwd.h><grp.h>

| Name      | Synopsis                                    | Description                                   | Support?                                                     |
| --------- | ------------------------------------------- | --------------------------------------------- | ------------------------------------------------------------ |
| getpid    | pid_t getpid(void);                         | get process identification                    | ![Yes](img/posix/checkmark.png)    |
| getppid   | pid_t getppid(void);                        | get parent process identification             | ![Yes](img/posix/checkmark.png)    |
| getlogin  | char * getlogin(void);                      | get user name                                 | X                                                            |
| getuid    | uid_t getuid(void);                         | get user identity                             | ![Yes](img/posix/checkmark.png)(Limited Support) |
| geteuid   | uid_t geteuid(void);                        | get effective user identity                   | ![Yes](img/posix/checkmark.png)(Limited Support) |
| cuserrid  | char * cuserid(char *string);               | get user name                                 | plan                                                         |
| getgid    | gid_t getgid(void);                         | get group identity                            | ![Yes](img/posix/checkmark.png)(Limited Support) |
| getegid   | gid_t getegid(void);                        | get effective group identity                  | ![Yes](img/posix/checkmark.png)(Limited Support) |
| getpwuid  | struct passwd *getpwuid(uid_t uid);         | get password file entry based on user id      | X                                                            |
| getpwnam  | struct passwd *getpwnam(const char * name); | get password file entry based on user name    | X                                                            |
| getgrgid  | struct group *getgrgid(gid_t gid);          | get group file entry based on group id        | X                                                            |
| getgrnam  | struct group *getgrnam(const char *name);   | get group file entry baes on group name       | X                                                            |
| getgroups | int getgroups(int size, gid_t list[]);      | get list of supplementary group IDs           | X                                                            |
| ctermid   | char *ctermid(char *s);                     | get controlling terminal name                 | plan                                                         |
| uname     | int uname(struct utsname *buf);             | get name and information about current kernel | ![Yes](img/posix/checkmark.png)    |
| getenv    | char *getenv(const char *name);             | get an environment variable                   | ![Yes](img/posix/checkmark.png)    |
| sysconf   | long sysconf(int name);                     | get configuration information at runtime      | plan                                                         |
| fpathconf | long fpathconf(int filedes, int name);      | get configuration values for files            | plan                                                         |
| isatty    | int isatty(int desc);                       | does this descriptor refer to a terminal      | ![Yes](img/posix/checkmark.png)    |
| ttyname   | char *ttyname(int desc);                    | return name of a terminal                     | plan                                                         |
| times     | clock_t times(struct tms *buf);             | get process times                             | plan                                                         |
| tzset     | void tzset(void);                           | initialize time conversion information        | plan                                                         |

### Terminal I/O - <termios.h>

| Name        | Synopsis                                                     | Description                                           | Support?                                                  |
| ----------- | ------------------------------------------------------------ | ----------------------------------------------------- | --------------------------------------------------------- |
| getpid      | pid_t getpid(void);                                          | get process identification                            | ![Yes](img/posix/checkmark.png) |
| tcgetattr   | int tcgetattr(int fd, struct termios *termios_p);            | get terminal attributes                               | ![Yes](img/posix/checkmark.png) |
| tcsetattr   | int tcsetattr(int fd, int optional_actions, struct termios *termios_p); | set terminal attributes                               | ![Yes](img/posix/checkmark.png) |
| tcdrain     | int tcdrain(int fd);                                         | wait for all output to be transmitted to the terminal | ![Yes](img/posix/checkmark.png) |
| tcflow      | int tcflow(int fd, int action);                              | suspend/restart terminal output                       | ![Yes](img/posix/checkmark.png) |
| tcflush     | int tcflush(int fd, int queue_selector);                     | discard terminal data                                 | ![Yes](img/posix/checkmark.png) |
| tcsendbreak | int tcsendbreak(int fd, int duration);                       | send a break to a terminal                            | ![Yes](img/posix/checkmark.png) |
| cfgetispeed | speed_t cfgetispeed(struct termios *termios_p);              | get input baud rate                                   | ![Yes](img/posix/checkmark.png) |
| cfgetospeed | speed_t cfgetospeed(struct termios *termios_p);              | get output baud rate                                  | ![Yes](img/posix/checkmark.png) |
| cfsetispeed | int cfsetispeed(struct termios *termios_p, speed_t speed);   | set input baud rate                                   | ![Yes](img/posix/checkmark.png) |
| cfsetospeed | speed_t cfsetospeed(const struct termios *termios_p);        | set output baud rate                                  | ![Yes](img/posix/checkmark.png) |
| tcgetpgrp   | pid_t tcgetpgrp(int fd);                                     | get terminal foreground process group ID              | ![Yes](img/posix/checkmark.png) |
| tcsetpgrp   | int tcsetpgrp(int fd, pid_t pgrpid);                         | set terminal foreground process group ID              | ![Yes](img/posix/checkmark.png) |

### Process Groups and Job Control - <unistd.h>

| Name    | Synopsis                            | Description                                     | Support?                                                  |
| ------- | ----------------------------------- | ----------------------------------------------- | --------------------------------------------------------- |
| setsid  | pid_t setsid(void);                 | creates a session and sets the process group ID | plan                                                      |
| setpgid | int setpgid(pid_t pid, pid_t pgid); | set process group                               | ![Yes](img/posix/checkmark.png) |
| getpgrp | pid_t getpgrp(void);                | get process group                               | ![Yes](img/posix/checkmark.png) |



Copyright© 2005-2009 Kohsuke Ohtani