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
        didSet { _memberById = Dictionary(uniqueKeysWithValues: allMembers.map { ($0.id, $0) }) }
    }
    /// O(1) member lookup by ID — use instead of allMembers.first(where:)
    private(set) var _memberById: [UUID: FamilyMember] = [:]
    func member(byId id: UUID) -> FamilyMember? { _memberById[id] }
    
    @Published var currentMemberChildren: [FamilyMember] = []
    @Published var activePath: [UUID] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    /// يزداد عند كل تحديث للأعضاء (حذف، تعديل، إضافة) لإعادة بناء الشجرة
    @Published var membersVersion: Int = 0

    /// صور المعرض المعلقة (للإدارة)
    @Published var pendingGalleryPhotos: [MemberGalleryPhoto] = []
    /// آخر الصور المعتمدة (للرئيسية)
    @Published var approvedGalleryPhotos: [MemberGalleryPhoto] = []
    
    // Fetch throttle timestamp
    private var lastMembersFetchDate: Date?
    
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
    
    func getSafeMemberName(for memberId: UUID) -> String {
        return memberId.uuidString
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

    // MARK: - Fetch Members
    
    func fetchAllMembers(force: Bool = false) async {
        // تجنب إعادة التحميل خلال 15 ثانية إلا إذا force
        if !force, let last = lastMembersFetchDate, Date().timeIntervalSince(last) < 15, !allMembers.isEmpty {
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
            self.lastMembersFetchDate = Date()
            self.membersVersion += 1

            // تحديث currentUser إذا تغيرت بياناته (مثلاً: تغيير الاسم من الإدارة)
            if let userId = currentUser?.id,
               let updatedUser = members.first(where: { $0.id == userId }),
               updatedUser != currentUser {
                authVM?.currentUser = updatedUser
                Log.info("[Members] تم تحديث بيانات المستخدم الحالي من الشجرة")
            }
        } catch {
            Log.error("خطأ برمجياً في الشجرة: \(error)")
        }
    }
    
    func fetchChildren(for fatherId: UUID) async {
        do {
            let response: [FamilyMember] = try await supabase.from("profiles")
                .select()
                .eq("father_id", value: fatherId)
                .order("sort_order", ascending: true)
                .execute()
                .value
            
            self.currentMemberChildren = response
        } catch {
            Log.error("خطأ في جلب الأبناء: \(error)")
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
        phoneNumber: String?
    ) async -> Bool {
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
            await fetchAllMembers(force: true)
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
                let requestData: [String: AnyEncodable] = [
                    "member_id": AnyEncodable(fatherId.uuidString),
                    "requester_id": AnyEncodable(requester.uuidString),
                    "request_type": AnyEncodable("child_add"),
                    "new_value": AnyEncodable(newId.uuidString),
                    "status": AnyEncodable("pending"),
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
                            "طلب إضافة ابن: \(firstNameOnly) لـ: \(father.fullName)",
                            "Child add request: \(firstNameOnly) to: \(father.fullName)"
                        ),
                        kind: "child_add"
                    )
                } catch {
                    Log.warning("لم يتم إدراج طلب child_add في admin_requests: \(error.localizedDescription)")
                }
            }
            
            // تحديث البيانات فوراً
            await fetchAllMembers(force: true)
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
    
    // رفع صورة العضو
    func uploadAvatar(image: UIImage, for memberId: UUID) async {
        self.isLoading = true
        
        // 1. ضغط الصورة وتحويلها لبيانات
        guard let imageData = image.jpegData(compressionQuality: 0.5) else {
            self.isLoading = false
            return
        }
        
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
            await fetchAllMembers(force: true)
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
            }

        } catch {
            Log.error("خطأ في الرفع أو الرابط: \(error.localizedDescription)")
        }
        self.isLoading = false
    }
    
    func deleteAvatar(for memberId: UUID) async {
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
            await fetchAllMembers(force: true)
            if memberId == currentUser?.id {
                await authVM?.checkUserProfile()
            }

            Log.info("تم حذف رابط الصورة بنجاح")
            
        } catch {
            Log.error("خطأ في حذف الصورة: \(error.localizedDescription)")
        }
        self.isLoading = false
    }
    
    // MARK: - صورة الغلاف (Cover) منفصلة عن الصورة الشخصية (Avatar)
    
    func uploadCover(image: UIImage, for memberId: UUID) async {
        self.isLoading = true
        
        guard let imageData = image.jpegData(compressionQuality: 0.5) else {
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
            
            await fetchAllMembers(force: true)
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
            
            await fetchAllMembers(force: true)
            if memberId == currentUser?.id {
                await authVM?.checkUserProfile()
            }
            
            Log.info("تم حذف صورة الغلاف بنجاح")
            
        } catch {
            Log.error("خطأ في حذف صورة الغلاف: \(error.localizedDescription)")
        }
        self.isLoading = false
    }
    
    // MARK: - صورة المعرض في تفاصيل العضو (منفصلة عن صورة البروفايل)
    
    func uploadMemberGalleryPhoto(image: UIImage, for memberId: UUID) async -> String? {
        self.isLoading = true
        
        guard let imageData = image.jpegData(compressionQuality: 0.55) else {
            self.isLoading = false
            return nil
        }
        
        let safeName = getSafeMemberName(for: memberId)
        let filePath = "member_photos/\(safeName).jpg"
        
        do {
            try await supabase.storage
                .from("gallery")
                .upload(
                    filePath,
                    data: imageData,
                    options: FileOptions(contentType: "image/jpeg", upsert: true)
                )
            
            let photoTimestamp = Int(Date().timeIntervalSince1970)
            let publicURL = "\(try supabase.storage.from("gallery").getPublicURL(path: filePath).absoluteString)?v=\(photoTimestamp)"
            
            try await supabase
                .from("profiles")
                .update(["photo_url": AnyEncodable(publicURL)])
                .eq("id", value: memberId.uuidString)
                .execute()
            
            await fetchAllMembers(force: true)
            if memberId == currentUser?.id {
                await authVM?.checkUserProfile()
            }
            
            self.isLoading = false
            return publicURL
        } catch {
            Log.error("خطأ رفع صورة المعرض: \(error.localizedDescription)")
            self.isLoading = false
            return nil
        }
    }
    
    func deleteMemberGalleryPhoto(for memberId: UUID) async -> Bool {
        guard memberId == currentUser?.id || canModerate else {
            Log.warning("[AUTH] Unauthorized deleteMemberGalleryPhoto attempt for \(memberId)")
            return false
        }
        self.isLoading = true
        let safeName = getSafeMemberName(for: memberId)
        
        let photoURL = _memberById[memberId]?.photoURL ?? (currentUser?.id == memberId ? currentUser?.photoURL : nil)
        var pathsToRemove: [String] = ["member_photos/\(memberId.uuidString).jpg", "member_photos/\(safeName).jpg"]
        
        if let photoURL, let parsedPath = storagePath(fromPublicURL: photoURL, bucket: "gallery"), !pathsToRemove.contains(parsedPath) {
            pathsToRemove.append(parsedPath)
        }
        
        do {
            _ = try? await supabase.storage
                .from("gallery")
                .remove(paths: pathsToRemove)
            
            try await supabase
                .from("profiles")
                .update(["photo_url": AnyEncodable(Optional<String>.none)])
                .eq("id", value: memberId.uuidString)
                .execute()
            
            await fetchAllMembers(force: true)
            if memberId == currentUser?.id {
                await authVM?.checkUserProfile()
            }
            
            self.isLoading = false
            return true
        } catch {
            Log.error("خطأ حذف صورة المعرض: \(error.localizedDescription)")
            self.isLoading = false
            return false
        }
    }
    
    func fetchMemberGalleryPhotos(for memberId: UUID) async -> [MemberGalleryPhoto] {
        do {
            let photos: [MemberGalleryPhoto] = try await supabase
                .from("member_gallery_photos")
                .select()
                .eq("member_id", value: memberId.uuidString)
                .order("created_at", ascending: false)
                .execute()
                .value
            return photos
        } catch {
            Log.error("خطأ جلب صور المعرض: \(error.localizedDescription)")
            return []
        }
    }
    
    func fetchAllGalleryPhotos() async -> [MemberGalleryPhoto] {
        do {
            let photos: [MemberGalleryPhoto] = try await supabase
                .from("member_gallery_photos")
                .select()
                .order("created_at", ascending: false)
                .limit(10000)
                .execute()
                .value
            return photos
        } catch {
            Log.error("خطأ جلب كل صور المعرض: \(error.localizedDescription)")
            return []
        }
    }
    
    /// جلب آخر الصور المعتمدة (للرئيسية)
    func fetchApprovedGalleryPhotos(limit: Int = 10) async {
        do {
            let photos: [MemberGalleryPhoto] = try await supabase
                .from("member_gallery_photos")
                .select()
                .eq("approval_status", value: "approved")
                .order("created_at", ascending: false)
                .limit(limit)
                .execute()
                .value
            self.approvedGalleryPhotos = photos
        } catch {
            Log.error("خطأ جلب الصور المعتمدة: \(error.localizedDescription)")
        }
    }

    /// جلب الصور المعلقة (للإدارة)
    func fetchPendingGalleryPhotos() async {
        do {
            let photos: [MemberGalleryPhoto] = try await supabase
                .from("member_gallery_photos")
                .select()
                .eq("approval_status", value: "pending")
                .order("created_at", ascending: false)
                .execute()
                .value
            self.pendingGalleryPhotos = photos
        } catch {
            Log.error("خطأ جلب الصور المعلقة: \(error.localizedDescription)")
        }
    }

    /// موافقة على صورة معلقة
    func approveGalleryPhoto(photoId: UUID) async {
        do {
            try await supabase
                .from("member_gallery_photos")
                .update(["approval_status": AnyEncodable("approved")])
                .eq("id", value: photoId.uuidString)
                .execute()
            withAnimation { pendingGalleryPhotos.removeAll { $0.id == photoId } }
            await fetchApprovedGalleryPhotos()
            Log.info("تمت الموافقة على الصورة: \(photoId)")
        } catch {
            Log.error("خطأ الموافقة على الصورة: \(error.localizedDescription)")
        }
    }

    /// رفض صورة معلقة (حذف)
    func rejectGalleryPhoto(photoId: UUID, photoURL: String) async {
        guard authVM?.isAdmin == true else { Log.warning("رفض الصورة: للمدير فقط"); return }
        do {
            // حذف من Storage
            if let storagePath = storagePath(fromPublicURL: photoURL, bucket: "gallery") {
                try await supabase.storage.from("gallery").remove(paths: [storagePath])
            }
            // حذف من DB
            try await supabase
                .from("member_gallery_photos")
                .delete()
                .eq("id", value: photoId.uuidString)
                .execute()
            withAnimation { pendingGalleryPhotos.removeAll { $0.id == photoId } }
            Log.info("تم رفض وحذف الصورة: \(photoId)")
        } catch {
            Log.error("خطأ رفض الصورة: \(error.localizedDescription)")
        }
    }

    func uploadMemberGalleryPhotoMulti(image: UIImage, for memberId: UUID, caption: String? = nil) async -> MemberGalleryPhoto? {
        self.isLoading = true
        
        guard let imageData = image.jpegData(compressionQuality: 0.6) else {
            self.isLoading = false
            return nil
        }
        
        let photoId = UUID()
        let safeName = getSafeMemberName(for: memberId)
        let filePath = "member_gallery/\(safeName)/\(photoId.uuidString).jpg"
        
        do {
            try await supabase.storage
                .from("gallery")
                .upload(
                    filePath,
                    data: imageData,
                    options: FileOptions(contentType: "image/jpeg", upsert: true)
                )
            
            let publicURL = try supabase.storage
                .from("gallery")
                .getPublicURL(path: filePath)
                .absoluteString
            
            // المدير/المشرف → approved مباشرة، العضو → pending
            let canModerate = authVM?.canModerate ?? false
            let approvalStatus = canModerate ? "approved" : "pending"

            var payload: [String: AnyEncodable] = [
                "id": AnyEncodable(photoId.uuidString),
                "member_id": AnyEncodable(memberId.uuidString),
                "photo_url": AnyEncodable(publicURL),
                "created_by": AnyEncodable(currentUser?.id.uuidString),
                "approval_status": AnyEncodable(approvalStatus)
            ]
            if let caption, !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                payload["caption"] = AnyEncodable(caption)
            }

            let inserted: [MemberGalleryPhoto] = try await supabase
                .from("member_gallery_photos")
                .insert(payload)
                .select()
                .execute()
                .value

            // إشعار المدراء فقط لو العضو أضاف (تحتاج موافقة)
            if !canModerate {
                await notificationVM?.notifyAdminsWithPush(
                    title: L10n.t("صورة جديدة تحتاج موافقة", "New Photo Needs Approval"),
                    body: L10n.t(
                        "تم إضافة صورة جديدة في المعرض تحتاج موافقتكم",
                        "A new gallery photo needs your approval"
                    ),
                    kind: "gallery_pending"
                )
            }
            
            self.isLoading = false
            return inserted.first
        } catch {
            Log.error("خطأ رفع صورة المعرض المتعدد: \(error.localizedDescription)")
            self.isLoading = false
            return nil
        }
    }
    
    func updateGalleryPhotoCaption(photoId: UUID, caption: String?) async -> Bool {
        do {
            let payload: [String: AnyEncodable] = [
                "caption": AnyEncodable(caption)
            ]
            try await supabase
                .from("member_gallery_photos")
                .update(payload)
                .eq("id", value: photoId.uuidString)
                .execute()
            return true
        } catch {
            Log.error("خطأ تحديث تعليق الصورة: \(error.localizedDescription)")
            return false
        }
    }

    func deleteMemberGalleryPhotoMulti(photoId: UUID, photoURL: String) async -> Bool {
        guard canModerate else {
            Log.warning("[AUTH] Unauthorized gallery photo delete attempt")
            return false
        }
        self.isLoading = true
        Log.info("بدء حذف صورة المعرض: id=\(photoId)")
        
        do {
            if let path = storagePath(fromPublicURL: photoURL, bucket: "gallery") {
                Log.info("حذف من التخزين: \(path)")
                _ = try? await supabase.storage
                    .from("gallery")
                    .remove(paths: [path])
            } else {
                Log.warning("لم يتم العثور على مسار التخزين للصورة")
            }
            
            try await supabase
                .from("member_gallery_photos")
                .delete()
                .eq("id", value: photoId.uuidString)
                .execute()
            
            Log.info("تم حذف سجل الصورة من قاعدة البيانات")
            self.isLoading = false
            return true
        } catch {
            Log.error("خطأ حذف صورة المعرض المتعدد: \(error)")
            self.isLoading = false
            return false
        }
    }
    
    // MARK: - Update Member Data
    
    @discardableResult
    func updateMemberData(
        memberId: UUID,
        fullName: String,
        phoneNumber: String,
        birthDate: Date,
        isMarried: Bool,
        isDeceased: Bool,
        deathDate: Date?,
        isPhoneHidden: Bool
    ) async -> Bool {
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

        // إعداد منسق التاريخ (Locale لضمان أرقام إنجليزية)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        // 2. تجهيز مصفوفة البيانات وإضافة حقل الهاتف ✅
        let normalizedPhone = KuwaitPhone.normalizeForStorageFromInput(phoneNumber) ?? ""
        var updateData: [String: AnyEncodable] = [
            "full_name": AnyEncodable(fullName),
            "first_name": AnyEncodable(firstName),
            "phone_number": AnyEncodable(normalizedPhone),
            "birth_date": AnyEncodable(formatter.string(from: birthDate)),
            "is_married": AnyEncodable(isMarried),
            "is_deceased": AnyEncodable(isDeceased),
            "is_phone_hidden": AnyEncodable(isPhoneHidden)
        ]

        if isDeceased, let dDate = deathDate {
            updateData["death_date"] = AnyEncodable(formatter.string(from: dDate))
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

            // 4. تحديث البيانات محلياً
            await fetchAllMembers(force: true)

            // إذا كان المستخدم يحدّث ملفه الشخصي "هو"
            if memberId == currentUser?.id {
                await authVM?.checkUserProfile()
            }

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
        do {
            try await supabase
                .from("profiles")
                .update(["bio_json": AnyEncodable(bio)])
                .eq("id", value: memberId.uuidString)
                .execute()

            await fetchAllMembers(force: true)
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
            await fetchAllMembers(force: true)
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
            await fetchAllMembers(force: true)
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
            await fetchAllMembers(force: true)
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
    
    func updateMemberName(memberId: UUID, fullName: String) async {
        self.isLoading = true
        let firstName = fullName.components(separatedBy: " ").first ?? fullName

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
            }

            Log.info("تم تحديث اسم العضو بنجاح")
        } catch {
            Log.error("فشل تحديث اسم العضو: \(error.localizedDescription)")
        }

        self.isLoading = false
    }
    
    // MARK: - Delete Member (Admin only)

    /// حذف عضو نهائياً من قاعدة البيانات (للمالك فقط)
    func deleteMember(memberId: UUID) async -> Bool {
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
            // حذف الإشعارات المرتبطة
            _ = try? await supabase.from("notifications")
                .delete()
                .eq("target_member_id", value: memberId.uuidString)
                .execute()

            // حذف device tokens
            _ = try? await supabase.from("device_tokens")
                .delete()
                .eq("member_id", value: memberId.uuidString)
                .execute()

            // حذف صور المعرض
            _ = try? await supabase.from("member_gallery_photos")
                .delete()
                .eq("member_id", value: memberId.uuidString)
                .execute()

            // حذف العضو من profiles
            try await supabase.from("profiles")
                .delete()
                .eq("id", value: memberId.uuidString)
                .execute()

            await fetchAllMembers(force: true)
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
            
            // 2. تحديث البيانات محلياً لكي تظهر التغييرات فوراً في الشجرة
            await fetchAllMembers(force: true)
            
            let memberName = _memberById[memberId]?.firstName ?? "عضو"
            let roleName = newRole == .admin ? "مدير" : (newRole == .supervisor ? "مشرف" : "عضو")
            
            // 3. إشعار المدراء بتغيير الرتبة (push + داخلي)
            await notificationVM?.notifyAdminsWithPush(
                title: L10n.t("تغيير صلاحيات", "Role Changed"),
                body: L10n.t(
                    "تم تغيير صلاحيات \(memberName) إلى: \(roleName)",
                    "\(memberName)'s role was changed to: \(roleName)"
                ),
                kind: "role_change"
            )

            // 4. إشعار العضو نفسه بتغيير رتبته
            if authVM?.notificationsFeatureAvailable == true {
                let personalPayload: [String: AnyEncodable] = [
                    "target_member_id": AnyEncodable(memberId.uuidString),
                    "title": AnyEncodable(L10n.t("تغيير مستوى الحساب", "Account Level Changed")),
                    "body": AnyEncodable(L10n.t(
                        "مستوى حسابك الآن: \(roleName).",
                        "Your account level is now: \(roleName)."
                    )),
                    "kind": AnyEncodable("role_change"),
                    "created_by": AnyEncodable(currentUser?.id.uuidString)
                ]
                do {
                    try await supabase.from("notifications").insert(personalPayload).execute()
                    await notificationVM?.sendPushToMembers(
                        title: L10n.t("تم تغيير مستوى حسابك", "Your Account Level Changed"),
                        body: L10n.t(
                            "مستوى حسابك الآن: \(roleName)",
                            "Your account level is now: \(roleName)"
                        ),
                        kind: "role_change",
                        targetMemberIds: [memberId]
                    )
                } catch {
                    Log.warning("تعذر إرسال إشعار تغيير الرتبة للعضو: \(error.localizedDescription)")
                }
            }
            
            Log.info("تم تحديث رتبة العضو بنجاح إلى: \(newRole.rawValue)")
            
        } catch {
            Log.error("فشل تحديث الرتبة: \(error.localizedDescription)")
        }
        
        self.isLoading = false
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
        await fetchAllMembers(force: true)
        if fatherId == self.currentUser?.id {
            await fetchChildren(for: fatherId)
        }
        self.isLoading = false
    }
    
    // MARK: - Update Member Phone
    
    func updateMemberPhone(memberId: UUID, newPhone: String) async {
        await updateMemberPhone(memberId: memberId, country: KuwaitPhone.defaultCountry, localPhone: newPhone)
    }

    func updateMemberPhone(memberId: UUID, country: KuwaitPhone.Country, localPhone: String) async {
        self.isLoading = true
        guard let normalizedPhone = KuwaitPhone.normalizedForStorage(country: country, rawLocalDigits: localPhone) else {
            Log.error("رقم الهاتف غير صالح للدولة المختارة.")
            self.isLoading = false
            return
        }
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
                    .update(["status": AnyEncodable("approved")])
                    .eq("member_id", value: memberId.uuidString)
                    .eq("request_type", value: "join_request")
                    .eq("status", value: "pending")
                    .execute()
            }
            
            await fetchAllMembers(force: true) // تحديث البيانات فوراً ✅
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
            
            await fetchAllMembers(force: true)
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
                
                await fetchAllMembers(force: true)
                Log.info("تم حذف رقم الهاتف محلياً (بدون حذف auth user)")
            } catch {
                Log.error("فشل التنظيف المحلي أيضاً: \(error.localizedDescription)")
            }
        }
        self.isLoading = false
    }

    // MARK: - Update Member Gender

    func updateMemberGender(memberId: UUID, gender: String) async {
        self.isLoading = true
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

            await fetchAllMembers(force: true)
            Log.info("تم تحديث الجنس")
        } catch {
            Log.error("خطأ تحديث الجنس: \(error.localizedDescription)")
        }
        self.isLoading = false
    }

    // MARK: - Update Member Birth Date (simple string)

    func updateMemberBirthDate(memberId: UUID, birthDate: String) async {
        self.isLoading = true
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

            await fetchAllMembers(force: true)
            Log.info("تم تحديث تاريخ الميلاد")
        } catch {
            Log.error("خطأ تحديث تاريخ الميلاد: \(error.localizedDescription)")
        }
        self.isLoading = false
    }

    // MARK: - Update Member Father
    
    func updateMemberFather(memberId: UUID, fatherId: UUID?) async {
        self.isLoading = true
        do {
            // نرسل الـ UUID كـ String، وإذا كان nil نرسل NULL للسيرفر
            var updateData: [String: AnyEncodable] = [
                "father_id": AnyEncodable(fatherId?.uuidString)
            ]
            updateData.merge(adminAuditFields(for: memberId)) { _, new in new }

            try await supabase
                .from("profiles")
                .update(updateData)
                .eq("id", value: memberId.uuidString)
                .execute()
            
            await fetchAllMembers(force: true)
            Log.info("تم تحديث ربط الأب بنجاح")
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
        self.isLoading = true

        // 1. تنسيق التواريخ
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        
        // تحويل التاريخ لنص فقط إذا كان المشرف قد أدخله، وإلا يبقى nil
        let birthDateString = birthDate.map { formatter.string(from: $0) }
        let deathDateString = isDeceased ? deathDate.map { formatter.string(from: $0) } : nil
        
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
            await fetchAllMembers(force: true)
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

        await fetchAllMembers(force: true)
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
