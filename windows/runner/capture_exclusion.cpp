#include "capture_exclusion.h"

#ifndef WDA_EXCLUDEFROMCAPTURE
#define WDA_EXCLUDEFROMCAPTURE 0x00000011
#endif

DWORD ExcludeFromCapture(HWND window) {
  if (window == nullptr) {
    return WDA_NONE;
  }
  if (::SetWindowDisplayAffinity(window, WDA_EXCLUDEFROMCAPTURE)) {
    return WDA_EXCLUDEFROMCAPTURE;
  }
  if (::SetWindowDisplayAffinity(window, WDA_MONITOR)) {
    return WDA_MONITOR;
  }
  return WDA_NONE;
}
