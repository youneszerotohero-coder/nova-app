import Flutter
import UIKit

/// iOS cannot block screenshots or recording, so per D-067 / conception
/// §6.5 the app detects them and lets Flutter blur and stop playback.
///
/// Event channel `nova/capture` emits:
/// * `{"captured": Bool}` whenever recording, AirPlay or mirroring
///   starts or stops (and once on listen with the current state);
/// * `{"screenshot": true}` after the user takes a screenshot (already
///   taken — used to warn and log, it cannot be undone).
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
    ]
    emitCaptured()
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
}
