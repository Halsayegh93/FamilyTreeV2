import UIKit
import UserNotifications

extension Notification.Name {
    /// تغيّر صف في women_members عبر realtime — الشاشات المفتوحة تعيد الجلب.
    static let womenMembersChanged           = Notification.Name("womenMembersChanged")
    static let didReceiveAPNSToken           = Notification.Name("didReceiveAPNSToken")
    static let didReceivePushNotification    = Notification.Name("didReceivePushNotification")
    static let didTapPushNotification        = Notification.Name("didTapPushNotification")
    /// Posted when the admin taps "قبول" on a push notification banner.
    /// userInfo: ["request_id": String, "request_type": String]
    static let didTapApproveRequestAction    = Notification.Name("didTapApproveRequestAction")
    /// Posted when the admin taps "فتح الطلب" on a push notification banner.
    /// userInfo: ["request_id": String, "request_type": String]
    static let didTapOpenRequestAction       = Notification.Name("didTapOpenRequestAction")
}

// MARK: - Action / Category identifiers

private enum PushAction {
    static let approveRequest = "APPROVE_REQUEST"
    /// زر «رفض» القديم — أُزيل من الإشعار (فحص الثغرات ب-١): كان يفصل الأبناء ويحذف من
    /// شاشة القفل بلا تحقق ولا تأكيد. بقي المعرّف فقط ليفتح المراجعة لو وصل من إشعار قديم.
    static let rejectRequest  = "REJECT_REQUEST"
    static let openRequest    = "OPEN_REQUEST"
}

private enum PushCategory {
    static let adminRequest     = "ADMIN_REQUEST"
    /// طلب انضمام — له خياران: قبول سريع + فتح للمراجعة
    static let joinRequest      = "JOIN_REQUEST"
}

final class PushNotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let approveAction = UNNotificationAction(
            identifier: PushAction.approveRequest,
            title: "قبول ✓",
            options: [.authenticationRequired]
        )
        // لا «رفض» من شاشة القفل (ب-١): الرفض من شاشة المراجعة فقط — بتحقق أن الطلب
        // ما زال معلّقاً، وصلاحية الدور، وتأكيد، وأخطاء ظاهرة. «فتح الطلب» يفتحها مباشرة.
        let openAction = UNNotificationAction(
            identifier: PushAction.openRequest,
            title: "فتح الطلب",
            options: [.foreground]
        )

        // فئة طلب الانضمام — قبول + فتح للمراجعة
        let joinCategory = UNNotificationCategory(
            identifier: PushCategory.joinRequest,
            actions: [approveAction, openAction],
            intentIdentifiers: [],
            options: []
        )

        // فئة باقي الطلبات — قبول + فتح للمراجعة
        let adminCategory = UNNotificationCategory(
            identifier: PushCategory.adminRequest,
            actions: [approveAction, openAction],
            intentIdentifiers: [],
            options: []
        )

        center.setNotificationCategories([joinCategory, adminCategory])

        Task { try? await center.setBadgeCount(0) }

        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            Task { @MainActor in
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

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        NotificationCenter.default.post(name: .didReceivePushNotification, object: notification.request.content.userInfo)
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let requestId   = userInfo["request_id"]   as? String
        let requestType = userInfo["request_type"] as? String

        switch response.actionIdentifier {
        case PushAction.approveRequest:
            if let requestId, let requestType {
                NotificationCenter.default.post(
                    name: .didTapApproveRequestAction,
                    object: nil,
                    userInfo: ["request_id": requestId, "request_type": requestType]
                )
            }
        case PushAction.openRequest, PushAction.rejectRequest:
            // «رفض» من إشعار قديم يفتح المراجعة فقط — لا إجراء هدّام من شاشة القفل (ب-١)
            // كان `as Any` يحوّل nil إلى NSNull → downstream `as? String` يرجع nil
            // حتى لو المفتاح موجود. الآن نُضمن أن المفتاح يطلع فقط لو القيمة موجودة.
            var info: [AnyHashable: Any] = [:]
            if let requestId   { info["request_id"]   = requestId }
            if let requestType { info["request_type"] = requestType }
            NotificationCenter.default.post(name: .didTapOpenRequestAction, object: nil, userInfo: info)
        default:
            // ضغط على الإشعار نفسه (بدون action)
            if let requestId {
                var info: [AnyHashable: Any] = ["request_id": requestId]
                if let requestType { info["request_type"] = requestType }
                NotificationCenter.default.post(name: .didTapOpenRequestAction, object: nil, userInfo: info)
            } else {
                NotificationCenter.default.post(name: .didTapPushNotification, object: userInfo)
            }
        }

        completionHandler()
    }
}
