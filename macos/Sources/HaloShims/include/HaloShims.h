#ifndef HALO_SHIMS_H
#define HALO_SHIMS_H

#include <sys/types.h>

/// Brings the process to the front as if the user had clicked it (SetFrontProcessWithOptions with
/// kSetFrontProcessCausedByUser). Fallback for apps that ignore NSRunningApplication.activate under
/// cooperative activation. Returns 0 on success, an OSStatus otherwise.
int halo_set_front_process(pid_t pid);

#endif
