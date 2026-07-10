import Foundation
import Supabase
import SwiftUI
import PhotosUI
import Combine

// MARK: - MemberViewModel
// Manages all member-related data: fetch, add, update, avatar/cover/gallery uploads.
// Extracted from AuthViewModel to reduce its size and follow single-responsibility.

@MainActor
class MemberViewModel: ObservableObject {
    
    // MARK: - Supabase Client
    let supabase = SupabaseConfig.client
    
    // MARK: - Published Properties
    
    @Published var allMembers: [FamilyMember] = [] {
        didSet { _memberByIdDirty = true }
    }

    /// O(1) member lookup by ID — use instead of allMembers.first(where:).
    /// الـ dict يُعاد بناؤه فقط عند أول قراءة بعد التعديل (lazy rebuild) —
    /// يمنع التهنيق عند تعديلات متتالية في حلقة (مثلاً sortOrder loop).
    private var _memberByIdCache: [UUID: FamilyMember] = [:]
    private var _memberByIdDirty: Bool = false

    var _memberById: [UUID: FamilyMember] {
        if _memberByIdDirty {
            _memberByIdCache = Dictionary(uniqueKeysWithValues: allMembers.map { ($0.id, $0) })
            _memberByIdDirty = false
        }
        return _memberByIdCache
    }

    func member(byId id: UUID) -> FamilyMember? { _memberById[id] }
    
    @Published var currentMemberChildren: [FamilyMember] = []
    /// عائلة العضو من شجرة النساء (الأم + الزوجة + الأبناء) — عرض فقط.
    @Published var currentMemberWomenFamily: [WomenFamilyEntry] = []
    @Published var activePath: [UUID] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    /// يصير true إذا فشل تحميل الأعضاء ولا توجد بيانات محلية (للشاشات تعرض حالة خطأ + إعادة محاولة)
    @Published var membersLoadFailed: Bool = false

    /// يزداد عند كل تحديث للأعضاء (حذف، تعديل، إضافة) لإعادة بناء الشجرة
    @Published var membersVersion: Int = 0

    // Fetch throttle
    private let throttler = FetchThrottler()

    /// Debounce لحفظ الكاش — يجمّع التعديلات المتتالية في حفظ واحد
    /// يحل مشكلة 14+ حفظ متلاحق للأعضاء (1.4MB كل مرة) خلال جلسة قصيرة
    private var cacheMembersSaveTask: Task<Void, Never>?

    private func scheduleMembersCacheSave() {
        cacheMembersSaveTask?.cancel()
        cacheMembersSaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 ثانية
            guard !Task.isCancelled, let self else { return }
            CacheManager.shared.save(self.allMembers, for: .members)
        }
    }
    
    // MARK: - Dependencies
    
    weak var authVM: AuthViewModel?
    weak var notificationVM: NotificationViewModel?
    
    func configure(authVM: AuthViewModel, notificationVM: NotificationViewModel) {
        self.authVM = authVM
        self.notificationVM = notificationVM
    }
    
    // MARK: - Private Helpers

    private var currentUser: FamilyMember? { authVM?.currentUser }
    private var canModerate: Bool { authVM?.canModerate ?? false }

    /// يُرجع حقول التتبع الإداري (updated_by + updated_at) إذا كان المدير يعدل بيانات عضو آخر
    private func adminAuditFields(for memberId: UUID) -> [String: AnyEncodable] {
        guard canModerate, let adminId = currentUser?.id, adminId != memberId else { return [:] }
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        return [
            "updated_by": AnyEncodable(adminId.uuidString),
            "updated_at": AnyEncodable(isoFormatter.string(from: Date()))
        ]
    }

    /// Broadcasts an admin-edit notification with structured `details` payload.
    /// - Skips when the editor is editing their own profile (not an admin action).
    /// - Filters out fields where `before == after` (no real change).
    /// - Returns silently if no real changes remain.
    private func notifyAdminsOfMemberEdit(
        memberId: UUID,
        kind: String,
        title: String,
        body: String,
        changes: [AppNotification.NotificationDetails.ChangeEntry]
    ) async {
        guard memberId != currentUser?.id else { return }
        let real = changes.filter { ($0.before ?? "") != ($0.after ?? "") }
        guard !real.isEmpty else { return }
        // نستخدم push + in-app: المدراء يحصلون على إشعار خارجي + داخلي بالتعديل
        await notificationVM?.notifyAdminsWithChangesAndPush(
            title: title,
            body: body,
            kind: kind,
            changes: real
        )
    }

    /// Builds a short "<title> for «<member>»" body string for admin-edit notifications.
    private func adminEditBody(verb: String, memberId: UUID) -> String {
        let name = _memberById[memberId]?.firstName ?? L10n.t("عضو", "member")
        return L10n.t("\(verb) للعضو «\(name)»", "\(verb) for «\(name)»")
    }
    
    // lowercase لمطابقة auth.uid()::text في سياسات RLS (التسجيل يستخدمها أصلاً)
    func getSafeMemberName(for memberId: UUID) -> String {
        return memberId.uuidString.lowercased()
    }

    // MARK: - Phone Duplicate Check

    /// يتحقق إذا الرقم مستخدم من عضو ثاني (يتجاهل العضو الحالي)
    func isPhoneDuplicate(_ phone: String, excludingMemberId: UUID? = nil) -> (isDuplicate: Bool, existingMember: FamilyMember?) {
        guard !phone.isEmpty else { return (false, nil) }
        let inputDigits = phone.filter(\.isNumber)
        let inputSuffix = String(inputDigits.suffix(8))
        guard inputSuffix.count >= 8 else { return (false, nil) }

        let match = allMembers.first { member in
            guard member.id != excludingMemberId else { return false }
            guard let memberPhone = member.phoneNumber, !memberPhone.isEmpty else { return false }
            let memberDigits = memberPhone.filter(\.isNumber)
            let memberSuffix = String(memberDigits.suffix(8))
            return memberSuffix == inputSuffix
        }
        return (match != nil, match)
    }

    /// يرجع كل مجموعات الأرقام المكررة: [[عضو1, عضو2], [عضو3, عضو4]]
    var duplicatePhoneGroups: [[FamilyMember]] {
        var phoneMap: [String: [FamilyMember]] = [:]
        for member in allMembers {
            guard let phone = member.phoneNumber, !phone.isEmpty else { continue }
            let digits = phone.filter(\.isNumber)
            let suffix = String(digits.suffix(8))
            guard suffix.count >= 8 else { continue }
            phoneMap[suffix, default: []].append(member)
        }
        return phoneMap.values.filter { $0.count > 1 }.sorted { $0[0].fullName < $1[0].fullName }
    }

    /// يمسح رقم الهاتف من عضو معين (profiles + auth.users)
    func clearPhoneNumber(for memberId: UUID) async -> Bool {
        await clearMemberPhone(memberId: memberId)
        return true
    }
    
    private func storagePath(fromPublicURL urlString: String, bucket: String) -> String? {
        guard let url = URL(string: urlString) else { return nil }
        let marker = "/storage/v1/object/public/\(bucket)/"
        guard let range = url.path.range(of: marker) else { return nil }
        return String(url.path[range.upperBound...])
    }
    
    // MARK: - Local State Updates

    /// تحديث بيانات عضو محلياً (deceased, birthDate, deathDate) بدون حفظ في السيرفر
    func updateMemberLocally(memberId: UUID, isDeceased: Bool, birthDate: String?, deathDate: String?) {
        guard let idx = allMembers.firstIndex(where: { $0.id == memberId }) else { return }
        allMembers[idx].isDeceased = isDeceased
        allMembers[idx].birthDate = birthDate
        allMembers[idx].deathDate = deathDate
        membersVersion += 1
    }

    // MARK: - Single Member Update

    /// تحديث أو إضافة عضو واحد محلياً بدون إعادة تحميل الكل
    func upsertMemberLocally(_ member: FamilyMember) {
        if let idx = allMembers.firstIndex(where: { $0.id == member.id }) {
            allMembers[idx] = member
        } else {
            allMembers.append(member)
        }
        membersVersion += 1
        scheduleMembersCacheSave()

        // تحديث currentUser إذا هو نفسه
        if member.id == currentUser?.id {
            authVM?.currentUser = member
        }
    }

    /// جلب عضو واحد من السيرفر وتحديثه محلياً
    func fetchSingleMember(id: UUID) async {
        guard NetworkMonitor.shared.isConnected else { return }
        do {
            let response = try await supabase
                .from("profiles")
                .select()
                .eq("id", value: id.uuidString)
                .single()
                .execute()

            let member = try JSONDecoder().decode(FamilyMember.self, from: response.data)
            upsertMemberLocally(member)
        } catch {
            Log.fetchError("[Members] خطأ جلب عضو واحد (\(id.uuidString.prefix(8)))", error)
        }
    }

    // MARK: - Fetch Members

    func fetchAllMembers(force: Bool = false) async {
        // تحميل من الكاش أولاً إذا لا توجد بيانات (في background لتجنب تجميد الواجهة)
        if allMembers.isEmpty,
           let cached = await CacheManager.shared.loadAsync([FamilyMember].self, for: .members) {
            self.allMembers = cached
            self.membersVersion += 1
            Log.info("[Members] تم تحميل \(cached.count) عضو من الكاش")
        }

        // تجنب إعادة التحميل خلال 15 ثانية إلا إذا force
        guard throttler.canFetch(key: "members", interval: 15, force: force) || allMembers.isEmpty else { return }

        // لا نحمل من السيرفر إذا مو متصلين بالنت
        guard NetworkMonitor.shared.isConnected else {
            if allMembers.isEmpty { membersLoadFailed = true }
            return
        }

        self.activePath = [] // تصفير المسار عند كل تحميل

        do {
            let response = try await supabase
                .from("profiles")
                .select()
                .limit(10000)
                .execute()

            let members = try JSONDecoder().decode([FamilyMember].self, from: response.data)

            self.allMembers = members
            self.membersLoadFailed = false
            self.throttler.didFetch(key: "members")
            self.membersVersion += 1

            // حفظ في الكاش (debounced — يلغي أي حفظ قيد الانتظار)
            scheduleMembersCacheSave()

            // تحديث currentUser إذا تغيرت بياناته (مثلاً: تغيير الاسم من الإدارة)
            if let userId = currentUser?.id,
               let updatedUser = members.first(where: { $0.id == userId }),
               updatedUser != currentUser {
                authVM?.currentUser = updatedUser
                Log.info("[Members] تم تحديث بيانات المستخدم الحالي من الشجرة")
            }
        } catch is CancellationError {
            // طبيعي عند خروج العضو من الشاشة أو الإصدار في الخلفية — ليس crash
            return
        } catch {
            // فلتر URLError "cancelled" من URLSession
            if (error as NSError).code == NSURLErrorCancelled { return }
            if allMembers.isEmpty { membersLoadFailed = true }
            Log.error("خطأ برمجياً في الشجرة: \(error)")
            CrashReporter.log(error, context: "fetchAllMembers")
        }
    }

    func fetchChildren(for fatherId: UUID) async {
        do {
            // فلاتر السيرفر تطابق المعيار القانوني (FamilyMember.isCountable)
            let response: [FamilyMember] = try await supabase.from("profiles")
                .select()
                .eq("father_id", value: fatherId)
                .eq("is_hidden_from_tree", value: false)
                .neq("status", value: "frozen")
                .neq("role", value: "pending")
                .order("sort_order", ascending: true)
                .execute()
                .value

            // فلتر إضافي بالعميل لاستبعاد الأسماء الفارغة (يدخل ضمن isCountable)
            self.currentMemberChildren = response.filter(\.isCountable).sortedForDisplay()
        } catch {
            Log.fetchError("خطأ في جلب الأبناء", error)
        }
        // بالإضافة: عائلة العضو من شجرة النساء (نفس العائلة الظاهرة على الويب)
        await fetchWomenFamily(for: fatherId)
    }

    /// جلب عائلة العضو من شجرة النساء (women_members): الأم + الزوجة + الأبناء.
    /// عقدة الذكر تحمل نفس معرّف profiles، فالأبناء parent_id==id، الزوجة husband_id==id،
    /// والأم = العضو الذي معرّفه == mother_id لعقدة المستخدم. عرض فقط في الآيفون.
    func fetchWomenFamily(for userId: UUID) async {
        let uid = userId.uuidString
        do {
            // 1) عقدة المستخدم نفسها — لقراءة mother_id
            let selfRows: [WomanMember] = try await supabase.from("women_members")
                .select().eq("id", value: uid).limit(1).execute().value
            let motherId = selfRows.first?.motherId

            // 2) الأبناء + الزوجات (المرئيون)
            let related: [WomanMember] = try await supabase.from("women_members")
                .select()
                .or("parent_id.eq.\(uid),husband_id.eq.\(uid)")
                .eq("is_hidden_from_tree", value: false)
                .order("sort_order", ascending: true)
                .execute().value

            func named(_ m: WomanMember) -> Bool {
                !m.firstName.trimmingCharacters(in: .whitespaces).isEmpty
            }

            var entries: [WomenFamilyEntry] = []

            // 3) الأم أولاً
            if let motherId {
                let momRows: [WomanMember] = try await supabase.from("women_members")
                    .select().eq("id", value: motherId.uuidString).limit(1).execute().value
                if let mom = momRows.first, named(mom) {
                    entries.append(WomenFamilyEntry(member: mom, role: .mother))
                }
            }
            // 4) الزوجة/الزوجات
            for w in related where w.husbandId == userId && named(w) {
                entries.append(WomenFamilyEntry(member: w, role: .wife))
            }
            // 5) الأبناء
            for c in related where c.parentId == userId && named(c) {
                entries.append(WomenFamilyEntry(member: c, role: .child))
            }
            self.currentMemberWomenFamily = entries
        } catch {
            // الجدول قد لا يكون موجوداً في بعض البيئات — تجاهل بهدوء
            self.currentMemberWomenFamily = []
            Log.warning("[Women] تعذّر جلب عائلة شجرة النساء: \(error.localizedDescription)")
        }
    }

    /// حفظ فوري لحالة الزواج فقط (عند الضغط على زر متزوج/أعزب) — لا يعتمد على زر
    /// الحفظ العام. يكتب is_married فقط (ليس ضمن مراقبة trigger النساء، فآمن).
    @discardableResult
    func setMaritalStatus(memberId: UUID, isMarried: Bool) async -> Bool {
        guard NetworkMonitor.shared.requireOnline() else { return false }
        do {
            try await supabase
                .from("profiles")
                .update(["is_married": isMarried])
                .eq("id", value: memberId.uuidString)
                .execute()
            Log.info("[Profile] حفظ حالة الزواج: \(isMarried)")
            // حدّث نسخة العضو محلياً + المستخدم الحالي ليتفاعل العرض فوراً
            await fetchSingleMember(id: memberId)
            if memberId == currentUser?.id {
                await authVM?.checkUserProfile()
            }
            return true
        } catch {
            self.errorMessage = L10n.t("تعذّر حفظ الحالة الاجتماعية.", "Failed to save marital status.")
            Log.error("[Profile] خطأ حفظ حالة الزواج: \(error.localizedDescription)")
            return false
        }
    }
    
    func reorderChildren(_ children: [FamilyMember]) async {
        // تحديث محلي فوري
        currentMemberChildren = children
        
        for (index, child) in children.enumerated() {
            do {
                try await supabase
                    .from("profiles")
                    .update(["sort_order": AnyEncodable(index)])
                    .eq("id", value: child.id.uuidString)
                    .execute()
            } catch {
                Log.error("خطأ تحديث ترتيب الابن: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - إدارة الأعضاء (Member Management)
    
    // MARK: - تسجيل عضو جديد من الإدارة (بدون حساب مصادقة)
    func adminAddMember(
        fullName: String,
        firstName: String,
        birthDate: String?,
        gender: String?,
        phoneNumber: String?,
        avatarImage: UIImage? = nil
    ) async -> Bool {
        guard NetworkMonitor.shared.requireOnline() else { return false }
        guard canModerate else {
            Log.warning("[AUTH] Unauthorized adminAddMember attempt")
            return false
        }
        // التحقق من تكرار الرقم
        if let phone = phoneNumber, !phone.isEmpty {
            let check = isPhoneDuplicate(phone)
            if check.isDuplicate {
                Log.warning("رقم الهاتف مستخدم من عضو آخر: \(check.existingMember?.fullName ?? "")")
                self.errorMessage = L10n.t(
                    "رقم الهاتف مستخدم من عضو آخر: \(check.existingMember?.fullName ?? "")",
                    "Phone number already used by: \(check.existingMember?.fullName ?? "")"
                )
                return false
            }
        }
        self.isLoading = true
        let newId = UUID()

        let memberData: [String: AnyEncodable] = [
            "id": AnyEncodable(newId.uuidString),
            "full_name": AnyEncodable(fullName),
            "first_name": AnyEncodable(firstName),
            "birth_date": AnyEncodable(birthDate ?? Optional<String>.none),
            "phone_number": AnyEncodable(phoneNumber ?? ""),
            "role": AnyEncodable("member"),
            "status": AnyEncodable("active"),
            "is_deceased": AnyEncodable(false),
            "is_married": AnyEncodable(false),
            "is_hidden_from_tree": AnyEncodable(false),
            "sort_order": AnyEncodable(0),
            "father_id": AnyEncodable(Optional<String>.none)
        ]
        _ = memberData // silence unused warning

        do {
            try await supabase.from("profiles").insert(memberData).execute()
            await fetchSingleMember(id: newId)

            // رفع الصورة الشخصية إن وُجدت (نفس مسار فورم التسجيل)
            if let avatarImage {
                await uploadAvatar(image: avatarImage, for: newId)
            }

            let adminName = currentUser?.firstName ?? "مدير"
            await notificationVM?.notifyAdminsWithPush(
                title: L10n.t("إضافة عضو جديد", "New Member Added"),
                body: L10n.t(
                    "\(adminName) أضاف «\(fullName)» للشجرة العائلية",
                    "\(adminName) added «\(fullName)» to the family tree"
                ),
                kind: "member_add"
            )

            self.isLoading = false
            return true
        } catch {
            Log.error("فشل إضافة عضو من الإدارة: \(error.localizedDescription)")
            self.isLoading = false
            return false
        }
    }

    // إضافة ابن جديد مع ترتيب تلقائي
    func addChild(
        firstNameOnly: String,
        phoneNumber: String,
        birthDate: String?,
        fatherId: UUID,
        isDeceased: Bool,
        deathDate: String?,
        gender: String?,
        silent: Bool = false
    ) async -> UUID? {
        guard NetworkMonitor.shared.requireOnline() else { return nil }
        self.isLoading = true
        
        // 1. دالة داخلية تضمن تحويل أي رقم عربي إلى إنجليزي يدوياً لقطع الشك باليقين ✅
        func cleanNumber(_ input: String) -> String {
            let arabicNumbers = ["٠":"0","١":"1","٢":"2","٣":"3","٤":"4","٥":"5","٦":"6","٧":"7","٨":"8","٩":"9"]
            var temp = input
            for (arabic, english) in arabicNumbers {
                temp = temp.replacingOccurrences(of: arabic, with: english)
            }
            return temp
        }
        
        // 2. تنظيف التواريخ قبل استخدامها
        let cleanedBirthDate = birthDate.flatMap { $0.isEmpty ? nil : cleanNumber($0) }
        let cleanedDeathDate = deathDate.flatMap { $0.isEmpty ? nil : cleanNumber($0) }
        
        // 3. البحث عن بيانات الأب لبناء الاسم الكامل
        let father: FamilyMember?
        if let localFather = _memberById[fatherId] {
            father = localFather
        } else {
            let remoteFathers: [FamilyMember]? = try? await supabase
                .from("profiles")
                .select()
                .eq("id", value: fatherId.uuidString)
                .limit(1)
                .execute()
                .value
            father = remoteFathers?.first
        }
        
        guard let father else {
            Log.error("لم يتم العثور على بيانات الأب في القائمة أو السيرفر")
            self.isLoading = false
            return nil
        }
        
        let finalFullName = "\(firstNameOnly) \(father.fullName)".trimmingCharacters(in: .whitespaces)
        let newId = UUID()
        
        // 4. بناء المصفوفة بالقيم النظيفة (cleanedBirthDate) ✅
        let storedPhone = KuwaitPhone.normalizeForStorageFromInput(phoneNumber) ?? ""
        var newChild: [String: AnyEncodable] = [
            "id": AnyEncodable(newId.uuidString),
            "full_name": AnyEncodable(finalFullName),
            "first_name": AnyEncodable(firstNameOnly),
            "father_id": AnyEncodable(fatherId.uuidString),
            "birth_date": AnyEncodable(cleanedBirthDate ?? Optional<String>.none),
            "role": AnyEncodable("member"),
            "phone_number": AnyEncodable(storedPhone),
            "is_deceased": AnyEncodable(isDeceased),
            "is_married": AnyEncodable(false),
            "sort_order": AnyEncodable(allMembers.filter { $0.fatherId == fatherId }.count),
            "status": AnyEncodable("active")
        ]
        
        // إلحاق الجنس إذا كان محدداً
        if let gender, !gender.isEmpty {
            newChild["gender"] = AnyEncodable(gender)
        }
        
        // إلحاق تاريخ الوفاة إذا كان الشخص متوفى
        if isDeceased, let dDate = cleanedDeathDate {
            newChild["death_date"] = AnyEncodable(dDate)
        }

        // تتبع المدير الذي أضاف العضو (إذا كان المدير يضيف)
        if canModerate, let adminId = currentUser?.id {
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime]
            newChild["updated_by"] = AnyEncodable(adminId.uuidString)
            newChild["updated_at"] = AnyEncodable(isoFormatter.string(from: Date()))
        }

        do {
            try await supabase.from("profiles").insert(newChild).execute()
            
            // إضافة فورية للقائمة المحلية لتحديث الواجهة بدون انتظار
            let optimisticChild = FamilyMember(
                id: newId,
                firstName: firstNameOnly,
                fullName: finalFullName,
                phoneNumber: storedPhone,
                birthDate: cleanedBirthDate,
                deathDate: isDeceased ? cleanedDeathDate : nil,
                isDeceased: isDeceased,
                role: .member,
                fatherId: fatherId,
                photoURL: nil,
                isPhoneHidden: false,
                isHiddenFromTree: false,
                sortOrder: allMembers.filter { $0.fatherId == fatherId }.count,
                bio: nil,
                status: .active,
                avatarUrl: nil,
                isMarried: false,
                gender: gender,
                createdAt: nil
            )
            self.allMembers.append(optimisticChild)
            
            // تسجيل طلب إداري + إشعار فقط إذا الإضافة من حسابي (وليس من تعديل المدير)
            if !silent {
                let requester = currentUser?.id ?? fatherId
                let details = "تمت إضافة ابن جديد: \(firstNameOnly) (\(isDeceased ? "متوفى" : "حي"))."
                let childRequestId = UUID()
                let requestData: [String: AnyEncodable] = [
                    "id": AnyEncodable(childRequestId.uuidString),
                    "member_id": AnyEncodable(fatherId.uuidString),
                    "requester_id": AnyEncodable(requester.uuidString),
                    "request_type": AnyEncodable(RequestType.childAdd.rawValue),
                    "new_value": AnyEncodable(newId.uuidString),
                    "status": AnyEncodable(ApprovalStatus.pending.rawValue),
                    "details": AnyEncodable(details)
                ]
                do {
                    try await supabase
                        .from("admin_requests")
                        .insert(requestData)
                        .execute()

                    await notificationVM?.notifyAdminsWithPush(
                        title: L10n.t("طلب إضافة ابن", "Child Add Request"),
                        body: L10n.t(
                            "\(firstNameOnly) لـ: \(father.fullName)",
                            "\(firstNameOnly) to: \(father.fullName)"
                        ),
                        kind: RequestType.childAdd.rawValue,
                        requestId: childRequestId,
                        requestType: RequestType.childAdd.rawValue
                    )
                } catch {
                    Log.warning("لم يتم إدراج طلب child_add في admin_requests: \(error.localizedDescription)")
                }
            }
            
            // تحديث البيانات فوراً — عضو واحد فقط
            await fetchSingleMember(id: newId)
            await fetchChildren(for: fatherId)
            
            Log.info("تمت إضافة الابن بنجاح")
            self.isLoading = false
            return newId
        } catch {
            Log.error("خطأ إضافة الابن: \(error)")
            Log.error("تفاصيل: name=\(firstNameOnly), fatherId=\(fatherId), birthDate=\(cleanedBirthDate ?? "nil")")
        }
        self.isLoading = false
        return nil
    }
    
    // MARK: - Avatar Upload/Delete
    
    // رفع صورة العضو — يرجع false مع errorMessage عند الفشل (لا فشل صامت)
    @discardableResult
    func uploadAvatar(image: UIImage, for memberId: UUID) async -> Bool {
        guard NetworkMonitor.shared.requireOnline() else { return false }
        self.isLoading = true

        // 1. ضغط الصورة وتحويلها لبيانات (في خلفية لتجنب تجميد UI)
        let processed = await Task.detached(priority: .userInitiated) {
            ImageProcessor.process(image, for: .avatar)
        }.value
        guard let imageData = processed else {
            self.isLoading = false
            self.errorMessage = L10n.t("تعذر معالجة الصورة", "Could not process the image")
            return false
        }

        // التقط رابط الصورة القديم قبل التعديل
        let oldAvatarUrl = _memberById[memberId]?.avatarUrl

        let safeName = getSafeMemberName(for: memberId)
        let fileName = "\(safeName).jpg"

        do {
            // 2. الرفع إلى السيرفر
            try await supabase.storage
                .from("avatars")
                .upload(
                    fileName,
                    data: imageData,
                    options: FileOptions(contentType: "image/jpeg", upsert: true)
                )

            // 3. الحصول على الرابط العام مع cache-busting
            let publicUrl = try supabase.storage
                .from("avatars")
                .getPublicURL(path: fileName)

            let timestamp = Int(Date().timeIntervalSince1970)
            let urlString = "\(publicUrl.absoluteString)?v=\(timestamp)"

            // 4. تحديث رابط الصورة في جدول profiles + تتبع المدير
            var avatarUpdate: [String: AnyEncodable] = [
                "avatar_url": AnyEncodable(urlString)
            ]
            avatarUpdate.merge(adminAuditFields(for: memberId)) { _, new in new }

            try await supabase
                .from("profiles")
                .update(avatarUpdate)
                .eq("id", value: memberId.uuidString)
                .execute()

            // 5. تحديث البيانات محلياً فوراً
            await fetchSingleMember(id: memberId)
            if memberId == currentUser?.id {
                await authVM?.checkUserProfile()
            }

            Log.info("تم رفع الصورة بنجاح: \(urlString)")

            // إشعار العضو بتغيير صورته (إذا المدير غيّرها وليس العضو نفسه)
            if memberId != currentUser?.id {
                await notificationVM?.sendPushToMembers(
                    title: L10n.t("تم تحديث صورتك", "Your Photo Was Updated"),
                    body: L10n.t(
                        "قام المشرف بتحديث صورتك الشخصية",
                        "An admin updated your profile photo"
                    ),
                    kind: "profile_update",
                    targetMemberIds: [memberId]
                )
                if let creator = currentUser?.id {
                    let payload: [String: AnyEncodable] = [
                        "target_member_id": AnyEncodable(memberId.uuidString),
                        "title": AnyEncodable(L10n.t("تحديث الصورة", "Photo Updated")),
                        "body": AnyEncodable(L10n.t("تم تحديث صورتك الشخصية", "Your profile photo was updated")),
                        "kind": AnyEncodable("profile_update"),
                        "created_by": AnyEncodable(creator.uuidString)
                    ]
                    _ = try? await supabase.from("notifications").insert(payload).execute()
                }

                // إشعار بقية المدراء في تاب المستجدات بتفاصيل التغيير
                await notifyAdminsOfMemberEdit(
                    memberId: memberId,
                    kind: NotificationKind.adminEditAvatar.rawValue,
                    title: L10n.t("تحديث صورة", "Photo Update"),
                    body: adminEditBody(verb: L10n.t("تم تحديث الصورة الشخصية", "Profile photo updated"), memberId: memberId),
                    changes: [
                        .init(field: "avatar_url", before: oldAvatarUrl, after: urlString)
                    ]
                )
            } else {
                // العضو غيّر صورته بنفسه → إشعار للمدراء في تاب "المستجدات"
                // (نتجاوز guard الـ notifyAdminsOfMemberEdit بالاستدعاء المباشر لأن العضو هنا = العامل)
                let memberName = _memberById[memberId]?.firstName ?? L10n.t("عضو", "member")
                await notificationVM?.notifyAdminsWithChangesAndPush(
                    title: L10n.t("تحديث صورة", "Photo Update"),
                    body: L10n.t(
                        "حدّث «\(memberName)» صورته الشخصية",
                        "«\(memberName)» updated their profile photo"
                    ),
                    kind: NotificationKind.adminEditAvatar.rawValue,
                    changes: [
                        .init(field: "avatar_url", before: oldAvatarUrl, after: urlString)
                    ]
                )
            }

        } catch {
            Log.error("خطأ في الرفع أو الرابط: \(error.localizedDescription)")
            self.errorMessage = L10n.t("تعذر رفع الصورة. حاول مرة أخرى.", "Photo upload failed. Try again.")
            self.isLoading = false
            return false
        }
        self.isLoading = false
        return true
    }

    func deleteAvatar(for memberId: UUID) async {
        guard NetworkMonitor.shared.requireOnline() else { return }
        guard memberId == currentUser?.id || canModerate else {
            Log.warning("[AUTH] Unauthorized deleteAvatar attempt for \(memberId)")
            return
        }
        self.isLoading = true
        do {
            // حذف الملف من التخزين إذا كان موجوداً
            let cachedAvatarURL =
                _memberById[memberId]?.avatarUrl ??
                (currentUser?.id == memberId ? currentUser?.avatarUrl : nil)
            
            let safeName = getSafeMemberName(for: memberId)
            var candidatePaths: [String] = ["\(memberId.uuidString).jpg", "\(safeName).jpg"]
            if let cachedAvatarURL,
               let parsedPath = storagePath(fromPublicURL: cachedAvatarURL, bucket: "avatars"),
               !parsedPath.isEmpty,
               !candidatePaths.contains(parsedPath) {
                candidatePaths.append(parsedPath)
            }
            
            _ = try? await supabase.storage
                .from("avatars")
                .remove(paths: candidatePaths)
            
            // 1. إرسال قيمة فارغة (Optional.none) لتمثيل الـ NULL في قاعدة البيانات ✅
            var updateData: [String: AnyEncodable] = [
                "avatar_url": AnyEncodable(Optional<String>.none)
            ]
            updateData.merge(adminAuditFields(for: memberId)) { _, new in new }
            
            try await supabase
                .from("profiles")
                .update(updateData)
                .eq("id", value: memberId.uuidString)
                .execute()
            
            // 2. تحديث البيانات محلياً
            await fetchSingleMember(id: memberId)
            if memberId == currentUser?.id {
                await authVM?.checkUserProfile()
            }

            Log.info("تم حذف رابط الصورة بنجاح")
            
        } catch {
            Log.error("خطأ في حذف الصورة: \(error.localizedDescription)")
            self.errorMessage = L10n.t("تعذر حذف الصورة. حاول مرة أخرى.", "Photo removal failed. Try again.")
        }
        self.isLoading = false
    }
    
    // MARK: - صورة الغلاف (Cover) منفصلة عن الصورة الشخصية (Avatar)
    
    func uploadCover(image: UIImage, for memberId: UUID) async {
        self.isLoading = true

        let processed = await Task.detached(priority: .userInitiated) {
            ImageProcessor.process(image, for: .cover)
        }.value
        guard let imageData = processed else {
            self.isLoading = false
            return
        }

        let safeName = getSafeMemberName(for: memberId)
        let fileName = "cover_\(safeName).jpg"
        
        do {
            try await supabase.storage
                .from("avatars")
                .upload(
                    fileName,
                    data: imageData,
                    options: FileOptions(contentType: "image/jpeg", upsert: true)
                )
            
            let publicUrl = try supabase.storage
                .from("avatars")
                .getPublicURL(path: fileName)
            
            let coverTimestamp = Int(Date().timeIntervalSince1970)
            let urlString = "\(publicUrl.absoluteString)?v=\(coverTimestamp)"
            
            try await supabase
                .from("profiles")
                .update(["cover_url": AnyEncodable(urlString)])
                .eq("id", value: memberId.uuidString)
                .execute()

            await fetchSingleMember(id: memberId)
            if memberId == currentUser?.id {
                await authVM?.checkUserProfile()
            }
            
            Log.info("تم رفع صورة الغلاف بنجاح: \(urlString)")
            
        } catch {
            Log.error("خطأ في رفع صورة الغلاف: \(error.localizedDescription)")
        }
        self.isLoading = false
    }
    
    func deleteCover(for memberId: UUID) async {
        guard memberId == currentUser?.id || canModerate else {
            Log.warning("[AUTH] Unauthorized deleteCover attempt for \(memberId)")
            return
        }
        self.isLoading = true
        do {
            let cachedCoverURL =
                _memberById[memberId]?.coverUrl ??
                (currentUser?.id == memberId ? currentUser?.coverUrl : nil)
            
            let safeName = getSafeMemberName(for: memberId)
            var candidatePaths: [String] = ["cover_\(safeName).jpg"]
            if let cachedCoverURL,
               let parsedPath = storagePath(fromPublicURL: cachedCoverURL, bucket: "avatars"),
               !parsedPath.isEmpty,
               !candidatePaths.contains(parsedPath) {
                candidatePaths.append(parsedPath)
            }
            
            _ = try? await supabase.storage
                .from("avatars")
                .remove(paths: candidatePaths)
            
            let updateData: [String: AnyEncodable] = [
                "cover_url": AnyEncodable(Optional<String>.none)
            ]

            try await supabase
                .from("profiles")
                .update(updateData)
                .eq("id", value: memberId.uuidString)
                .execute()

            await fetchSingleMember(id: memberId)
            if memberId == currentUser?.id {
                await authVM?.checkUserProfile()
            }
            
            Log.info("تم حذف صورة الغلاف بنجاح")
            
        } catch {
            Log.error("خطأ في حذف صورة الغلاف: \(error.localizedDescription)")
        }
        self.isLoading = false
    }
    
    
    // MARK: - Update Member Data
    
    @discardableResult
    func updateMemberData(
        memberId: UUID,
        fullName: String,
        phoneNumber: String,
        birthDate: Date?,
        isMarried: Bool,
        isDeceased: Bool,
        deathDate: Date?,
        isPhoneHidden: Bool
    ) async -> Bool {
        guard NetworkMonitor.shared.requireOnline() else { return false }
        // التحقق من تكرار الرقم
        if !phoneNumber.isEmpty {
            let check = isPhoneDuplicate(phoneNumber, excludingMemberId: memberId)
            if check.isDuplicate {
                Log.warning("رقم الهاتف مستخدم من عضو آخر: \(check.existingMember?.fullName ?? "")")
                self.errorMessage = L10n.t(
                    "رقم الهاتف مستخدم من عضو آخر: \(check.existingMember?.fullName ?? "")",
                    "Phone number already used by: \(check.existingMember?.fullName ?? "")"
                )
                return false
            }
        }
        self.isLoading = true

        // استخراج الاسم الأول تلقائياً
        let firstName = fullName.components(separatedBy: " ").first ?? fullName
        let normalizedPhone = KuwaitPhone.normalizeForStorageFromInput(phoneNumber) ?? ""

        // التقط الحالة قبل التحديث للمقارنة
        let oldMember = _memberById[memberId]

        // 2. نكتب الحقول المتغيّرة فقط — حاسم: كتابة حقول لم تتغيّر (خصوصاً
        //    birth_date/first_name/full_name) تُفعّل trigger مزامنة النساء على
        //    السيرفر الذي قد يفصل الزوجة/الأبناء/الأم. تبديل «متزوج» وحده يكتب
        //    is_married فقط (ليس ضمن مراقبة الـtrigger) → لا فقدان بيانات.
        var updateData: [String: AnyEncodable] = [:]

        if oldMember == nil || oldMember?.fullName != fullName {
            updateData["full_name"]  = AnyEncodable(fullName)
            updateData["first_name"] = AnyEncodable(firstName)
        }
        if !normalizedPhone.isEmpty, (oldMember?.phoneNumber ?? "") != normalizedPhone {
            updateData["phone_number"] = AnyEncodable(normalizedPhone)
        }
        // birth_date يُكتب فقط إذا زُوّد فعلاً وتغيّر — لا نفبرك "اليوم" لمن لا تاريخ له
        if let birthDate {
            let newBirth = DateHelper.format(birthDate)
            if (oldMember?.birthDate ?? "") != newBirth {
                updateData["birth_date"] = AnyEncodable(newBirth)
            }
        }
        if (oldMember?.isMarried ?? false) != isMarried {
            updateData["is_married"] = AnyEncodable(isMarried)
        }
        if (oldMember?.isDeceased ?? false) != isDeceased {
            updateData["is_deceased"] = AnyEncodable(isDeceased)
        }
        if isDeceased, let dDate = deathDate {
            let newDeath = DateHelper.format(dDate)
            if (oldMember?.deathDate ?? "") != newDeath {
                updateData["death_date"] = AnyEncodable(newDeath)
            }
        }
        if (oldMember?.isPhoneHidden ?? false) != isPhoneHidden {
            updateData["is_phone_hidden"] = AnyEncodable(isPhoneHidden)
        }

        // لا شيء تغيّر فعلاً → لا نكتب (نتجنّب تفعيل triggers السيرفر بلا داعٍ)
        guard !updateData.isEmpty else {
            self.isLoading = false
            return true
        }

        // تتبع المدير إذا كان يعدل بيانات عضو آخر
        updateData.merge(adminAuditFields(for: memberId)) { _, new in new }

        do {
            // 3. تنفيذ التحديث في Supabase
            try await supabase
                .from("profiles")
                .update(updateData)
                .eq("id", value: memberId.uuidString)
                .execute()

            // 4. تحديث أسماء الذرية تلقائياً (إذا تغير الاسم)
            if oldMember?.fullName != fullName || oldMember?.firstName != firstName {
                await propagateNameToDescendants(of: memberId)
                // تحديث كل الأعضاء لأن الذرية تغيرت
                await fetchAllMembers(force: true)
            } else {
                await fetchSingleMember(id: memberId)
            }

            // إذا كان المستخدم يحدّث ملفه الشخصي "هو"
            if memberId == currentUser?.id {
                await authVM?.checkUserProfile()
            }

            // إشعار المدراء بتفاصيل التغيير (إذا المدير عدّل عضو آخر)
            var changes: [AppNotification.NotificationDetails.ChangeEntry] = []
            if let old = oldMember {
                let newBirth: String? = birthDate.map { DateHelper.format($0) }
                let newDeath: String? = (isDeceased && deathDate != nil) ? DateHelper.format(deathDate!) : nil
                let oldDeceased = old.isDeceased ?? false
                let oldMarried = old.isMarried ?? false
                let oldPhoneHidden = old.isPhoneHidden ?? false

                if old.fullName != fullName {
                    changes.append(.init(field: "full_name", before: old.fullName, after: fullName))
                }
                if !normalizedPhone.isEmpty, (old.phoneNumber ?? "") != normalizedPhone {
                    changes.append(.init(field: "phone_number", before: old.phoneNumber, after: normalizedPhone))
                }
                if let newBirth, (old.birthDate ?? "") != newBirth {
                    changes.append(.init(field: "birth_date", before: old.birthDate, after: newBirth))
                }
                if oldMarried != isMarried {
                    changes.append(.init(
                        field: "is_married",
                        before: oldMarried ? L10n.t("متزوج", "Married") : L10n.t("غير متزوج", "Single"),
                        after: isMarried ? L10n.t("متزوج", "Married") : L10n.t("غير متزوج", "Single")
                    ))
                }
                if oldDeceased != isDeceased {
                    changes.append(.init(
                        field: "is_deceased",
                        before: oldDeceased ? L10n.t("متوفى", "Deceased") : L10n.t("على قيد الحياة", "Alive"),
                        after: isDeceased ? L10n.t("متوفى", "Deceased") : L10n.t("على قيد الحياة", "Alive")
                    ))
                }
                if isDeceased, (old.deathDate ?? "") != (newDeath ?? "") {
                    changes.append(.init(field: "death_date", before: old.deathDate, after: newDeath))
                }
                if oldPhoneHidden != isPhoneHidden {
                    changes.append(.init(
                        field: "is_phone_hidden",
                        before: oldPhoneHidden ? L10n.t("مخفي", "Hidden") : L10n.t("ظاهر", "Visible"),
                        after: isPhoneHidden ? L10n.t("مخفي", "Hidden") : L10n.t("ظاهر", "Visible")
                    ))
                }
            }
            await notifyAdminsOfMemberEdit(
                memberId: memberId,
                kind: NotificationKind.adminEdit.rawValue,
                title: L10n.t("تعديل بيانات عضو", "Member Edit"),
                body: adminEditBody(verb: L10n.t("تم تعديل البيانات", "Profile data updated"), memberId: memberId),
                changes: changes
            )

            Log.info("تم تحديث بيانات: \(fullName) بنجاح")
            self.isLoading = false
            return true

        } catch {
            Log.error("خطأ في التحديث: \(error.localizedDescription)")
            self.isLoading = false
            return false
        }
    }

    /// تحديث السيرة الذاتية (bio_json)
    func updateMemberBio(memberId: UUID, bio: [FamilyMember.BioStation]) async {
        guard NetworkMonitor.shared.requireOnline() else { return }
        do {
            try await supabase
                .from("profiles")
                .update(["bio_json": AnyEncodable(bio)])
                .eq("id", value: memberId.uuidString)
                .execute()

            await fetchSingleMember(id: memberId)
            if memberId == currentUser?.id {
                await authVM?.checkUserProfile()
            }
            Log.info("تم تحديث السيرة الذاتية بنجاح")
        } catch {
            Log.error("خطأ في تحديث السيرة: \(error.localizedDescription)")
        }
    }

    /// تحديث إخفاء رقم الهاتف فقط
    @discardableResult
    func updatePhoneHidden(_ isHidden: Bool) async -> Bool {
        guard let userId = currentUser?.id else { return false }
        do {
            try await supabase
                .from("profiles")
                .update(["is_phone_hidden": AnyEncodable(isHidden)])
                .eq("id", value: userId.uuidString)
                .execute()
            await fetchSingleMember(id: userId)
            if let updated = _memberById[userId] {
                authVM?.currentUser = updated
            }
            return true
        } catch {
            Log.error("خطأ تحديث إخفاء الرقم: \(error.localizedDescription)")
            return false
        }
    }

    /// تحديث إخفاء تاريخ الميلاد
    @discardableResult
    func updateBirthDateHidden(_ isHidden: Bool) async -> Bool {
        guard let userId = currentUser?.id else { return false }
        do {
            try await supabase
                .from("profiles")
                .update(["is_birth_date_hidden": AnyEncodable(isHidden)])
                .eq("id", value: userId.uuidString)
                .execute()
            await fetchSingleMember(id: userId)
            if let updated = _memberById[userId] {
                authVM?.currentUser = updated
            }
            return true
        } catch {
            Log.error("خطأ تحديث إخفاء تاريخ الميلاد: \(error.localizedDescription)")
            return false
        }
    }

    func updateBadgeEnabled(_ isEnabled: Bool) async {
        guard let userId = currentUser?.id else { return }
        do {
            try await supabase
                .from("profiles")
                .update(["badge_enabled": AnyEncodable(isEnabled)])
                .eq("id", value: userId.uuidString)
                .execute()
            await fetchSingleMember(id: userId)
            if let updated = _memberById[userId] {
                authVM?.currentUser = updated
            }
        } catch {
            Log.error("خطأ تحديث إعداد شارة الإشعارات: \(error.localizedDescription)")
        }
    }

    // تحديث ترتيب الأبناء بالسحب والإفلات
    func moveChild(from source: IndexSet, to destination: Int) {
        currentMemberChildren.move(fromOffsets: source, toOffset: destination)
        Task {
            for (index, child) in currentMemberChildren.enumerated() {
                _ = try? await supabase
                    .from("profiles")
                    .update(["sort_order": AnyEncodable(index)])
                    .eq("id", value: child.id.uuidString)
                    .execute()
                
                if let idx = allMembers.firstIndex(where: { $0.id == child.id }) {
                    allMembers[idx].sortOrder = index
                }
            }
            objectWillChange.send()
        }
    }
    
    // MARK: - Update Member Name
    
    /// - Parameter silent: لو true، تتخطّى إشعار الـadmin-edit لكل المدراء.
    ///   تُستخدم من saveAction (admin sheet) عشان نرسل إشعار موحَّد بكل التغييرات
    ///   بدل إشعار لكل حقل.
    func updateMemberName(memberId: UUID, fullName: String, silent: Bool = false) async {
        guard NetworkMonitor.shared.requireOnline() else { return }
        self.isLoading = true
        let firstName = fullName.components(separatedBy: " ").first ?? fullName

        // التقط الاسم القديم قبل التعديل
        let oldFullName = _memberById[memberId]?.fullName

        var nameUpdate: [String: AnyEncodable] = [
            "full_name": AnyEncodable(fullName),
            "first_name": AnyEncodable(firstName)
        ]
        nameUpdate.merge(adminAuditFields(for: memberId)) { _, new in new }

        do {
            try await supabase
                .from("profiles")
                .update(nameUpdate)
                .eq("id", value: memberId.uuidString)
                .execute()

            // تحديث أسماء كل الذرية تلقائياً
            await propagateNameToDescendants(of: memberId)

            await fetchAllMembers(force: true)

            // إشعار العضو بتغيير اسمه (إذا المدير غيّره وليس العضو نفسه)
            if memberId != currentUser?.id {
                await notificationVM?.sendPushToMembers(
                    title: L10n.t("تم تحديث اسمك", "Your Name Was Updated"),
                    body: L10n.t(
                        "تم تحديث اسمك إلى: \(fullName)",
                        "Your name was updated to: \(fullName)"
                    ),
                    kind: "profile_update",
                    targetMemberIds: [memberId]
                )
                if let creator = currentUser?.id {
                    let payload: [String: AnyEncodable] = [
                        "target_member_id": AnyEncodable(memberId.uuidString),
                        "title": AnyEncodable(L10n.t("تحديث الاسم", "Name Updated")),
                        "body": AnyEncodable(L10n.t("تم تحديث اسمك إلى: \(fullName)", "Your name was updated to: \(fullName)")),
                        "kind": AnyEncodable("profile_update"),
                        "created_by": AnyEncodable(creator.uuidString)
                    ]
                    _ = try? await supabase.from("notifications").insert(payload).execute()
                }

                // إشعار المدراء بتفاصيل التغيير (يُتخطّى لو silent=true)
                if !silent {
                    await notifyAdminsOfMemberEdit(
                        memberId: memberId,
                        kind: NotificationKind.adminEditName.rawValue,
                        title: L10n.t("تعديل الاسم", "Name Edit"),
                        body: adminEditBody(verb: L10n.t("تم تعديل الاسم", "Name was updated"), memberId: memberId),
                        changes: [
                            .init(field: "full_name", before: oldFullName, after: fullName)
                        ]
                    )
                }
            }

            Log.info("تم تحديث اسم العضو بنجاح")
        } catch {
            Log.error("فشل تحديث اسم العضو: \(error.localizedDescription)")
        }

        self.isLoading = false
    }

    // MARK: - تحديث أسماء الذرية تلقائياً عند تغيير اسم الأب/الجد
    //
    // المنطق المعتمد (يطابق Supabase trigger trg_cascade_full_name_to_children):
    //
    //   child.full_name = child.first_name + " " + parent.full_name
    //
    // ✅ يلتقط أي تغيير في full_name للأب — حتى لو الجزء الأوسط بس
    //    (مثلاً: "حسن صلاح ال محمد" → "حسن صلاح آل محمد").
    // ❌ المنطق القديم كان يبني من سلسلة firstName للآباء — فيتجاهل
    //    تغييرات في أي جزء غير الاسم الأول.

    /// تحديث **محلّي فوري** لأسماء الذرّية في الكاش — استجابة فورية في الـUI.
    /// يجب استدعاؤه **بعد** تحديث الأب محلياً (full_name + first_name).
    /// السيرفر (trigger) يتولّى نفس العملية للحفظ النهائي.
    @MainActor
    func propagateNameToDescendantsLocally(of memberId: UUID) {
        guard let edited = _memberById[memberId] else {
            Log.warning("[Cascade-Local] الأب غير موجود في الكاش — memberId=\(memberId)")
            return
        }
        Log.info("[Cascade-Local] 🌳 بدء انتشار اسم: \(edited.firstName) → fullName=«\(edited.fullName)»")

        // BFS من الأب نحو الأسفل — كل مستوى يستخدم fullName المحدّث للأب
        var queue: [UUID] = [memberId]
        var updatedCount = 0
        var visited: Set<UUID> = [memberId]
        var levelByMember: [UUID: Int] = [memberId: 0]

        while let parentId = queue.first {
            queue.removeFirst()
            guard let parentNow = _memberById[parentId] else { continue }
            let parentFullName = parentNow.fullName
            let parentLevel = levelByMember[parentId] ?? 0

            // أبناء مباشرين لهذا الأب — نقرأ من allMembers (مُحدَّث بعد upsertMemberLocally)
            let directChildren = allMembers.filter { $0.fatherId == parentId }
            if !directChildren.isEmpty {
                Log.info("[Cascade-Local] L\(parentLevel + 1): \(parentNow.firstName) عنده \(directChildren.count) ذرّية مباشرة")
            }

            for child in directChildren {
                guard !visited.contains(child.id) else { continue }
                visited.insert(child.id)
                queue.append(child.id)
                levelByMember[child.id] = parentLevel + 1

                let firstName = child.firstName.trimmingCharacters(in: .whitespacesAndNewlines)
                let newFullName = (firstName.isEmpty
                    ? parentFullName
                    : "\(firstName) \(parentFullName)")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                guard newFullName != child.fullName else {
                    Log.info("[Cascade-Local]   • \(child.firstName) (L\(parentLevel + 1)) متطابق مسبقاً")
                    continue
                }
                var updated = child
                updated.fullName = newFullName
                upsertMemberLocally(updated)
                updatedCount += 1
                Log.info("[Cascade-Local]   ✓ \(child.firstName) (L\(parentLevel + 1)): «\(child.fullName)» → «\(newFullName)»")
            }
        }

        let maxLevel = levelByMember.values.max() ?? 0
        Log.info("[Cascade-Local] 🌳 انتهى — محدّث \(updatedCount) من \(visited.count - 1) ذرّية، \(maxLevel) أجيال")
    }

    /// (طبقة احتياط) — السيرفر trigger يتولّى الـcascade على البيانات.
    /// نكتفي هنا بـfetch بسيط للتحقق من تطابق الكاش مع السيرفر.
    private func propagateNameToDescendants(of memberId: UUID) async {
        // الـtrigger السيرفري حدّث الذرّية فعلاً. fetchAllMembers (المُستدعى
        // بعد هذه الدالة) يجلب التحديثات. لا داعي لـHTTP per descendant.
        Log.info("[Cascade] السيرفر trigger يتولّى cascade — في انتظار fetchAllMembers")
    }
    
    // MARK: - Delete Member (Admin only)

    /// حذف عضو نهائياً من قاعدة البيانات (للمالك فقط)
    func deleteMember(memberId: UUID) async -> Bool {
        guard NetworkMonitor.shared.requireOnline() else { return false }
        guard authVM?.canDeleteMembers == true else {
            Log.error("حذف العضو مرفوض: الصلاحية للمالك فقط")
            return false
        }
        guard memberId != currentUser?.id else {
            Log.error("لا يمكن حذف حسابك الشخصي")
            return false
        }

        isLoading = true
        do {
            // حذف الإشعارات المرتبطة — نسجّل الفشل لكن لا نوقف الحذف
            do {
                try await supabase.from("notifications")
                    .delete()
                    .eq("target_member_id", value: memberId.uuidString)
                    .execute()
            } catch { Log.warning("[Delete] فشل حذف notifications للعضو \(memberId): \(error.localizedDescription)") }

            // حذف device tokens
            do {
                try await supabase.from("device_tokens")
                    .delete()
                    .eq("member_id", value: memberId.uuidString)
                    .execute()
            } catch { Log.warning("[Delete] فشل حذف device_tokens للعضو \(memberId): \(error.localizedDescription)") }

            // حذف صور المعرض
            do {
                try await supabase.from("member_gallery_photos")
                    .delete()
                    .eq("member_id", value: memberId.uuidString)
                    .execute()
            } catch { Log.warning("[Delete] فشل حذف member_gallery_photos للعضو \(memberId): \(error.localizedDescription)") }

            // حذف العضو من profiles
            try await supabase.from("profiles")
                .delete()
                .eq("id", value: memberId.uuidString)
                .execute()

            // إزالة العضو محلياً
            allMembers.removeAll { $0.id == memberId }
            membersVersion += 1
            scheduleMembersCacheSave()
            Log.info("تم حذف العضو بنجاح: \(memberId)")
            isLoading = false
            return true
        } catch {
            Log.error("فشل حذف العضو: \(error.localizedDescription)")
            isLoading = false
            return false
        }
    }

    // MARK: - Update Member Role

    // هذه الدالة لتحديث رتبة العضو (مدير، مشرف، عضو) — المالك فقط
    func updateMemberRole(memberId: UUID, newRole: FamilyMember.UserRole) async {
        guard authVM?.canManageRoles == true else {
            Log.error("تم رفض تحديث الرتبة: الصلاحية للمالك فقط")
            return
        }
        
        // تجاهل إذا الرتبة نفسها لم تتغير
        let currentRole = _memberById[memberId]?.role
        guard currentRole != newRole else {
            Log.info("الرتبة لم تتغير، تم التجاهل")
            return
        }
        
        self.isLoading = true
        
        do {
            // 1. تحديث حقل role في قاعدة البيانات + تتبع المدير
            var roleUpdate: [String: AnyEncodable] = [
                "role": AnyEncodable(newRole.rawValue)
            ]
            roleUpdate.merge(adminAuditFields(for: memberId)) { _, new in new }

            try await supabase
                .from("profiles")
                .update(roleUpdate)
                .eq("id", value: memberId.uuidString)
                .execute()

            // 2. تحديث البيانات محلياً
            await fetchSingleMember(id: memberId)

            // الاسم الرباعي في الإشعار — أوضح من الاسم الأول، أقصر من الكامل
            let memberName = _memberById[memberId]?.fourPartName ?? L10n.t("عضو", "member")
            let roleName: String = {
                switch newRole {
                case .admin, .owner: return L10n.t("مدير", "Admin")
                case .monitor: return L10n.t("مراقب", "Monitor")
                case .supervisor: return L10n.t("مشرف", "Supervisor")
                default: return L10n.t("عضو", "Member")
                }
            }()

            // 3. إشعار المدراء بتغيير الرتبة (push + داخلي مع تفاصيل قبل/بعد)
            let oldRoleLabel: String = {
                guard let current = currentRole else { return L10n.t("غير محدد", "Unknown") }
                switch current {
                case .admin, .owner: return L10n.t("مدير", "Admin")
                case .monitor: return L10n.t("مراقب", "Monitor")
                case .supervisor: return L10n.t("مشرف", "Supervisor")
                case .pending: return L10n.t("قيد المراجعة", "Pending")
                default: return L10n.t("عضو", "Member")
                }
            }()

            if memberId != currentUser?.id {
                await notificationVM?.notifyAdminsWithChangesAndPush(
                    title: L10n.t("تغيير الصلاحية", "Role Change"),
                    body: L10n.t(
                        "تم تغيير صلاحية «\(memberName)» إلى: «\(roleName)»",
                        "«\(memberName)»'s role changed to: «\(roleName)»"
                    ),
                    kind: NotificationKind.adminEditRole.rawValue,
                    changes: [.init(field: "role", before: oldRoleLabel, after: roleName)]
                )
            } else {
                // المالك يحدّث رتبته الخاصة (نادر) — أبقِ خلف الكواليس بدون details
                await notificationVM?.notifyAdminsWithPush(
                    title: L10n.t("تغيير الصلاحية", "Role Change"),
                    body: L10n.t(
                        "تم تغيير صلاحية «\(memberName)» إلى: «\(roleName)»",
                        "«\(memberName)»'s role changed to: «\(roleName)»"
                    ),
                    kind: "role_change"
                )
            }

            // 4. إشعار العضو نفسه بتغيير رتبته
            if authVM?.notificationsFeatureAvailable == true {
                let personalPayload: [String: AnyEncodable] = [
                    "target_member_id": AnyEncodable(memberId.uuidString),
                    "title": AnyEncodable(L10n.t("تغيير الصلاحية", "Role Change")),
                    "body": AnyEncodable(L10n.t(
                        "صلاحيتك الآن: «\(roleName)»",
                        "Your role is now: «\(roleName)»"
                    )),
                    "kind": AnyEncodable("role_change"),
                    "created_by": AnyEncodable(currentUser?.id.uuidString)
                ]
                do {
                    try await supabase.from("notifications").insert(personalPayload).execute()
                    await notificationVM?.sendPushToMembers(
                        title: L10n.t("تغيير الصلاحية", "Role Change"),
                        body: L10n.t(
                            "صلاحيتك الآن: «\(roleName)»",
                            "Your role is now: «\(roleName)»"
                        ),
                        kind: "role_change",
                        targetMemberIds: [memberId]
                    )
                } catch {
                    Log.warning("تعذر إرسال إشعار تغيير الرتبة للعضو: \(error.localizedDescription)")
                }
            }
            
            // 5. إيميل للعضو (إذا عنده إيميل) + للإدارة (سجل)
            let memberEmail = _memberById[memberId]?.email
            var emailPayload: [String: AnyEncodable] = [
                "type": AnyEncodable("role_changed"),
                "member_name": AnyEncodable(memberName),
                "old_role": AnyEncodable(currentRole?.rawValue ?? "member"),
                "new_role": AnyEncodable(newRole.rawValue)
            ]
            if let email = memberEmail, !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                emailPayload["member_email"] = AnyEncodable(email)
            }
            await authVM?.sendEventEmail(payload: emailPayload)

            Log.info("تم تحديث رتبة العضو بنجاح إلى: \(newRole.rawValue)")

        } catch {
            Log.error("فشل تحديث الرتبة: \(error.localizedDescription)")
        }

        self.isLoading = false
    }

    // MARK: - Set Member Status (freeze / activate)

    /// تجميد حساب عضو أو إعادة تفعيله — يمنع/يسمح بالدخول للتطبيق
    func setMemberStatus(memberId: UUID, status: FamilyMember.MemberStatus) async {
        guard authVM?.canEditMembers == true else {
            Log.error("[MEMBER] تم رفض تغيير الحالة: لا توجد صلاحية")
            return
        }
        let oldStatus = _memberById[memberId]?.status
        let memberName = _memberById[memberId]?.fourPartName ?? L10n.t("عضو", "member")
        let memberEmail = _memberById[memberId]?.email

        do {
            try await supabase
                .from("profiles")
                .update(["status": AnyEncodable(status.rawValue)])
                .eq("id", value: memberId.uuidString)
                .execute()

            if let index = allMembers.firstIndex(where: { $0.id == memberId }) {
                allMembers[index].status = status
            }
            Log.info("[MEMBER] تم تغيير حالة \(memberId) إلى \(status.rawValue)")

            // إيميل للعضو (إذا عنده إيميل) + للإدارة
            if oldStatus != status {
                var emailPayload: [String: AnyEncodable] = [
                    "type": AnyEncodable("status_changed"),
                    "member_name": AnyEncodable(memberName),
                    "old_status": AnyEncodable(oldStatus?.rawValue ?? "active"),
                    "new_status": AnyEncodable(status.rawValue)
                ]
                if let email = memberEmail, !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    emailPayload["member_email"] = AnyEncodable(email)
                }
                await authVM?.sendEventEmail(payload: emailPayload)
            }
        } catch {
            Log.error("[MEMBER] فشل تغيير الحالة: \(error.localizedDescription)")
        }
    }

    // MARK: - Update Children Order
    
    // دالة لتحديث ترتيب الأبناء بناءً على القائمة الجديدة
    func updateChildrenOrder(for fatherId: UUID, newOrder: [FamilyMember]) async {
        self.isLoading = true
        
        // 1) تحديث الترتيب في الذاكرة مباشرة لظهور أسرع
        for (index, child) in newOrder.enumerated() {
            if let allIdx = self.allMembers.firstIndex(where: { $0.id == child.id }) {
                self.allMembers[allIdx].sortOrder = index
            }
        }
        if fatherId == self.currentUser?.id {
            self.currentMemberChildren = newOrder.enumerated().map { idx, child in
                var mutable = child
                mutable.sortOrder = idx
                return mutable
            }
        }
        self.objectWillChange.send()
        
        // 2) تحديث sort_order فعلياً في Supabase
        for (index, child) in newOrder.enumerated() {
            do {
                try await supabase
                    .from("profiles")
                    .update(["sort_order": AnyEncodable(index)])
                    .eq("id", value: child.id.uuidString)
                    .execute()
            } catch {
                Log.error("فشل تحديث ترتيب \(child.firstName) إلى \(index): \(error)")
            }
        }
        
        // 3) مزامنة نهائية مع الشجرة بعد الحفظ
        await fetchAllMembers(force: false)
        if fatherId == self.currentUser?.id {
            await fetchChildren(for: fatherId)
        }
        self.isLoading = false
    }
    
    // MARK: - Update Member Phone
    
    func updateMemberPhone(memberId: UUID, newPhone: String) async {
        await updateMemberPhone(memberId: memberId, country: KuwaitPhone.defaultCountry, localPhone: newPhone)
    }

    func updateMemberPhone(memberId: UUID, country: KuwaitPhone.Country, localPhone: String, silent: Bool = false) async {
        guard NetworkMonitor.shared.requireOnline() else { return }
        self.isLoading = true
        guard let normalizedPhone = KuwaitPhone.normalizedForStorage(country: country, rawLocalDigits: localPhone) else {
            Log.error("رقم الهاتف غير صالح للدولة المختارة.")
            self.isLoading = false
            return
        }
        // التقط الرقم القديم قبل التحديث
        let oldPhone = _memberById[memberId]?.phoneNumber

        do {
            // 1) تحديث الهاتف + تتبع المدير
            var phoneUpdate: [String: AnyEncodable] = [
                "phone_number": AnyEncodable(normalizedPhone)
            ]
            phoneUpdate.merge(adminAuditFields(for: memberId)) { _, new in new }

            try await supabase
                .from("profiles")
                .update(phoneUpdate)
                .eq("id", value: memberId.uuidString)
                .execute()
            
            // 2) تفعيل العضو مباشرة بعد إضافة الرقم
            let profileResponse: [FamilyMember] = try await supabase
                .from("profiles")
                .select()
                .eq("id", value: memberId.uuidString)
                .limit(1)
                .execute()
                .value
            
            if let profile = profileResponse.first {
                var activationPayload: [String: AnyEncodable] = [
                    "status": AnyEncodable("active")
                ]
                
                if profile.role == .pending {
                    activationPayload["role"] = AnyEncodable("member")
                }
                
                try await supabase
                    .from("profiles")
                    .update(activationPayload)
                    .eq("id", value: memberId.uuidString)
                    .execute()
                
                // 3) اعتماد أي طلب انضمام معلق لنفس العضو
                _ = try? await supabase
                    .from("admin_requests")
                    .update(["status": AnyEncodable(ApprovalStatus.approved.rawValue)])
                    .eq("member_id", value: memberId.uuidString)
                    .eq("request_type", value: RequestType.joinRequest.rawValue)
                    .eq("status", value: ApprovalStatus.pending.rawValue)
                    .execute()
            }

            await fetchSingleMember(id: memberId)

            // إشعار المدراء بتغيير رقم الهاتف مع التفاصيل (يُتخطّى لو silent=true)
            if !silent {
                await notifyAdminsOfMemberEdit(
                    memberId: memberId,
                    kind: NotificationKind.adminEditPhone.rawValue,
                    title: L10n.t("تعديل رقم الهاتف", "Phone Update"),
                    body: adminEditBody(verb: L10n.t("تم تعديل رقم الهاتف", "Phone number updated"), memberId: memberId),
                    changes: [
                        .init(field: "phone_number", before: oldPhone, after: normalizedPhone)
                    ]
                )
            }

            Log.info("تم تحديث الهاتف وتفعيل العضو للدخول المباشر")
        } catch {
            Log.error("خطأ تحديث الهاتف: \(error.localizedDescription)")
        }
        self.isLoading = false
    }

    // MARK: - Clear Member Phone

    func clearMemberPhone(memberId: UUID) async {
        self.isLoading = true
        do {
            // استدعاء edge function لحذف الرقم + auth user بالكامل
            // هذا يضمن فك ارتباط الرقم نهائياً من العضو
            try await supabase.functions.invoke(
                "admin-unlink-phone",
                options: .init(body: ["memberId": memberId.uuidString.lowercased()])
            )

            await fetchSingleMember(id: memberId)
            Log.info("تم حذف رقم الهاتف وفك ارتباط حساب المصادقة بالكامل")
        } catch {
            Log.error("خطأ حذف الهاتف: \(error.localizedDescription)")
            // fallback: محاولة التنظيف المحلي في حالة فشل الـ edge function
            do {
                var fallbackUpdate: [String: AnyEncodable] = [
                    "phone_number": AnyEncodable(String?.none),
                    "status": AnyEncodable("pending")
                ]
                fallbackUpdate.merge(adminAuditFields(for: memberId)) { _, new in new }

                try await supabase
                    .from("profiles")
                    .update(fallbackUpdate)
                    .eq("id", value: memberId.uuidString)
                    .execute()
                
                _ = try? await supabase
                    .from("device_tokens")
                    .delete()
                    .eq("user_id", value: memberId.uuidString)
                    .execute()

                await fetchSingleMember(id: memberId)
                Log.info("تم حذف رقم الهاتف محلياً (بدون حذف auth user)")
            } catch {
                Log.error("فشل التنظيف المحلي أيضاً: \(error.localizedDescription)")
            }
        }
        self.isLoading = false
    }

    // MARK: - Update Member Gender

    // MARK: - Update Member Email

    /// تحديث إيميل العضو — يستخدمه المستخدم نفسه من EditProfileView
    /// nil يعني حذف الإيميل
    func updateMemberEmail(memberId: UUID, email: String?) async {
        guard NetworkMonitor.shared.requireOnline() else { return }
        self.isLoading = true

        var emailUpdate: [String: AnyEncodable] = [
            "email": AnyEncodable(email)
        ]
        emailUpdate.merge(adminAuditFields(for: memberId)) { _, new in new }

        do {
            try await supabase
                .from("profiles")
                .update(emailUpdate)
                .eq("id", value: memberId.uuidString)
                .execute()

            await fetchSingleMember(id: memberId)
            Log.info("تم تحديث الإيميل")
        } catch {
            Log.error("خطأ تحديث الإيميل: \(error.localizedDescription)")
        }
        self.isLoading = false
    }

    func updateMemberGender(memberId: UUID, gender: String, silent: Bool = false) async {
        guard NetworkMonitor.shared.requireOnline() else { return }
        self.isLoading = true
        let oldGender = _memberById[memberId]?.gender

        var genderUpdate: [String: AnyEncodable] = [
            "gender": AnyEncodable(gender)
        ]
        genderUpdate.merge(adminAuditFields(for: memberId)) { _, new in new }

        do {
            try await supabase
                .from("profiles")
                .update(genderUpdate)
                .eq("id", value: memberId.uuidString)
                .execute()

            await fetchSingleMember(id: memberId)

            if !silent {
                await notifyAdminsOfMemberEdit(
                    memberId: memberId,
                    kind: NotificationKind.adminEdit.rawValue,
                    title: L10n.t("تعديل الجنس", "Gender Update"),
                    body: adminEditBody(verb: L10n.t("تم تعديل الجنس", "Gender updated"), memberId: memberId),
                    changes: [
                        .init(field: "gender", before: oldGender, after: gender)
                    ]
                )
            }

            Log.info("تم تحديث الجنس")
        } catch {
            Log.error("خطأ تحديث الجنس: \(error.localizedDescription)")
        }
        self.isLoading = false
    }

    // MARK: - Update Member Birth Date (simple string)

    func updateMemberBirthDate(memberId: UUID, birthDate: String) async {
        self.isLoading = true
        // التقط القيمة القديمة قبل التحديث
        let oldBirth = _memberById[memberId]?.birthDate

        var birthUpdate: [String: AnyEncodable] = [
            "birth_date": AnyEncodable(birthDate)
        ]
        birthUpdate.merge(adminAuditFields(for: memberId)) { _, new in new }

        do {
            try await supabase
                .from("profiles")
                .update(birthUpdate)
                .eq("id", value: memberId.uuidString)
                .execute()

            await fetchSingleMember(id: memberId)

            await notifyAdminsOfMemberEdit(
                memberId: memberId,
                kind: NotificationKind.adminEditDates.rawValue,
                title: L10n.t("تعديل تاريخ الميلاد", "Birth Date Update"),
                body: adminEditBody(verb: L10n.t("تم تعديل تاريخ الميلاد", "Birth date updated"), memberId: memberId),
                changes: [
                    .init(field: "birth_date", before: oldBirth, after: birthDate)
                ]
            )

            Log.info("تم تحديث تاريخ الميلاد")
        } catch {
            Log.error("خطأ تحديث تاريخ الميلاد: \(error.localizedDescription)")
        }
        self.isLoading = false
    }

    // MARK: - Update Member Father
    
    func updateMemberFather(memberId: UUID, fatherId: UUID?, silent: Bool = false) async {
        guard NetworkMonitor.shared.requireOnline() else { return }
        self.isLoading = true
        // التقط الأب القديم قبل التحديث (نستخدم اسمه لا UUID للعرض)
        let oldFatherName = _memberById[memberId]?.fatherId.flatMap { _memberById[$0]?.firstName }
        let newFatherName = fatherId.flatMap { _memberById[$0]?.firstName }

        // أعد بناء full_name للعضو نفسه — تغيير الأب يغيّر السلسلة:
        //   member.full_name = member.first_name + ' ' + new_father.full_name
        // (لو null/جذر شجرة → full_name = first_name فقط)
        let memberFirstName = _memberById[memberId]?.firstName ?? ""
        let newFatherFullName: String? = fatherId.flatMap { _memberById[$0]?.fullName }
        let rebuiltFullName: String = {
            let f = memberFirstName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let parentName = newFatherFullName else { return f }
            return f.isEmpty ? parentName : "\(f) \(parentName)"
        }()

        do {
            // نرسل الـ UUID كـ String، وإذا كان nil نرسل NULL للسيرفر
            // + نرسل full_name الجديد لتُفعّل trigger الـcascade على الذرّية
            var updateData: [String: AnyEncodable] = [
                "father_id": AnyEncodable(fatherId?.uuidString),
                "full_name": AnyEncodable(rebuiltFullName)
            ]
            updateData.merge(adminAuditFields(for: memberId)) { _, new in new }

            try await supabase
                .from("profiles")
                .update(updateData)
                .eq("id", value: memberId.uuidString)
                .execute()

            // الـtrigger السيرفري cascadeّت الذرّية. نجلب البيانات الكاملة المحدّثة.
            await fetchAllMembers(force: true)

            if !silent {
                await notifyAdminsOfMemberEdit(
                    memberId: memberId,
                    kind: NotificationKind.adminEditFather.rawValue,
                    title: L10n.t("تعديل ولي الأمر", "Father Update"),
                    body: adminEditBody(verb: L10n.t("تم تعديل ولي الأمر", "Father reference updated"), memberId: memberId),
                    changes: [
                        .init(field: "father_id", before: oldFatherName, after: newFatherName)
                    ]
                )
            }

            Log.info("تم تحديث ربط الأب + إعادة بناء full_name → cascade للذرّية")
        } catch {
            Log.error("خطأ في ربط الأب: \(error.localizedDescription)")
        }
        self.isLoading = false
    }
    
    // MARK: - Update Member Health And Birth
    
    func updateMemberHealthAndBirth(
        memberId: UUID,
        birthDate: Date?,    // أصبح اختيارياً ليدعم "Not Available"
        isDeceased: Bool,
        deathDate: Date?     // أصبح اختيارياً ليدعم "Not Available"
    ) async {
        guard NetworkMonitor.shared.requireOnline() else { return }
        self.isLoading = true

        // 1. تنسيق التواريخ
        let birthDateString = birthDate.map { DateHelper.format($0) }
        let deathDateString = isDeceased ? deathDate.map { DateHelper.format($0) } : nil
        
        // 2. تجهيز البيانات للإرسال
        // نستخدم Optional<String>.none لإرسال NULL لقاعدة البيانات عند عدم توفر التاريخ
        var updateData: [String: AnyEncodable] = [
            "birth_date": AnyEncodable(birthDateString ?? Optional<String>.none),
            "is_deceased": AnyEncodable(isDeceased)
        ]
        
        // إضافة تاريخ الوفاة بناءً على حالة الوفاة وتوفر التاريخ
        if isDeceased {
            updateData["death_date"] = AnyEncodable(deathDateString ?? Optional<String>.none)
        } else {
            updateData["death_date"] = AnyEncodable(Optional<String>.none)
        }

        // تتبع المدير إذا كان يعدل بيانات عضو آخر
        updateData.merge(adminAuditFields(for: memberId)) { _, new in new }

        do {
            // 3. التحديث في قاعدة بيانات Supabase
            try await supabase
                .from("profiles")
                .update(updateData)
                .eq("id", value: memberId.uuidString)
                .execute()
            
            // 4. تحديث القائمة المحلية فوراً
            await fetchSingleMember(id: memberId)
            Log.info("تم تحديث البيانات بنجاح (مع دعم التواريخ المفقودة)")
            
        } catch {
            Log.error("خطأ في تحديث البيانات: \(error.localizedDescription)")
        }
        
        self.isLoading = false
    }
    
    // MARK: - Update Child Data
    
    @discardableResult
    func updateChildData(
        member: FamilyMember,
        firstName: String,
        phoneNumber: String,
        birthDate: String?,
        isDeceased: Bool,
        deathDate: String?,
        gender: String?
    ) async -> Bool {
        self.isLoading = true

        let safeFirstName = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalFullName = member.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let normalizedPhone = KuwaitPhone.normalizeForStorageFromInput(phoneNumber)
        let storedPhone = normalizedPhone ?? Optional<String>.none
        
        var payload: [String: AnyEncodable] = [
            "first_name": AnyEncodable(safeFirstName),
            "full_name": AnyEncodable(finalFullName),
            "phone_number": AnyEncodable(storedPhone),
            "birth_date": AnyEncodable(birthDate ?? Optional<String>.none),
            "is_deceased": AnyEncodable(isDeceased)
        ]

        if isDeceased {
            payload["death_date"] = AnyEncodable(deathDate ?? Optional<String>.none)
        } else {
            payload["death_date"] = AnyEncodable(Optional<String>.none)
        }

        // تتبع المدير إذا كان يعدل بيانات عضو آخر
        payload.merge(adminAuditFields(for: member.id)) { _, new in new }

        do {
            try await supabase
                .from("profiles")
                .update(payload)
                .eq("id", value: member.id.uuidString)
                .execute()
        } catch {
            Log.error("خطأ تعديل بيانات الابن: \(error.localizedDescription)")
            self.isLoading = false
            return false
        }

        // تحديث الجنس بشكل منفصل (العمود قد لا يكون في schema cache)
        if let gender, !gender.isEmpty {
            var genderPayload: [String: AnyEncodable] = ["gender": AnyEncodable(gender)]
            genderPayload.merge(adminAuditFields(for: member.id)) { _, new in new }

            do {
                try await supabase
                    .from("profiles")
                    .update(genderPayload)
                    .eq("id", value: member.id.uuidString)
                    .execute()
            } catch {
                Log.warning("عمود gender غير متوفر: \(error.localizedDescription)")
            }
        }

        await fetchSingleMember(id: member.id)
        if let fatherId = member.fatherId {
            await fetchChildren(for: fatherId)
        }

        self.isLoading = false
        return true
    }

    // MARK: - Bulk Gender Update
    /// تحديث الجنس لمجموعة أعضاء دفعة واحدة
    func bulkUpdateGender(memberIds: Set<UUID>, gender: String) async -> Int {
        self.isLoading = true
        var successCount = 0

        for id in memberIds {
            var bulkUpdate: [String: AnyEncodable] = ["gender": AnyEncodable(gender)]
            bulkUpdate.merge(adminAuditFields(for: id)) { _, new in new }

            do {
                try await supabase
                    .from("profiles")
                    .update(bulkUpdate)
                    .eq("id", value: id.uuidString)
                    .execute()
                successCount += 1
            } catch {
                Log.error("فشل تحديث جنس العضو \(id): \(error.localizedDescription)")
            }
        }

        await fetchAllMembers(force: true)
        self.isLoading = false
        Log.info("تم تحديث الجنس لـ \(successCount)/\(memberIds.count) عضو")
        return successCount
    }
}
