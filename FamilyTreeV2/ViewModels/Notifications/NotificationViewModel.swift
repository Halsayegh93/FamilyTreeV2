import Foundation
import Supabase
import SwiftUI
import Combine

@MainActor
class NotificationViewModel: ObservableObject {
    
    let supabase = SupabaseConfig.client
    
    @Published var notifications: [AppNotification] = []
    @Published var notificationsFeatureAvailable: Bool = true
    @Published var pushToken: String?
    @Published var isLoading: Bool = false
    
    private var lastNotificationsFetchDate: Date?
    
    weak var authVM: AuthViewModel?
    
    // MARK: - Computed Properties
    
    var unreadNotificationsCount: Int {
        notifications.filter { !$0.read }.count
    }
    
    private var currentUser: FamilyMember? {
        authVM?.currentUser
    }
    
    private var canModerate: Bool {
        authVM?.canModerate ?? false
    }
    
    // MARK: - Configure
    
    func configure(authVM: AuthViewModel) {
        self.authVM = authVM
    }
    
    // MARK: - Error Helpers
    
    private func schemaErrorDescription(_ error: Error) -> String {
        let raw = String(describing: error)
        return "\(raw) \(error.localizedDescription)".lowercased()
    }
    
    private func isMissingNotificationsTableError(_ error: Error) -> Bool {
        let desc = schemaErrorDescription(error)
        return desc.contains("public.notifications") ||
        desc.contains("could not find the table") ||
        desc.contains("relation \"notifications\" does not exist") ||
        desc.contains("42p01")
    }
    
    private func isCancellationError(_ error: Error) -> Bool {
        if error is CancellationError { return true }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return true
        }

        let desc = schemaErrorDescription(error)
        return desc.contains("cancelled") || desc.contains("canceled") || desc.contains("مُلغى")
    }
    
    // MARK: - Push Token
    
    func registerPushToken(_ token: String) async {
        let cleanToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanToken.isEmpty else { return }

        self.pushToken = cleanToken

        // لا ترسل التوكن للسيرفر إذا الإشعارات مغلقة
        let notificationsEnabled = UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true
        guard notificationsEnabled else { return }

        guard let memberId = currentUser?.id else { return }
        do {
            let payload: [String: AnyEncodable] = [
                "member_id": AnyEncodable(memberId.uuidString),
                "token": AnyEncodable(cleanToken),
                "platform": AnyEncodable("ios")
            ]

            try await supabase
                .from("device_tokens")
                .upsert(payload, onConflict: "token")
                .execute()
        } catch {
            Log.error("خطأ حفظ Push Token: \(error.localizedDescription)")
        }
    }

    func unregisterPushToken() async {
        guard let memberId = currentUser?.id else { return }
        guard let token = pushToken, !token.isEmpty else { return }
        do {
            try await supabase
                .from("device_tokens")
                .delete()
                .eq("member_id", value: memberId.uuidString)
                .eq("token", value: token)
                .execute()
            Log.info("تم إلغاء تسجيل التوكن للإشعارات")
        } catch {
            Log.error("خطأ إلغاء تسجيل Push Token: \(error.localizedDescription)")
        }
    }
    
    private func sendExternalAdminPush(title: String, body: String, kind: String = "admin_request") async {
        do {
            let payload = [
                "title": title,
                "body": body,
                "kind": kind
            ]
            
            try await supabase.functions
                .invoke(
                    "push-admins",
                    options: FunctionInvokeOptions(body: payload)
                )
        } catch {
            Log.warning("تعذر إرسال Push خارجي للمدير: \(error.localizedDescription)")
        }
    }
    
    /// إرسال push حقيقي لأعضاء محددين أو للجميع عبر Edge Function
    func sendPushToMembers(title: String, body: String, kind: String = "general", targetMemberIds: [UUID]? = nil) async {
        do {
            var payload: [String: AnyEncodable] = [
                "title": AnyEncodable(title),
                "body": AnyEncodable(body),
                "kind": AnyEncodable(kind)
            ]
            if let ids = targetMemberIds, !ids.isEmpty {
                payload["member_ids"] = AnyEncodable(ids.map { $0.uuidString })
            }
            
            try await supabase.functions
                .invoke(
                    "push-notify",
                    options: FunctionInvokeOptions(body: payload)
                )
        } catch {
            Log.warning("تعذر إرسال Push للأعضاء: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Notifications
    
    func fetchNotifications(force: Bool = false) async {
        if !force, let last = lastNotificationsFetchDate, Date().timeIntervalSince(last) < 15, !notifications.isEmpty { return }
        lastNotificationsFetchDate = Date()
        guard let userId = currentUser?.id else {
            notifications = []
            return
        }
        guard notificationsFeatureAvailable else {
            notifications = []
            return
        }
        
        do {
            // المدراء يشوفون الإشعارات الموجهة لهم + البث العام (notifyAdmins)
            // الأعضاء العاديون يشوفون فقط الإشعارات الموجهة لهم شخصياً
            let filter = canModerate
                ? "target_member_id.is.null,target_member_id.eq.\(userId.uuidString)"
                : "target_member_id.eq.\(userId.uuidString)"
            
            let response: [AppNotification] = try await supabase
                .from("notifications")
                .select()
                .or(filter)
                .order("created_at", ascending: false)
                .execute()
                .value
            
            let unreadCount = response.filter { !$0.read }.count
            self.notificationsFeatureAvailable = true
            self.notifications = response
            let badgeOn = currentUser?.badgeEnabled ?? true
            try? await UNUserNotificationCenter.current().setBadgeCount(badgeOn ? unreadCount : 0)
        } catch {
            if isMissingNotificationsTableError(error) {
                notificationsFeatureAvailable = false
                notifications = []
            } else {
                Log.error("خطأ جلب الإشعارات: \(error.localizedDescription)")
            }
        }
    }
    
    func deleteNotification(id: UUID) async {
        // تحديث محلي فوري
        notifications.removeAll { $0.id == id }
        let badgeOn = currentUser?.badgeEnabled ?? true
        let unread = notifications.filter { !$0.read }.count
        try? await UNUserNotificationCenter.current().setBadgeCount(badgeOn ? unread : 0)
        
        do {
            try await supabase
                .from("notifications")
                .delete()
                .eq("id", value: id.uuidString)
                .execute()
        } catch {
            Log.error("خطأ حذف إشعار: \(error.localizedDescription)")
            await fetchNotifications(force: true)
        }
    }
    
    func deleteNotifications(ids: Set<UUID>) async {
        guard !ids.isEmpty else { return }
        // تحديث محلي فوري
        notifications.removeAll { ids.contains($0.id) }
        let badgeOn = currentUser?.badgeEnabled ?? true
        let unread = notifications.filter { !$0.read }.count
        try? await UNUserNotificationCenter.current().setBadgeCount(badgeOn ? unread : 0)
        
        do {
            let idStrings = ids.map { $0.uuidString }
            try await supabase
                .from("notifications")
                .delete()
                .in("id", values: idStrings)
                .execute()
        } catch {
            Log.error("خطأ حذف إشعارات: \(error.localizedDescription)")
            await fetchNotifications(force: true)
        }
    }
    
    func markNotificationAsRead(id: UUID) async {
        // تحديث محلي فوري
        if let idx = notifications.firstIndex(where: { $0.id == id }) {
            notifications[idx] = notifications[idx].withRead(true)
        }
        let badgeOn = currentUser?.badgeEnabled ?? true
        let unread = notifications.filter { !$0.read }.count
        try? await UNUserNotificationCenter.current().setBadgeCount(badgeOn ? unread : 0)
        
        do {
            try await supabase
                .from("notifications")
                .update(["is_read": AnyEncodable(true)])
                .eq("id", value: id.uuidString)
                .execute()
        } catch {
            Log.error("خطأ تحديث حالة الإشعار: \(error.localizedDescription)")
            await fetchNotifications(force: true)
        }
    }
    
    func markNotificationsAsRead(ids: Set<UUID>) async {
        guard !ids.isEmpty else { return }
        // تحديث محلي فوري
        for i in notifications.indices where ids.contains(notifications[i].id) {
            notifications[i] = notifications[i].withRead(true)
        }
        let badgeOn = currentUser?.badgeEnabled ?? true
        let unread = notifications.filter { !$0.read }.count
        try? await UNUserNotificationCenter.current().setBadgeCount(badgeOn ? unread : 0)
        
        do {
            let idStrings = ids.map { $0.uuidString }
            try await supabase
                .from("notifications")
                .update(["is_read": AnyEncodable(true)])
                .in("id", values: idStrings)
                .execute()
        } catch {
            Log.error("خطأ تعليم إشعارات كمقروءة: \(error.localizedDescription)")
            await fetchNotifications(force: true)
        }
    }
    
    func markAllNotificationsAsRead() async {
        guard let userId = currentUser?.id else { return }
        // تحديث محلي فوري
        for i in notifications.indices where !notifications[i].read {
            notifications[i] = notifications[i].withRead(true)
        }
        try? await UNUserNotificationCenter.current().setBadgeCount(0)
        
        let filter = canModerate
            ? "target_member_id.is.null,target_member_id.eq.\(userId.uuidString)"
            : "target_member_id.eq.\(userId.uuidString)"
        do {
            try await supabase
                .from("notifications")
                .update(["is_read": AnyEncodable(true)])
                .or(filter)
                .eq("is_read", value: false)
                .execute()
        } catch {
            Log.error("خطأ تعليم كل الإشعارات كمقروءة: \(error.localizedDescription)")
            await fetchNotifications(force: true)
        }
    }
    
    func sendNotification(title: String, body: String, targetMemberIds: [UUID]?, sendPush: Bool = true) async {
        guard canModerate, let creator = currentUser?.id else { return }
        guard notificationsFeatureAvailable else { return }
        self.isLoading = true
        
        do {
            if let ids = targetMemberIds, !ids.isEmpty {
                for memberId in ids {
                    let payload: [String: AnyEncodable] = [
                        "target_member_id": AnyEncodable(memberId.uuidString),
                        "title": AnyEncodable(title),
                        "body": AnyEncodable(body),
                        "kind": AnyEncodable("admin"),
                        "created_by": AnyEncodable(creator.uuidString)
                    ]
                    try await supabase.from("notifications").insert(payload).execute()
                }
            } else {
                let payload: [String: AnyEncodable] = [
                    "target_member_id": AnyEncodable(Optional<String>.none),
                    "title": AnyEncodable(title),
                    "body": AnyEncodable(body),
                    "kind": AnyEncodable("admin"),
                    "created_by": AnyEncodable(creator.uuidString)
                ]
                try await supabase.from("notifications").insert(payload).execute()
            }
            
            // إرسال push حقيقي للأعضاء المستهدفين
            if sendPush {
                await sendPushToMembers(
                    title: title,
                    body: body,
                    kind: "admin",
                    targetMemberIds: targetMemberIds
                )
            }
            
            // إشعار المدراء الآخرين بإرسال إشعار إداري
            await notifyAdmins(
                title: "إشعار إداري",
                body: "تم إرسال إشعار: \(title)",
                kind: "admin"
            )
            
            await fetchNotifications(force: true)
        } catch {
            if isMissingNotificationsTableError(error) {
                notificationsFeatureAvailable = false
            } else {
                Log.error("خطأ إرسال الإشعار: \(error.localizedDescription)")
            }
        }
        
        self.isLoading = false
    }

    /// إرسال إشعار واحد في مركز الإشعارات (broadcast) يراه المدراء والمشرفون
    /// target_member_id = NULL يعني broadcast — الـ RLS يتكفل بإظهاره للمدراء فقط
    func notifyAdmins(title: String, body: String, kind: String) async {
        let creatorId = currentUser?.id
        guard notificationsFeatureAvailable else { return }
        
        do {
            let payload: [String: AnyEncodable] = [
                "target_member_id": AnyEncodable(Optional<String>.none),
                "title": AnyEncodable(title),
                "body": AnyEncodable(body),
                "kind": AnyEncodable(kind),
                "created_by": AnyEncodable(creatorId?.uuidString)
            ]
            try await supabase.from("notifications").insert(payload).execute()
        } catch {
            if isMissingNotificationsTableError(error) {
                notificationsFeatureAvailable = false
            } else {
                Log.warning("تعذر إرسال إشعار للمدراء: \(error.localizedDescription)")
            }
        }
    }
    
    /// إشعار موحّد: يرسل push خارجي + إشعار داخلي في استدعاء واحد
    func notifyAdminsWithPush(title: String, body: String, kind: String) async {
        async let push: Void = sendExternalAdminPush(title: title, body: body, kind: kind)
        async let inApp: Void = notifyAdmins(title: title, body: body, kind: kind)
        _ = await (push, inApp)
    }
}
