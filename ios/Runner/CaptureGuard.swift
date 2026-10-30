import Flutter
import UIKit

/// Capture detection, the second layer of the iPhone protection. The
/// first is `SecureCapture` (SceneDelegate, owner decision 2026-10-29):
/// the app is drawn in the system's secure layer, so screenshots and
/// recordings come out black. Detection still matters: per D-067 /
/// conception §6.5 Flutter blurs the app and stops video while the screen
/// is captured (the blur also covers the first frames), stops the audio a
/// black recording would still carry (the Live speaking stage, voice
/// notes), and warns after a screenshot.
///
/// Event channel `nova/capture` emits:
/// * `{"captured": Bool}` whenever recording, AirPlay or mirroring
///   starts or stops (and once on listen with the current state);
/// * `{"screenshot": true}` after the user takes a screenshot (already
///   taken — used to warn and log, it cannot be undone);
/// * `{"secure": Bool, "reason": String?}` once the secure layer is
///   confirmed on screen, or when it is unavailable and the app falls
///   back to detection only (on listen with the state known so far).
final class CaptureGuard: NSObject, FlutterStreamHandler {
  private var sink: FlutterEventSink?
  private var observers: [NSObjectProtocol] = []

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterEventChannel(
      name: "nova/capture",
      binaryMessenger: registrar.messenger()
    )
    channel.setStreamHandler(CaptureGuard())
  }

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    sink = events
    let center = NotificationCenter.default
    observers = [
      center.addObserver(
        forName: UIScreen.capturedDidChangeNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in self?.emitCaptured() },
      center.addObserver(
        forName: UIApplication.userDidTakeScreenshotNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in self?.sink?(["screenshot": true]) },
      center.addObserver(
        forName: SecureCapture.statusDidChange,
        object: nil,
        queue: .main
      ) { [weak self] _ in self?.emitSecure() },
    ]
    emitCaptured()
    emitSecure()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    observers.forEach(NotificationCenter.default.removeObserver)
    observers = []
    sink = nil
    return nil
  }

  private func emitCaptured() {
    let captured = UIApplication.shared.connectedScenes
      .compactMap { ($0 as? UIWindowScene)?.screen.isCaptured }
      .contains(true)
    sink?(["captured": captured])
  }

  private func emitSecure() {
    switch SecureCapture.status {
    case .pending:
      break
    case .active:
      sink?(["secure": true])
    case .unavailable(let reason):
      sink?(["secure": false, "reason": reason])
    }
  }
}
