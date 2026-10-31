#ifndef RUNNER_CAPTURE_EXCLUSION_H_
#define RUNNER_CAPTURE_EXCLUSION_H_

#include <windows.h>

// Owner decision 2026-10-29: screen capture of NOVA must be impossible. Every
// top-level NOVA window (the app and each video window) is protected from
// capture: screenshots (Snipping Tool, Win+Shift+S, PrintScreen), recorders
// (Xbox Game Bar, OBS display/window/game capture) and screen sharing (Teams,
// Discord, Meet).
//
// D-188 (owner decision 2026-10-31): a capture shows the NOVA window as a
// BLACK rectangle. WDA_MONITOR (Windows 7 and later) does exactly that.
// WDA_EXCLUDEFROMCAPTURE is no longer used: it removed the window from
// captures, so the capture showed whatever was behind the app instead.
//
// Display affinity applies to top-level windows only; the Flutter view and
// the WebView2 of a video window are child windows and are covered by their
// top-level window. Returns the affinity applied, or WDA_NONE on failure
// (e.g. desktop composition off, very old Windows).
DWORD ProtectFromCapture(HWND window);

#endif  // RUNNER_CAPTURE_EXCLUSION_H_
