# Prex Sample Applications

### Table of Contents

- [Introduction](#introduction)
- [Hello World](#hello-world)
- [Alarm Timer](#alarm-timer)
- [Moving Balls](moving-balls)
- [Thread Benchmark](#thread-benchmark)
- [IPC Transmission](#ipc-transmission)
- [Task Creation](#task-creation)
- [Thread Creation](#thread-creation)
- [Mutex](#mutex)
- [Semaphore](#semaphore)
- [CPU Voltage Monitor](#cpu-voltage-monitor)



## Introduction

Prex includes a number of sample programs for using Prex application interface. The source code for these programs are generally found in /usr/sample directory of the Prex distribution.

This document describes the purpose and the screenshot for each sample program.

## Hello World

- Task Type: UNIX Process
- Source Code Directory: /usr/sample/hello
- Description: A simple program to print "Hello World!"

```
[prex:/boot]# hello
Hello World!
[prex:/boot]#
```

## Alarm Timer

- Task Type: Real-time Task
- Source Code Directory: /usr/sample/alarm
- Description: A sample program to install an alarm handler and to program an alarm timer.

```
Alarm sample program
Start alarm timer
Ring! count=1 time=1000 msec
Ring! count=2 time=1200 msec
Ring! count=3 time=1600 msec
Ring! count=4 time=2200 msec
Ring! count=5 time=3000 msec
Ring! count=6 time=4000 msec
Ring! count=7 time=5200 msec
Ring! count=8 time=6600 msec
Ring! count=9 time=8200 msec
Ring! count=10 time=10000 msec
End...
```

## Moving Balls

- Task Type: Real-time Task
- Source Code Directory: /usr/sample/balls
- Description: A program to create many threads. Each thread displays one ball and moves it in the screen.

```
                                        *                            *
                           *
                *
                                                              *
                                                         *

                                                       *  *


                                                                *           *
   *                                                        **

                *                  *                     *
                                                                    *    *
                    *
      *
                                       *

                             *                                 *

              *
                       *
                 *    *   *                           *
```

## Thread Benchmark

- Task Type: Real-time Task
- Source Code Directory: /usr/sample/bench
- Description: A benchmark program for running many threads

```
Benchmark to create/terminate 100000 threads
Complete. The score is 612 msec (612 ticks).
```

## IPC Transmission

- Task Type: Real-time Task
- Source Code Directory: /usr/sample/ipc
- Description: A sample program for IPC message transmission

```
IPC sample program
Client is started
server: Received "Hello!"
client: Received "Hi."
server: Received "This is a client task."
client: Received "OK."
server: Received "Who are you?"
client: Received "OK."
server: Received "How are you?"
client: Received "OK."
server: Received "...."
client: Received "OK."
server: Received "Bye!"
client: Received "Bye."
server: Received "Exit"
client: Received "OK."
Exit client task...
End...
```

## Task Creation

- Task Type: Real-time Task
- Source Code Directory: /usr/sample/task
- Description: A sample program to run tasks

```
Task sample program
Task 8000abc4: Hey, Yo!
Task 8000ae24: Hey, Yo!
Task 80027714: Hey, Yo!
Task 80027c44: Hey, Yo!
Task 80027ea4: Hey, Yo!
Task 80037744: Hey, Yo!
Task 80037cb4: Hey, Yo!
Task 80037f14: Hey, Yo!
Task 800477a4: Hey, Yo!
Task 80047d14: Hey, Yo!
Task 8000abc4: Bye!
Task 8000ae24: Bye!
Task 80027714: Bye!
Task 80027c44: Bye!
Task 80027ea4: Bye!
Task 80037744: Bye!
Task 80037cb4: Bye!
Task 80037f14: Bye!
Task 800477a4: Bye!
Task 80047d14: Bye!
```

## Thread Creation

- Task Type: Real-time Task
- Source Code Directory: /usr/sample/thread
- Description: A sample program to create three threads

```
Thread sample program

thread A is starting
A
thread B is starting
B
thread C is starting
CAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB
BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB
BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB
BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC
CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC
CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC
CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABBBBBBBBBBBBBCCCCCCCCCCCCCCAAA
```

## Mutex

- Task Type: Real-time Task
- Source Code Directory: /usr/sample/mutex
- Description: A sample program for mutex with priority inheritance

```
Senario:

 This sample shows how the mutex priority is changed when three different threads
 lock two mutexes at same time.

 The priority of each thread are as follows:
    Thread1 - priority 100 (highest)
    Thread2 - priority 101
    Thread3 - priority 102

Thread priority and state are changed as follows:

   Action                    Thread 1  Thread 2  Thread 3  Mutex A  Mutex B
   ------------------------  --------  --------  --------  -------  -------
1) Thread 3 locks mutex A    susp/100  susp/101  run /102  owner=3
2) Thread 2 locks mutex B    susp/100  run /101  run /102  owner=3  owner=2
3) Thread 2 locks mutex A    susp/100  wait/101  run /101* owner=3  owner=2
4) Thread 1 locks mutex B    wait/100  wait/100* run /100* owner=3  owner=2
5) Thread 3 unlocks mutex A  wait/100  run /100  run /102* owner=2* owner=2
6) Thread 2 unlocks mutex B  run /100* run /100  run /102  owner=2  owner=1*
7) Thread 2 unlocks mutex A  run /100  run /100  run /102           owner=1
8) Thread 1 unlocks mutex B  wait/100  run /101  run /102
Mutex sample program
th_1: prio=100
th_2: prio=101
th_3: prio=102
thread_3: start
thread_3: 1) lock A
th_1: prio=100
th_2: prio=101
th_3: prio=102
thread_2: starting
thread_2: 2) lock B
th_1: prio=100
th_2: prio=100
th_2: prio=101
th_3: prio=102
thread_2: 3) lock A
thread_3: running-1
th_1: prio=100
th_2: prio=101
th_3: prio=101
thread_1: starting
thread_1: 4) lock B
thread_3: running-2
th_1: prio=100
th_2: prio=100
```

## Semaphore

- Task Type: Real-time Task
- Source Code Directory: /usr/sample/sem
- Description: A sample program for semaphore. This sample demonstrates that 10 threads try to aquire one semaphore which has initial sempaphore count = 3.

```
Semaphore sample program
Start thread=8000abf4
Start thread=8001e014
Start thread=8001e404
Start thread=8001e7f4
Start thread=8001ebe4
Start thread=8001f014
Start thread=8001f404
Start thread=8001f7f4
Start thread=8001fbe4
Start thread=80020014
Running thread=8000abf4
Running thread=8001e014
Running thread=8001e404
Running thread=8001e7f4
End thread=8000abf4
Running thread=8001ebe4
End thread=8001e014
Running thread=8001f014
End thread=8001e404
Running thread=8001f404
End thread=8001e7f4
Running thread=8001f7f4
End thread=8001ebe4
Running thread=8001fbe4
```

## CPU Voltage Monitor

- Task Type: Real-time Task
- Source Code Directory: /usr/sample/cpumon
- Description: CPU voltage monitoring program

```
CPU voltage monitor
Speed:  600MHz  0|********------------|100
Power:  956mV   0|*************-------|100
```



Copyright© 2005-2009 Kohsuke Ohtani
