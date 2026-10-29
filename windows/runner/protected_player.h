#ifndef RUNNER_PROTECTED_PLAYER_H_
#define RUNNER_PROTECTED_PLAYER_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/event_channel.h>
#include <flutter/method_channel.h>
#include <windows.h>
#include <wrl.h>

#pragma warning(push, 0)
#include <WebView2.h>
#pragma warning(pop)

#include <functional>
#include <map>
#include <memory>
#include <optional>
#include <string>
#include <vector>

namespace nova {

class ProtectedPlayback;

// One video (Lesson, Replay or Live), the Windows counterpart of Android's
// ProtectedPlayerView.kt. Flutter on Windows has no platform views and a
// PlayReady picture cannot be copied into a Flutter texture, so the video
// plays in its own borderless window: a WebView2 (Edge's PlayReady CDM,
// Shaka Player, windows/runner/player) placed exactly under a transparent
// hole that the Flutter page leaves in its player box, directly behind the
// app window. The Flutter controls and the moving watermark are drawn over
// it by the app, as on the phone. The window is excluded from capture.
//
// Control arrives on `nova/protected_player_<id>` (play, pause, seekTo,
// seekToLiveEdge, setSpeed, setVolume, setQuality, renewToken, release, and
// setRect on Windows), state leaves on `nova/protected_player_<id>/events`
// as JSON strings (state, playing, position, firstFrame, tracks, error, drm).
class VideoWindow {
 public:
  // [probe]: a hidden window that only reports the PC's PlayReady level.
  VideoWindow(ProtectedPlayback* owner, int64_t id, std::string params_json,
              bool probe);
  ~VideoWindow();

  VideoWindow(const VideoWindow&) = delete;
  VideoWindow& operator=(const VideoWindow&) = delete;

  bool Create();
  void Attach(ICoreWebView2Environment* environment, HRESULT error);

  // Where the hole is, in physical pixels of the Flutter view.
  void SetRect(const RECT& rect, bool visible);

  // Follows the app window: position, clip, z-order, minimized.
  void Place();

  // Stops the video now and destroys the window a moment later, once the
  // Flutter page no longer shows the hole.
  void Close();

  int64_t id() const { return id_; }
  bool probe() const { return probe_; }

 private:
  static LRESULT CALLBACK WndProc(HWND window, UINT message, WPARAM wparam,
                                  LPARAM lparam);

  void Configure();
  void OnWebMessage(const std::wstring& message);
  void OnMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void Run(const std::wstring& script);
  void Emit(const std::string& json);
  void Fail(const char* category, const char* message);
  void Resize();

  ProtectedPlayback* owner_;
  int64_t id_;
  std::string params_json_;
  bool probe_;
  std::shared_ptr<int> life_ = std::make_shared<int>(0);

  HWND window_ = nullptr;
  Microsoft::WRL::ComPtr<ICoreWebView2Controller> controller_;
  Microsoft::WRL::ComPtr<ICoreWebView2> webview_;
  bool page_ready_ = false;
  bool closing_ = false;
  std::vector<std::wstring> pending_scripts_;

  RECT rect_{};
  bool has_rect_ = false;
  bool visible_ = false;
  RECT clip_{};
  bool clipped_ = false;

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> methods_;
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>> events_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> sink_;
  std::vector<std::string> pending_events_;
};

// Registers `nova/protected_player` (create) and `nova/drm`
// (playreadyLevel: "SL3000", "SL2000" or null, like Android's widevineLevel)
// and owns the shared WebView2 environment and every video window.
class ProtectedPlayback {
 public:
  ProtectedPlayback(flutter::BinaryMessenger* messenger, HWND main_window,
                    HWND view_window);
  ~ProtectedPlayback();

  ProtectedPlayback(const ProtectedPlayback&) = delete;
  ProtectedPlayback& operator=(const ProtectedPlayback&) = delete;

  void OnTopLevelMessage(UINT message, WPARAM wparam, LPARAM lparam);

  flutter::BinaryMessenger* messenger() const { return messenger_; }
  HWND main_window() const { return main_window_; }
  HWND view_window() const { return view_window_; }

  // Called by the video windows.
  void Remove(VideoWindow* window);
  // [definitive]: the probe answered (or WebView2 is missing); a timeout is
  // not kept, so the next video asks again.
  void ProbeFinished(const std::string& level, bool definitive);
  void HardwareFailed() { hardware_failed_ = true; }
  static std::wstring PlayerFolder();

 private:
  using Environment = std::function<void(ICoreWebView2Environment*, HRESULT)>;

  void WithEnvironment(Environment ready);
  void Create(const flutter::EncodableValue* arguments,
              std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void PlayReadyLevel(
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void AnswerLevel();
  void UpdateTransparency();

  flutter::BinaryMessenger* messenger_;
  HWND main_window_;
  HWND view_window_;
  std::shared_ptr<int> life_ = std::make_shared<int>(0);

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> drm_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> players_channel_;

  Microsoft::WRL::ComPtr<ICoreWebView2Environment> environment_;
  HRESULT environment_error_ = S_OK;
  std::vector<Environment> environment_waiters_;

  std::map<int64_t, std::unique_ptr<VideoWindow>> players_;
  int64_t next_id_ = 1;
  bool transparent_ = false;

  std::unique_ptr<VideoWindow> probe_;
  std::vector<std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>>
      level_waiters_;
  std::optional<std::string> level_;
  bool probe_running_ = false;
  bool hardware_failed_ = false;
};

}  // namespace nova

#endif  // RUNNER_PROTECTED_PLAYER_H_
