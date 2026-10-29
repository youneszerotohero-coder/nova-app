import AVFoundation
import DeviceCheck
import Flutter
import UIKit

/// D-168 phase 1a (`nova/measure`): what this iPhone can do with DRM,
/// measured once per app version by `lib/core/security/device_measurement.dart`.
/// Nothing here touches the Student's playback:
///
/// * `snapshot`      model identifier (e.g. `iPhone14,5`), iOS version,
///                   FairPlay availability and, only when the server asks,
///                   App Attest support (`DCAppAttestService.isSupported`);
/// * `testPlayback`  a few seconds of the FairPlay HLS of the `/device-check`
///                   test pattern with its real Axinom licence (the mode A
///                   policy), muted and off-screen; answers
///                   `{result, error, code}`.
enum DeviceMeasurement {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "nova/measure", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      let args = call.arguments as? [String: Any] ?? [:]
      switch call.method {
      case "snapshot":
        result(snapshot(appAttest: args["appAttest"] as? Bool ?? false))
      case "testPlayback":
        FairPlayTestPlayback(result: result).start(args)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func snapshot(appAttest: Bool) -> [String: Any] {
    #if targetEnvironment(simulator)
      // The simulator has no FairPlay.
      let fairplay = false
      let model = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "Simulator"
    #else
      let fairplay = true
      let model = machine()
    #endif
    var value: [String: Any] = [
      "model": String(model.prefix(80)),
      "osVersion": String(UIDevice.current.systemVersion.prefix(32)),
      "fairplay": fairplay,
    ]
    if appAttest {
      value["appAttestSupported"] = DCAppAttestService.shared.isSupported
    }
    return value
  }

  /// The hardware model identifier, e.g. `iPhone14,5` (never the phone's name).
  private static func machine() -> String {
    var info = utsname()
    uname(&info)
    let identifier = withUnsafePointer(to: &info.machine) { pointer in
      pointer.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
    }
    return identifier.isEmpty ? "iPhone" : identifier
  }
}

/// One measured FairPlay playback of the test pattern (`FairPlayKeys`, the
/// lesson player's key exchange): `passed` once 3 s played (encrypted
/// segments only play with the keys), `failed` on a key or player error,
/// `inconclusive` when it neither played nor failed in time, when another
/// app is playing sound (the test would interrupt it) or when a real
/// player started meanwhile.
final class FairPlayTestPlayback: NSObject {
  private static let played: Double = 3
  private static var current: FairPlayTestPlayback?

  /// A lesson, Replay or Live player is about to start (main thread).
  static func interrupt() {
    current?.finish("inconclusive", "interrupted")
  }

  private let player = AVPlayer()
  private let layer = AVPlayerLayer()
  private var result: FlutterResult?
  private var keys: FairPlayKeys?
  private var observation: NSKeyValueObservation?
  private var failure: NSObjectProtocol?
  private var poll: Timer?
  private var timeout: Timer?

  init(result: @escaping FlutterResult) {
    self.result = result
    super.init()
  }

  func start(_ args: [String: Any]) {
    guard
      let manifest = URL(string: args["manifest"] as? String ?? ""),
      let license = URL(string: args["license"] as? String ?? ""),
      let certificate = URL(string: args["certificate"] as? String ?? ""),
      license.scheme == "https", certificate.scheme == "https"
    else {
      finish("unavailable", "no_test_video")
      return
    }
    if AVAudioSession.sharedInstance().isOtherAudioPlaying {
      finish("inconclusive", "other_audio")
      return
    }
    FairPlayTestPlayback.current?.finish("inconclusive", "interrupted")
    FairPlayTestPlayback.current = self

    let asset = AVURLAsset(url: manifest)
    let keys = FairPlayKeys(license: license, certificate: certificate, token: args["token"] as? String ?? "") {
      [weak self] category, code, _, _ in
      self?.finish("failed", category, code)
    }
    keys.attach(asset)
    self.keys = keys
    let item = AVPlayerItem(asset: asset)
    item.preferredMaximumResolution = CGSize(width: 854, height: 480)
    player.isMuted = true
    player.allowsExternalPlayback = false
    player.preventsDisplaySleepDuringVideoPlayback = false
    layer.player = player
    observation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
      guard item.status == .failed else { return }
      DispatchQueue.main.async { self?.failed(item.error) }
    }
    failure = NotificationCenter.default.addObserver(
      forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main
    ) { [weak self] note in
      self?.failed(note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)
    }
    player.replaceCurrentItem(with: item)
    player.play()

    poll = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
      guard let self = self, let item = self.player.currentItem else { return }
      if item.status == .readyToPlay && item.currentTime().seconds >= FairPlayTestPlayback.played {
        self.finish("passed")
      }
    }
    let seconds = min(60, max(5, ((args["timeoutMs"] as? NSNumber)?.doubleValue ?? 30_000) / 1000))
    timeout = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
      let started = (self?.player.currentItem?.currentTime().seconds ?? 0) > 0
      self?.finish(started ? "inconclusive" : "failed", "timeout")
    }
  }

  /// The lesson player's categories (`ClearPlayerView.fail`).
  private func failed(_ error: Error?) {
    let ns = error as NSError?
    var category = "delivery"
    if let ns = ns {
      if ns.domain == NSURLErrorDomain {
        category = ns.code == NSURLErrorTimedOut ? "timeout" : "delivery"
      } else if ns.domain == AVFoundationErrorDomain {
        switch AVError.Code(rawValue: ns.code) {
        case .decoderNotFound?, .decoderTemporarilyUnavailable?, .decodeFailed?:
          category = "decode"
        default:
          category = "playback"
        }
      }
    }
    finish("failed", category, ns?.code)
  }

  private func finish(_ outcome: String, _ error: String? = nil, _ code: Int? = nil) {
    guard let result = result else { return }
    self.result = nil
    if FairPlayTestPlayback.current === self { FairPlayTestPlayback.current = nil }
    poll?.invalidate()
    timeout?.invalidate()
    observation?.invalidate()
    if let failure = failure { NotificationCenter.default.removeObserver(failure) }
    player.pause()
    player.replaceCurrentItem(with: nil)
    layer.player = nil
    keys?.close()
    keys = nil
    var value: [String: Any] = ["result": outcome]
    if let error = error { value["error"] = error }
    if let code = code { value["code"] = code }
    result(value)
  }
}
