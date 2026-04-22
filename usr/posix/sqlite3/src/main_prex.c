#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/prex.h>
#include "sqlite3.h"

extern int sqlite3_shell_main(int argc, char **argv);

int main(int argc, char **argv)
{
    int rc;
    if (argc > 1 && strcmp(argv[1], "-t") == 0) {
        char *new_argv[4];
        new_argv[0] = argv[0];
        new_argv[1] = (argc > 2) ? argv[2] : "test.db";
        new_argv[2] = "CREATE TABLE student(id INT, name TEXT); INSERT INTO student VALUES(1, 'prex'); INSERT INTO student VALUES(99, 'test'); SELECT * FROM student;";
        new_argv[3] = NULL;
        printf("Running Prex SQLite3 hardcoded test on %s...\n", new_argv[1]);
        rc = sqlite3_shell_main(3, new_argv);
        task_terminate(task_self());
    }
    rc = sqlite3_shell_main(argc, argv);
    task_terminate(task_self());
    return rc;
}
