import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var pendingTokenResult: FlutterResult?
  private var pushRegistrationChannel: FlutterMethodChannel?
  private var pendingAutoCouponDay: String?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "GoalVdLinePushRegistration") else {
      return
    }
    let channel = FlutterMethodChannel(name: "goalvdline/push_registration",
      binaryMessenger: registrar.messenger())
    pushRegistrationChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "requestDeviceToken":
        DispatchQueue.main.async { self?.requestDeviceToken(result: result) }
      case "consumePendingAutoCouponDay":
        DispatchQueue.main.async {
          let value = self?.pendingAutoCouponDay
          self?.pendingAutoCouponDay = nil
          result(value)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // Save a cold-start notification tap until Flutter can consume it.
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let info = response.notification.request.content.userInfo
    if (info["kind"] as? String) == "auto_coupon_ready",
       let day = info["dayKey"] as? String,
       day.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil {
      pendingAutoCouponDay = day
      pushRegistrationChannel?.invokeMethod("autoCouponOpened", arguments: day)
    }
    super.userNotificationCenter(center, didReceive: response,
      withCompletionHandler: completionHandler)
  }

  private func requestDeviceToken(result: @escaping FlutterResult) {
    guard pendingTokenResult == nil else {
      result(FlutterError(code: "busy", message: "Registrazione già in corso", details: nil))
      return
    }
    pendingTokenResult = result
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) {
      [weak self] granted, error in
      DispatchQueue.main.async {
        guard let self = self else { return }
        if error != nil || !granted {
          self.completeDeviceToken(nil, message: "Notifiche non autorizzate")
          return
        }
        UIApplication.shared.registerForRemoteNotifications()
      }
    }
  }

  private func completeDeviceToken(_ token: String?, message: String? = nil) {
    guard let callback = pendingTokenResult else { return }
    pendingTokenResult = nil
    if let token = token {
      callback(token)
    } else {
      callback(FlutterError(code: "registration_failed",
        message: message ?? "Registrazione APNs non disponibile", details: nil))
    }
  }

  override func application(_ application: UIApplication,
      didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
    let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
    completeDeviceToken(hex)
  }

  override func application(_ application: UIApplication,
      didFailToRegisterForRemoteNotificationsWithError error: Error) {
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
    completeDeviceToken(nil, message: "Registrazione APNs non disponibile")
  }
}
