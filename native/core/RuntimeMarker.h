#include <sys/stat.h>
#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>
#include <fcntl.h>
#include <limits.h>

static void KCLMarkLoaded(void) {
    const char *home = getenv("HOME");
    if (!home) return;
    char directory[PATH_MAX], marker[PATH_MAX];
    int n = snprintf(directory,sizeof(directory),"%s/Library/Application Support/Keychain Compatibility Layer",home);
    if (n < 0 || (size_t)n >= sizeof(directory)) return;
    mkdir(directory,0700);
    n = snprintf(directory,sizeof(directory),"%s/Library/Application Support/Keychain Compatibility Layer/runtime",home);
    if (n < 0 || (size_t)n >= sizeof(directory)) return;
    mkdir(directory,0700);
    n = snprintf(marker,sizeof(marker),"%s/%d.loaded",directory,getpid());
    if (n < 0 || (size_t)n >= sizeof(marker)) return;
    int fd = open(marker,O_CREAT|O_WRONLY|O_TRUNC|O_NOFOLLOW,0600);
    if (fd >= 0) { write(fd,"loaded\n",7); close(fd); }
}
