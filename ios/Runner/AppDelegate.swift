import AudioToolbox
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "CaptureGuard") {
      CaptureGuard.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ClearPlayer") {
      ClearPlayerFactory.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "NotificationChime") {
      AppDelegate.registerChime(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AppUpdate") {
      AppDelegate.registerAppUpdate(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ScreenAwake") {
      AppDelegate.registerScreenAwake(with: registrar)
    }
  }

  /// `nova/screen` (D-133): the screen stays on while a video plays, as on
  /// YouTube; Dart releases it on pause, end or exit, and the normal
  /// auto-lock applies again.
  private static func registerScreenAwake(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "nova/screen", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      guard call.method == "keepOn" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let on = (call.arguments as? Bool) ?? false
      DispatchQueue.main.async {
        UIApplication.shared.isIdleTimerDisabled = on
      }
      result(nil)
    }
  }

  /// `nova/app_update`: the installed version and bundle id, compared by
  /// Dart with the App Store lookup (store updates, 2026-09-26).
  private static func registerAppUpdate(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "nova/app_update", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      guard call.method == "version" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let info = Bundle.main.infoDictionary ?? [:]
      result([
        "bundleId": Bundle.main.bundleIdentifier ?? "",
        "version": info["CFBundleShortVersionString"] as? String ?? "",
        "build": info["CFBundleVersion"] as? String ?? "",
        "osVersion": UIDevice.current.systemVersion,
      ])
    }
  }

  /// `nova/chime`: a short system sound when a notification arrives in
  /// realtime (the in-app banner's chime). A system sound, unlike an
  /// alert sound, stays silent when the ring/silent switch is on silent.
  private static func registerChime(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "nova/chime", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      guard call.method == "play" else {
        result(FlutterMethodNotImplemented)
        return
      }
      AudioServicesPlaySystemSound(SystemSoundID(1007))
      result(true)
    }
  }
}
