import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var pendingTokenResult: FlutterResult?
  private var pushRegistrationChannel: FlutterMethodChannel?
  private var pendingAutoCouponDay: String?
  private var pendingOnDemandCouponTap = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let launched = super.application(
      application, didFinishLaunchingWithOptions: launchOptions
    )
    // iOS suppresses presentation of local notifications in the foreground
    // unless the app registers a UNUserNotificationCenter delegate.
    // Delegate methods below preserve existing remote APNs forwarding.
    UNUserNotificationCenter.current().delegate = self
    return launched
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "GoalVdLinePushRegistration") else {
      return
    }
    let channel = FlutterMethodChannel(name: "goalvdline/push_registration",
      binaryMessenger: registrar.messenger())
    // Local on-demand notifications are independent from the remote APNs
    // AutoSchedina feature, which remains disabled until a future release.
    if let localRegistrar = engineBridge.pluginRegistry.registrar(forPlugin: "GoalVdLineLocalCouponNotifications") {
      let localChannel = FlutterMethodChannel(
        name: "goalvdline/local_coupon_notifications",
        binaryMessenger: localRegistrar.messenger()
      )
      localChannel.setMethodCallHandler { call, result in
        switch call.method {
        case "requestPermission":
          UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) {
            granted, _ in
            DispatchQueue.main.async { result(granted) }
          }
        case "getNotificationStatus":
          UNUserNotificationCenter.current().getNotificationSettings { settings in
            let authorization: String
            switch settings.authorizationStatus {
            case .authorized:
              authorization = "authorized"
            case .provisional:
              authorization = "provisional"
            case .denied:
              authorization = "denied"
            case .notDetermined:
              authorization = "notDetermined"
            case .ephemeral:
              authorization = "ephemeral"
            @unknown default:
              authorization = "unknown"
            }
            DispatchQueue.main.async {
              result([
                "authorization": authorization,
                "lockScreen": settings.lockScreenSetting == .enabled,
                "alerts": settings.alertSetting == .enabled,
                "notificationCenter": settings.notificationCenterSetting == .enabled
              ])
            }
          }
        case "sendLockScreenTestNotification":
          // Delayed local notification is scheduled BEFORE the phone locks.
          // It tests iOS delivery, not background coupon generation or APNs.
          let center = UNUserNotificationCenter.current()
          center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized ||
                  settings.authorizationStatus == .provisional else {
              DispatchQueue.main.async { result(false) }
              return
            }
            let content = UNMutableNotificationContent()
            content.title = "GoalVdLine • Prova schermo bloccato"
            content.body = "Test iOS: notifica programmata 15 secondi fa. Nessuna schedina generata."
            content.sound = .default
            content.userInfo = ["kind": "local_notification_test"]
            let request = UNNotificationRequest(
              identifier: "goalvdline-lock-screen-diagnostic",
              content: content,
              trigger: UNTimeIntervalNotificationTrigger(timeInterval: 15, repeats: false)
            )
            center.add(request) { error in
              DispatchQueue.main.async { result(error == nil) }
            }
          }
        case "sendTestNotification":
          // Only a user-initiated diagnostics notification. Never claim
          // a coupon was created or re-use a coupon-ready tap payload.
          let center = UNUserNotificationCenter.current()
          center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized ||
                  settings.authorizationStatus == .provisional else {
              DispatchQueue.main.async { result(false) }
              return
            }
            let content = UNMutableNotificationContent()
            content.title = "GoalVdLine • Prova notifiche"
            content.body = "Notifica di prova ricevuta. Non è stata generata una schedina."
            content.sound = .default
            content.userInfo = ["kind": "local_notification_test"]
            let request = UNNotificationRequest(
              identifier: "goalvdline-local-notification-test",
              content: content,
              trigger: UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
            )
            center.add(request) { error in
              DispatchQueue.main.async { result(error == nil) }
            }
          }
        case "notifyReady":
          guard let args = call.arguments as? [String: Any],
                let coupons = args["coupons"] as? Int,
                let fixtures = args["fixtures"] as? Int,
                coupons > 0, coupons <= 10,
                fixtures > 0, fixtures <= 15 else {
            result(false)
            return
          }
          let center = UNUserNotificationCenter.current()
          center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized ||
                  settings.authorizationStatus == .provisional else {
              DispatchQueue.main.async { result(false) }
              return
            }
            let content = UNMutableNotificationContent()
            content.title = "GoalVdLine • Schedina pronta"
            content.body = coupons == 1
              ? "La tua schedina AI è pronta: \(fixtures) partite."
              : "\(coupons) schedine AI pronte. \(fixtures) partite nella principale."
            content.sound = .default
            content.userInfo = ["kind": "on_demand_coupon_ready"]
            // Only the latest locally saved coupon is actionable.
            // Do not leave older notifications pointing to a newer snapshot.
            let latestId = "goalvdline-on-demand-latest"
            center.removePendingNotificationRequests(withIdentifiers: [latestId])
            center.removeDeliveredNotifications(withIdentifiers: [latestId])
            let request = UNNotificationRequest(
              identifier: latestId,
              content: content,
              trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            )
            center.add(request) { error in
              DispatchQueue.main.async { result(error == nil) }
            }
          }
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
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
      case "consumePendingOnDemandCouponTap":
        DispatchQueue.main.async {
          let value = self?.pendingOnDemandCouponTap ?? false
          self?.pendingOnDemandCouponTap = false
          result(value)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }

  }

  // Display on-demand local completion notifications while the app is open.
  // Remote AutoSchedina APNs handling stays unchanged.
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler:
      @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    let kind = notification.request.content.userInfo["kind"] as? String
    if kind == "on_demand_coupon_ready" ||
        kind == "local_notification_test" {
      completionHandler([.banner, .sound, .list])
      return
    }
    super.userNotificationCenter(
      center, willPresent: notification, withCompletionHandler: completionHandler)
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
    } else if (info["kind"] as? String) == "on_demand_coupon_ready" {
      pendingOnDemandCouponTap = true
      pushRegistrationChannel?.invokeMethod("onDemandCouponOpened", arguments: nil)
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
