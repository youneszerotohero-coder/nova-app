import AVFoundation
import Flutter
import UIKit

/// The iPhone player (Lives, Lessons, Replays) on AVPlayer: the FairPlay
/// HLS stream with its Axinom licence (D-118), or the D-070 clear adaptive
/// HLS copy. It speaks the same channels and events as Android's
/// `ProtectedPlayerView`: control on `nova/protected_player_<id>`, state on
/// `nova/protected_player_<id>/events`.
///
/// Protection is FairPlay when protected, the identity watermark Flutter
/// draws above this view, and `CaptureGuard` (recording/mirroring stops
/// playback). AirPlay is disabled so the picture never leaves the
/// watermarked screen.
final class ClearPlayerFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    registrar.register(
      ClearPlayerFactory(messenger: registrar.messenger()),
      withId: "nova/clear-player"
    )
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    ClearPlayerView(
      frame: frame,
      viewId: viewId,
      params: args as? [String: Any] ?? [:],
      messenger: messenger
    )
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
}

private final class PlayerLayerView: UIView {
  override class var layerClass: AnyClass { AVPlayerLayer.self }
  var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

final class ClearPlayerView: NSObject, FlutterPlatformView, FlutterStreamHandler {
  /// A Live plays this far behind the edge (web/Android live tuning).
  private static let liveOffset = CMTime(seconds: 12, preferredTimescale: 600)

  private let container: PlayerLayerView
  private let player = AVPlayer()
  private let methods: FlutterMethodChannel
  private let events: FlutterEventChannel
  private let live: Bool
  private var keys: FairPlayKeys?
  /// A key failure was reported: the item failure that follows is its echo.
  private var keyFailed = false
  private var sink: FlutterEventSink?
  private var observations: [NSKeyValueObservation] = []
  private var tokens: [NSObjectProtocol] = []
  private var timeObserver: Any?
  private var pendingStart: CMTime?
  private var variants: [(height: Int, peak: Double)] = []
  private var speed: Float = 1
  private var firstFrameSent = false
  private var released = false

  init(frame: CGRect, viewId: Int64, params: [String: Any], messenger: FlutterBinaryMessenger) {
    container = PlayerLayerView(frame: frame)
    methods = FlutterMethodChannel(
      name: "nova/protected_player_\(viewId)",
      binaryMessenger: messenger
    )
    events = FlutterEventChannel(
      name: "nova/protected_player_\(viewId)/events",
      binaryMessenger: messenger
    )
    live = params["live"] as? Bool ?? false
    super.init()

    container.backgroundColor = .black
    container.playerLayer.videoGravity = .resizeAspect
    container.playerLayer.player = player
    player.allowsExternalPlayback = false
    player.preventsDisplaySleepDuringVideoPlayback = true
    // Sound even with the silent switch on, like any video app.
    try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    try? AVAudioSession.sharedInstance().setActive(true)

    methods.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    events.setStreamHandler(self)
    load(params)
  }

  deinit {
    release()
  }

  func view() -> UIView { container }

  // Loading ----------------------------------------------------------------

  private func load(_ params: [String: Any]) {
    guard let raw = params["manifest"] as? String, let url = URL(string: raw) else {
      emit(["event": "error", "category": "delivery", "kind": "other", "code": 0, "licenseStatus": 0])
      return
    }
    let asset = AVURLAsset(url: url)
    if !(params["clear"] as? Bool ?? true) {
      guard
        let license = URL(string: params["license"] as? String ?? ""),
        let certificate = URL(string: params["certificate"] as? String ?? ""),
        license.scheme == "https", certificate.scheme == "https"
      else {
        emit(["event": "error", "category": "drm_init", "kind": "drm", "code": 0, "licenseStatus": 0])
        return
      }
      let keys = FairPlayKeys(
        license: license,
        certificate: certificate,
        token: params["token"] as? String ?? ""
      ) { [weak self] category, code, status, message in
        guard let self = self, !self.released, !self.keyFailed else { return }
        self.keyFailed = true
        self.emit([
          "event": "error", "category": category, "kind": "drm",
          "code": code, "licenseStatus": status, "message": message,
        ])
      }
      keys.attach(asset)
      self.keys = keys
    }
    let item = AVPlayerItem(asset: asset)
    if live {
      item.configuredTimeOffsetFromLive = ClearPlayerView.liveOffset
      item.automaticallyPreservesTimeOffsetFromLive = true
    }
    if let maxHeight = (params["maxHeight"] as? NSNumber)?.intValue, maxHeight > 0 {
      item.preferredMaximumResolution = ClearPlayerView.size(forHeight: maxHeight)
    }
    let startMs = (params["startMs"] as? NSNumber)?.doubleValue ?? 0
    if !live && startMs > 0 {
      pendingStart = CMTime(seconds: startMs / 1000, preferredTimescale: 600)
    }
    observe(item)
    player.replaceCurrentItem(with: item)
    player.play()
    loadVariants(asset)
  }

  private func observe(_ item: AVPlayerItem) {
    observations = [
      item.observe(\.status, options: [.new]) { [weak self] item, _ in
        DispatchQueue.main.async { self?.statusChanged(item) }
      },
      player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
        DispatchQueue.main.async { self?.timeControlChanged(player.timeControlStatus) }
      },
      container.playerLayer.observe(\.isReadyForDisplay, options: [.new]) { [weak self] layer, _ in
        guard layer.isReadyForDisplay else { return }
        DispatchQueue.main.async { self?.firstFrame() }
      },
    ]
    let center = NotificationCenter.default
    tokens = [
      center.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) {
        [weak self] _ in self?.emit(["event": "state", "state": "ended"])
      },
      center.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) {
        [weak self] note in
        self?.fail(note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)
      },
    ]
    timeObserver = player.addPeriodicTimeObserver(
      forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
      queue: .main
    ) { [weak self] _ in self?.tick() }
  }

  /// Heights of the HLS variants (quality menu), highest first.
  private func loadVariants(_ asset: AVURLAsset) {
    asset.loadValuesAsynchronously(forKeys: ["variants"]) { [weak self] in
      var error: NSError?
      guard asset.statusOfValue(forKey: "variants", error: &error) == .loaded else { return }
      let pairs: [(height: Int, peak: Double)] = asset.variants.compactMap { variant in
        guard let size = variant.videoAttributes?.presentationSize, size.height > 0 else { return nil }
        return (Int(size.height), variant.peakBitRate ?? variant.averageBitRate ?? 0)
      }
      DispatchQueue.main.async {
        guard let self = self, !self.released else { return }
        self.variants = pairs
        self.emitTracks()
      }
    }
  }

  // Player events -----------------------------------------------------------

  private func statusChanged(_ item: AVPlayerItem) {
    switch item.status {
    case .readyToPlay:
      if let start = pendingStart {
        pendingStart = nil
        item.seek(to: start, completionHandler: nil)
      }
      emit(["event": "state", "state": "ready"])
    case .failed:
      fail(item.error)
    default:
      break
    }
  }

  private func timeControlChanged(_ status: AVPlayer.TimeControlStatus) {
    emit(["event": "playing", "value": status == .playing])
    switch status {
    case .waitingToPlayAtSpecifiedRate:
      emit(["event": "state", "state": "buffering"])
    case .playing:
      emit(["event": "state", "state": "ready"])
    default:
      break
    }
  }

  private func firstFrame() {
    guard !firstFrameSent else { return }
    firstFrameSent = true
    emit(["event": "firstFrame"])
  }

  private func tick() {
    guard let item = player.currentItem else { return }
    let now = item.currentTime()
    let position = now.seconds
    let duration = live || !item.duration.isNumeric ? 0 : item.duration.seconds
    let buffered = item.loadedTimeRanges
      .map { $0.timeRangeValue }
      .first { $0.containsTime(now) }
      .map { CMTimeRangeGetEnd($0).seconds } ?? position
    var offset = -1.0
    if live, let range = item.seekableTimeRanges.last?.timeRangeValue {
      offset = max(0, CMTimeRangeGetEnd(range).seconds - position)
    }
    emit([
      "event": "position",
      "position": ClearPlayerView.ms(position),
      "duration": ClearPlayerView.ms(duration),
      "buffered": ClearPlayerView.ms(buffered),
      "liveOffset": offset < 0 ? -1 : ClearPlayerView.ms(offset),
    ])
  }

  private func emitTracks() {
    let heights = Array(Set(variants.map { $0.height })).sorted(by: >)
    emit(["event": "tracks", "heights": heights])
  }

  /// Same categories as the Android player; a decoder failure is `decode`.
  private func fail(_ error: Error?) {
    guard !keyFailed else { return }
    let ns = error as NSError?
    var category = "delivery"
    var kind = "other"
    if let ns = ns {
      if ns.domain == NSURLErrorDomain {
        category = ns.code == NSURLErrorTimedOut ? "timeout" : "delivery"
      } else if ns.domain == AVFoundationErrorDomain {
        switch AVError.Code(rawValue: ns.code) {
        case .decoderNotFound?, .decoderTemporarilyUnavailable?, .decodeFailed?:
          category = "decode"
          kind = "decoder"
        default:
          break
        }
      }
    }
    emit([
      "event": "error",
      "category": category,
      "kind": kind,
      "code": ns?.code ?? 0,
      "licenseStatus": 0,
      "message": ns?.localizedDescription ?? "",
    ])
  }

  // Commands ----------------------------------------------------------------

  private func handle(_ call: FlutterMethodCall, result: FlutterResult) {
    if released {
      result(nil)
      return
    }
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "play":
      player.rate = speed
    case "pause":
      player.pause()
    case "seekTo":
      let ms = (args["ms"] as? NSNumber)?.doubleValue ?? 0
      player.seek(to: CMTime(seconds: ms / 1000, preferredTimescale: 600))
    case "seekToLiveEdge":
      seekToLiveEdge()
    case "setSpeed":
      speed = (args["speed"] as? NSNumber)?.floatValue ?? 1
      if player.timeControlStatus != .paused { player.rate = speed }
    case "setVolume":
      player.volume = (args["volume"] as? NSNumber)?.floatValue ?? 1
    case "setQuality":
      setQuality((args["height"] as? NSNumber)?.intValue ?? 0)
    case "renewToken":
      // Later licence requests of this Live carry the renewed entitlement.
      keys?.renew(token: args["token"] as? String ?? "")
    case "release":
      release()
    default:
      result(FlutterMethodNotImplemented)
      return
    }
    result(nil)
  }

  private func seekToLiveEdge() {
    guard let range = player.currentItem?.seekableTimeRanges.last?.timeRangeValue else { return }
    let target = CMTimeSubtract(CMTimeRangeGetEnd(range), ClearPlayerView.liveOffset)
    player.seek(to: CMTimeMaximum(target, range.start))
  }

  /// 0 = automatic. AVPlayer cannot pin one variant: a choice caps the
  /// resolution and bitrate at that rendition, ABR works below it.
  private func setQuality(_ height: Int) {
    guard let item = player.currentItem else { return }
    guard height > 0 else {
      item.preferredMaximumResolution = .zero
      item.preferredPeakBitRate = 0
      return
    }
    item.preferredMaximumResolution = ClearPlayerView.size(forHeight: height)
    item.preferredPeakBitRate = variants.filter { $0.height == height }.map { $0.peak }.max() ?? 0
  }

  private func release() {
    guard !released else { return }
    released = true
    if let observer = timeObserver { player.removeTimeObserver(observer) }
    timeObserver = nil
    observations.forEach { $0.invalidate() }
    observations = []
    tokens.forEach(NotificationCenter.default.removeObserver)
    tokens = []
    player.pause()
    player.replaceCurrentItem(with: nil)
    keys?.close()
    keys = nil
    methods.setMethodCallHandler(nil)
    events.setStreamHandler(nil)
    sink = nil
  }

  // Event channel -----------------------------------------------------------

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    emitTracks()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }

  private func emit(_ event: [String: Any]) {
    if Thread.isMainThread {
      sink?(event)
    } else {
      DispatchQueue.main.async { [weak self] in self?.sink?(event) }
    }
  }

  private static func ms(_ seconds: Double) -> Int {
    seconds.isFinite ? Int((seconds * 1000).rounded()) : 0
  }

  private static func size(forHeight height: Int) -> CGSize {
    CGSize(width: (CGFloat(height) * 16 / 9).rounded(.up), height: CGFloat(height))
  }
}

/// D-118: FairPlay keys for one protected stream, as Axinom's FairPlay
/// integration sample and the website (Shaka) do it: the content id is
/// everything after `skd://` in the playlist's key URI, the SPC goes raw to
/// the Axinom licence URL with the entitlement in `X-AxDRM-Message`, and the
/// raw CKC comes back. Failures use the Android player's categories.
final class FairPlayKeys: NSObject, AVContentKeySessionDelegate {
  typealias Failure = (_ category: String, _ code: Int, _ licenseStatus: Int, _ message: String) -> Void

  private static let timeout: TimeInterval = 12

  private let session = AVContentKeySession(keySystem: .fairPlayStreaming)
  private let queue = DispatchQueue(label: "nova.fairplay")
  private let license: URL
  private let certificateUrl: URL
  private let onFailure: Failure
  // Read and written on `queue` only.
  private var token: String
  private var certificate: Data?
  private var closed = false

  init(license: URL, certificate: URL, token: String, onFailure: @escaping Failure) {
    self.license = license
    certificateUrl = certificate
    self.token = token
    self.onFailure = onFailure
    super.init()
    session.setDelegate(self, queue: queue)
  }

  func attach(_ asset: AVURLAsset) {
    session.addContentKeyRecipient(asset)
  }

  func renew(token: String) {
    queue.async { self.token = token }
  }

  func close() {
    queue.async { self.closed = true }
  }

  func contentKeySession(_ session: AVContentKeySession, didProvide keyRequest: AVContentKeyRequest) {
    answer(keyRequest)
  }

  func contentKeySession(
    _ session: AVContentKeySession,
    didProvideRenewingContentKeyRequest keyRequest: AVContentKeyRequest
  ) {
    answer(keyRequest)
  }

  func contentKeySession(
    _ session: AVContentKeySession,
    contentKeyRequest keyRequest: AVContentKeyRequest,
    didFailWithError err: Error
  ) {
    report("license", err, status: 0)
  }

  // Everything below runs on `queue`.

  private func answer(_ request: AVContentKeyRequest) {
    guard !closed else { return }
    guard
      let identifier = request.identifier as? String,
      identifier.hasPrefix("skd://"),
      let contentId = String(identifier.dropFirst("skd://".count)).data(using: .utf8)
    else {
      fail(request, "drm_init", FairPlayKeys.error("The key URI is not skd://"), status: 0)
      return
    }
    withCertificate { certificate, status, error in
      guard let certificate = certificate else {
        self.fail(request, "drm_init", error ?? FairPlayKeys.error("No FairPlay certificate"), status: status)
        return
      }
      request.makeStreamingContentKeyRequestData(
        forApp: certificate,
        contentIdentifier: contentId,
        options: [AVContentKeyRequestProtocolVersionsKey: [1]]
      ) { spc, error in
        self.queue.async {
          guard let spc = spc else {
            self.fail(request, "drm_init", error ?? FairPlayKeys.error("No SPC"), status: 0)
            return
          }
          self.fetchLicense(spc, for: request)
        }
      }
    }
  }

  /// The application certificate, downloaded once per stream.
  private func withCertificate(_ done: @escaping (Data?, Int, Error?) -> Void) {
    if let certificate = certificate {
      done(certificate, 200, nil)
      return
    }
    let request = URLRequest(url: certificateUrl, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: FairPlayKeys.timeout)
    URLSession.shared.dataTask(with: request) { data, response, error in
      self.queue.async {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard error == nil, status == 200, let data = data, !data.isEmpty else {
          done(nil, status, error)
          return
        }
        self.certificate = data
        done(data, status, nil)
      }
    }.resume()
  }

  private func fetchLicense(_ spc: Data, for keyRequest: AVContentKeyRequest) {
    guard !closed else { return }
    var request = URLRequest(url: license, timeoutInterval: FairPlayKeys.timeout)
    request.httpMethod = "POST"
    request.setValue(token, forHTTPHeaderField: "X-AxDRM-Message")
    request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
    request.httpBody = spc
    URLSession.shared.dataTask(with: request) { data, response, error in
      self.queue.async {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard error == nil, status == 200, let ckc = data, !ckc.isEmpty else {
          let timedOut = (error as NSError?)?.code == NSURLErrorTimedOut
          self.fail(
            keyRequest,
            timedOut ? "timeout" : "license",
            error ?? FairPlayKeys.error("Licence refused (HTTP \(status))"),
            status: status
          )
          return
        }
        keyRequest.processContentKeyResponse(AVContentKeyResponse(fairPlayStreamingKeyResponseData: ckc))
      }
    }.resume()
  }

  private func fail(_ request: AVContentKeyRequest, _ category: String, _ error: Error, status: Int) {
    request.processContentKeyResponseError(error)
    report(category, error, status: status)
  }

  private func report(_ category: String, _ error: Error, status: Int) {
    guard !closed else { return }
    let ns = error as NSError
    DispatchQueue.main.async { self.onFailure(category, ns.code, status, ns.localizedDescription) }
  }

  private static func error(_ message: String) -> NSError {
    NSError(domain: "nova.fairplay", code: -1, userInfo: [NSLocalizedDescriptionKey: message])
  }
}
