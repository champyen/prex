/*
 * Iterative find for Prex to save file descriptors.
 */

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>
#include <sys/param.h>
#include <sys/stat.h>
#include <unistd.h>
#include <time.h>

#ifdef CMDBOX
#define main(argc, argv) find_main(argc, argv)
#endif

#define MAX_DEPTH 16
#define EQ(x, y) (strcmp(x, y) == 0)

static char Pathname[MAXPATHLEN + 1];
static struct stat Statb;
static long Now;

struct predicate {
    int (*func)(char *path, struct stat *st, void *arg);
    void *arg;
};

static int print_pred(char *path, struct stat *st, void *arg) {
    puts(path);
    return 1;
}

static int name_pred(char *path, struct stat *st, void *arg) {
    char *name = strrchr(path, '/');
    if (name) name++; else name = path;
    /* Simple exact match for now */
    return strcmp(name, (char *)arg) == 0;
}

static void find_path(char *start_path, struct predicate *preds, int npreds) {
    char *stack[MAX_DEPTH];
    int depth = 0;
    DIR *dir;
    struct dirent *entry;
    char current_full[MAXPATHLEN + 1];
    struct stat st;

    stack[depth++] = strdup(start_path);

    while (depth > 0) {
        char *path = stack[--depth];
        
        if (lstat(path, &st) < 0) {
            free(path);
            continue;
        }

        /* Apply predicates */
        int match = 1;
        for (int i = 0; i < npreds; i++) {
            if (!preds[i].func(path, &st, preds[i].arg)) {
                match = 0;
                break;
            }
        }
        /* Default print if match and no explicit print? 
           Original find is more complex, we just print if it's the only predicate. */
        if (npreds == 0) puts(path);

        if (S_ISDIR(st.st_mode)) {
            if ((dir = opendir(path)) != NULL) {
                while ((entry = readdir(dir)) != NULL) {
                    if (EQ(entry->d_name, ".") || EQ(entry->d_name, ".."))
                        continue;
                    
                    if (depth < MAX_DEPTH) {
                        int plen = strlen(path);
                        int elen = strlen(entry->d_name);
                        if (plen + elen + 2 <= MAXPATHLEN) {
                            char *new_path = malloc(plen + elen + 2);
                            strcpy(new_path, path);
                            if (new_path[plen-1] != '/') strcat(new_path, "/");
                            strcat(new_path, entry->d_name);
                            stack[depth++] = new_path;
                        }
                    }
                }
                closedir(dir);
            }
        }
        free(path);
    }
}

int main(int argc, char **argv) {
    struct predicate preds[10];
    int npreds = 0;
    int paths_end = 1;

    time(&Now);

    if (argc < 2) {
        fprintf(stderr, "usage: find path [predicates]\n");
        return 1;
    }

    /* Find where predicates start */
    for (int i = 1; i < argc; i++) {
        if (argv[i][0] == '-') {
            paths_end = i;
            break;
        }
        paths_end = i + 1;
    }

    /* Parse predicates (very limited) */
    for (int i = paths_end; i < argc; i++) {
        if (EQ(argv[i], "-print")) {
            preds[npreds].func = print_pred;
            preds[npreds++].arg = NULL;
        } else if (EQ(argv[i], "-name") && i + 1 < argc) {
            preds[npreds].func = name_pred;
            preds[npreds++].arg = argv[++i];
        }
    }

    for (int i = 1; i < paths_end; i++) {
        find_path(argv[i], preds, npreds);
    }

    return 0;
}
