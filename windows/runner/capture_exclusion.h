#ifndef RUNNER_CAPTURE_EXCLUSION_H_
#define RUNNER_CAPTURE_EXCLUSION_H_

#include <windows.h>

// Owner decision 2026-10-29: screen capture of NOVA must be impossible. Every
// top-level NOVA window (the app and each video window) is excluded from
// capture: screenshots (Snipping Tool, Win+Shift+S, PrintScreen), recorders
// (Xbox Game Bar, OBS display/window/game capture) and screen sharing (Teams,
// Discord, Meet) see nothing or black instead of it.
//
// WDA_EXCLUDEFROMCAPTURE (Windows 10 version 2004 and later) removes the
// window from captures; older Windows 10 builds fall back to WDA_MONITOR,
// which shows it black. Returns the affinity applied, or WDA_NONE on failure.
DWORD ExcludeFromCapture(HWND window);

#endif  // RUNNER_CAPTURE_EXCLUSION_H_
