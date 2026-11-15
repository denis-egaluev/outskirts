#include <stdio.h>

// Glibc declares stdout and stderr as mutable globals, which Swift 6 rejects; these accessors are the same on every platform.
static inline FILE *periphery_stdout(void) { return stdout; }
static inline FILE *periphery_stderr(void) { return stderr; }

#if defined(__linux__)
#include <fcntl.h>
// Glibc declares pipe2 only under _GNU_SOURCE, which Swift does not define.
int pipe2(int pipefd[2], int flags);
static inline int outskirts_pipe_cloexec(int fds[2]) { return pipe2(fds, O_CLOEXEC); }
#endif
