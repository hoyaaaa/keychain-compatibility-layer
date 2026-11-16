#include <fcntl.h>
#include <stdlib.h>
#include <unistd.h>
__attribute__((constructor)) static void probe(void) {
    const char *marker=getenv("KCL_PROBE_MARKER");
    if (!marker) return;
    int fd=open(marker,O_WRONLY|O_CREAT|O_EXCL,0600);
    if(fd>=0){write(fd,"loaded\n",7);close(fd);}
    _exit(0);
}
