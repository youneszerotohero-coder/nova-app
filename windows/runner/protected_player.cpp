#include "protected_player.h"

#include <dwmapi.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/standard_method_codec.h>
#include <knownfolders.h>
#include <shlobj.h>

#include <set>
#include <utility>

#include "capture_exclusion.h"
#include "json_writer.h"

namespace nova {

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;
using flutter::MethodCall;
using flutter::MethodResult;
using Microsoft::WRL::Callback;
using Microsoft::WRL::ComPtr;

constexpr wchar_t kWindowClass[] = L"NOVA_VIDEO_WINDOW";

// The player page is served from the app's own folder under this name
// (WebView2 virtual host: https, a secure context for EME). Nothing else is
// ever loaded: every other navigation is cancelled.
constexpr wchar_t kHost[] = L"player.nova-app.example";
constexpr wchar_t kOrigin[] = L"https://player.nova-app.example/";
constexpr wchar_t kPage[] = L"https://player.nova-app.example/index.html";

constexpr UINT_PTR kCloseTimer = 1;
constexpr UINT_PTR kProbeTimer = 2;
// A released video window lives on until the Flutter page has repainted
// without its hole (a few frames), so the hole never shows the desktop.
constexpr UINT kCloseDelayMs = 250;
// A first WebView2 start on a slow PC can take seconds; past this the
// level is unknown for now and asked again next time.
constexpr UINT kProbeTimeoutMs = 25000;

const flutter::StandardMethodCodec& Codec() {
  return flutter::StandardMethodCodec::GetInstance();
}

bool StartsWith(const std::wstring& text, const wchar_t* prefix) {
  return text.rfind(prefix, 0) == 0;
}

double Number(const EncodableMap& map, const char* key) {
  const auto found = map.find(EncodableValue(key));
  if (found == map.end()) {
    return 0;
  }
  if (const auto* real = std::get_if<double>(&found->second)) {
    return *real;
  }
  if (const auto* small = std::get_if<int32_t>(&found->second)) {
    return static_cast<double>(*small);
  }
  if (const auto* large = std::get_if<int64_t>(&found->second)) {
    return static_cast<double>(*large);
  }
  return 0;
}

bool Flag(const EncodableMap& map, const char* key) {
  const auto found = map.find(EncodableValue(key));
  if (found == map.end()) {
    return false;
  }
  const auto* flag = std::get_if<bool>(&found->second);
  return flag != nullptr && *flag;
}

LONG Pixels(double value) {
  return static_cast<LONG>(value < 0 ? value - 0.5 : value + 0.5);
}

void RegisterWindowClass(WNDPROC procedure) {
  static bool registered = false;
  if (registered) {
    return;
  }
  WNDCLASSEXW window_class{};
  window_class.cbSize = sizeof(window_class);
  window_class.lpfnWndProc = procedure;
  window_class.hInstance = ::GetModuleHandleW(nullptr);
  window_class.hCursor = ::LoadCursorW(nullptr, IDC_ARROW);
  window_class.hbrBackground = static_cast<HBRUSH>(::GetStockObject(BLACK_BRUSH));
  window_class.lpszClassName = kWindowClass;
  registered = ::RegisterClassExW(&window_class) != 0;
}

std::wstring UserDataFolder() {
  PWSTR local = nullptr;
  std::wstring folder;
  if (SUCCEEDED(::SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr,
                                       &local)) &&
      local != nullptr) {
    folder = std::wstring(local) + L"\\NOVA\\WebView2";
  }
  if (local != nullptr) {
    ::CoTaskMemFree(local);
  }
  return folder;
}

}  // namespace

// VideoWindow ---------------------------------------------------------------

VideoWindow::VideoWindow(ProtectedPlayback* owner, int64_t id,
                         std::string params_json, bool probe)
    : owner_(owner),
      id_(id),
      params_json_(std::move(params_json)),
      probe_(probe) {
  if (probe_) {
    return;
  }
  const std::string name = "nova/protected_player_" + std::to_string(id_);
  methods_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      owner_->messenger(), name, &Codec());
  methods_->SetMethodCallHandler(
      [this](const MethodCall<EncodableValue>& call,
             std::unique_ptr<MethodResult<EncodableValue>> result) {
        OnMethodCall(call, std::move(result));
      });
  events_ = std::make_unique<flutter::EventChannel<EncodableValue>>(
      owner_->messenger(), name + "/events", &Codec());
  events_->SetStreamHandler(
      std::make_unique<flutter::StreamHandlerFunctions<EncodableValue>>(
          [this](const EncodableValue* arguments,
                 std::unique_ptr<flutter::EventSink<EncodableValue>>&& sink)
              -> std::unique_ptr<flutter::StreamHandlerError<EncodableValue>> {
            sink_ = std::move(sink);
            for (const std::string& event : pending_events_) {
              sink_->Success(EncodableValue(event));
            }
            pending_events_.clear();
            return nullptr;
          },
          [this](const EncodableValue* arguments)
              -> std::unique_ptr<flutter::StreamHandlerError<EncodableValue>> {
            sink_.reset();
            return nullptr;
          }));
}

VideoWindow::~VideoWindow() {
  life_.reset();
  if (methods_) {
    methods_->SetMethodCallHandler(nullptr);
  }
  if (events_) {
    events_->SetStreamHandler(nullptr);
  }
  sink_.reset();
  if (controller_) {
    controller_->Close();
  }
  webview_.Reset();
  controller_.Reset();
  if (window_ != nullptr) {
    ::KillTimer(window_, kCloseTimer);
    ::KillTimer(window_, kProbeTimer);
    ::SetWindowLongPtrW(window_, GWLP_USERDATA, 0);
    ::DestroyWindow(window_);
    window_ = nullptr;
  }
}

bool VideoWindow::Create() {
  RegisterWindowClass(VideoWindow::WndProc);
  // A borderless tool window: no taskbar button, no Alt+Tab entry, never
  // activated. It stays hidden until the Flutter page says where it goes.
  window_ = ::CreateWindowExW(WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE, kWindowClass,
                              L"NOVA", WS_POPUP | WS_CLIPCHILDREN, 0, 0, 16, 16,
                              nullptr, nullptr, ::GetModuleHandleW(nullptr),
                              this);
  if (window_ == nullptr) {
    return false;
  }
  ExcludeFromCapture(window_);
  if (probe_) {
    ::SetTimer(window_, kProbeTimer, kProbeTimeoutMs, nullptr);
  }
  return true;
}

void VideoWindow::Attach(ICoreWebView2Environment* environment, HRESULT error) {
  if (closing_ || window_ == nullptr) {
    return;
  }
  if (environment == nullptr || FAILED(error)) {
    // No WebView2 runtime: the installer normally adds it (Evergreen).
    Fail("capability", "WEBVIEW2_UNAVAILABLE");
    return;
  }
  std::weak_ptr<int> life = life_;
  const HRESULT started = environment->CreateCoreWebView2Controller(
      window_,
      Callback<ICoreWebView2CreateCoreWebView2ControllerCompletedHandler>(
          [this, life](HRESULT result,
                       ICoreWebView2Controller* controller) -> HRESULT {
            if (life.expired()) {
              if (controller != nullptr) {
                controller->Close();
              }
              return S_OK;
            }
            if (FAILED(result) || controller == nullptr) {
              Fail("capability", "WEBVIEW2_CONTROLLER");
              return S_OK;
            }
            controller_ = controller;
            if (FAILED(controller_->get_CoreWebView2(&webview_)) ||
                webview_ == nullptr) {
              Fail("capability", "WEBVIEW2_CONTROLLER");
              return S_OK;
            }
            Configure();
            return S_OK;
          })
          .Get());
  if (FAILED(started)) {
    Fail("capability", "WEBVIEW2_CONTROLLER");
  }
}

void VideoWindow::Configure() {
  ComPtr<ICoreWebView2Settings> settings;
  if (SUCCEEDED(webview_->get_Settings(&settings)) && settings != nullptr) {
    settings->put_AreDefaultContextMenusEnabled(FALSE);
    settings->put_AreDefaultScriptDialogsEnabled(FALSE);
    settings->put_IsStatusBarEnabled(FALSE);
    settings->put_IsZoomControlEnabled(FALSE);
    settings->put_IsBuiltInErrorPageEnabled(FALSE);
#ifdef NDEBUG
    settings->put_AreDevToolsEnabled(FALSE);
#endif
    ComPtr<ICoreWebView2Settings3> keys;
    if (SUCCEEDED(settings.As(&keys))) {
      keys->put_AreBrowserAcceleratorKeysEnabled(FALSE);
    }
  }
  ComPtr<ICoreWebView2Controller2> colors;
  if (SUCCEEDED(controller_.As(&colors))) {
    colors->put_DefaultBackgroundColor(COREWEBVIEW2_COLOR{255, 0, 0, 0});
  }

  ComPtr<ICoreWebView2_3> hosting;
  if (FAILED(webview_.As(&hosting)) ||
      FAILED(hosting->SetVirtualHostNameToFolderMapping(
          kHost, ProtectedPlayback::PlayerFolder().c_str(),
          COREWEBVIEW2_HOST_RESOURCE_ACCESS_KIND_DENY_CORS))) {
    Fail("capability", "WEBVIEW2_TOO_OLD");
    return;
  }

  std::weak_ptr<int> life = life_;
  EventRegistrationToken token{};
  webview_->add_WebMessageReceived(
      Callback<ICoreWebView2WebMessageReceivedEventHandler>(
          [this, life](ICoreWebView2* sender,
                       ICoreWebView2WebMessageReceivedEventArgs* args) -> HRESULT {
            if (life.expired()) {
              return S_OK;
            }
            LPWSTR source = nullptr;
            const bool ours = SUCCEEDED(args->get_Source(&source)) &&
                              source != nullptr && StartsWith(source, kOrigin);
            if (source != nullptr) {
              ::CoTaskMemFree(source);
            }
            LPWSTR message = nullptr;
            if (ours && SUCCEEDED(args->TryGetWebMessageAsString(&message)) &&
                message != nullptr) {
              const std::wstring text(message);
              ::CoTaskMemFree(message);
              OnWebMessage(text);
            } else if (message != nullptr) {
              ::CoTaskMemFree(message);
            }
            return S_OK;
          })
          .Get(),
      &token);
  // Only the player page: links, redirects and new windows are refused.
  webview_->add_NavigationStarting(
      Callback<ICoreWebView2NavigationStartingEventHandler>(
          [](ICoreWebView2* sender,
             ICoreWebView2NavigationStartingEventArgs* args) -> HRESULT {
            LPWSTR uri = nullptr;
            const bool allowed = SUCCEEDED(args->get_Uri(&uri)) &&
                                 uri != nullptr && StartsWith(uri, kOrigin);
            if (uri != nullptr) {
              ::CoTaskMemFree(uri);
            }
            if (!allowed) {
              args->put_Cancel(TRUE);
            }
            return S_OK;
          })
          .Get(),
      &token);
  webview_->add_NewWindowRequested(
      Callback<ICoreWebView2NewWindowRequestedEventHandler>(
          [](ICoreWebView2* sender,
             ICoreWebView2NewWindowRequestedEventArgs* args) -> HRESULT {
            args->put_Handled(TRUE);
            return S_OK;
          })
          .Get(),
      &token);
  webview_->add_PermissionRequested(
      Callback<ICoreWebView2PermissionRequestedEventHandler>(
          [](ICoreWebView2* sender,
             ICoreWebView2PermissionRequestedEventArgs* args) -> HRESULT {
            args->put_State(COREWEBVIEW2_PERMISSION_STATE_DENY);
            return S_OK;
          })
          .Get(),
      &token);
  webview_->add_ProcessFailed(
      Callback<ICoreWebView2ProcessFailedEventHandler>(
          [this, life](ICoreWebView2* sender,
                       ICoreWebView2ProcessFailedEventArgs* args) -> HRESULT {
            // A GPU or utility process restarts by itself; the page's own
            // processes do not.
            COREWEBVIEW2_PROCESS_FAILED_KIND kind{};
            if (life.expired() || FAILED(args->get_ProcessFailedKind(&kind))) {
              return S_OK;
            }
            if (kind == COREWEBVIEW2_PROCESS_FAILED_KIND_BROWSER_PROCESS_EXITED ||
                kind == COREWEBVIEW2_PROCESS_FAILED_KIND_RENDER_PROCESS_EXITED ||
                kind == COREWEBVIEW2_PROCESS_FAILED_KIND_RENDER_PROCESS_UNRESPONSIVE) {
              Fail("decode", "WEBVIEW2_PROCESS_FAILED");
            }
            return S_OK;
          })
          .Get(),
      &token);

  Resize();
  controller_->put_IsVisible(TRUE);
  webview_->Navigate(kPage);
}

void VideoWindow::OnWebMessage(const std::wstring& message) {
  if (message == L"ready") {
    page_ready_ = true;
    if (probe_) {
      Run(L"window.nova.probe()");
    } else {
      Run(L"window.nova.load(" + Utf8ToWide(params_json_) + L")");
    }
    std::vector<std::wstring> scripts = std::move(pending_scripts_);
    pending_scripts_.clear();
    for (const std::wstring& script : scripts) {
      Run(script);
    }
    return;
  }
  if (StartsWith(message, L"probe:")) {
    const std::wstring level = message.substr(6);
    owner_->ProbeFinished(level == L"3000"   ? "SL3000"
                          : level == L"2000" ? "SL2000"
                                             : "",
                          true);
    return;
  }
  if (message == L"hwfail") {
    owner_->HardwareFailed();
    return;
  }
  if (StartsWith(message, L"event:")) {
    Emit(WideToUtf8(message.substr(6)));
  }
}

void VideoWindow::OnMethodCall(
    const MethodCall<EncodableValue>& call,
    std::unique_ptr<MethodResult<EncodableValue>> result) {
  static const std::set<std::string> commands = {
      "play",       "pause",      "seekTo",     "seekToLiveEdge", "setSpeed",
      "setQuality", "setVolume",  "renewToken",
  };
  const std::string& method = call.method_name();
  if (closing_) {
    result->Success();
    return;
  }
  if (method == "setRect") {
    const auto* args = std::get_if<EncodableMap>(call.arguments());
    if (args == nullptr) {
      result->Error("bad_args", "setRect needs x, y, width, height.");
      return;
    }
    const double x = Number(*args, "x");
    const double y = Number(*args, "y");
    const RECT rect{Pixels(x), Pixels(y), Pixels(x + Number(*args, "width")),
                    Pixels(y + Number(*args, "height"))};
    SetRect(rect, Flag(*args, "visible"));
    result->Success();
    return;
  }
  if (method == "release") {
    Close();
    result->Success();
    return;
  }
  if (commands.count(method) == 0) {
    result->NotImplemented();
    return;
  }
  const EncodableValue message(EncodableMap{
      {EncodableValue("method"), EncodableValue(method)},
      {EncodableValue("args"),
       call.arguments() != nullptr ? *call.arguments() : EncodableValue()},
  });
  Run(L"window.nova.command(" + Utf8ToWide(ToJson(message)) + L")");
  result->Success();
}

void VideoWindow::Run(const std::wstring& script) {
  if (webview_ == nullptr || !page_ready_) {
    pending_scripts_.push_back(script);
    return;
  }
  webview_->ExecuteScript(
      script.c_str(),
      Callback<ICoreWebView2ExecuteScriptCompletedHandler>(
          [](HRESULT error, LPCWSTR result) -> HRESULT { return S_OK; })
          .Get());
}

void VideoWindow::Emit(const std::string& json) {
  if (probe_) {
    return;
  }
  if (sink_) {
    sink_->Success(EncodableValue(json));
    return;
  }
  // Before Dart listens (right after create): kept for onListen.
  if (pending_events_.size() < 64) {
    pending_events_.push_back(json);
  }
}

void VideoWindow::Fail(const char* category, const char* message) {
  if (probe_) {
    owner_->ProbeFinished("", true);
    return;
  }
  Emit(std::string("{\"event\":\"error\",\"category\":\"") + category +
       "\",\"kind\":\"other\",\"code\":0,\"licenseStatus\":0,\"message\":\"" +
       message + "\"}");
}

void VideoWindow::Resize() {
  if (controller_ == nullptr || window_ == nullptr) {
    return;
  }
  RECT bounds{};
  ::GetClientRect(window_, &bounds);
  controller_->put_Bounds(bounds);
}

void VideoWindow::SetRect(const RECT& rect, bool visible) {
  rect_ = rect;
  has_rect_ = rect.right > rect.left && rect.bottom > rect.top;
  visible_ = visible;
  Place();
}

void VideoWindow::Place() {
  if (window_ == nullptr || probe_) {
    return;
  }
  const HWND main = owner_->main_window();
  const HWND view = owner_->view_window();
  bool show = has_rect_ && visible_ && !closing_ && main != nullptr &&
              view != nullptr && ::IsWindowVisible(main) && !::IsIconic(main);
  RECT video{};
  RECT clip{};
  if (show) {
    POINT origin{0, 0};
    ::ClientToScreen(view, &origin);
    RECT client{};
    ::GetClientRect(view, &client);
    video = RECT{origin.x + rect_.left, origin.y + rect_.top,
                 origin.x + rect_.right, origin.y + rect_.bottom};
    const RECT bounds{origin.x, origin.y, origin.x + client.right,
                      origin.y + client.bottom};
    show = ::IntersectRect(&clip, &video, &bounds) != FALSE;
  }
  if (!show) {
    if (::IsWindowVisible(window_)) {
      ::ShowWindow(window_, SW_HIDE);
    }
    return;
  }
  // Directly behind the app window: only its transparent hole shows it,
  // and everything the app draws (controls, watermark, sheets, dialogs)
  // stays above it.
  ::SetWindowPos(window_, main, video.left, video.top, video.right - video.left,
                 video.bottom - video.top,
                 SWP_NOACTIVATE | SWP_NOOWNERZORDER | SWP_SHOWWINDOW);
  // Never outside the app window (a player scrolled half out of view).
  const RECT local{clip.left - video.left, clip.top - video.top,
                   clip.right - video.left, clip.bottom - video.top};
  if (::EqualRect(&clip, &video)) {
    if (clipped_) {
      ::SetWindowRgn(window_, nullptr, TRUE);
      clipped_ = false;
    }
  } else if (!clipped_ || !::EqualRect(&local, &clip_)) {
    ::SetWindowRgn(window_,
                   ::CreateRectRgn(local.left, local.top, local.right,
                                   local.bottom),
                   TRUE);
    clip_ = local;
    clipped_ = true;
  }
}

void VideoWindow::Close() {
  if (closing_) {
    return;
  }
  closing_ = true;
  if (page_ready_) {
    Run(L"window.nova.command({\"method\":\"release\"})");
  }
  pending_scripts_.clear();
  // Removed from WM_TIMER, never from inside a channel or WebView2 callback
  // of this window.
  if (window_ != nullptr) {
    ::SetTimer(window_, kCloseTimer, kCloseDelayMs, nullptr);
  }
}

// static
LRESULT CALLBACK VideoWindow::WndProc(HWND window, UINT message, WPARAM wparam,
                                      LPARAM lparam) {
  if (message == WM_NCCREATE) {
    const auto* create = reinterpret_cast<const CREATESTRUCTW*>(lparam);
    ::SetWindowLongPtrW(window, GWLP_USERDATA,
                        reinterpret_cast<LONG_PTR>(create->lpCreateParams));
    return ::DefWindowProcW(window, message, wparam, lparam);
  }
  auto* self =
      reinterpret_cast<VideoWindow*>(::GetWindowLongPtrW(window, GWLP_USERDATA));
  if (self == nullptr) {
    return ::DefWindowProcW(window, message, wparam, lparam);
  }
  switch (message) {
    case WM_SIZE:
      self->Resize();
      return 0;
    case WM_MOUSEACTIVATE:
      return MA_NOACTIVATE;
    case WM_TIMER:
      if (wparam == kCloseTimer) {
        ::KillTimer(window, kCloseTimer);
        ProtectedPlayback* owner = self->owner_;
        owner->Remove(self);  // Destroys this window: nothing after.
        return 0;
      }
      if (wparam == kProbeTimer) {
        ::KillTimer(window, kProbeTimer);
        self->owner_->ProbeFinished("", false);
        return 0;
      }
      break;
    default:
      break;
  }
  return ::DefWindowProcW(window, message, wparam, lparam);
}

// ProtectedPlayback ----------------------------------------------------------

ProtectedPlayback::ProtectedPlayback(flutter::BinaryMessenger* messenger,
                                     HWND main_window, HWND view_window)
    : messenger_(messenger), main_window_(main_window), view_window_(view_window) {
  // Edge would wait for a click in the page before playing with sound; the
  // click is on the app's own play button. No media keys in the page: the
  // app's controls drive the video.
  ::SetEnvironmentVariableW(
      L"WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS",
      L"--autoplay-policy=no-user-gesture-required "
      L"--disable-features=HardwareMediaKeyHandling");

  drm_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, "nova/drm", &Codec());
  drm_->SetMethodCallHandler(
      [this](const MethodCall<EncodableValue>& call,
             std::unique_ptr<MethodResult<EncodableValue>> result) {
        if (call.method_name() == "playreadyLevel") {
          PlayReadyLevel(std::move(result));
          return;
        }
        result->NotImplemented();
      });
  players_channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, "nova/protected_player", &Codec());
  players_channel_->SetMethodCallHandler(
      [this](const MethodCall<EncodableValue>& call,
             std::unique_ptr<MethodResult<EncodableValue>> result) {
        if (call.method_name() == "create") {
          Create(call.arguments(), std::move(result));
          return;
        }
        result->NotImplemented();
      });
}

ProtectedPlayback::~ProtectedPlayback() {
  life_.reset();
  drm_->SetMethodCallHandler(nullptr);
  players_channel_->SetMethodCallHandler(nullptr);
  level_waiters_.clear();
  players_.clear();
  probe_.reset();
  UpdateTransparency();
}

void ProtectedPlayback::OnTopLevelMessage(UINT message, WPARAM wparam,
                                          LPARAM lparam) {
  switch (message) {
    case WM_MOVE:
    case WM_SIZE:
    case WM_WINDOWPOSCHANGED:
    case WM_ACTIVATE:
    case WM_SHOWWINDOW:
    case WM_DPICHANGED:
      for (auto& entry : players_) {
        entry.second->Place();
      }
      break;
    default:
      break;
  }
}

// static
std::wstring ProtectedPlayback::PlayerFolder() {
  std::wstring path(MAX_PATH, L'\0');
  DWORD length = 0;
  for (;;) {
    length = ::GetModuleFileNameW(nullptr, path.data(),
                                  static_cast<DWORD>(path.size()));
    if (length == 0 || length < path.size()) {
      break;
    }
    path.resize(path.size() * 2);
  }
  path.resize(length);
  const size_t slash = path.find_last_of(L"\\/");
  const std::wstring folder =
      slash == std::wstring::npos ? std::wstring(L".") : path.substr(0, slash);
  return folder + L"\\data\\nova_player";
}

void ProtectedPlayback::WithEnvironment(Environment ready) {
  if (environment_ != nullptr) {
    ready(environment_.Get(), S_OK);
    return;
  }
  if (FAILED(environment_error_)) {
    ready(nullptr, environment_error_);
    return;
  }
  environment_waiters_.push_back(std::move(ready));
  if (environment_waiters_.size() > 1) {
    return;
  }
  const auto flush = [this]() {
    std::vector<Environment> waiters = std::move(environment_waiters_);
    environment_waiters_.clear();
    for (Environment& waiter : waiters) {
      waiter(environment_.Get(), environment_error_);
    }
  };
  const std::wstring folder = UserDataFolder();
  std::weak_ptr<int> life = life_;
  const HRESULT started = ::CreateCoreWebView2EnvironmentWithOptions(
      nullptr, folder.empty() ? nullptr : folder.c_str(), nullptr,
      Callback<ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler>(
          [this, life, flush](HRESULT result,
                              ICoreWebView2Environment* environment) -> HRESULT {
            if (life.expired()) {
              return S_OK;
            }
            if (SUCCEEDED(result) && environment != nullptr) {
              environment_ = environment;
            } else {
              environment_error_ = FAILED(result) ? result : E_FAIL;
            }
            flush();
            return S_OK;
          })
          .Get());
  if (FAILED(started)) {
    environment_error_ = started;
    flush();
  }
}

void ProtectedPlayback::Create(
    const EncodableValue* arguments,
    std::unique_ptr<MethodResult<EncodableValue>> result) {
  const int64_t id = next_id_++;
  auto window = std::make_unique<VideoWindow>(
      this, id, arguments != nullptr ? ToJson(*arguments) : std::string("{}"),
      false);
  if (!window->Create()) {
    result->Error("unavailable", "The video window could not be created.");
    return;
  }
  players_[id] = std::move(window);
  UpdateTransparency();
  std::weak_ptr<int> life = life_;
  WithEnvironment([this, life, id](ICoreWebView2Environment* environment,
                                   HRESULT error) {
    if (life.expired()) {
      return;
    }
    const auto found = players_.find(id);
    if (found != players_.end()) {
      found->second->Attach(environment, error);
    }
  });
  result->Success(EncodableValue(id));
}

void ProtectedPlayback::Remove(VideoWindow* window) {
  if (probe_.get() == window) {
    probe_.reset();
    return;
  }
  const auto found = players_.find(window->id());
  if (found != players_.end() && found->second.get() == window) {
    players_.erase(found);
  }
  UpdateTransparency();
}

void ProtectedPlayback::PlayReadyLevel(
    std::unique_ptr<MethodResult<EncodableValue>> result) {
  level_waiters_.push_back(std::move(result));
  if (level_.has_value()) {
    AnswerLevel();
    return;
  }
  if (probe_running_) {
    return;
  }
  probe_running_ = true;
  probe_ = std::make_unique<VideoWindow>(this, 0, std::string(), true);
  if (!probe_->Create()) {
    ProbeFinished("", false);
    return;
  }
  std::weak_ptr<int> life = life_;
  WithEnvironment([this, life](ICoreWebView2Environment* environment,
                               HRESULT error) {
    if (!life.expired() && probe_ != nullptr && probe_running_) {
      probe_->Attach(environment, error);
    }
  });
}

void ProtectedPlayback::ProbeFinished(const std::string& level,
                                      bool definitive) {
  if (!probe_running_) {
    return;
  }
  probe_running_ = false;
  if (definitive) {
    level_ = level;
  }
  AnswerLevel();
  if (probe_ != nullptr) {
    probe_->Close();
  }
}

void ProtectedPlayback::AnswerLevel() {
  std::string level = level_.value_or(std::string());
  // Hardware PlayReady failed on this PC during this run: software only.
  if (level == "SL3000" && hardware_failed_) {
    level = "SL2000";
  }
  std::vector<std::unique_ptr<MethodResult<EncodableValue>>> waiters =
      std::move(level_waiters_);
  level_waiters_.clear();
  for (auto& waiter : waiters) {
    if (level.empty()) {
      waiter->Success();
    } else {
      waiter->Success(EncodableValue(level));
    }
  }
}

void ProtectedPlayback::UpdateTransparency() {
  // While a video window exists, the app window composes with per-pixel
  // alpha (Flutter's transparent hole shows the video behind it); the empty
  // blur region means nothing is blurred.
  const bool wanted = !players_.empty();
  if (wanted == transparent_ || main_window_ == nullptr) {
    return;
  }
  DWM_BLURBEHIND blur{};
  blur.dwFlags = DWM_BB_ENABLE;
  blur.fEnable = wanted ? TRUE : FALSE;
  HRGN region = nullptr;
  if (wanted) {
    region = ::CreateRectRgn(0, 0, -1, -1);
    blur.dwFlags |= DWM_BB_BLURREGION;
    blur.hRgnBlur = region;
  }
  if (SUCCEEDED(::DwmEnableBlurBehindWindow(main_window_, &blur))) {
    transparent_ = wanted;
  }
  if (region != nullptr) {
    ::DeleteObject(region);
  }
}

}  // namespace nova
