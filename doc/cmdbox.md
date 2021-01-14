# CmdBox User's Guide

### Table of Contents

- Introduction
- How to use CmdBox?
- Configuring CmdBox
- Command Usage
  - cat
  - clear
  - cp
  - date
  - dmesg
  - echo
  - free
  - head
  - hostname
  - kill
  - ls
  - mkdir
  - more
  - mv
  - nice
  - printenv
  - ps
  - pwd
  - rm
  - rmdir
  - sh
  - sleep
  - sync
  - test
  - touch
  - uname



## Introduction

CmdBox (Command Box) is a small application which includes tiny versions of many UNIX utilities - A.K.A. the Swiss Army Knife of Prex.

This document describes the usage of each command and how to customize commands.

## How to use CmdBox?

The CmdBox utility can execute the specific command with the following syntax.

```
cmdbox [command] [arguments...]
```

The first argument for CmdBox is the name of the command. Or, if the command is invoked under CmdBox's shell, we can use as follows.

```
command [arguments...]
```

The following example shows the usage of the some major UNIX commands.

```
[prex:/]# cd boot
[prex:/boot]# cmdbox pwd
/boot
[prex:/boot]# cmdbox ps
  PID     TIME CMD
    0        5 proc
    3       20 exec
    2       25 fs
    1        2 init
    4        4 cmdbox
    6        6 cmdbox
[prex:/boot]# cmdbox sh
[prex:/boot]# uname -?
usage: uname [-amnsrv]
[prex:/boot]# uname -a
Prex 0.8.2 Feb  4 2009 i386-pc preky
[prex:/boot]# exit
[prex:/boot]# _
```

## Configuring CmdBox

You can select the available commands included in CmdBox utility. This can be done by changing 'command' options in the configuration file - */conf/$(arch)/$(platform)*. You must change this file before running the configure script to compile the Prex source tree.

```
command         cat
command         clear
command         cp
command         date
command         dmesg
command         echo
command         free
command         head
command         hostname
command         kill
command         ls
command         mkdir
...
```

The 'help' command will display the list of supported built-in commands. So, you can identify which commands are included in CmdBox.

```
[prex:/]# help
usage: cmdbox [command] [arguments]...
builtin commands:
    cat, clear, cp, date, dmesg, echo, free, head, help, hostname,
    kill, ls, mkdir, more, mv, nice, printenv, ps, pwd, rm,
    rmdir, sleep, sync, touch, uname, cd, exec, exit, export,
    mem, set, unset
use `-?` to find out more about each command.
[prex:/]# _
```

## Command Usage

Most of CmdBox commands support the "-?" argument to provide an usage description of their command.



------

### NAME

**cat** -- concatenate and print files

### SYNOPSIS

```
cat [-u] [-] [file ...]
```

### DESCRIPTION

The cat utility reads files sequentially, writing them to the standard output.  The file operands are processed in command-line order.  If file is a single dash (`-') or absent, cat reads from the standard input.

The options are as follows:

- -u

  Disable output buffering.

### EXIT STATUS

The cat utility exits 0 on success, and >0 if an error occurs.



------

### NAME

**clear** -- clear the terminal screen

### SYNOPSIS

```
clear
```

### DESCRIPTION

The clear utility clears the terminal screen if this is possible.



------

### NAME

**cp** -- copy files

### SYNOPSIS

```
cp [-i] src target
cp [-i] src1 ... srcN directory
```

### DESCRIPTION

In the first synopsis form, the cp utility copies the contents of the *src* to the *target*. In the second synopsis form, the contents of each named *srcN* is copied to the destination *directory*.	The names of the files themselves are not changed.  If     cp detects an attempt to copy a file to itself, the copy will fail.

The options are as follows:

- -i

  Cause cp to write a prompt to the standard error output before copying a file that would overwrite an existing file.  If the response from the standard input begins with the character `y' or `Y', the file copy is attempted.



------

### NAME

**date** -- display date and time

### SYNOPSIS

```
date
```

### DESCRIPTION

The date utility displays the current date and time.

*NOTE: There is no function to change date or time.*



------

### NAME

**dmesg** -- display the system message buffer

### SYNOPSIS

```
dmesg
```

### DESCRIPTION

The dmesg utility displays the contents of the system message buffer.



------

### NAME

**echo** -- write arguments to the standard output

### SYNOPSIS

```
echo [-n] [string ...]
```

### DESCRIPTION

The echo utility writes any specified operands, separated by single blank (` ') characters and followed by a newline (`\n') character, to the standard output.

​     The following option is available:

- -n

   Do not print the trailing newline character.

### EXIT STATUS

The echo utility exits 0 on success, and >0 if an error occurs.



------

### NAME

**free** -- display information about free and used memory on the system

### SYNOPSIS

```
free
```

### DESCRIPTION

The free utility displays the total amount of free and used physical memory.



------

### NAME

**head** -- display first lines of a file

### SYNOPSIS

```
head [-n lines] [file ...]
```

### DESCRIPTION

This filter displays the first count lines or bytes of each of the  specified files, or of the standard input if no files are specified.  If count is omitted it defaults to 10.

If more than a single file is specified, each file is preceded by a header consisting of the string ``==> XXX <=='' where ``XXX'' is the name of the file.

### EXIT STATUS

The head utility exits 0 on success, and >0 if an error occurs.



------

### NAME

**hostname** --  print name of current host system

### SYNOPSIS

```
hostname
```

### DESCRIPTION

The hostname utility prints the name of the current host.

*NOTE: There is no function to change the host name.*



------

### NAME

**kill** -- terminate or signal a process

### SYNOPSIS

```
kill [-s signal_name] pid ...
kill -l [exit_status]
kill -signal_name pid ...
kill -signal_number pid ...
```

### DESCRIPTION

The kill utility sends a signal to the processes specified by the pid operands.

Only the super-user may send signals to other users' processes.

The options are as follows:

- -s signal_name

  A symbolic signal name specifying the signal to be sent instead of the default TERM.

- -l [exit_status]

  If no operand is given, list the signal names; otherwise, write the signal name corresponding to exit_status.

- -signal_name

  A symbolic signal name specifying the signal to be sent instead of the default TERM.

- -signal_number

  A non-negative decimal integer, specifying the signal to be sent instead of the default TERM.

The following PIDs have special meanings:

-1 ...  If superuser, broadcast the signal to all processes; otherwise broadcast to all processes belonging to the user.

### EXIT STATUS

The kill utility exits 0 on success, and >0 if an error occurs.



------

### NAME

**ls** -- list directory contents

### SYNOPSIS

```
ls [-1CFAal] [file ...]
```

### DESCRIPTION

For each operand that names a file of a type other than directory, ls displays its name as well as any requested, associated information.  For each operand that names a file of type directory, ls displays the names of files contained within that directory, as well as any requested, associated information.

If no operands are given, the contents of the current directory are displayed. 

The following options are available:

- -A

  Include directory entries whose names begin with a dot (`.') except for . and ...

- -C

  Force multi-column output; this is the default when output is to a terminal.

- -F

  Display a slash (`/') immediately after each pathname that is a      directory, an asterisk (`*') after each that is executable, an at      sign (`@') after each symbolic link, an equals sign (`=') after      each socket, a percent sign (`%') after each whiteout, and a ver-      tical bar (`|') after each that is a FIFO.

- -a

  Include directory entries whose names begin with a dot (`.').

- -l

  List files in the long format, as described in the The Long Format subsection below.

- -1

  Force output to be one entry per line. This is the default when output is not to a terminal.

### EXIT STATUS

The ls utility exits 0 on success, and >0 if an error occurs.



------

### NAME

**mkdir** -- make directories

### SYNOPSIS

```
mkdir [-p] directory ...
```

### DESCRIPTION

The mkdir utility creates the directories named as operands.

The following option is available:

- -p

  Create intermediate directories as required.  If this option is not specified, the full path prefix of each operand must already exist.  On the other hand, with this option specified, no error will be reported if a directory given as an operand already exists.

### EXIT STATUS

The mkdir utility exits 0 on success, and >0 if an error occurs.



------

### NAME

**more** -- file perusal filter for crt viewing.

### SYNOPSIS

```
more [FILE...]
```

### DESCRIPTION

View FILE or standard input one screenful at a time.



------

### NAME

**mv** -- move files

### SYNOPSIS

```
mv source target
```

### DESCRIPTION

The mv utility renames the file named by the *source* operand to the destination path named by the *target* operand. It assumes the last operand does not name an already existing directory.

### EXIT STATUS

The mv utility exits 0 on success, and >0 if an error occurs.



------

### NAME

**nice** -- execute a utility at an altered scheduling priority

### SYNOPSIS

```
nice [ -n increment ] utility [ argument ...]
```

### DESCRIPTION

The nice utility runs utility at an altered scheduling priority, by incrementing its ``nice'' value by the specified increment, or a default value of 10.  The lower the nice value of a process, the higher its scheduling priority.

The superuser may specify a negative increment in order to run a utility with a higher scheduling priority.

### EXIT STATUS

If utility is invoked, the exit status of nice is the exit status of utility. An exit status of 126 indicates utility was found, but could not be executed. An exit status of 127 indicates utility could not be found.



------

### NAME

**printenv** -- display environment variables currently set

### SYNOPSIS

```
printenv [name]
```

### DESCRIPTION

printenv prints out the values of the variables in the environment. If a variable is specified, only its value is printed.



------

### NAME

**ps** -- process status

### SYNOPSIS

```
ps [-lx]
```

### DESCRIPTION

The ps utility displays a header line, followed by lines containing information about all of your processes that have controlling terminals.

- -l

  Display information associated with the following keywords: uid, pid, ppid, pri, stat, pol, time, wchan, state, time, and command.

- -x

  When displaying processes matched by other options, include processes which do not have a controlling terminal.



------

### NAME

**pwd** -- return working directory name

### SYNOPSIS

```
pwd
```

### DESCRIPTION

The pwd utility writes the absolute pathname of the current working     directory to the standard output.

### EXIT STATUS

The pwd utility exits 0 on success, and >0 if an error occurs.



------

### NAME

**rm** -- remove directory entries

### SYNOPSIS

```
rm file...
```

### DESCRIPTION

The rm utility attempts to remove the non-directory type files specified     on the command line.

### EXIT STATUS

The rm utility exits 0 if all of the named files or file hierarchies were removed. If an error occurs, rm exits with a value >0.



------

### NAME

**rmdir** -- remove directories

### SYNOPSIS

```
rmdir dirname...
```

### DESCRIPTION

The rmdir utility removes the directory entry specified by each directory argument, provided it is empty.

### EXIT STATUS

The rmdir utility exits 0 if all of the directories are removed. If an error occurs, rmdir exits with a value >0.



------

### NAME

**sh** -- command interpreter (shell)

### SYNOPSIS

```
sh
```

### DESCRIPTION

The sh utility is the standard command interpreter for the system.



------

### NAME

**sleep** -- suspend execution for an interval of time

### SYNOPSIS

```
sleep seconds
```

### DESCRIPTION

The sleep command suspends execution for a minimum of seconds.

If the sleep command receives a signal, it takes the standard action.

### EXIT STATUS

The sleep utility exits 0 on success, and >0 if an error occurs.



------

### NAME

**sync** -- force completion of pending disk writes (flush cache)

### SYNOPSIS

```
sync
```

### DESCRIPTION

The sync utility can be called to ensure that all disk writes have been completed before the processor is halted in a way not suitably done by reboot.



------

### NAME

**test** -- condition evaluation utility

### SYNOPSIS

```
test expression
```

### DESCRIPTION

The test utility evaluates the expression and, if it evaluates to true, returns a zero (true) exit status; otherwise it returns 1 (false).  If there is no expression, test also returns 1 (false).



------

### NAME

**touch** -- create a file

### SYNOPSIS

```
touch file
```

### DESCRIPTION

The touch utility creates the file if it does not exist.

*NOTE: There is no function to change the modification time of the existing file.*



------

### NAME

**uname** -- display information about the system

### SYNOPSIS

```
uname [-amnpsrv]
```

### DESCRIPTION

The uname command writes the name of the operating system implementation to standard output.  When options are specified, strings representing one or more system characteristics are written to standard output.

​    The options are as follows:

- -a

  Behave as though the options -m, -n, -r, -s, and -v were specified.

- -m

  Write the type of the current hardware platform to standard output.

- -n

  Write the name of the system to standard output.

- -s

  Write the name of the operating system implementation to standard output.

- -r

  Write the current release level of the operating system to standard output.

- -v

  Write the version level of this release of the operating system to standard output.

### EXIT STATUS

The uname utility exits 0 on success, and >0 if an error occurs.


Copyright© 2005-2009 Kohsuke Ohtani