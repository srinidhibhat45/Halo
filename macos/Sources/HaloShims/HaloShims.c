#include "HaloShims.h"
#include <ApplicationServices/ApplicationServices.h>

// These Process Manager calls are deprecated and unavailable to Swift, but still the only way to
// front another app on the user's behalf from a background agent.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
int halo_set_front_process(pid_t pid) {
    ProcessSerialNumber psn = {0, 0};
    OSStatus status = GetProcessForPID(pid, &psn);
    if (status != noErr) return (int)status;
    return (int)SetFrontProcessWithOptions(&psn, kSetFrontProcessCausedByUser);
}
#pragma clang diagnostic pop
