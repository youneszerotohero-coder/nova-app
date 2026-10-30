import Flutter
import UIKit

/// Flutter's scene delegate, plus the iPhone capture protection (owner
/// decision 2026-10-29, school requirement: no screenshot and no screen
/// recording anywhere in the apps).
class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    // Flutter first, while the storyboard's FlutterViewController is still
    // the window's root: its engine is registered for the scene's life
    // cycle (plugins, deep links) exactly as before.
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    SecureCapture.install(in: window)
  }
}

/// Hosts the whole Flutter view in the layer iOS uses to hide typed
/// passwords — the canvas of a `UITextField` with `isSecureTextEntry`
/// (iOS 13+), the technique banking apps use. The system leaves that layer
/// tree out of screenshots, screen recordings, AirPlay mirroring and
/// QuickTime capture: they show black. Everything Flutter draws is inside
/// it: every route, the platform views (the `ClearPlayerView` players) and
/// the textures (LiveKit video, PDFs).
///
/// Self-check: the canvas is found by its class name, read with the public
/// `NSStringFromClass` (no private method is called), and once on screen
/// a hit test must reach Flutter through it. When either fails (a future
/// iOS), the app keeps today's protection — `CaptureGuard`'s blur, pause
/// and screenshot warning — and the reason is logged and sent to Dart.
enum SecureCapture {
  enum Status: Equatable {
    /// Not decided yet (the window is not on screen).
    case pending
    /// Flutter is inside the secure layer.
    case active
    /// The fallback: detection only, as before 2026-10-29.
    case unavailable(String)
  }

  /// Posted on the main thread whenever `status` changes.
  static let statusDidChange = Notification.Name("NovaSecureCaptureStatusDidChange")

  private(set) static var status: Status = .pending

  static func install(in window: UIWindow?) {
    guard let window = window, let flutter = window.rootViewController as? FlutterViewController else {
      report(.unavailable("the window's root is not Flutter"))
      return
    }
    guard let secure = makeSecureCanvas() else {
      report(.unavailable("no secure text canvas on iOS \(UIDevice.current.systemVersion)"))
      return
    }
    // Flutter installs its launch splash when its view loads with no
    // parent: load it now, while it is still the root, so a cold start
    // looks as before.
    flutter.loadViewIfNeeded()
    let root = SecureRootViewController(flutter: flutter, field: secure.field, canvas: secure.canvas)
    window.rootViewController = root
    // Only once UIKit has let go of Flutter as the root.
    root.embedFlutter()
  }

  static func report(_ new: Status) {
    guard new != status else { return }
    status = new
    switch new {
    case .pending:
      break
    case .active:
      NSLog("NOVA capture protection: the app is in the secure layer (screenshots and recordings are black)")
    case .unavailable(let reason):
      NSLog("NOVA capture protection: secure layer unavailable (%@), detection and blur only", reason)
    }
    NotificationCenter.default.post(name: statusDidChange, object: nil)
  }

  /// The secure field and its canvas, taken out of the field. Since
  /// iOS 15 the canvas is `_UITextLayoutCanvasView` (`_UITextFieldCanvasView`
  /// on iOS 13–14). The field is returned so the caller keeps it alive: the
  /// canvas may still refer to it.
  private static func makeSecureCanvas() -> (field: UITextField, canvas: UIView)? {
    let field = UITextField(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
    field.isSecureTextEntry = true
    var found = canvasView(of: field)
    if found == nil {
      // Some versions build the canvas on the first layout.
      field.layoutIfNeeded()
      found = canvasView(of: field)
    }
    guard let canvas = found else { return nil }
    canvas.removeFromSuperview()
    // An empty field draws nothing, but clear whatever text fragments it made.
    canvas.subviews.forEach { $0.removeFromSuperview() }
    canvas.translatesAutoresizingMaskIntoConstraints = true
    canvas.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    canvas.transform = .identity
    canvas.isHidden = false
    canvas.alpha = 1
    canvas.backgroundColor = .clear
    canvas.overrideUserInterfaceStyle = .unspecified
    // The field's canvas ignores touches; Flutter needs them. Its text
    // gestures and interactions (selection, loupe, edit menu, drag) would
    // compete with Flutter's over the whole screen: none is kept.
    canvas.isUserInteractionEnabled = true
    canvas.gestureRecognizers?.forEach { canvas.removeGestureRecognizer($0) }
    canvas.interactions.forEach { canvas.removeInteraction($0) }
    canvas.isAccessibilityElement = false
    return (field, canvas)
  }

  private static func canvasView(of field: UITextField) -> UIView? {
    field.subviews.first { NSStringFromClass(type(of: $0)).hasSuffix("CanvasView") }
  }
}

/// The window's root: Flutter's view controller as a child, its view inside
/// the secure canvas. The status bar, home indicator, system-gesture edges
/// and supported orientations are Flutter's, as when it was the root (the
/// player's fullscreen still turns to landscape and hides the bars).
final class SecureRootViewController: UIViewController {
  private let flutter: FlutterViewController
  /// Kept alive for the canvas, never shown.
  private let field: UITextField
  /// Nil after a fallback: Flutter's view then sits directly in `view`.
  private var canvas: UIView?
  private var checked = false

  init(flutter: FlutterViewController, field: UITextField, canvas: UIView) {
    self.flutter = flutter
    self.field = field
    self.canvas = canvas
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("SecureRootViewController is created in code")
  }

  override func loadView() {
    let root = UIView()
    // What a screenshot or a recording shows instead of the app.
    root.backgroundColor = .black
    view = root
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    if let canvas = canvas {
      canvas.frame = view.bounds
      view.addSubview(canvas)
    }
  }

  /// Makes Flutter's view controller a child, its view in the canvas.
  func embedFlutter() {
    addChild(flutter)
    placeFlutterView()
    flutter.didMove(toParent: self)
    setNeedsStatusBarAppearanceUpdate()
  }

  /// Puts Flutter's view back in its host (the canvas, or `view` after a
  /// fallback) if anything took it out, and sizes it to the window.
  private func placeFlutterView() {
    guard let flutterView = flutter.viewIfLoaded, let root = viewIfLoaded else { return }
    let host: UIView = canvas ?? root
    if flutterView.superview !== host {
      flutterView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      host.addSubview(flutterView)
      // VoiceOver reads Flutter's semantics directly, without walking
      // through the text field's canvas.
      root.accessibilityElements = [flutterView]
    }
    flutterView.frame = host.bounds
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    // Rotation, split screen, Stage Manager: the canvas and Flutter follow
    // the window (Flutter then updates its own size and safe areas).
    canvas?.frame = view.bounds
    if flutter.parent === self { placeFlutterView() }
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    guard !checked else { return }
    checked = true
    verifySecureLayer()
  }

  /// On screen, a touch in the middle of the window must reach Flutter
  /// through the canvas; otherwise Flutter leaves the secure layer.
  private func verifySecureLayer() {
    guard let canvas = canvas else { return }
    guard let flutterView = flutter.viewIfLoaded else {
      leaveSecureLayer(reason: "Flutter's view is not loaded")
      return
    }
    view.layoutIfNeeded()
    let center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
    let reachesFlutter = view.hitTest(center, with: nil)?.isDescendant(of: flutterView) ?? false
    guard canvas.window != nil, flutterView.isDescendant(of: canvas), reachesFlutter else {
      leaveSecureLayer(reason: "touches do not reach Flutter through the secure canvas")
      return
    }
    SecureCapture.report(.active)
  }

  private func leaveSecureLayer(reason: String) {
    guard let canvas = canvas else { return }
    self.canvas = nil
    placeFlutterView()
    canvas.removeFromSuperview()
    SecureCapture.report(.unavailable(reason))
  }

  // Flutter decides, as when it was the window's root ---------------------

  override var childForStatusBarStyle: UIViewController? { flutter }

  override var childForStatusBarHidden: UIViewController? { flutter }

  override var childForHomeIndicatorAutoHidden: UIViewController? { flutter }

  override var childForScreenEdgesDeferringSystemGestures: UIViewController? { flutter }

  override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
    flutter.supportedInterfaceOrientations
  }
}
