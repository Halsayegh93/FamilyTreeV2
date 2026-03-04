import UIKit
import UserNotifications

extension Notification.Name {
    static let didReceiveAPNSToken = Notification.Name("didReceiveAPNSToken")
    static let didReceivePushNotification = Notification.Name("didReceivePushNotification")
    static let didTapPushNotification = Notification.Name("didTapPushNotification")
}

final class PushNotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // مسح Badge عند فتح التطبيق
        Task { try? await UNUserNotificationCenter.current().setBadgeCount(0) }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        NotificationCenter.default.post(name: .didReceiveAPNSToken, object: token)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Log.error("APNs registration failed: \(error.localizedDescription)")
    }

    /// عرض الإشعار وهو داخل التطبيق (foreground)
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // إعلام التطبيق بوصول إشعار جديد لتحديث القائمة
        NotificationCenter.default.post(name: .didReceivePushNotification, object: notification.request.content.userInfo)
        completionHandler([.banner, .sound, .badge])
    }
    
    /// عند ضغط المستخدم على الإشعار
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        NotificationCenter.default.post(name: .didTapPushNotification, object: response.notification.request.content.userInfo)
        completionHandler()
    }
}
