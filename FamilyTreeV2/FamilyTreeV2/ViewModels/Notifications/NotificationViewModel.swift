import Foundation
import Supabase
import SwiftUI
import Combine
import UIKit

@MainActor
class NotificationViewModel: ObservableObject {
    
    let supabase = SupabaseConfig.client
    
    @Published var notifications: [AppNotification] = []
    @Published var notificationsFeatureAvailable: Bool = true
    @Published var pushToken: String?
    @Published var isLoading: Bool = false
    @Published var linkedDevices: [LinkedDevice] = []
    
    /// نموذج الجهاز المرتبط
    struct LinkedDevice: Identifiable, Codable {
        let id: Int
        let memberId: UUID
        let token: String?
        let platform: String
        let deviceName: String?
        let deviceId: String?
        let createdAt: String
        let updatedAt: String
        
        enum CodingKeys: String, CodingKey {
            case id
            case memberId = "member_id"
            case token
            case platform
            case deviceName = "device_name"
            case deviceId = "device_id"
            case createdAt = "created_at"
            case updatedAt = "updated_at"
        }
        
        /// هل هذا الجهاز الحالي
        func isCurrent(currentDeviceId: String?) -> Bool {
            guard let currentDeviceId, let deviceId else { return false }
            return deviceId == currentDeviceId
        }
        
        /// اسم الجهاز للعرض (نوع الجهاز)
        var displayName: String {
            if let name = deviceName, !name.isEmpty {
                return name
            }
            return platform.uppercased()
        }
    }
    
    /// الحصول على نوع الجهاز الحقيقي (مثل iPhone 16 Pro Max)
    static var deviceModelName: String {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        let identifier = String(cString: machine)
        return mapIdentifierToName(identifier)
    }
    
    private static func mapIdentifierToName(_ id: String) -> String {
        // Simulator
        if id == "x86_64" || id == "arm64" {
            return "Simulator"
        }
        
        let map: [String: String] = [
            // iPhone
            "iPhone10,1": "iPhone 8", "iPhone10,4": "iPhone 8",
            "iPhone10,2": "iPhone 8 Plus", "iPhone10,5": "iPhone 8 Plus",
            "iPhone10,3": "iPhone X", "iPhone10,6": "iPhone X",
            "iPhone11,2": "iPhone XS",
            "iPhone11,4": "iPhone XS Max", "iPhone11,6": "iPhone XS Max",
            "iPhone11,8": "iPhone XR",
            "iPhone12,1": "iPhone 11",
            "iPhone12,3": "iPhone 11 Pro",
            "iPhone12,5": "iPhone 11 Pro Max",
            "iPhone12,8": "iPhone SE (2nd)",
            "iPhone13,1": "iPhone 12 mini",
            "iPhone13,2": "iPhone 12",
            "iPhone13,3": "iPhone 12 Pro",
            "iPhone13,4": "iPhone 12 Pro Max",
            "iPhone14,4": "iPhone 13 mini",
            "iPhone14,5": "iPhone 13",
            "iPhone14,2": "iPhone 13 Pro",
            "iPhone14,3": "iPhone 13 Pro Max",
            "iPhone14,6": "iPhone SE (3rd)",
            "iPhone14,7": "iPhone 14",
            "iPhone14,8": "iPhone 14 Plus",
            "iPhone15,2": "iPhone 14 Pro",
            "iPhone15,3": "iPhone 14 Pro Max",
            "iPhone15,4": "iPhone 15",
            "iPhone15,5": "iPhone 15 Plus",
            "iPhone16,1": "iPhone 15 Pro",
            "iPhone16,2": "iPhone 15 Pro Max",
            "iPhone17,1": "iPhone 16 Pro",
            "iPhone17,2": "iPhone 16 Pro Max",
            "iPhone17,3": "iPhone 16",
            "iPhone17,4": "iPhone 16 Plus",
            "iPhone17,5": "iPhone 16e",
            // iPad
            "iPad13,1": "iPad Air (4th)", "iPad13,2": "iPad Air (4th)",
            "iPad13,4": "iPad Pro 11\" (3rd)", "iPad13,5": "iPad Pro 11\" (3rd)",
            "iPad13,6": "iPad Pro 11\" (3rd)", "iPad13,7": "iPad Pro 11\" (3rd)",
            "iPad13,8": "iPad Pro 12.9\" (5th)", "iPad13,9": "iPad Pro 12.9\" (5th)",
            "iPad13,10": "iPad Pro 12.9\" (5th)", "iPad13,11": "iPad Pro 12.9\" (5th)",
            "iPad13,16": "iPad Air (5th)", "iPad13,17": "iPad Air (5th)",
            "iPad13,18": "iPad (10th)", "iPad13,19": "iPad (10th)",
            "iPad14,1": "iPad mini (6th)", "iPad14,2": "iPad mini (6th)",
            "iPad14,3": "iPad Pro 11\" (4th)", "iPad14,4": "iPad Pro 11\" (4th)",
            "iPad14,5": "iPad Pro 12.9\" (6th)", "iPad14,6": "iPad Pro 12.9\" (6th)",
            "iPad14,8": "iPad Air 11\" (M2)", "iPad14,9": "iPad Air 11\" (M2)",
            "iPad14,10": "iPad Air 13\" (M2)", "iPad14,11": "iPad Air 13\" (M2)",
            "iPad16,1": "iPad mini (A17 Pro)", "iPad16,2": "iPad mini (A17 Pro)",
            "iPad16,3": "iPad Pro 11\" (M4)", "iPad16,4": "iPad Pro 11\" (M4)",
            "iPad16,5": "iPad Pro 13\" (M4)", "iPad16,6": "iPad Pro 13\" (M4)",
            // 2025 iPads
            "iPad15,3": "iPad Air 11\" (M3)", "iPad15,4": "iPad Air 11\" (M3)",
            "iPad15,5": "iPad Air 13\" (M3)", "iPad15,6": "iPad Air 13\" (M3)",
            "iPad15,7": "iPad (A16)", "iPad15,8": "iPad (A16)",
        ]
        
        return map[id] ?? UIDevice.current.model
    }
    
    /// معرّف الجهاز الحالي
    var currentDeviceId: String? {
        UIDevice.current.identifierForVendor?.uuidString
    }
    
    private var lastNotificationsFetchDate: Date?
    
    weak var authVM: AuthViewModel?
    weak var appSettingsVM: AppSettingsViewModel?

    /// الحد الأقصى للأجهزة — يُقرأ من إعدادات التطبيق أو القيمة الافتراضية
    private var maxDevicesAllowed: Int {
        appSettingsVM?.settings.maxDevicesPerUser ?? AuthViewModel.maxDevicesPerAccount
    }
    
    // MARK: - Computed Properties
    
    var unreadNotificationsCount: Int {
        notifications.filter { !$0.read && $0.targetMemberId != nil }.count
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
    
    // MARK: - Device Registration
    
    /// تسجيل الجهاز عند تسجيل الدخول (بغض النظر عن الإشعارات)
    func registerDevice() async {
        guard let memberId = currentUser?.id else {
            Log.warning("[DEVICE] لا يوجد مستخدم حالي — تخطي تسجيل الجهاز")
            return
        }
        guard let deviceId = currentDeviceId else {
            Log.warning("[DEVICE] لا يمكن الحصول على معرّف الجهاز")
            return
        }

        let deviceModelName = NotificationViewModel.deviceModelName
        let platform = UIDevice.current.userInterfaceIdiom == .pad ? "ipados" : "ios"

        Log.info("[DEVICE] بدء تسجيل الجهاز: \(deviceModelName) (\(platform)), deviceId=\(deviceId.prefix(8))...")

        // فحص حد الأجهزة
        do {
            let existingDevices: [LinkedDevice] = try await supabase
                .from("device_tokens")
                .select()
                .eq("member_id", value: memberId.uuidString)
                .execute()
                .value

            let isAlreadyRegistered = existingDevices.contains { $0.deviceId == deviceId }

            if !isAlreadyRegistered && existingDevices.count >= maxDevicesAllowed {
                Log.warning("[DEVICE] تجاوز الحد: \(existingDevices.count) أجهزة مسجلة، الحد \(maxDevicesAllowed)")
                self.linkedDevices = existingDevices
                self.isDeviceLimitExceeded = true
                authVM?.status = .deviceLimitExceeded
                return
            }
        } catch {
            Log.error("[DEVICE] خطأ فحص حد الأجهزة: \(error.localizedDescription)")
        }

        // تسجيل الجهاز — نرسل token فارغ احتياطاً لتفادي خطأ NOT NULL
        do {
            let isoNow = ISO8601DateFormatter().string(from: Date())
            let payload: [String: AnyEncodable] = [
                "member_id": AnyEncodable(memberId.uuidString),
                "device_id": AnyEncodable(deviceId),
                "platform": AnyEncodable(platform),
                "device_name": AnyEncodable(deviceModelName),
                "token": AnyEncodable(pushToken ?? ""),
                "updated_at": AnyEncodable(isoNow)
            ]

            try await supabase
                .from("device_tokens")
                .upsert(payload, onConflict: "member_id,device_id")
                .execute()

            Log.info("[DEVICE] تم تسجيل الجهاز بنجاح: \(deviceModelName)")
        } catch {
            Log.error("[DEVICE] خطأ تسجيل الجهاز: \(error.localizedDescription) — deviceId=\(deviceId.prefix(8)), model=\(deviceModelName)")
        }
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
        guard let deviceId = currentDeviceId else { return }
        
        // تحديث التوكن على سجل الجهاز الحالي
        do {
            try await supabase
                .from("device_tokens")
                .update([
                    "token": AnyEncodable(cleanToken)
                ])
                .eq("member_id", value: memberId.uuidString)
                .eq("device_id", value: deviceId)
                .execute()
            
            Log.info("[DEVICE] تم تحديث Push Token للجهاز")
        } catch {
            Log.error("خطأ تحديث Push Token: \(error.localizedDescription)")
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
    
    @Published var isDeviceLimitExceeded: Bool = false
    
    // MARK: - Linked Devices
    
    func fetchLinkedDevices() async {
        guard let memberId = currentUser?.id else { return }
        do {
            let devices: [LinkedDevice] = try await supabase
                .from("device_tokens")
                .select()
                .eq("member_id", value: memberId.uuidString)
                .order("updated_at", ascending: false)
                .execute()
                .value
            self.linkedDevices = devices
        } catch {
            Log.error("خطأ جلب الأجهزة المرتبطة: \(error.localizedDescription)")
        }
    }
    
    /// التحقق من عدد الأجهزة عند تسجيل الدخول
    func checkDeviceLimit() async {
        guard let memberId = currentUser?.id else { return }
        do {
            let devices: [LinkedDevice] = try await supabase
                .from("device_tokens")
                .select()
                .eq("member_id", value: memberId.uuidString)
                .execute()
                .value
            self.linkedDevices = devices
            
            let isCurrentDeviceRegistered = devices.contains { $0.deviceId == currentDeviceId }
            
            // إذا الجهاز الحالي مسجل، ما في مشكلة
            if isCurrentDeviceRegistered {
                self.isDeviceLimitExceeded = false
                return
            }
            
            // إذا وصل الحد الأقصى وهذا جهاز جديد
            if devices.count >= maxDevicesAllowed {
                Log.warning("[DEVICE] تجاوز الحد الأقصى للأجهزة: \(devices.count)/\(maxDevicesAllowed)")
                self.isDeviceLimitExceeded = true
                self.linkedDevices = devices
                authVM?.status = .deviceLimitExceeded
            } else {
                self.isDeviceLimitExceeded = false
            }
        } catch {
            Log.error("خطأ فحص حد الأجهزة: \(error.localizedDescription)")
        }
    }
    
    func removeDevice(_ device: LinkedDevice) async {
        do {
            try await supabase
                .from("device_tokens")
                .delete()
                .eq("id", value: device.id)
                .execute()
            self.linkedDevices.removeAll { $0.id == device.id }
            Log.info("تم حذف الجهاز بنجاح")
        } catch {
            Log.error("خطأ حذف الجهاز: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Admin Device Management
    
    /// جلب أجهزة عضو محدد (للمدير)
    func fetchDevicesForMember(_ memberId: UUID) async -> [LinkedDevice] {
        do {
            let devices: [LinkedDevice] = try await supabase
                .from("device_tokens")
                .select()
                .eq("member_id", value: memberId.uuidString)
                .order("updated_at", ascending: false)
                .execute()
                .value
            return devices
        } catch {
            Log.error("[ADMIN-DEVICE] خطأ جلب أجهزة العضو: \(error.localizedDescription)")
            return []
        }
    }
    
    /// حذف جهاز عضو بواسطة المدير
    func removeDeviceByAdmin(_ device: LinkedDevice) async -> Bool {
        do {
            try await supabase
                .from("device_tokens")
                .delete()
                .eq("id", value: device.id)
                .execute()
            Log.info("[ADMIN-DEVICE] تم حذف جهاز العضو بنجاح: \(device.displayName)")
            return true
        } catch {
            Log.error("[ADMIN-DEVICE] خطأ حذف جهاز العضو: \(error.localizedDescription)")
            return false
        }
    }
    
    /// جلب جميع الأجهزة المسجلة (للمدير)
    func fetchAllDevices() async -> [LinkedDevice] {
        do {
            let devices: [LinkedDevice] = try await supabase
                .from("device_tokens")
                .select()
                .order("updated_at", ascending: false)
                .execute()
                .value
            return devices
        } catch {
            Log.error("[ADMIN-DEVICE] خطأ جلب جميع الأجهزة: \(error.localizedDescription)")
            return []
        }
    }
    
    // MARK: - Device Authorization
    
    /// فحص: هل الجهاز كان مسجّل سابقاً وتم حذفه بواسطة المدير أو المستخدم؟
    /// يرجع true إذا العضو عنده أجهزة أخرى لكن هذا الجهاز مو منهم (يعني انحذف)
    func checkIfDeviceWasRevoked() async -> Bool {
        guard let memberId = currentUser?.id else { return false }
        guard let deviceId = currentDeviceId else { return false }
        
        do {
            // جلب كل أجهزة العضو
            let allDevices: [LinkedDevice] = try await supabase
                .from("device_tokens")
                .select()
                .eq("member_id", value: memberId.uuidString)
                .execute()
                .value
            
            // إذا ما في أجهزة أبداً = أول تسجيل، مو محذوف
            if allDevices.isEmpty {
                Log.info("[DEVICE-REVOKE] لا توجد أجهزة مسجلة — أول تسجيل")
                return false
            }
            
            // إذا في أجهزة لكن هذا الجهاز مو منهم = تم حذفه
            let thisDeviceExists = allDevices.contains { $0.deviceId == deviceId }
            if !thisDeviceExists {
                Log.warning("[DEVICE-REVOKE] الجهاز \(deviceId.prefix(8))… محذوف — العضو عنده \(allDevices.count) أجهزة أخرى")
                return true
            }
            
            return false
        } catch {
            Log.error("[DEVICE-REVOKE] خطأ فحص الحذف: \(error.localizedDescription)")
            return false
        }
    }
    
    /// التحقق من أن الجهاز الحالي مسجّل
    /// - إذا حذفه المدير (توجد أجهزة أخرى) → يمنع الوصول
    /// - إذا ما في أجهزة مسجلة أصلاً → يسجله عادي
    func verifyDeviceAuthorization() async {
        guard let memberId = currentUser?.id else {
            Log.info("[DEVICE-VERIFY] تخطي — لا يوجد مستخدم حالي")
            return
        }
        guard let deviceId = currentDeviceId else {
            Log.info("[DEVICE-VERIFY] تخطي — لا يوجد معرّف جهاز")
            return
        }

        Log.info("[DEVICE-VERIFY] التحقق من تصريح الجهاز: \(deviceId.prefix(8))… للعضو: \(memberId.uuidString.prefix(8))…")

        do {
            // جلب كل أجهزة العضو (مو بس الجهاز الحالي)
            let allDevices: [LinkedDevice] = try await supabase
                .from("device_tokens")
                .select()
                .eq("member_id", value: memberId.uuidString)
                .execute()
                .value

            let thisDeviceExists = allDevices.contains { $0.deviceId == deviceId }

            if thisDeviceExists {
                Log.info("[DEVICE-VERIFY] الجهاز مصرّح ✓")
            } else if allDevices.isEmpty {
                // ما في أجهزة مسجلة أصلاً → تسجيل أول مرة
                Log.info("[DEVICE-VERIFY] لا توجد أجهزة مسجلة — تسجيل تلقائي…")
                await registerDevice()
                Log.info("[DEVICE-VERIFY] تم تسجيل الجهاز ✓")
            } else {
                // توجد أجهزة أخرى لكن هذا محذوف → المدير حذفه
                Log.warning("[DEVICE-VERIFY] الجهاز محذوف من قِبل المدير — منع الوصول")
                self.linkedDevices = allDevices
                self.isDeviceLimitExceeded = true
                authVM?.status = .deviceLimitExceeded
            }
        } catch {
            Log.error("[DEVICE-VERIFY] خطأ التحقق من تصريح الجهاز: \(error.localizedDescription)")
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
        if !force, let last = lastNotificationsFetchDate, Date().timeIntervalSince(last) < 15, !notifications.isEmpty {
            Log.info("[NOTIF-FETCH] تخطي الجلب (cache ≤ 15 ثانية) — عدد حالي: \(notifications.count)")
            return
        }
        lastNotificationsFetchDate = Date()
        guard let userId = currentUser?.id else {
            Log.warning("[NOTIF-FETCH] لا يوجد مستخدم حالي — تفريغ الإشعارات")
            notifications = []
            return
        }
        guard notificationsFeatureAvailable else {
            Log.warning("[NOTIF-FETCH] الإشعارات غير متاحة — تفريغ")
            notifications = []
            return
        }
        
        Log.info("[NOTIF-FETCH] جلب إشعارات للعضو: \(userId.uuidString) (force: \(force))")
        
        do {
            // جلب الإشعارات الموجهة للعضو شخصياً فقط (بدون البث الإداري)
            let response: [AppNotification] = try await supabase
                .from("notifications")
                .select()
                .eq("target_member_id", value: userId.uuidString)
                .order("created_at", ascending: false)
                .limit(10000)
                .execute()
                .value
            
            let unreadCount = response.filter { !$0.read }.count
            Log.info("[NOTIF-FETCH] ✅ تم الجلب — إجمالي: \(response.count) | غير مقروء: \(unreadCount)")
            
            self.notificationsFeatureAvailable = true
            self.notifications = response
            let badgeOn = currentUser?.badgeEnabled ?? true
            try? await UNUserNotificationCenter.current().setBadgeCount(badgeOn ? unreadCount : 0)
        } catch {
            if isMissingNotificationsTableError(error) {
                notificationsFeatureAvailable = false
                notifications = []
                Log.error("[NOTIF-FETCH] ❌ جدول الإشعارات غير موجود")
            } else {
                Log.error("[NOTIF-FETCH] ❌ خطأ جلب الإشعارات: \(error.localizedDescription)")
            }
        }
    }
    
    func deleteNotification(id: UUID) async {
        Log.info("[NOTIF-DELETE] حذف إشعار واحد: \(id.uuidString.prefix(8))… | قبل الحذف: \(notifications.count)")
        // تحديث محلي فوري
        notifications.removeAll { $0.id == id }
        Log.info("[NOTIF-DELETE] بعد الحذف المحلي: \(notifications.count)")
        let badgeOn = currentUser?.badgeEnabled ?? true
        let unread = notifications.filter { !$0.read }.count
        try? await UNUserNotificationCenter.current().setBadgeCount(badgeOn ? unread : 0)
        
        do {
            try await supabase
                .from("notifications")
                .delete()
                .eq("id", value: id.uuidString)
                .execute()
            Log.info("[NOTIF-DELETE] ✅ تم الحذف من قاعدة البيانات — إعادة جلب للتأكد")
            await fetchNotifications(force: true)
        } catch {
            Log.error("[NOTIF-DELETE] ❌ خطأ حذف إشعار: \(error.localizedDescription)")
            await fetchNotifications(force: true)
        }
    }
    
    func deleteNotifications(ids: Set<UUID>) async {
        guard !ids.isEmpty else { return }
        Log.info("[NOTIF-DELETE-MULTI] حذف \(ids.count) إشعار | قبل الحذف: \(notifications.count)")
        for id in ids {
            Log.info("[NOTIF-DELETE-MULTI]   → \(id.uuidString.prefix(8))…")
        }
        // تحديث محلي فوري
        notifications.removeAll { ids.contains($0.id) }
        Log.info("[NOTIF-DELETE-MULTI] بعد الحذف المحلي: \(notifications.count)")
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
            Log.info("[NOTIF-DELETE-MULTI] ✅ تم الحذف من قاعدة البيانات — إعادة جلب للتأكد")
            await fetchNotifications(force: true)
        } catch {
            Log.error("[NOTIF-DELETE-MULTI] ❌ خطأ حذف إشعارات: \(error.localizedDescription)")
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
        
        do {
            try await supabase
                .from("notifications")
                .update(["is_read": AnyEncodable(true)])
                .eq("target_member_id", value: userId.uuidString)
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
                let payloads = ids.map { memberId in
                    [
                        "target_member_id": AnyEncodable(memberId.uuidString),
                        "title": AnyEncodable(title),
                        "body": AnyEncodable(body),
                        "kind": AnyEncodable("admin"),
                        "created_by": AnyEncodable(creator.uuidString)
                    ]
                }
                try await supabase.from("notifications").insert(payloads).execute()
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
