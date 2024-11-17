/*
 * Compile with:
 *
 * clang  fopenn.c -o frida-core-example -L. -lfrida-core -lbsm -ldl
 * -lm -lresolv
 * -Wl,-framework,Foundation,-framework,CoreGraphics,-framework,UIKit
 *
 * Visit https://frida.re to learn more about Frida.
 */
#include <stdio.h>
#include <stdlib.h>
#include <spawn.h>
#include <sys/types.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>

extern char **environ;

void spawn_process(const char *path, char *const argv[], char *const envp[]) {
    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
    posix_spawnattr_setflags(&attr, POSIX_SPAWN_START_SUSPENDED);

    pid_t pid;
    int status = posix_spawn(&pid, path, NULL, &attr, argv, envp);
    if (status == 0) {
        printf("Spawned process with PID: %d\n", pid);
        // Resume the process if needed
        // kill(pid, SIGCONT);
    } else {
        fprintf(stderr, "posix_spawn failed: %s\n", strerror(status));
    }

    posix_spawnattr_destroy(&attr);
}

int main(int argc, char *argv[]) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <program> [args...]\n", argv[0]);
        return 1;
    }

    char *const prog_argv[] = {argv[1], NULL};
    spawn_process(argv[1], prog_argv, environ);

    return 0;
}
