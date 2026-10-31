#include "capture_exclusion.h"

DWORD ProtectFromCapture(HWND window) {
  if (window == nullptr) {
    return WDA_NONE;
  }
  // D-188: black in every capture (not excluded, which showed the screen
  // behind the app).
  if (::SetWindowDisplayAffinity(window, WDA_MONITOR)) {
    return WDA_MONITOR;
  }
  return WDA_NONE;
}
