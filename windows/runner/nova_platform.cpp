#include "nova_platform.h"

#include <flutter/standard_method_codec.h>
#include <mmsystem.h>

#include <string>

#ifndef FLUTTER_VERSION
#define FLUTTER_VERSION ""
#endif

namespace nova {

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;

const flutter::StandardMethodCodec& Codec() {
  return flutter::StandardMethodCodec::GetInstance();
}

}  // namespace

NovaPlatform::NovaPlatform(flutter::BinaryMessenger* messenger,
                           HWND main_window,
                           HWND view_window)
    : main_window_(main_window) {
  chime_ = std::make_unique<Channel>(messenger, "nova/chime", &Codec());
  chime_->SetMethodCallHandler(
      [](const flutter::MethodCall<EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
        if (call.method_name() != "play") {
          result->NotImplemented();
          return;
        }
        // The user's "Notification" sound; silent when they turned it off.
        const BOOL played = ::PlaySoundW(L"Notification.Default", nullptr,
                                         SND_ALIAS | SND_ASYNC | SND_NODEFAULT);
        result->Success(EncodableValue(played != FALSE));
      });

  screen_ = std::make_unique<Channel>(messenger, "nova/screen", &Codec());
  screen_->SetMethodCallHandler(
      [this](const flutter::MethodCall<EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
        const auto* on = std::get_if<bool>(call.arguments());
        if (call.method_name() == "fullscreen") {
          SetFullscreen(on != nullptr && *on);
          result->Success();
          return;
        }
        if (call.method_name() != "keepOn") {
          result->NotImplemented();
          return;
        }
        // D-133 on PC: neither the screen saver nor display sleep while a
        // video plays; the normal timers again once it stops.
        ::SetThreadExecutionState(
            on != nullptr && *on
                ? ES_CONTINUOUS | ES_DISPLAY_REQUIRED | ES_SYSTEM_REQUIRED
                : ES_CONTINUOUS);
        result->Success();
      });

  update_ = std::make_unique<Channel>(messenger, "nova/app_update", &Codec());
  update_->SetMethodCallHandler(
      [](const flutter::MethodCall<EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
        if (call.method_name() != "version") {
          result->NotImplemented();
          return;
        }
        result->Success(EncodableValue(EncodableMap{
            {EncodableValue("version"), EncodableValue(std::string(FLUTTER_VERSION))},
        }));
      });

  playback_ = std::make_unique<ProtectedPlayback>(messenger, main_window,
                                                  view_window);
}

NovaPlatform::~NovaPlatform() {
  chime_->SetMethodCallHandler(nullptr);
  screen_->SetMethodCallHandler(nullptr);
  update_->SetMethodCallHandler(nullptr);
  ::SetThreadExecutionState(ES_CONTINUOUS);
  playback_ = nullptr;
}

void NovaPlatform::SetFullscreen(bool on) {
  if (main_window_ == nullptr || on == fullscreen_) {
    return;
  }
  if (on) {
    saved_style_ = ::GetWindowLongPtrW(main_window_, GWL_STYLE);
    saved_placement_.length = sizeof(WINDOWPLACEMENT);
    ::GetWindowPlacement(main_window_, &saved_placement_);
    MONITORINFO monitor{};
    monitor.cbSize = sizeof(MONITORINFO);
    if (!::GetMonitorInfoW(
            ::MonitorFromWindow(main_window_, MONITOR_DEFAULTTONEAREST),
            &monitor)) {
      return;
    }
    ::SetWindowLongPtrW(main_window_, GWL_STYLE,
                        saved_style_ & ~static_cast<LONG_PTR>(WS_OVERLAPPEDWINDOW));
    ::SetWindowPos(main_window_, HWND_TOP, monitor.rcMonitor.left,
                   monitor.rcMonitor.top,
                   monitor.rcMonitor.right - monitor.rcMonitor.left,
                   monitor.rcMonitor.bottom - monitor.rcMonitor.top,
                   SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
  } else {
    ::SetWindowLongPtrW(main_window_, GWL_STYLE, saved_style_);
    ::SetWindowPlacement(main_window_, &saved_placement_);
    ::SetWindowPos(main_window_, nullptr, 0, 0, 0, 0,
                   SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOOWNERZORDER |
                       SWP_FRAMECHANGED);
  }
  fullscreen_ = on;
}

void NovaPlatform::OnTopLevelMessage(UINT message, WPARAM wparam,
                                     LPARAM lparam) {
  if (playback_) {
    playback_->OnTopLevelMessage(message, wparam, lparam);
  }
}

}  // namespace nova
