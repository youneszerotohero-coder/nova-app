#ifndef RUNNER_NOVA_PLATFORM_H_
#define RUNNER_NOVA_PLATFORM_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <memory>

#include "protected_player.h"

namespace nova {

// The Windows side of the app's own platform channels, the same names as
// Android/iPhone (MainActivity.kt, AppDelegate.swift):
//
//   nova/chime       play            the Windows notification sound
//   nova/screen      keepOn(bool)    the display stays on while a video plays
//                    fullscreen(bool) the player's full screen: the window
//                                    covers its monitor, without its frame
//   nova/app_update  version         {version: "X.Y.Z+build"} of this build
//   nova/drm, nova/protected_player  see protected_player.h
class NovaPlatform {
 public:
  NovaPlatform(flutter::BinaryMessenger* messenger, HWND main_window,
               HWND view_window);
  ~NovaPlatform();

  NovaPlatform(const NovaPlatform&) = delete;
  NovaPlatform& operator=(const NovaPlatform&) = delete;

  // Every message of the app's top-level window (move, resize, minimize,
  // z-order) keeps the video windows under their place in the app.
  void OnTopLevelMessage(UINT message, WPARAM wparam, LPARAM lparam);

 private:
  using Channel = flutter::MethodChannel<flutter::EncodableValue>;

  void SetFullscreen(bool on);

  HWND main_window_;
  bool fullscreen_ = false;
  LONG_PTR saved_style_ = 0;
  WINDOWPLACEMENT saved_placement_{};

  std::unique_ptr<Channel> chime_;
  std::unique_ptr<Channel> screen_;
  std::unique_ptr<Channel> update_;
  std::unique_ptr<ProtectedPlayback> playback_;
};

}  // namespace nova

#endif  // RUNNER_NOVA_PLATFORM_H_
