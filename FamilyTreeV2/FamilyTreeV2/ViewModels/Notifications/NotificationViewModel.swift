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

    /// IDs قيد التحديث — يمنع fetchNotifications من الكتابة فوقها
    private var pendingReadIds: Set<UUID> = []
    /// IDs قيد الحذف — يمنع fetchNotifications من إعادتها
    private var pendingDeleteIds: Set<UUID> = []
    /// مدة الكاش بالثواني
    private let cacheDuration: TimeInterval = 30

    weak var authVM: AuthViewModel?
    weak var appSettingsVM: AppSettingsViewModel?

    /// الحد الأقصى للأجهزة — يُقرأ من إعدادات التطبيق أو القيمة الافتراضية
    private var maxDevicesAllowed: Int {
        appSettingsVM?.settings.maxDevicesPerUser ?? AuthViewModel.maxDevicesPerAccount
    }
    
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
    
    // MARK: - Error Helpers (delegated to ErrorHelper)
    
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
        #if DEBUG
        let apnsEnvironment = "sandbox"
        #else
        let apnsEnvironment = "production"
        #endif

        Log.info("[DEVICE] بدء تسجيل الجهاز: \(deviceModelName) (\(platform)/\(apnsEnvironment)), deviceId=\(deviceId.prefix(8))...")

        // فحص حد الأجهزة — إذا تجاوز الحد أظهر شاشة الإدارة بدل الحذف التلقائي
        do {
            let existingDevices: [LinkedDevice] = try await supabase
                .from("device_tokens")
                .select()
                .eq("member_id", value: memberId.uuidString)
                .execute()
                .value

            let isAlreadyRegistered = existingDevices.contains { $0.deviceId == deviceId }

            if !isAlreadyRegistered && existingDevices.count >= maxDevicesAllowed {
                Log.warning("[DEVICE] الحد الأقصى (\(maxDevicesAllowed)) — طلب المستخدم اختيار جهاز للإزالة")
                self.linkedDevices = existingDevices.sorted { $0.updatedAt > $1.updatedAt }
                await MainActor.run {
                    authVM?.status = .deviceLimitExceeded
                }
                return
            }
        } catch {
            Log.error("[DEVICE] خطأ فحص حد الأجهزة: \(error.localizedDescription)")
        }

        // تسجيل الجهاز — نرسل token فارغ احتياطاً لتفادي خطأ NOT NULL
        do {
            let isoNow = DateHelper.now
            let payload: [String: AnyEncodable] = [
                "member_id": AnyEncodable(memberId.uuidString),
                "device_id": AnyEncodable(deviceId),
                "platform": AnyEncodable(platform),
                "environment": AnyEncodable(apnsEnvironment),
                "device_name": AnyEncodable(deviceModelName),
                "token": AnyEncodable(pushToken ?? ""),
                "updated_at": AnyEncodable(isoNow)
            ]

            // نضيف .select() عشان نرجع الصفوف المتأثرة ونتحقق إن العملية نجحت فعلاً
            // (RLS قد يمنع بصمت بدون خطأ ويرجع 0 rows)
            let response: [LinkedDevice] = try await supabase
                .from("device_tokens")
                .upsert(payload, onConflict: "member_id,device_id")
                .select()
                .execute()
                .value

            let tokenPreview = (pushToken ?? "").prefix(12)
            if response.isEmpty {
                Log.error("[DEVICE] ❌ فشل تسجيل الجهاز بصمت — 0 صفوف أُدرجت. RLS قد يمنع العملية. memberId=\(memberId.uuidString.prefix(8)), deviceId=\(deviceId.prefix(8))")
            } else {
                // ✅ نخزّن محلياً أن الجهاز مسجّل — يُستخدم للكشف إذا حُذف لاحقاً
                NotificationViewModel.markDeviceAsRegistered(memberId: memberId.uuidString, deviceId: deviceId)
                Log.info("[DEVICE] ✅ تم تسجيل الجهاز بنجاح: \(deviceModelName), platform=\(platform)/\(apnsEnvironment), tokenLen=\(pushToken?.count ?? 0), token=\(tokenPreview)..., rowsAffected=\(response.count)")
            }
        } catch {
            Log.error("[DEVICE] ❌ خطأ تسجيل الجهاز: \(error.localizedDescription) — deviceId=\(deviceId.prefix(8)), model=\(deviceModelName)")
        }
    }

    // MARK: - Device Registration State (Local Tracking)

    /// مفتاح UserDefaults لتتبع حالة تسجيل الجهاز محلياً
    private static func deviceRegisteredKey(memberId: String, deviceId: String) -> String {
        "deviceRegistered_\(memberId)_\(deviceId)"
    }

    /// تخزين حالة التسجيل الناجح محلياً
    static func markDeviceAsRegistered(memberId: String, deviceId: String) {
        UserDefaults.standard.set(true, forKey: deviceRegisteredKey(memberId: memberId, deviceId: deviceId))
    }

    /// هل كان الجهاز مسجّلاً في السابق؟
    static func wasDevicePreviouslyRegistered(memberId: String, deviceId: String) -> Bool {
        UserDefaults.standard.bool(forKey: deviceRegisteredKey(memberId: memberId, deviceId: deviceId))
    }

    /// مسح علم التسجيل (عند تسجيل الخروج أو إعادة الإعداد)
    static func clearDeviceRegistrationFlag(memberId: String, deviceId: String) {
        UserDefaults.standard.removeObject(forKey: deviceRegisteredKey(memberId: memberId, deviceId: deviceId))
    }
    
    // MARK: - Enforce Device Limit

    /// تطبيق حد الأجهزة فوراً على جميع الأعضاء — يُستدعى عند تغيير الإعداد من الإدارة
    func enforceDeviceLimitForAll(_ maxDevices: Int) async {
        guard maxDevices >= 1 else { return }

        struct DeviceRow: Codable {
            let id: Int
            let memberId: UUID
            let updatedAt: String
            enum CodingKeys: String, CodingKey {
                case id
                case memberId  = "member_id"
                case updatedAt = "updated_at"
            }
        }

        do {
            // جلب كل الأجهزة مرتبة من الأقدم إلى الأحدث
            let allDevices: [DeviceRow] = try await supabase
                .from("device_tokens")
                .select("id, member_id, updated_at")
                .order("updated_at", ascending: true)
                .execute()
                .value

            // تجميع حسب member_id
            var byMember: [UUID: [DeviceRow]] = [:]
            for device in allDevices {
                byMember[device.memberId, default: []].append(device)
            }

            // حذف الزائد عن الحد (الأقدم أولاً)
            var deletedCount = 0
            for (_, devices) in byMember {
                guard devices.count > maxDevices else { continue }
                let toDelete = devices.prefix(devices.count - maxDevices)
                for device in toDelete {
                    try? await supabase
                        .from("device_tokens")
                        .delete()
                        .eq("id", value: device.id)
                        .execute()
                    deletedCount += 1
                }
            }

            if deletedCount > 0 {
                Log.info("[DEVICE] ✅ حُذف \(deletedCount) جهاز زائد عند تطبيق الحد الجديد (\(maxDevices))")
                await fetchLinkedDevices()
            } else {
                Log.info("[DEVICE] لا أجهزة زائدة عند الحد (\(maxDevices))")
            }
        } catch {
            Log.error("[DEVICE] خطأ تطبيق حد الأجهزة: \(error.localizedDescription)")
        }
    }

    // MARK: - Push Token
    
    /// إعادة تسجيل التوكن المحفوظ عند فتح التطبيق — يضمن إن السيرفر عنده أحدث توكن
    func reRegisterPushTokenIfNeeded() async {
        guard let token = pushToken, !token.isEmpty else {
            // لو ما فيه توكن محفوظ، نطلب واحد جديد من النظام
            await MainActor.run {
                UIApplication.shared.registerForRemoteNotifications()
            }
            Log.info("[PUSH] طلب توكن APNs جديد من النظام")
            return
        }
        // نعيد إرسال التوكن الحالي للسيرفر
        await registerPushToken(token)
        Log.info("[PUSH] أعيد تسجيل التوكن المحفوظ عند فتح التطبيق")
    }

    func registerPushToken(_ token: String) async {
        let cleanToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanToken.isEmpty else {
            Log.error("[PUSH] ❌ توكن APNs فارغ — لن يتم التسجيل")
            return
        }

        self.pushToken = cleanToken
        Log.info("[PUSH] استلام توكن APNs: len=\(cleanToken.count), token=\(cleanToken.prefix(12))...")

        // لا ترسل التوكن للسيرفر إذا الإشعارات مغلقة
        let notificationsEnabled = UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true
        guard notificationsEnabled else {
            Log.error("[PUSH] ❌ الإشعارات معطّلة من UserDefaults — لن يتم تحديث التوكن بالسيرفر. المستخدم لن يستلم إشعارات!")
            return
        }

        guard let memberId = currentUser?.id else {
            Log.error("[PUSH] ❌ لا يوجد مستخدم حالي — تخطي تحديث التوكن. (قد يكون التسجيل استُدعي قبل تحميل المستخدم)")
            return
        }
        guard let deviceId = currentDeviceId else {
            Log.error("[PUSH] ❌ لا يوجد معرّف جهاز — تخطي تحديث التوكن. (registerDevice لم يُستدعى بعد)")
            return
        }

        // تحديث التوكن على سجل الجهاز الحالي — upsert يضمن إنه يُنشئ لو ما كان موجود
        do {
            let platform = UIDevice.current.userInterfaceIdiom == .pad ? "ipados" : "ios"
            let deviceModelName = NotificationViewModel.deviceModelName
            #if DEBUG
            let apnsEnvironment = "sandbox"
            #else
            let apnsEnvironment = "production"
            #endif
            let isoNow = DateHelper.now
            let payload: [String: AnyEncodable] = [
                "member_id": AnyEncodable(memberId.uuidString),
                "device_id": AnyEncodable(deviceId),
                "platform": AnyEncodable(platform),
                "environment": AnyEncodable(apnsEnvironment),
                "device_name": AnyEncodable(deviceModelName),
                "token": AnyEncodable(cleanToken),
                "updated_at": AnyEncodable(isoNow)
            ]

            let response: [LinkedDevice] = try await supabase
                .from("device_tokens")
                .upsert(payload, onConflict: "member_id,device_id")
                .select()
                .execute()
                .value

            if response.isEmpty {
                Log.error("[PUSH] ❌ فشل تحديث Push Token بصمت — 0 صفوف. RLS قد يمنع. memberId=\(memberId.uuidString.prefix(8)), deviceId=\(deviceId.prefix(8))")
            } else {
                Log.info("[PUSH] ✅ تم تحديث Push Token بنجاح — memberId=\(memberId.uuidString.prefix(8)), deviceId=\(deviceId.prefix(8)), rows=\(response.count)")
            }
        } catch {
            Log.error("[PUSH] ❌ خطأ تحديث Push Token: \(error.localizedDescription)")
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
    
    func removeDevice(_ device: LinkedDevice) async {
        do {
            try await supabase
                .from("device_tokens")
                .delete()
                .eq("id", value: device.id)
                .execute()
            self.linkedDevices.removeAll { $0.id == device.id }
            Log.info("تم حذف الجهاز بنجاح")

            // إذا حذف المستخدم جهازه الحالي — نعيد تسجيله فوراً ونحدث القائمة
            if device.deviceId == currentDeviceId {
                Log.info("[DEVICE] الجهاز المحذوف هو الجهاز الحالي — إعادة تسجيل تلقائية…")
                await registerDevice()
                await fetchLinkedDevices()
            }
        } catch {
            Log.error("خطأ حذف الجهاز: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Admin Device Management
    
    /// جلب أجهزة عضو محدد (للمدير)
    func fetchDevicesForMember(_ memberId: UUID) async -> [LinkedDevice] {
        guard canModerate else {
            Log.warning("[AUTH] Unauthorized fetchDevicesForMember attempt")
            return []
        }
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
        guard canModerate else {
            Log.warning("[AUTH] Unauthorized removeDeviceByAdmin attempt")
            return false
        }
        do {
            try await supabase
                .from("device_tokens")
                .delete()
                .eq("id", value: device.id)
                .execute()
            Log.info("[ADMIN-DEVICE] تم حذف جهاز العضو بنجاح: \(device.displayName)")

            // إذا المدير حذف جهازه هو — نعيد تسجيله فوراً
            if device.deviceId == currentDeviceId {
                Log.info("[DEVICE] المدير حذف جهازه الحالي — إعادة تسجيل تلقائية…")
                await registerDevice()
                await fetchLinkedDevices()
            }

            return true
        } catch {
            Log.error("[ADMIN-DEVICE] خطأ حذف جهاز العضو: \(error.localizedDescription)")
            return false
        }
    }
    
    /// جلب جميع الأجهزة المسجلة (للمدير)
    func fetchAllDevices() async -> [LinkedDevice] {
        guard canModerate else {
            Log.warning("[AUTH] Unauthorized fetchAllDevices attempt")
            return []
        }
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
                if allDevices.count > maxDevicesAllowed {
                    // الجهاز مسجّل لكن المجموع تجاوز الحد (الأدمن قلّل الحد) → يجب حذف الزائد
                    let excess = allDevices.count - maxDevicesAllowed
                    Log.warning("[DEVICE-VERIFY] ⚠️ الجهاز مصرّح لكن العدد (\(allDevices.count)) تجاوز الحد (\(maxDevicesAllowed)) — حذف \(excess) جهاز")
                    self.linkedDevices = allDevices.sorted { $0.updatedAt > $1.updatedAt }
                    await MainActor.run { authVM?.status = .deviceOverLimit }
                } else {
                    Log.info("[DEVICE-VERIFY] الجهاز مصرّح ✓")
                }
            } else if allDevices.count >= maxDevicesAllowed {
                // الحد ممتلئ بأجهزة غير هذا الجهاز
                let wasRegistered = NotificationViewModel.wasDevicePreviouslyRegistered(
                    memberId: memberId.uuidString,
                    deviceId: deviceId
                )
                if wasRegistered {
                    // كان مسجّلاً وانحذف ليحل محله جهاز آخر → شاشة "تم إزالة جهازك"
                    Log.warning("[DEVICE-VERIFY] ❌ الجهاز حُذف والحد (\(maxDevicesAllowed)) ممتلئ — شاشة إدارة الأجهزة")
                    self.linkedDevices = allDevices.sorted { $0.updatedAt > $1.updatedAt }
                    await MainActor.run { authVM?.status = .deviceRevoked }
                } else {
                    // جهاز جديد تماماً والحد ممتلئ → اختر جهازاً للإزالة
                    Log.warning("[DEVICE-VERIFY] جهاز جديد والحد (\(maxDevicesAllowed)) ممتلئ — شاشة حد الأجهزة")
                    self.linkedDevices = allDevices.sorted { $0.updatedAt > $1.updatedAt }
                    await MainActor.run { authVM?.status = .deviceLimitExceeded }
                }
            } else {
                // في مكان شاغر (سواء جهاز جديد أو أُزيل وفُرغ المكان) → سجّل عادي
                Log.info("[DEVICE-VERIFY] مكان شاغر (\(allDevices.count)/\(maxDevicesAllowed)) — تسجيل…")
                await registerDevice()
            }
        } catch {
            Log.error("[DEVICE-VERIFY] خطأ التحقق من تصريح الجهاز: \(error.localizedDescription)")
        }
    }
    
    private func sendExternalAdminPush(
        title: String,
        body: String,
        kind: String = NotificationKind.adminRequest.rawValue,
        requestId: UUID? = nil,
        requestType: String? = nil
    ) async {
        Log.info("[PUSH] إرسال push-admins: kind=\(kind), requestType=\(requestType ?? "none")")
        do {
            var payload: [String: AnyEncodable] = [
                "title": AnyEncodable(title),
                "body": AnyEncodable(body),
                "kind": AnyEncodable(kind)
            ]
            if let rid = requestId  { payload["request_id"]   = AnyEncodable(rid.uuidString) }
            if let rt  = requestType { payload["request_type"] = AnyEncodable(rt) }

            try await supabase.functions
                .invoke("push-admins", options: FunctionInvokeOptions(body: payload))

            Log.info("[PUSH] push-admins اكتمل بنجاح")
        } catch {
            Log.warning("[PUSH] push-admins فشل، محاولة تحديث الجلسة: \(error.localizedDescription)")
            do {
                _ = try await supabase.auth.refreshSession()
                var retryPayload: [String: AnyEncodable] = [
                    "title": AnyEncodable(title),
                    "body": AnyEncodable(body),
                    "kind": AnyEncodable(kind)
                ]
                if let rid = requestId  { retryPayload["request_id"]   = AnyEncodable(rid.uuidString) }
                if let rt  = requestType { retryPayload["request_type"] = AnyEncodable(rt) }
                try await supabase.functions.invoke("push-admins", options: FunctionInvokeOptions(body: retryPayload))
                Log.info("[PUSH] push-admins نجح بعد تحديث الجلسة")
            } catch {
                Log.error("[PUSH] push-admins فشل نهائياً: \(error.localizedDescription)")
            }
        }
    }
    
    /// إرسال push حقيقي لأعضاء محددين أو للجميع عبر Edge Function
    func sendPushToMembers(title: String, body: String, kind: String = "general", targetMemberIds: [UUID]? = nil) async {
        let targetCount = targetMemberIds?.count ?? 0
        Log.info("[PUSH] إرسال push-notify: targets=\(targetCount == 0 ? "ALL" : "\(targetCount)"), kind=\(kind)")
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

            Log.info("[PUSH] push-notify اكتمل بنجاح")
        } catch {
            Log.warning("[PUSH] push-notify فشل، محاولة تحديث الجلسة: \(error.localizedDescription)")
            // إعادة محاولة بعد refresh session
            do {
                _ = try await supabase.auth.refreshSession()
                var retryPayload: [String: AnyEncodable] = [
                    "title": AnyEncodable(title),
                    "body": AnyEncodable(body),
                    "kind": AnyEncodable(kind)
                ]
                if let ids = targetMemberIds, !ids.isEmpty {
                    retryPayload["member_ids"] = AnyEncodable(ids.map { $0.uuidString })
                }
                try await supabase.functions.invoke("push-notify", options: FunctionInvokeOptions(body: retryPayload))
                Log.info("[PUSH] push-notify نجح بعد تحديث الجلسة")
            } catch {
                Log.error("[PUSH] push-notify فشل نهائياً: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Notifications
    
    func fetchNotifications(force: Bool = false) async {
        if !force, let last = lastNotificationsFetchDate, Date().timeIntervalSince(last) < cacheDuration, !notifications.isEmpty {
            return
        }
        lastNotificationsFetchDate = Date()
        guard let userId = currentUser?.id else {
            notifications = []
            return
        }
        guard notificationsFeatureAvailable else {
            notifications = []
            return
        }

        if force { isLoading = true }

        do {
            var allNotifications: [AppNotification] = []

            // 1) جلب الإشعارات الشخصية
            let personal: [AppNotification] = try await supabase
                .from("notifications")
                .select()
                .eq("target_member_id", value: userId.uuidString)
                .order("created_at", ascending: false)
                .limit(200)
                .execute()
                .value
            allNotifications.append(contentsOf: personal)

            // 2) للمدراء/المشرفين: جلب إشعارات broadcast
            if canModerate {
                let broadcast: [AppNotification] = try await supabase
                    .from("notifications")
                    .select()
                    .is("target_member_id", value: nil)
                    .order("created_at", ascending: false)
                    .limit(200)
                    .execute()
                    .value
                allNotifications.append(contentsOf: broadcast)
            }

            // ترتيب + إزالة تكرارات
            var seen = Set<UUID>()
            allNotifications = allNotifications
                .sorted { $0.createdDate > $1.createdDate }
                .filter { seen.insert($0.id).inserted }

            // ── دمج مع الحالة المحلية (حماية العمليات الجارية) ──
            // إزالة الإشعارات المحذوفة محلياً
            if !pendingDeleteIds.isEmpty {
                allNotifications.removeAll { pendingDeleteIds.contains($0.id) }
            }
            // تطبيق حالة القراءة المحلية
            if !pendingReadIds.isEmpty {
                allNotifications = allNotifications.map { notif in
                    if pendingReadIds.contains(notif.id) {
                        return notif.withRead(true)
                    }
                    return notif
                }
            }

            self.notificationsFeatureAvailable = true
            self.notifications = allNotifications
            await updateBadgeCount()
        } catch {
            if ErrorHelper.isMissingTable(error, table: "notifications") {
                notificationsFeatureAvailable = false
                notifications = []
            } else if !ErrorHelper.isCancellation(error) {
                Log.error("[NOTIF] خطأ جلب الإشعارات: \(error.localizedDescription)")
            }
        }

        if force { isLoading = false }
    }

    /// تحديث عداد الـ badge
    private func updateBadgeCount() async {
        let badgeOn = currentUser?.badgeEnabled ?? true
        let unread = notifications.filter { !$0.read }.count
        try? await UNUserNotificationCenter.current().setBadgeCount(badgeOn ? unread : 0)
    }
    
    func deleteNotification(id: UUID) async {
        let backup = notifications.first { $0.id == id }
        pendingDeleteIds.insert(id)

        withAnimation(.snappy(duration: 0.25)) {
            notifications.removeAll { $0.id == id }
        }
        await updateBadgeCount()

        do {
            try await supabase.from("notifications").delete().eq("id", value: id.uuidString).execute()
            pendingDeleteIds.remove(id)
        } catch {
            pendingDeleteIds.remove(id)
            Log.error("[NOTIF] خطأ حذف: \(error.localizedDescription)")
            if let backup {
                withAnimation(.snappy(duration: 0.25)) {
                    notifications.append(backup)
                    notifications.sort { $0.createdDate > $1.createdDate }
                }
                await updateBadgeCount()
            }
        }
    }

    func deleteNotifications(ids: Set<UUID>) async {
        guard !ids.isEmpty else { return }
        let backup = notifications.filter { ids.contains($0.id) }
        pendingDeleteIds.formUnion(ids)

        withAnimation(.snappy(duration: 0.25)) {
            notifications.removeAll { ids.contains($0.id) }
        }
        await updateBadgeCount()

        do {
            try await supabase.from("notifications").delete().in("id", values: ids.map(\.uuidString)).execute()
            pendingDeleteIds.subtract(ids)
        } catch {
            pendingDeleteIds.subtract(ids)
            Log.error("[NOTIF] خطأ حذف متعدد: \(error.localizedDescription)")
            if !backup.isEmpty {
                withAnimation(.snappy(duration: 0.25)) {
                    notifications.append(contentsOf: backup)
                    notifications.sort { $0.createdDate > $1.createdDate }
                }
                await updateBadgeCount()
            }
        }
    }

    func markNotificationAsRead(id: UUID) async {
        pendingReadIds.insert(id)
        if let idx = notifications.firstIndex(where: { $0.id == id }) {
            notifications[idx] = notifications[idx].withRead(true)
        }
        await updateBadgeCount()

        do {
            try await supabase.from("notifications").update(["is_read": AnyEncodable(true)]).eq("id", value: id.uuidString).execute()
            pendingReadIds.remove(id)
        } catch {
            pendingReadIds.remove(id)
            Log.error("[NOTIF] خطأ قراءة: \(error.localizedDescription)")
            if let idx = notifications.firstIndex(where: { $0.id == id }) {
                notifications[idx] = notifications[idx].withRead(false)
            }
            await updateBadgeCount()
        }
    }

    func markNotificationsAsRead(ids: Set<UUID>) async {
        guard !ids.isEmpty else { return }
        pendingReadIds.formUnion(ids)
        for i in notifications.indices where ids.contains(notifications[i].id) {
            notifications[i] = notifications[i].withRead(true)
        }
        await updateBadgeCount()

        do {
            try await supabase.from("notifications").update(["is_read": AnyEncodable(true)]).in("id", values: ids.map(\.uuidString)).execute()
            pendingReadIds.subtract(ids)
        } catch {
            pendingReadIds.subtract(ids)
            Log.error("[NOTIF] خطأ قراءة متعدد: \(error.localizedDescription)")
            for i in notifications.indices where ids.contains(notifications[i].id) {
                notifications[i] = notifications[i].withRead(false)
            }
            await updateBadgeCount()
        }
    }

    func markAllNotificationsAsRead() async {
        guard let userId = currentUser?.id else { return }
        let unreadIds = Set(notifications.filter { !$0.read }.map(\.id))
        guard !unreadIds.isEmpty else { return }

        pendingReadIds.formUnion(unreadIds)
        for i in notifications.indices where !notifications[i].read {
            notifications[i] = notifications[i].withRead(true)
        }
        try? await UNUserNotificationCenter.current().setBadgeCount(0)

        do {
            try await supabase.from("notifications")
                .update(["is_read": AnyEncodable(true)])
                .eq("target_member_id", value: userId.uuidString)
                .eq("is_read", value: false)
                .execute()

            // إذا moderator، نحدث broadcast أيضاً
            if canModerate {
                try await supabase.from("notifications")
                    .update(["is_read": AnyEncodable(true)])
                    .is("target_member_id", value: nil)
                    .eq("is_read", value: false)
                    .execute()
            }
            pendingReadIds.subtract(unreadIds)
        } catch {
            pendingReadIds.subtract(unreadIds)
            Log.error("[NOTIF] خطأ قراءة الكل: \(error.localizedDescription)")
            for i in notifications.indices where unreadIds.contains(notifications[i].id) {
                notifications[i] = notifications[i].withRead(false)
            }
            await updateBadgeCount()
        }
    }
    
    func sendNotification(title: String, body: String, targetMemberIds: [UUID]?, sendPush: Bool = true, kind: String = "admin") async {
        guard authVM?.isAdmin == true, let creator = currentUser?.id else { return }
        guard notificationsFeatureAvailable else { return }
        self.isLoading = true

        do {
            if let ids = targetMemberIds, !ids.isEmpty {
                let payloads = ids.map { memberId in
                    [
                        "target_member_id": AnyEncodable(memberId.uuidString),
                        "title": AnyEncodable(title),
                        "body": AnyEncodable(body),
                        "kind": AnyEncodable(kind),
                        "created_by": AnyEncodable(creator.uuidString)
                    ]
                }
                try await supabase.from("notifications").insert(payloads).execute()
            } else {
                let payload: [String: AnyEncodable] = [
                    "target_member_id": AnyEncodable(Optional<String>.none),
                    "title": AnyEncodable(title),
                    "body": AnyEncodable(body),
                    "kind": AnyEncodable(kind),
                    "created_by": AnyEncodable(creator.uuidString)
                ]
                try await supabase.from("notifications").insert(payload).execute()
            }

            if sendPush {
                await sendPushToMembers(
                    title: title,
                    body: body,
                    kind: kind,
                    targetMemberIds: targetMemberIds
                )
            }

            await fetchNotifications(force: true)
        } catch {
            if ErrorHelper.isMissingTable(error, table: "notifications") {
                notificationsFeatureAvailable = false
            } else {
                Log.error("خطأ إرسال الإشعار: \(error.localizedDescription)")
            }
        }
        
        self.isLoading = false
    }

    /// إرسال إشعار واحد في مركز الإشعارات (broadcast) يراه المدراء والمشرفون
    /// target_member_id = NULL يعني broadcast — الـ RLS يتكفل بإظهاره للمدراء فقط
    func notifyAdmins(
        title: String,
        body: String,
        kind: String,
        requestId: UUID? = nil,
        requestType: String? = nil
    ) async {
        let creatorId = currentUser?.id
        guard notificationsFeatureAvailable else { return }

        do {
            var payload: [String: AnyEncodable] = [
                "target_member_id": AnyEncodable(Optional<String>.none),
                "title": AnyEncodable(title),
                "body": AnyEncodable(body),
                "kind": AnyEncodable(kind),
                "created_by": AnyEncodable(creatorId?.uuidString)
            ]
            if let rid = requestId  { payload["request_id"]   = AnyEncodable(rid.uuidString) }
            if let rt  = requestType { payload["request_type"] = AnyEncodable(rt) }

            try await supabase.from("notifications").insert(payload).execute()
        } catch {
            if ErrorHelper.isMissingTable(error, table: "notifications") {
                notificationsFeatureAvailable = false
            } else if !ErrorHelper.isMissingColumn(error, column: "request_id") {
                Log.warning("تعذر إرسال إشعار للمدراء: \(error.localizedDescription)")
            } else {
                // migration not applied yet — fallback without request fields
                let fallback: [String: AnyEncodable] = [
                    "target_member_id": AnyEncodable(Optional<String>.none),
                    "title": AnyEncodable(title),
                    "body": AnyEncodable(body),
                    "kind": AnyEncodable(kind),
                    "created_by": AnyEncodable(creatorId?.uuidString)
                ]
                try? await supabase.from("notifications").insert(fallback).execute()
            }
        }
    }

    /// إشعار موحّد: يرسل push خارجي + إشعار داخلي في استدعاء واحد
    func notifyAdminsWithPush(
        title: String,
        body: String,
        kind: String,
        requestId: UUID? = nil,
        requestType: String? = nil
    ) async {
        async let push: Void = sendExternalAdminPush(title: title, body: body, kind: kind, requestId: requestId, requestType: requestType)
        async let inApp: Void = notifyAdmins(title: title, body: body, kind: kind, requestId: requestId, requestType: requestType)
        _ = await (push, inApp)
    }

    // MARK: - Approve Request from Notification

    /// موافقة سريعة على طلب من الإشعار — تحديث DB مباشرة بدون side-effects كاملة
    /// للموافقة الكاملة مع جميع الإجراءات استخدم AdminRequestViewModel
    func approveRequest(requestId: UUID, requestType: String) async -> Bool {
        guard canModerate else { return false }

        do {
            if requestType == RequestType.joinRequest.rawValue {
                // طلب انضمام: تفعيل العضو مباشرة
                try await supabase.from("profiles")
                    .update([
                        "role": AnyEncodable("member"),
                        "status": AnyEncodable("active"),
                        "is_hidden_from_tree": AnyEncodable(false)
                    ])
                    .eq("id", value: requestId.uuidString)
                    .execute()

                // إشعار للعضو بأنه تم قبوله
                let adminName = currentUser?.firstName ?? "الإدارة"
                let approvedPayload: [String: AnyEncodable] = [
                    "target_member_id": AnyEncodable(requestId.uuidString),
                    "title": AnyEncodable(L10n.t("تم قبول طلبك", "Your Request Was Approved")),
                    "body": AnyEncodable(L10n.t(
                        "وافق \(adminName) على انضمامك — مرحباً في عائلة المحمدعلي 🌿",
                        "\(adminName) approved your membership — Welcome to the Al-Mohammad Ali family 🌿"
                    )),
                    "kind": AnyEncodable("join_approved"),
                    "created_by": AnyEncodable(currentUser?.id.uuidString ?? "")
                ]
                _ = try? await supabase.from("notifications").insert(approvedPayload).execute()
                await sendPushToMembers(
                    title: L10n.t("تم قبول طلبك", "Your Request Was Approved"),
                    body: L10n.t("مرحباً في عائلة المحمدعلي 🌿", "Welcome to the Al-Mohammad Ali family 🌿"),
                    kind: "join_approved",
                    targetMemberIds: [requestId]
                )
            } else {
                // بقية الطلبات: تحديث status في admin_requests
                try await supabase.from("admin_requests")
                    .update(["status": AnyEncodable("approved")])
                    .eq("id", value: requestId.uuidString)
                    .execute()
            }
            Log.info("[APPROVE] ✅ تمت الموافقة: requestType=\(requestType), id=\(requestId.uuidString.prefix(8))")
            return true
        } catch {
            Log.error("[APPROVE] ❌ فشل: \(error.localizedDescription)")
            return false
        }
    }

    func rejectRequest(requestId: UUID, requestType: String) async -> Bool {
        guard canModerate else { return false }

        do {
            if requestType == RequestType.joinRequest.rawValue {
                _ = try? await supabase
                    .from("admin_requests")
                    .delete()
                    .eq("requester_id", value: requestId.uuidString)
                    .execute()
                _ = try? await supabase
                    .from("admin_requests")
                    .delete()
                    .eq("member_id", value: requestId.uuidString)
                    .execute()
                _ = try? await supabase
                    .from("profiles")
                    .update(["father_id": AnyEncodable(Optional<String>.none)])
                    .eq("father_id", value: requestId.uuidString)
                    .execute()
                try await supabase
                    .from("profiles")
                    .delete()
                    .eq("id", value: requestId.uuidString)
                    .execute()
            } else {
                try await supabase.from("admin_requests")
                    .update(["status": AnyEncodable(ApprovalStatus.rejected.rawValue)])
                    .eq("id", value: requestId.uuidString)
                    .execute()
            }
            Log.info("[REJECT] ✅ تم الرفض: requestType=\(requestType), id=\(requestId.uuidString.prefix(8))")
            return true
        } catch {
            Log.error("[REJECT] ❌ فشل: \(error.localizedDescription)")
            return false
        }
    }
}
