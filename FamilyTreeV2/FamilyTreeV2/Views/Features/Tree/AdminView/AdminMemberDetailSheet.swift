import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// ════════════════════════════════════════════════════════════════════
// AdminMemberDetailSheet — تصميم جديد كلياً (2026-05-27)
// مبني على Form الأصلي من iOS بدل ScrollView+DSCard المخصّص.
// نفس البنية والعناصر — تصميم native أنظف وضامن لكل الـinteractions.
// ════════════════════════════════════════════════════════════════════
struct AdminMemberDetailSheet: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    @Environment(\.dismiss) var dismiss
    /// لون القسم الذي فُتح منه (الشجرة، الإدارة، حسابي…) — كحلي «الإطار» يتبعه
    @Environment(\.dsSection) private var section
    private var chromeInk: Color { DS.Color.primary.dsChrome(in: section) }

    let member: FamilyMember
    /// false = من «بيانات العضو» في لوحة الإدارة: بطاقة الحساب والحذف هناك (بيت واحد لكل أمر)
    let showsAccount: Bool
    /// «متوفى» من «تحقق من الأحياء» (الدفعة ١٢): نفس السجل وحفظه (`saveAction` — التحديث، سجل الإدارة، إشعار التعديل،
    /// مربّع إعلان الوفاة) مفتوحاً على «التواريخ والحالة» وحدها و«متوفّى» مفعّل؛ تاريخ الوفاة اختياري («بدون تاريخ»)
    let deathOnly: Bool
    /// حالة الوفاة التي فُتح عليها المربّع («إلغاء» بلا تعديل لا يسأل — مثل مربّع الوفاة في شجرة النساء)
    private let startDeceased: Bool

    // MARK: - States
    @State private var selectedPhoneCountry: KuwaitPhone.Country
    @State private var phoneNumber: String
    @State private var selectedFatherId: UUID?
    /// مربّع «السيرة الذاتية» (مربّع عمل)
    @State private var showBioBox = false
    @State private var fullName: String
    /// «الاسم الأول» (طلب المالك ٢٠٢٦-١٠-١٨): يبدأ بالمخزّن، وتعديله يستبدل بادئة الاسم الكامل مباشرة
    /// (PersonName القاعدة ١)، ويُحفظ كما هو في first_name — للأسماء المركّبة مثل «زين العابدين»
    @State private var firstName: String
    /// آخر اسم أول طُبّق على الاسم الكامل — مرجع الاستبدال عند الكتابة حرفاً حرفاً
    @State private var appliedFirstName: String
    private let startFirstName: String
    @State private var familyName: String

    @State private var birthDate: Date
    @State private var hasBirthDate: Bool

    @State private var isDeceased: Bool
    @State private var deathDate: Date
    @State private var hasDeathDate: Bool
    @State private var selectedGender: String

    @State private var localChildren: [FamilyMember] = []
    @State private var editMode: EditMode = .inactive

    @State private var bioStations: [FamilyMember.BioStation] = []

    @State private var localAvatarPreview: UIImage? = nil
    @State private var currentAvatarURL: String?
    @State private var showAddSonSheet = false
    @State private var showFatherPicker = false
    @State private var showDeleteConfirmation = false
    @State private var childToDelete: FamilyMember?
    @State private var childToEdit: FamilyMember?
    @State private var phoneDuplicateWarning: String?
    @State private var showOfflineAlert = false

    @State private var isSaving = false
    @State private var showEmptyNameAlert = false
    @State private var showAvatarUploadError = false

    // «حالة الحساب»: تجميد / حظر الرقم وإلغاؤهما من هنا (طلب المالك ٢٠٢٦-١٠-١٠)
    private enum AccountAction: Identifiable { case activate, freeze, unfreeze, ban, unban; var id: Self { self } }
    @State private var pendingAccountAction: AccountAction?
    @State private var accountBusy: AccountAction?
    /// حالة الحساب هنا — المجمّد قد لا يكون في قائمة الأعضاء المحمّلة، فلا يُقرأ منها
    @State private var accountStatus: FamilyMember.MemberStatus?
    /// له حساب دخول (من `AdminAccountsStore`) — nil قبل وصول القوائم
    @State private var hasLogin: Bool?
    @State private var activeBan: BannedPhone?
    @State private var accountError = false
    /// سبب الفشل إن عُرف (مثل تفعيل حساب بلا أب) — وإلا رسالة الاتصال العامة
    @State private var accountErrorText: String?

    // تغيير الجنس = نقل بين شجرة الرجال وشجرة النساء (`move_child_gender`، طلب المالك ٢٠٢٦-١٠-٢٤)
    /// تأكيد النقل قبل الحفظ
    @State private var showGenderMoveConfirm = false
    /// نُقل إلى «ذكر» على السيرفر — الحفظ العادي يكمل بلا كتابة عمود الجنس
    @State private var genderMoved = false
    /// له حساب في التطبيق (أو دور إداري) — لا يُنقل: النقل يحذف ملفه من شجرة الرجال
    @State private var genderLockedByAccount = false
    /// السجل نُقل لشجرة النساء وتعذّر حفظ الباقي — «حسناً» يغلق المربّع (السجل القديم لم يعد موجوداً)
    @State private var dismissAfterError = false

    // MARK: - تغييرات لم تُحفظ (توصية أبل)
    // ما يُحفظ بزر «حفظ» فقط يُقارن بما فُتح عليه السجل — الصورة والأبناء (إضافة/تعديل/حذف)
    // تُحفظ فوراً فلا تُحسب.

    /// اسم العائلة وتاريخا الميلاد والوفاة كما فُتح السجل («yyyy-MM-dd» أو nil)
    private let startFamilyName: String
    private let startBirthKey: String?
    private let startDeathKey: String?
    /// ترتيب الأبناء كما حُمّل آخر مرة (setupLocalChildren)
    @State private var loadedChildIds: [UUID] = []

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private var hasUnsavedChanges: Bool {
        if fullName != member.fullName || familyName != startFamilyName { return true }
        if PersonName.clean(firstName) != startFirstName { return true }
        let original = KuwaitPhone.detectCountryAndLocal(member.phoneNumber)
        if selectedPhoneCountry.id != original.country.id || phoneNumber != original.localDigits { return true }
        if selectedFatherId != member.fatherId || selectedGender != (member.gender ?? "male") { return true }
        if isDeceased != startDeceased { return true }
        let birthKey = hasBirthDate ? Self.dayFormatter.string(from: birthDate) : nil
        let deathKey = hasDeathDate ? Self.dayFormatter.string(from: deathDate) : nil
        if birthKey != startBirthKey || deathKey != startDeathKey { return true }
        let bioKey: ([FamilyMember.BioStation]) -> String = { list in
            list.map { "\($0.year ?? "")|\($0.title)|\($0.details)" }.joined(separator: ";")
        }
        if bioKey(bioStations) != bioKey(member.bio ?? []) { return true }
        // الترتيب النسبي فقط — حذف ابن (يُحفظ فوراً) لا يُعدّ تغييراً في الترتيب
        let localIds = localChildren.map(\.id)
        let remaining = Set(localIds)
        return localIds != loadedChildIds.filter { remaining.contains($0) }
    }

    /// لا يُعرض حذف المالك ولا حذف سجلك أنت (فحص الثغرات)
    private var canDeleteMember: Bool {
        authVM.canDeleteMembers && member.role != .owner && member.id != authVM.currentUser?.id
    }
    /// رأس الشجرة (المحمدعلي): بلا أب وله ذرّية — اسمه هو العائلة نفسها، فلا
    /// «اسم العائلة» ولا «الأب في الشجرة» (طلب المالك). عضو بلا أب وبلا أبناء
    /// (غير مرتبط) يبقى له ربط الأب.
    private var isFamilyRoot: Bool {
        member.fatherId == nil && memberVM.allMembers.contains { $0.fatherId == member.id }
    }

    private var isMonitorOnly: Bool { authVM.currentUser?.role == .monitor }

    init(member: FamilyMember, showsAccount: Bool = true, deathOnly: Bool = false) {
        self.member = member
        self.showsAccount = showsAccount
        self.deathOnly = deathOnly
        self.startDeceased = deathOnly || (member.isDeceased ?? false)
        self._currentAvatarURL = State(initialValue: member.avatarUrl)
        self._accountStatus = State(initialValue: member.status)
        let detectedPhone = KuwaitPhone.detectCountryAndLocal(member.phoneNumber)
        self._selectedPhoneCountry = State(initialValue: detectedPhone.country)
        self._phoneNumber = State(initialValue: detectedPhone.localDigits)
        self._selectedFatherId = State(initialValue: member.fatherId)
        self._fullName = State(initialValue: member.fullName)
        // المخزّن كما هو؛ سجلّ بلا first_name ← أول وحدة من الاسم الكامل
        let storedFirst = PersonName.clean(member.firstName)
        let startFirst = storedFirst.isEmpty ? PersonName.firstUnit(member.fullName) : storedFirst
        self._firstName = State(initialValue: startFirst)
        self._appliedFirstName = State(initialValue: startFirst)
        self.startFirstName = startFirst
        let nameParts = member.fullName.trimmingCharacters(in: .whitespacesAndNewlines).split(whereSeparator: \.isWhitespace).map(String.init)
        let startFamily = nameParts.count > 1 ? (nameParts.last ?? "") : ""
        self._familyName = State(initialValue: startFamily)
        self.startFamilyName = startFamily

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        // IMPORTANT: لا تحذف هذا — بدونه parsing التواريخ يفشل على الأجهزة العربية
        formatter.locale = Locale(identifier: "en_US_POSIX")

        if let bDateStr = member.birthDate, !bDateStr.isEmpty, let date = formatter.date(from: bDateStr) {
            self._birthDate = State(initialValue: date)
            self._hasBirthDate = State(initialValue: true)
            self.startBirthKey = formatter.string(from: date)
        } else {
            self._birthDate = State(initialValue: Date())
            self._hasBirthDate = State(initialValue: false)
            self.startBirthKey = nil
        }

        self._bioStations = State(initialValue: member.bio ?? [])
        self._selectedGender = State(initialValue: member.gender ?? "male")
        self._isDeceased = State(initialValue: deathOnly || (member.isDeceased ?? false))
        if let dDateStr = member.deathDate, !dDateStr.isEmpty, let date = formatter.date(from: dDateStr) {
            self._deathDate = State(initialValue: date)
            self._hasDeathDate = State(initialValue: true)
            self.startDeathKey = formatter.string(from: date)
        } else {
            self._deathDate = State(initialValue: Date())
            self._hasDeathDate = State(initialValue: false)
            self.startDeathKey = nil
        }
    }

    // MARK: - Body
    var body: some View {
        // نفس هيكل مربّعات الإضافة وحركتها (طلب المالك): رأس متدرّج، أقسام تدخل
        // تباعاً، و«حفظ» / «إلغاء» أسفل المربّع
        DSComposer(
            title: deathOnly ? L10n.t("تسجيل الوفاة", "Record death") : L10n.t("بيانات العضو", "Member details"),
            subtitle: member.displayFullName,
            icon: deathOnly ? "heart.text.square.fill" : "person.badge.shield.checkmark.fill",
            tint: deathOnly || member.isDeceased == true ? DS.Color.textSecondary : DS.Color.actionNavy,
            actionTitle: L10n.t("حفظ", "Save"),
            actionIcon: "checkmark",
            canSubmit: deathOnly || (isPhoneValid && isFirstNameValid),
            isBusy: isSaving,
            hasUnsavedChanges: hasUnsavedChanges,
            onSubmit: saveAction,
            onCancel: { dismiss() }
        ) {
            if deathOnly {
                datesCard.dsStaggerIn(0)
            } else {
                heroSection.dsStaggerIn(0)
                basicsCard.dsStaggerIn(1)
                datesCard.dsStaggerIn(2)
                if !isMonitorOnly { lineageCard.dsStaggerIn(3) }
                bioCard.dsStaggerIn(4)
                if showsAccount && showsAccountCard { accountCard.dsStaggerIn(5) }
                if showsAccount, !isMonitorOnly, canDeleteMember { deleteButton.dsStaggerIn(6) }
            }
        }
            // كل نوافذ التعديل المباشر ألواح بمنتصف الشاشة (طلب المالك)
            // قائمة أعضاء طويلة — مربّع طويل من الأسفل يُغلق بالسحب (توصية أبل)
            .dsTallBox(isPresented: $showFatherPicker) {
                FatherPickerSheet(selectedId: $selectedFatherId, editingMemberId: member.id)
            }
            .dsCenterBox(isPresented: $showBioBox) {
                BioEditCard(
                    initial: bioStations,
                    goesToAdmins: false,
                    remaining: 3,
                    onCancel: { showBioBox = false },
                    onDone: { updated in
                        showBioBox = false
                        bioStations = updated   // يُحفظ مع «حفظ» السجل
                    }
                )
            }
            .fullScreenCover(isPresented: $showAddSonSheet) {
                DSCenterPanel(onBackgroundTap: nil, hugsContent: true) {
                    AddSonByAdminSheet(parent: member)
                }
                .background(ClearPresentationBackground())
            }
            .fullScreenCover(item: $childToEdit) { child in
                DSCenterPanel(onBackgroundTap: nil, hugsContent: true) {
                    AddSonByAdminSheet(parent: member, editingChild: child)
                }
                .background(ClearPresentationBackground())
            }
            .transaction { t in
                // بلا انزلاق من الأسفل — الألواح تظهر في المنتصف
                if showAddSonSheet || childToEdit != nil {
                    t.disablesAnimations = true
                }
            }
            .onAppear { setupLocalChildren() }
            .task {
                await refreshAccount()
                await refreshGenderLock()
            }
            // تأكيد تغيير الجنس — ينقل السجل بين الشجرتين قبل حفظ بقية الحقول
            .dsAlert(L10n.t("تغيير الجنس", "Change gender"), isPresented: $showGenderMoveConfirm) {
                Button(L10n.t("نقل وحفظ", "Move and save")) { performGenderMove() }
                Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { }
            } message: {
                Text(genderMoveMessage)
            }
            // تأكيد التجميد / الحظر وإلغائهما — المربّع الوسطي الموحّد
            .dsAlert(pendingAccountAction.map(accountActionTitle) ?? "",
                     isPresented: Binding(get: { pendingAccountAction != nil },
                                          set: { if !$0 { pendingAccountAction = nil } }),
                     presenting: pendingAccountAction) { action in
                Button(accountActionButton(action),
                       role: action == .freeze || action == .ban ? .destructive : nil) {
                    performAccountAction(action)
                }
                Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { pendingAccountAction = nil }
            } message: { action in
                Text(accountActionMessage(action))
            }
            .dsAlert(L10n.t("تعذّر التنفيذ", "Couldn't Complete"), isPresented: $accountError) {
                Button(L10n.t("حسناً", "OK")) {
                    accountErrorText = nil
                    if dismissAfterError { closeAfterMoveToWomen() }
                }
            } message: {
                Text(accountErrorText ?? L10n.t("تأكد من الاتصال ثم حاول مرة أخرى.", "Check your connection and try again."))
            }
            .onChange(of: showAddSonSheet) { isShowing in
                if !isShowing { setupLocalChildren() }
            }
            .onChange(of: childToEdit) { child in
                if child == nil { setupLocalChildren() }
            }
            .onChange(of: memberVM.membersVersion) { _ in
                setupLocalChildren()
            }
            .dsAlert(
                L10n.t("اسم فارغ", "Empty Name"),
                isPresented: $showEmptyNameAlert
            ) {
                Button(L10n.t("حسناً", "OK")) {}
            } message: {
                Text(L10n.t(
                    "لا يمكن حفظ عضو بدون اسم. اكتب الاسم أولاً.",
                    "Cannot save a member with an empty name. Please enter a name first."
                ))
            }
            .dsAlert(
                L10n.t("تعذر رفع الصورة", "Photo Upload Failed"),
                isPresented: $showAvatarUploadError
            ) {
                Button(L10n.t("حسناً", "OK")) {}
            } message: {
                Text(L10n.t(
                    "تعذر رفع الصورة. تأكد من الاتصال ثم حاول مرة أخرى.",
                    "The photo could not be uploaded. Check your connection and try again."
                ))
            }
            .dsAlert(
                L10n.t("لا يوجد اتصال بالإنترنت", "No Internet Connection"),
                isPresented: $showOfflineAlert
            ) {
                Button(L10n.t("حسناً", "OK")) {}
            } message: {
                Text(L10n.t(
                    "لا يمكن حفظ التعديلات بدون اتصال بالإنترنت. تأكد من الاتصال ثم حاول مجدداً.",
                    "Changes cannot be saved without an internet connection. Check your connection and try again."
                ))
            }
            .dsAlert(L10n.t("حذف العضو نهائياً", "Delete member permanently"), isPresented: $showDeleteConfirmation) {
                Button(L10n.t("حذف", "Delete"), role: .destructive) {
                    Task {
                        guard canDeleteMember else { return }
                        // الإغلاق وإعلان الحذف بعد نجاحه فقط — الفشل (روابط عائلة، صلاحية…) يُعرض والمربّع باقٍ
                        adminRequestVM.errorMessage = nil
                        guard await adminRequestVM.rejectOrDeleteMember(memberId: member.id) else {
                            showDeleteFailure()
                            return
                        }
                        dismiss()
                        NotificationCenter.default.post(name: .memberDeleted, object: member.id)
                    }
                }
                Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { }
            } message: {
                Text(L10n.t(
                    "هل أنت متأكد من حذف \(member.fullName) نهائياً؟ لا يمكن التراجع.",
                    "Permanently delete \(member.fullName)? This cannot be undone."
                ))
            }
            .dsAlert(L10n.t("حذف الابن", "Delete Child"), isPresented: Binding(
                get: { childToDelete != nil },
                set: { if !$0 { childToDelete = nil } }
            )) {
                Button(L10n.t("حذف", "Delete"), role: .destructive) {
                    if let child = childToDelete {
                        let capturedChild = child
                        Task {
                            adminRequestVM.errorMessage = nil
                            let deleted = await adminRequestVM.rejectOrDeleteMember(memberId: capturedChild.id)
                            childToDelete = nil
                            // إشعار «حذف ابن» بعد نجاح الحذف فقط
                            guard deleted else {
                                showDeleteFailure()
                                return
                            }
                            localChildren.removeAll { $0.id == capturedChild.id }
                            let adminName = authVM.currentUser?.firstName ?? "مدير"
                            await memberVM.notificationVM?.notifyAdminsWithPush(
                                title: L10n.t("حذف ابن", "Child Removed"),
                                body: L10n.t(
                                    "\(adminName) حذف «\(capturedChild.firstName)» من أبناء «\(member.fullName)»",
                                    "\(adminName) removed «\(capturedChild.firstName)» from «\(member.fullName)»'s children"
                                ),
                                kind: "admin_edit_child_remove"
                            )
                        }
                    }
                }
                Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { childToDelete = nil }
            } message: {
                if let child = childToDelete {
                    Text(L10n.t("حذف \(child.firstName)؟", "Delete \(child.firstName)?"))
                }
            }
        // حين يُدفع صفحةً (سجل الأعضاء) لا شريط نظام أبيض فوق رأس المربّع الملوّن («أسلوب واحد»
        // ٢٠٢٦-١٠-٠٧) — الرجوع بـ«إلغاء» أسفل المربّع أو السحب من الحافة؛ داخل المربّع الطويل لا أثر له
        .background(DS.Color.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    // MARK: - Hero Section (Avatar + Name + Role)
    private var heroSection: some View {
        VStack(spacing: DS.Spacing.sm) {
            DSProfilePhotoPicker(
                selectedImage: $localAvatarPreview,
                existingURL: currentAvatarURL,
                enableCrop: true,
                cropShape: .circle,
                trailing: nil,
                showDeleteForExisting: currentAvatarURL != nil,
                onDeleteExisting: {
                    Task {
                        await memberVM.deleteAvatar(for: member.id)
                        await MainActor.run { currentAvatarURL = nil }
                        await memberVM.notificationVM?.notifyAdminsWithPush(
                            title: L10n.t("حذف صورة عضو", "Member Photo Removed"),
                            body: L10n.t(
                                "تم حذف صورة: «\(member.fullName)»",
                                "Photo removed for: «\(member.fullName)»"
                            ),
                            kind: "admin_edit_avatar_remove"
                        )
                    }
                },
                useOverlayActionsOnly: true
            )
            .onChange(of: localAvatarPreview) { newImage in
                guard let newImage else { return }
                Task {
                    let uploaded = await memberVM.uploadAvatar(image: newImage, for: member.id)
                    guard uploaded else {
                        // فشل الرفع: رجّع المعاينة للصورة الحالية وأظهر الخطأ
                        await MainActor.run {
                            localAvatarPreview = nil
                            showAvatarUploadError = true
                        }
                        return
                    }
                    if let updated = memberVM.member(byId: member.id) {
                        await MainActor.run { currentAvatarURL = updated.avatarUrl }
                    }
                    let adminName = authVM.currentUser?.firstName ?? "مدير"
                    await memberVM.notificationVM?.notifyAdminsWithPush(
                        title: L10n.t("تحديث صورة عضو", "Member Photo Updated"),
                        body: L10n.t(
                            "تم تحديث صورة: «\(member.fullName)»",
                            "Photo updated: «\(member.fullName)»"
                        ),
                        kind: "admin_edit_avatar"
                    )
                    Log.info("[Admin] \(adminName) عدّل صورة \(member.firstName)")
                }
            }

            VStack(spacing: DS.Spacing.xs) {
                Text(member.displayFullName)
                    .dsFont(.headline)
                    .foregroundColor(DS.Color.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)

                DSRoleBadge(title: member.roleName, color: member.roleColor)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.xs)
    }

    // MARK: - مكوّنات التصميم — مشتركة في DSFormBoxes.swift (طلب المالك)

    private func adminCard<Content: View, Trailing: View>(
        _ title: String,
        icon: String,
        color: Color,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() },
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        DSFormCard(title, icon: icon, color: color, trailing: trailing, content: content)
    }

    /// الاسم الأول موجود والاسم الكامل يبدأ فيه
    private var isFirstNameValid: Bool {
        PersonName.startsWithFirstName(fullName, firstName)
    }

    /// تعديل «الاسم الأول» يستبدل بادئته في «الاسم الكامل» مباشرة (القاعدة ١): الباقي = اسم الأب الكامل
    /// إن كان الاسم ينتهي به (يصلّح سجلاً محفوظاً أوله «زين» فقط)، وإلا ما بعد الاسم الأول السابق.
    private func applyFirstNameToFullName() {
        if firstName.count > 50 { firstName = String(firstName.prefix(50)) }
        let fatherFullName = member.fatherId.flatMap { memberVM.member(byId: $0)?.fullName }
        let updated = PersonName.replacingFirstName(in: fullName, old: appliedFirstName, new: firstName,
                                                    fatherFullName: fatherFullName)
        appliedFirstName = firstName
        // مسافة في آخر الحقل وهو يكتب ما تغيّر الاسم الكامل — لا نلمسه
        if PersonName.clean(updated) != PersonName.clean(fullName) { fullName = updated }
    }

    private func fieldBox<Content: View>(_ label: String, @ViewBuilder content: @escaping () -> Content) -> some View {
        DSFieldBox(label, content: content)
    }

    private func toggleBox(_ title: String, isOn: Binding<Bool>, tint: Color) -> some View {
        DSToggleBox(title: title, isOn: isOn, tint: tint)
    }

    // MARK: - البيانات الأساسية: الاسم، العائلة، الرقم، الجنس
    private var basicsCard: some View {
        adminCard(L10n.t("البيانات الأساسية", "Basic Info"),
                  icon: "person.text.rectangle.fill", color: chromeInk) {
            fieldBox(L10n.t("الاسم الأول", "First Name")) {
                TextField(L10n.t("الاسم الأول", "First Name"), text: $firstName)
                    .padding(.vertical, DS.Spacing.sm)
                    .onChange(of: firstName) { _ in applyFirstNameToFullName() }
            }
            Text(L10n.t("للأسماء المركبة مثل زين العابدين اكتبها كاملة هنا",
                        "For compound names like Zain Al-Abidin, write the whole name here"))
                .dsFont(.footnote)
                .foregroundColor(DS.Color.textTertiary)

            fieldBox(L10n.t("الاسم الكامل", "Full Name")) {
                TextField(L10n.t("الاسم الكامل", "Full Name"), text: $fullName, axis: .vertical)
                    .lineLimit(1...3)
                    .padding(.vertical, DS.Spacing.sm)
                    .onChange(of: fullName) { _ in
                        if fullName.count > 100 { fullName = String(fullName.prefix(100)) }
                    }
            }
            if !isFirstNameValid {
                Label(L10n.t("الاسم الكامل لازم يبدأ بالاسم الأول", "The full name must start with the first name"),
                      systemImage: "exclamationmark.circle.fill")
                    .dsFont(.subtitle)
                    .foregroundColor(DS.Color.error)
            }

            // رأس الشجرة: اسمه هو العائلة نفسها — لا حقل «اسم العائلة» (طلب المالك)
            if !isFamilyRoot {
                fieldBox(L10n.t("اسم العائلة", "Family Name")) {
                    TextField(L10n.t("اسم العائلة", "Family Name"), text: $familyName)
                        .onChange(of: familyName) { _ in
                            if familyName.count > 50 { familyName = String(familyName.prefix(50)) }
                        }
                }
            }

            // المتوفّى بلا رقم هاتف (طلب المالك)
            if !isDeceased {
                fieldBox(L10n.t("رقم الهاتف", "Phone Number")) {
                    DSPhoneField(
                        country: $selectedPhoneCountry,
                        digits: $phoneNumber,
                        placeholder: L10n.t("الرقم", "Number"),
                        compact: true,
                        bordered: false
                    )
                    .onChange(of: phoneNumber) { _ in checkPhoneDuplicate() }
                    .onChange(of: selectedPhoneCountry) { _ in checkPhoneDuplicate() }
                }

                if let warning = phoneDuplicateWarning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .dsFont(.subtitle)
                        .foregroundColor(DS.Color.warning)
                }
                if !isPhoneValid {
                    Label(
                        L10n.t("أدخل رقماً صحيحاً للدولة أو اترك الحقل فارغاً.",
                               "Enter a valid number or leave it empty."),
                        systemImage: "exclamationmark.circle.fill"
                    )
                    .dsFont(.subtitle)
                    .foregroundColor(DS.Color.error)
                }
            }

            // الجنس — تغييره ينقل العضو بين شجرة الرجال وشجرة النساء (`move_child_gender`)؛
            // من له حساب في التطبيق لا يُنقل (النقل يحذف ملفه) فيُعرض للقراءة
            if genderLockedByAccount {
                DSGenderReadOnlyRow(gender: member.gender ?? "male")
                Text(L10n.t("له حساب في التطبيق — لا يُنقل", "Has an app account — can't be moved"))
                    .dsFont(.footnote)
                    .foregroundColor(DS.Color.textTertiary)
            } else {
                DSGenderPicker(selection: $selectedGender)
            }
        }
    }

    // MARK: - التواريخ والحالة (طلب المالك)
    private var datesCard: some View {
        adminCard(L10n.t("التواريخ والحالة", "Dates & Status"),
                  icon: "calendar", color: DS.Color.palm) {
            DSLifeDatesBox(hasBirthDate: $hasBirthDate, birthDate: $birthDate,
                           isDeceased: $isDeceased,
                           hasDeathDate: $hasDeathDate, deathDate: $deathDate)
        }
    }

    // MARK: - النسب: الأب والأبناء
    private var isSortingChildren: Bool { editMode == .active }

    private var lineageCard: some View {
        adminCard(L10n.t("النسب", "Lineage"), icon: "link", color: chromeInk) {
            // الأب — لا يظهر لرأس الشجرة (طلب المالك)
            if !isFamilyRoot {
                VStack(alignment: .leading, spacing: DS.Spacing.xsm) {
                    Text(L10n.t("الأب في الشجرة", "Father in Tree"))
                        .dsFont(.sectionTitle)
                        .foregroundColor(DS.Color.fieldValue)
                    Button { showFatherPicker = true } label: {
                        HStack(spacing: DS.Spacing.sm) {
                            if let fId = selectedFatherId, let father = memberVM.member(byId: fId) {
                                Text(father.displayFullName)
                                    .dsFieldFont(DSBox.fieldValueSize, weight: .semibold)
                                    .foregroundColor(DS.Color.textPrimary)
                                    .dsNameLines()
                            } else {
                                Text(L10n.t("رأس شجرة (غير مرتبط)", "Tree root (unlinked)"))
                                    .dsFieldFont(.fieldValue)
                                    .foregroundColor(DS.Color.textSecondary)
                            }
                            Spacer(minLength: 0)
                            DSChevron()
                        }
                        .frame(minHeight: DS.Icon.tapTarget)
                        // صندوق صفوف المربّعات الموحّد
                        .dsRowBox()
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                if selectedFatherId != member.fatherId, descendantCount > 0 {
                    Label(
                        L10n.t("سيُعاد بناء أسماء \(descendantCount) من الذرّية.",
                               "\(descendantCount) descendant names will be rebuilt."),
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .dsFont(.subtitle)
                    .foregroundColor(DS.Color.warning)
                }
            }

            // الأبناء
            HStack {
                Text(L10n.t("الأبناء (\(localChildren.count))", "Children (\(localChildren.count))"))
                    .dsFont(.sectionTitle)
                    .foregroundColor(DS.Color.fieldValue)
                Spacer()
                if localChildren.count > 1 {
                    // «ترتيب» / «تم» — الشريحة الموحّدة (مساحة ضغط ٤٤ فيها)
                    DSChipButton(isSortingChildren ? L10n.t("تم", "Done") : L10n.t("ترتيب", "Sort"),
                                 icon: isSortingChildren ? "checkmark" : "arrow.up.arrow.down",
                                 tint: chromeInk,
                                 isSelected: isSortingChildren, size: .small) {
                        withAnimation(DS.Anim.snappy) {
                            editMode = isSortingChildren ? .inactive : .active
                        }
                    }
                }
            }
            .padding(.top, DS.Spacing.xs)

            VStack(spacing: DS.Spacing.sm) {
                ForEach(Array(localChildren.enumerated()), id: \.element.id) { index, child in
                    childRow(child: child, index: index)
                }

                // الزرّ الواحد — ثانوي (رمادي) داخل البطاقة، والإجراء الرئيسي «حفظ» أسفل المربّع
                DSButton(localChildren.isEmpty ? L10n.t("إضافة ابن", "Add Child")
                                               : L10n.t("إضافة ابن آخر", "Add Another Child"),
                         icon: "plus.circle.fill", role: .cancel) {
                    showAddSonSheet = true
                }
            }
        }
    }

    private var descendantCount: Int {
        var count = 0
        var stack: [UUID] = [member.id]
        var visited: Set<UUID> = [member.id]
        while let cur = stack.popLast() {
            for m in memberVM.allMembers where m.fatherId == cur {
                if visited.insert(m.id).inserted {
                    stack.append(m.id)
                    count += 1
                }
            }
        }
        return count
    }

    /// ابن واحد داخل مربّع. وضع «ترتيب»: أسهم للأعلى/الأسفل وزر حذف.
    private func childRow(child: FamilyMember, index: Int) -> some View {
        let isChildDeceased = child.isDeceased ?? false
        // الكحلي يتبع لون القسم (كان يبقى كحلياً داخل الشجرة)؛ الأحمر للوفاة يبقى بمعناه
        let tint = isChildDeceased ? DS.Color.error : chromeInk

        return HStack(spacing: DS.Spacing.sm) {
            DSStateIcon(isChildDeceased ? "person.fill.xmark" : "person.fill",
                        tint: tint, size: DS.Icon.discSmall, mapsChrome: false)
                // القارئ الصوتي: الأيقونة زخرفة، إلا علامة الوفاة فتُقرأ كلمةً
                .accessibilityLabel(L10n.t("متوفى", "Deceased"))
                .accessibilityHidden(!isChildDeceased)

            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(child.firstName)
                    .dsFieldFont(DSBox.fieldValueSize, weight: .semibold)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)
                if let birth = child.birthDate, !birth.isEmpty {
                    Text(birth)
                        .dsFont(.footnote)
                        .foregroundColor(DS.Color.textSecondary)
                }
            }

            Spacer(minLength: 0)

            if isSortingChildren {
                // منطقة ضغط ٤٤×٤٤ لكل زر (حد أبل) بلا تداخل والأقراص كما هي: الطرفان
                // يمتدّان للخارج بفرق المقاسين، والأوسط (مع زر الحذف) يأخذ نصفه من كل جهة
                let canDelete = authVM.canDeleteMembers
                let hit = Self.sortHit
                HStack(spacing: hit / 2) {
                    sortArrow("chevron.up", enabled: index > 0,
                              label: L10n.t("نقل لأعلى", "Move up"),
                              hitLeading: hit, hitTrailing: 0) {
                        localChildren.swapAt(index, index - 1)
                    }
                    sortArrow("chevron.down", enabled: index < localChildren.count - 1,
                              label: L10n.t("نقل لأسفل", "Move down"),
                              hitLeading: canDelete ? hit / 2 : 0, hitTrailing: canDelete ? hit / 2 : hit) {
                        localChildren.swapAt(index, index + 1)
                    }
                    if canDelete {
                        Button { childToDelete = child } label: {
                            Image(systemName: "trash")
                                .dsGlyph(DS.Glyph.sm)
                                .foregroundColor(DS.Color.error)
                                .frame(width: Self.sortDisc, height: Self.sortDisc)
                                .background(DS.Color.error.opacity(DS.Opacity.tintFill), in: Circle())
                                .padding(.trailing, hit)
                                .padding(.vertical, hit / 2)
                                .contentShape(Rectangle())
                                .padding(.trailing, -hit)
                                .padding(.vertical, -hit / 2)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.t("حذف \(child.firstName)", "Delete \(child.firstName)"))
                    }
                }
            } else {
                DSChevron()
            }
        }
        .frame(minHeight: DS.Icon.tapTarget)
        // صندوق صفوف المربّعات الموحّد
        .dsRowBox()
        .contentShape(Rectangle())
        .onTapGesture { if !isSortingChildren { childToEdit = child } }
        // القارئ الصوتي: خارج الترتيب الصف كله زر «تعديل»؛ في الترتيب تبقى أزراره منفصلة
        .accessibilityElement(children: isSortingChildren ? .contain : .combine)
        .accessibilityAddTraits(isSortingChildren ? [] : .isButton)
    }

    /// قرص أسهم الترتيب وزرّ الحذف (قرص الصفّ)، وفرقه عن مساحة الضغط ٤٤
    private static let sortDisc: CGFloat = DS.Icon.row
    private static let sortHit: CGFloat = DS.Icon.tapTarget - DS.Icon.row

    /// سهم ترتيب: القرص كما هو، ومنطقة ضغط ٤٤×٤٤ (حد أبل) حولها بلا تغيير مكانها —
    /// الحشو الموجب يوسّع منطقة الضغط، والسالب يعيد حجمها في التخطيط
    private func sortArrow(_ icon: String, enabled: Bool, label: String,
                           hitLeading: CGFloat, hitTrailing: CGFloat,
                           action: @escaping () -> Void) -> some View {
        Button { withAnimation(DS.Anim.snappy) { action() } } label: {
            Image(dsSymbol: icon)
                .dsGlyph(DS.Glyph.sm)
                .foregroundColor(enabled ? chromeInk : DS.Color.textTertiary.opacity(DS.Opacity.disabled))
                .frame(width: Self.sortDisc, height: Self.sortDisc)
                .background(chromeInk.opacity(enabled ? DS.Opacity.tintFill : DS.Opacity.tintFillSoft / 2), in: Circle())
                .padding(.leading, hitLeading)
                .padding(.trailing, hitTrailing)
                .padding(.vertical, Self.sortHit / 2)
                .contentShape(Rectangle())
                .padding(.leading, -hitLeading)
                .padding(.trailing, -hitTrailing)
                .padding(.vertical, -Self.sortHit / 2)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    // MARK: - السيرة الذاتية
    private var bioCard: some View {
        adminCard(L10n.t("السيرة الذاتية", "Biography"),
                  icon: "book.pages.fill", color: DS.Color.accent) {
            if !bioStations.isEmpty {
                VStack(spacing: DS.Spacing.sm) {
                    ForEach(bioStations) { station in
                        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                            HStack(spacing: DS.Spacing.xs) {
                                if let year = station.year, !year.isEmpty {
                                    DSStatusChip(text: year, tint: DS.Color.accent, size: .mini)
                                }
                                Text(station.title)
                                    .dsFont(.rowTitle)
                                    .foregroundColor(DS.Color.textPrimary)
                            }
                            if !station.details.isEmpty {
                                Text(station.details)
                                    .dsFont(.subtitle)
                                    .foregroundColor(DS.Color.textSecondary)
                                    .lineLimit(2)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        // صندوق صفوف المربّعات الموحّد
                        .dsRowBox()
                    }
                }
            }

            // الزرّ الواحد — ثانوي (رمادي) داخل البطاقة
            DSButton(bioStations.isEmpty ? L10n.t("إضافة حدث للسيرة", "Add Biography Entry")
                                         : L10n.t("تعديل السيرة", "Edit Biography"),
                     icon: bioStations.isEmpty ? "plus.circle.fill" : "pencil", role: .cancel) {
                openBioPopup()
            }
        }
    }

    /// السيرة: مربّع عمل بمنتصف الشاشة (`dsCenterBox`) — نفس مربّع تعديل البيانات
    private func openBioPopup() { showBioBox = true }

    // MARK: - حالة الحساب: التسجيل في التطبيق والإيقاف ومنع الرقم (طلب المالك ٢٠٢٦-١٠-١٠؛ المسميات الرسمية ٢٠٢٦-١٠-٢٠)
    /// لكل عضو مسجّلاً كان أو مقيّداً في الشجرة — للإدارة والمراقب، لا على المالك ولا على النفس ولا على المتوفى.
    /// الإيقاف للمالك والمدير (`canFreezeMembers`، والسيرفر يرفضه لغيرهما)، ومنع الرقم للمالك
    private var showsAccountCard: Bool {
        authVM.canEditMembers && member.role != .owner
            && member.id != authVM.currentUser?.id && member.isDeceased != true
    }
    /// «تسجيل في التطبيق» (كان «تفعيل»): حالته التاريخية «معلّق» وله رقم — طلبات الانضمام تُعتمد من «الوارد»
    private var canActivate: Bool {
        (accountStatus == nil || accountStatus == .pending) && !savedPhone.isEmpty && member.role != .pending
    }

    /// شارة الحالة الرسمية في رأس البطاقة: حساب موقوف · عضو مسجّل (له حساب دخول) · مقيّد في الشجرة
    /// («مفعّل / بانتظار التفعيل» تقسيم تاريخي لا يُعرض)
    private var accountChip: (text: String, tint: Color)? {
        if isFrozen { return (AdminMemberStatus.frozen.title, AdminMemberStatus.frozen.tint) }
        guard let hasLogin else { return nil }
        let status: AdminMemberStatus = hasLogin ? .registered : .treeOnly
        return (status.title, status.tint)
    }

    /// سطر «تسجيل في التطبيق» لغير المسجّل: لماذا، وما المطلوب
    private var activationNote: String? {
        if hasLogin == true || isFrozen { return nil }
        if savedPhone.isEmpty {
            return L10n.t("لا يوجد رقم يدخل به — أضف رقمه في «البيانات الأساسية» واحفظ.",
                          "No number to sign in with — add it under Basic Info and save.")
        }
        if member.role == .pending {
            return L10n.t("طلب انضمام قيد المراجعة — القرار من «الوارد».", "A join request under review — decide in the Inbox.")
        }
        return canActivate
            ? L10n.t("يتيح له الدخول برقمه فيصير «عضواً مسجّلاً».", "Lets them sign in with their number.")
            : nil
    }
    /// منع الأرقام للمالك وحده (نفس صفحة «الأرقام الممنوعة من التسجيل» وصلاحية السيرفر)
    private var canBan: Bool { authVM.canManageBannedPhones }
    private var isFrozen: Bool { accountStatus == .frozen }
    private var savedPhone: String {
        (memberVM.member(byId: member.id)?.phoneNumber ?? member.phoneNumber ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// زرّان بالصفّ ونصّ الزرّ نفسه يقول الحالة، وتحتهما سطر يشرح فائدة كلٍّ منهما
    /// (طلب المالك ٢٠٢٦-١٠-١٠ «بسّط الأزرار» — بدل مربّع لكل إجراء بشارة ووصف طويل)
    private var accountCard: some View {
        adminCard(L10n.t("الحساب", "Account"), icon: "lock.shield.fill", color: DS.Color.error,
                  trailing: {
                      if let chip = accountChip {
                          DSStatusChip(text: chip.text, tint: chip.tint)
                              .id(chip.text)
                              .transition(.scale(scale: 0.8).combined(with: .opacity))
                      }
                  }) {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                if let note = activationNote {
                    accountNote(L10n.t("تسجيل في التطبيق", "Register in the app"), note)
                    if canActivate {
                        DSButton(L10n.t("تسجيل في التطبيق", "Register in the app"), icon: "checkmark.seal.fill",
                                 tint: DS.Color.success, isLoading: accountBusy == .activate) {
                            pendingAccountAction = .activate
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }
                }
                HStack(spacing: DSBox.buttonSpacing) {
                    if authVM.canFreezeMembers {
                        if isFrozen {
                            DSButton(L10n.t("رفع الإيقاف", "Lift suspension"), icon: "checkmark.circle.fill",
                                     tint: DS.Color.success, isLoading: accountBusy == .unfreeze) {
                                pendingAccountAction = .unfreeze
                            }
                        } else {
                            DSButton(L10n.t("إيقاف الحساب", "Suspend"), icon: "hand.raised.fill",
                                     tint: DS.Color.info, isLoading: accountBusy == .freeze) {
                                pendingAccountAction = .freeze
                            }
                        }
                    }
                    if canBan {
                        if activeBan != nil {
                            DSButton(L10n.t("رفع المنع", "Unblock"), icon: "checkmark.circle.fill",
                                     tint: DS.Color.success, isLoading: accountBusy == .unban) {
                                pendingAccountAction = .unban
                            }
                        } else {
                            // برتقالي «الرفض» لا أحمر الحذف — يتميّز عن «حذف العضو نهائياً» (طلب المالك ٢٠٢٦-١٠-١١)
                            DSButton(L10n.t("منع الرقم", "Block number"), icon: "nosign",
                                     tint: DS.Color.reject, isLoading: accountBusy == .ban) {
                                pendingAccountAction = .ban
                            }
                            .disabled(savedPhone.isEmpty)
                        }
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.85)

                if authVM.canFreezeMembers {
                    accountNote(L10n.t("إيقاف الحساب", "Suspend"),
                                L10n.t("يمنعه من الدخول مؤقتاً ويخفيه من الشجرة، وبياناته محفوظة.",
                                       "Blocks sign-in for now and hides them from the tree; data is kept."))
                }
                if canBan {
                    accountNote(L10n.t("منع الرقم من التسجيل", "Block from signing up"),
                                savedPhone.isEmpty
                                ? L10n.t("لا يوجد رقم محفوظ لهذا العضو.", "No saved number for this member.")
                                : L10n.t("يمنع الرقم من التسجيل نهائياً ويوقف حساب صاحبه. رفع المنع لا يرفع الإيقاف.",
                                         "Blocks the number from signing up and suspends its account. Unblocking doesn't lift the suspension."))
                }
            }
            .animation(DS.Anim.snappy, value: accountStatus)
            .animation(DS.Anim.snappy, value: activeBan?.id)
        }
    }

    /// سطر الشرح: اسم الإجراء بخطّ أثقل ثم فائدته
    private func accountNote(_ title: String, _ text: String) -> some View {
        (Text(title + ": ").fontWeight(.semibold) + Text(text))
            .dsFont(.footnote)
            .foregroundColor(DS.Color.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func accountActionTitle(_ action: AccountAction) -> String {
        switch action {
        case .activate: return L10n.t("تسجيل \(member.firstName) في التطبيق؟", "Register \(member.firstName) in the app?")
        case .freeze: return L10n.t("إيقاف حساب \(member.firstName)؟", "Suspend \(member.firstName)'s account?")
        case .unfreeze: return L10n.t("رفع إيقاف \(member.firstName)؟", "Lift \(member.firstName)'s suspension?")
        case .ban: return L10n.t("منع رقم \(member.firstName) من التسجيل؟", "Block \(member.firstName)'s number?")
        case .unban: return L10n.t("رفع منع رقم \(member.firstName)؟", "Unblock \(member.firstName)'s number?")
        }
    }

    private func accountActionButton(_ action: AccountAction) -> String {
        switch action {
        case .activate: return L10n.t("تسجيل في التطبيق", "Register")
        case .freeze: return L10n.t("إيقاف الحساب", "Suspend")
        case .unfreeze: return L10n.t("رفع الإيقاف", "Lift suspension")
        case .ban: return L10n.t("منع الرقم", "Block number")
        case .unban: return L10n.t("رفع المنع", "Unblock")
        }
    }

    private func accountActionMessage(_ action: AccountAction) -> String {
        switch action {
        case .activate: return L10n.t("سيتمكن من الدخول للتطبيق برقمه.", "They will be able to sign in with their number.")
        case .freeze: return L10n.t("لن يتمكن من الدخول للتطبيق حتى يُرفع الإيقاف.",
                                    "They won't be able to use the app until the suspension is lifted.")
        case .unfreeze: return L10n.t("سيتمكن من الدخول للتطبيق مجدداً.", "They will be able to use the app again.")
        case .ban: return L10n.t("لن يتمكن هذا الرقم من التسجيل، ويُوقف حساب صاحبه.",
                                 "This number won't be able to sign up, and its account will be suspended.")
        case .unban: return L10n.t("سيتمكن هذا الرقم من التسجيل مجدداً. الحساب يبقى موقوفاً حتى ترفع إيقافه.",
                                   "This number can sign up again. The account stays suspended until you lift it.")
        }
    }

    /// فشل الحذف: السبب من الـ VM (مثل حماية روابط العائلة) في مربّع «تعذّر التنفيذ»
    private func showDeleteFailure() {
        accountErrorText = adminRequestVM.errorMessage
            ?? L10n.t("تعذّر حذف العضو. حاول مرة أخرى.", "Couldn't delete the member. Try again.")
        adminRequestVM.errorMessage = nil
        accountError = true
    }

    private func performAccountAction(_ action: AccountAction) {
        pendingAccountAction = nil
        accountBusy = action
        Task {
            var ok = true
            switch action {
            case .activate:
                adminRequestVM.errorMessage = nil
                await adminRequestVM.activateAccount(memberId: member.id)
                // يرفض تفعيل حساب بلا أب في الشجرة ويشرح السبب
                if let reason = adminRequestVM.errorMessage {
                    adminRequestVM.errorMessage = nil
                    accountErrorText = reason
                    ok = false
                }
                await refreshStatus()
            case .freeze, .unfreeze:
                // الإيقاف ورفعه للمالك والمدير فقط (`canFreezeMembers`) — `setMemberStatus` يقبل `canEditMembers`
                guard authVM.canFreezeMembers else {
                    accountErrorText = L10n.t("إيقاف الحسابات ورفعه للمالك والمدير فقط.",
                                              "Only the owner and admins can suspend accounts.")
                    ok = false
                    break
                }
                let target: FamilyMember.MemberStatus = action == .freeze ? .frozen : .active
                ok = await memberVM.setMemberStatus(memberId: member.id, status: target)
                if ok { withAnimation(DS.Anim.snappy) { accountStatus = target } }
            case .ban:
                ok = await authVM.banPhone(savedPhone, reason: L10n.t("من «بيانات العضو»: \(member.fullName)",
                                                                      "From Member details: \(member.fullName)"))
                await refreshBan()
                await refreshStatus()   // السيرفر يجمّد صاحب الرقم المحظور
            case .unban:
                if let ban = activeBan { ok = await authVM.unbanPhone(ban.id) }
                await refreshBan()
            }
            accountBusy = nil
            if !ok { accountError = true }
        }
    }

    /// الحالة والحظر من السيرفر عند الفتح — العضو المعروض قد يكون قديماً
    private func refreshAccount() async {
        guard showsAccount, showsAccountCard else { return }
        await refreshStatus()
        await refreshBan()
        await AdminAccountsStore.shared.refresh()
        if AdminAccountsStore.shared.loaded {
            withAnimation(DS.Anim.snappy) { hasLogin = AdminAccountsStore.shared.info(member.id) != nil }
        }
    }

    private func refreshStatus() async {
        guard let status = await memberVM.fetchMemberStatus(memberId: member.id) else { return }
        withAnimation(DS.Anim.snappy) { accountStatus = status }
    }

    private func refreshBan() async {
        guard canBan, showsAccountCard, !savedPhone.isEmpty else { return }
        let ban = await authVM.activeBan(for: savedPhone)
        withAnimation(DS.Anim.snappy) { activeBan = ban }
    }

    // MARK: - حذف السجل
    /// نصّ أحمر صغير في آخر المربّع مع تنبيه تحته — يختلف بالشكل والحجم والمكان عن «حظر الرقم»
    /// (طلب المالك ٢٠٢٦-١٠-١١، نفس تفريق «حذف الحساب» في الإعدادات) — التأكيد كما هو
    private var deleteButton: some View {
        VStack(spacing: DS.Spacing.xs) {
            DSDangerTextButton(L10n.t("حذف العضو نهائياً", "Delete member permanently")) {
                showDeleteConfirmation = true
            }
            Text(L10n.t("يحذف العضو وكل بياناته من الشجرة، ولا يمكن التراجع عنه.",
                        "Removes the member and all their data from the tree. This can't be undone."))
                .dsFont(.footnote)
                .foregroundColor(DS.Color.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, DS.Spacing.md)
    }

    // MARK: - Setup / Validation Helpers

    private func setupLocalChildren() {
        let newChildren = memberVM.allMembers
            .filter { $0.fatherId == member.id && $0.isCountable }
            .sortedForDisplay()

        let currentKeys = localChildren.map { "\($0.id.uuidString)-\($0.sortOrder)" }
        let newKeys = newChildren.map { "\($0.id.uuidString)-\($0.sortOrder)" }
        if currentKeys != newKeys {
            localChildren = newChildren
            loadedChildIds = newChildren.map(\.id)   // نقطة البداية لـ«ترتيب لم يُحفظ»
        }
    }

    private var isPhoneValid: Bool {
        phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            KuwaitPhone.normalizedForStorage(
                country: selectedPhoneCountry,
                rawLocalDigits: phoneNumber
            ) != nil
    }

    private func checkPhoneDuplicate() {
        let digits = phoneNumber.filter(\.isNumber)
        guard digits.count >= 4 else {
            phoneDuplicateWarning = nil
            return
        }
        let normalized = KuwaitPhone.normalizedForStorage(
            country: selectedPhoneCountry,
            rawLocalDigits: phoneNumber
        )
        let result = memberVM.isPhoneDuplicate(normalized ?? phoneNumber, excludingMemberId: member.id)
        withAnimation(.easeInOut(duration: 0.2)) {
            if result.isDuplicate, let existing = result.existingMember {
                let existingPhone = KuwaitPhone.display(existing.phoneNumber)
                phoneDuplicateWarning = L10n.t(
                    "الرقم مستخدم من: \(existing.firstName) — \(existingPhone) (\(existing.fullName))",
                    "Used by: \(existing.firstName) — \(existingPhone) (\(existing.fullName))"
                )
            } else {
                phoneDuplicateWarning = nil
            }
        }
    }

    /// الاسم الكامل كما يُحفظ: الحقل + اسم العائلة الجديد إن كُتب
    private func composedFullName() -> String {
        let cleanFamily = familyName.trimmingCharacters(in: .whitespacesAndNewlines)
        var finalFullName = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        let originalFamily = member.fullName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .last
            .map(String.init) ?? ""

        // فقط نُجري عملية استبدال اسم العائلة لو المستخدم كتب اسم عائلة جديد
        // (cleanFamily غير فارغ ويختلف عن الأصلي).
        // بدون هذا الشرط: عضو باسم بكلمة واحدة + cleanFamily فارغ → يدخل البرانش
        // → يشيل الكلمة الوحيدة → finalFullName يصير "" → تظهر رسالة "اسم فارغ".
        if !cleanFamily.isEmpty, cleanFamily != originalFamily {
            var nameParts = finalFullName.split(whereSeparator: \.isWhitespace).map(String.init)
            if nameParts.last == originalFamily, !originalFamily.isEmpty {
                nameParts.removeLast()
            }
            if nameParts.last != cleanFamily {
                nameParts.append(cleanFamily)
            }
            finalFullName = nameParts.joined(separator: " ")
        }
        return finalFullName
    }

    // MARK: - تغيير الجنس (نقل بين الشجرتين)

    /// له حساب دخول مؤكَّد من بياناته: هو نفسه، أو دور إداري، أو حساب موقوف
    private var memberHasAccountByRole: Bool {
        member.id == authVM.currentUser?.id
            || [.owner, .admin, .monitor, .supervisor].contains(member.role)
            || accountStatus == .frozen
    }

    /// يقفل الجنس لمن له حساب في التطبيق (`AdminAccountsStore` — نفس «عضو مسجّل»)
    private func refreshGenderLock(force: Bool = false) async {
        guard !deathOnly, authVM.canEditMembers else { return }
        if memberHasAccountByRole {
            genderLockedByAccount = true
            selectedGender = member.gender ?? "male"
            return
        }
        await AdminAccountsStore.shared.refresh(force: force)
        guard AdminAccountsStore.shared.loaded else { return }
        let locked = AdminAccountsStore.shared.info(member.id) != nil
        withAnimation(DS.Anim.snappy) {
            genderLockedByAccount = locked
            if locked { selectedGender = member.gender ?? "male" }
        }
    }

    private var genderMoveMessage: String {
        if selectedGender == "female" {
            return L10n.t("سيُنقل «\(member.firstName)» إلى شجرة النساء مع روابطه. أفراد شجرة النساء بلا رقم ولا صورة ولا سيرة، فتُحذف هذه من سجله.",
                          "«\(member.firstName)» will move to the women's tree with their links. Women's tree entries have no phone, photo or biography, so these are removed.")
        }
        return L10n.t("سيُنقل «\(member.firstName)» إلى شجرة الرجال ويُسجَّل ذكراً.",
                      "«\(member.firstName)» will move to the men's tree as male.")
    }

    /// بعد التأكيد: التحقق من الحساب ← النقل على السيرفر (`moveChildGender`) ← بقية الحقول على السجل
    /// بعد النقل (ترتيب EditChildSheet). ذكر: السجل نفسه فيكمل الحفظ العادي؛ أنثى: السجل صار في شجرة
    /// النساء — الاسم والتواريخ فقط
    private func performGenderMove() {
        guard !isSaving else { return }
        guard NetworkMonitor.shared.isConnected else {
            showOfflineAlert = true
            return
        }
        let toFemale = selectedGender == "female"
        isSaving = true
        Task {
            // من له حساب لا يُنقل — السيرفر لا يمنعه والنقل يحذف ملفه
            await refreshGenderLock(force: true)
            guard memberHasAccountByRole || AdminAccountsStore.shared.loaded else {
                failGenderMove(L10n.t("تعذّر التحقق من حساب العضو. حاول مرة أخرى.",
                                      "Couldn't check the member's account. Try again."))
                return
            }
            guard !genderLockedByAccount else {
                failGenderMove(L10n.t("له حساب في التطبيق — لا يُنقل بين الشجرتين.",
                                      "Has an app account — can't be moved between trees."))
                return
            }

            memberVM.errorMessage = nil
            guard let newId = await memberVM.moveChildGender(childId: member.id,
                                                             toGender: toFemale ? "female" : "male") else {
                failGenderMove(memberVM.errorMessage
                               ?? L10n.t("فشل حفظ التعديلات. حاول مرة أخرى.", "Save failed. Try again."))
                return
            }
            Log.info("[AdminEdit] ⚧ نقل بين الشجرتين → \(toFemale ? "female" : "male")")

            guard toFemale else {
                // ذكر: السجل نفسه في شجرة الرجال — بقية الحقول بالحفظ العادي (بلا كتابة الجنس مرة ثانية)
                isSaving = false
                genderMoved = true
                if newId != member.id {
                    Log.warning("[AdminEdit] النقل لذكر غيّر المعرّف — يُغلق المربّع")
                    closeAfterMoveToWomen()
                    return
                }
                saveAction()
                return
            }

            // أنثى: الاسم والتواريخ على سجلها الجديد في شجرة النساء
            let fullNameToSave = composedFullName()
            let deathToSave: Date? = (isDeceased && hasDeathDate) ? deathDate : nil
            let deceasedJustMarked = isDeceased && !(member.isDeceased ?? false)
            let saved = await memberVM.updateWomanMember(
                id: newId,
                firstName: PersonName.clean(firstName),
                birthDate: hasBirthDate ? birthDate : nil,
                isDeceased: isDeceased,
                deathDate: deathToSave,
                gender: "female",
                fullName: fullNameToSave.isEmpty ? nil : fullNameToSave
            )
            // تخرج من «الأبناء» في شجرة الرجال
            if let fatherId = member.fatherId { await memberVM.fetchChildren(for: fatherId) }

            let adminName = authVM.currentUser?.firstName ?? "مدير"
            await memberVM.notificationVM?.notifyAdminsWithChangesAndPush(
                title: L10n.t("تعديل بيانات عضو", "Member Data Updated"),
                body: L10n.t("\(adminName) نقل «\(member.fullName)» إلى شجرة النساء",
                             "\(adminName) moved «\(member.fullName)» to the women's tree"),
                kind: "admin_edit",
                changes: [.init(field: "gender", before: member.gender, after: "female")]
            )
            if saved, deceasedJustMarked {
                let target = DeathAnnouncementTarget(
                    id: newId, name: fullNameToSave.isEmpty ? member.fullName : fullNameToSave,
                    isFemale: true, deathDate: DeathRecency.string(from: deathToSave))
                let canAnnounce = authVM.isAdmin
                Task { await DeathAnnouncementPresenter.offer(target, canAnnounce: canAnnounce) }
            }

            isSaving = false
            guard saved else {
                // نُقلت ولم يُحفظ الباقي — السجل القديم لم يعد في شجرة الرجال، فالمربّع يُغلق بعد «حسناً»
                dismissAfterError = true
                failGenderMove(L10n.t("نُقل إلى شجرة النساء، لكن تعذّر حفظ بقية التعديلات. عدّلها من شجرة النساء.",
                                      "Moved to the women's tree, but the other changes couldn't be saved. Edit them from the women's tree."))
                return
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            closeAfterMoveToWomen()
        }
    }

    private func failGenderMove(_ text: String) {
        isSaving = false
        accountErrorText = text
        accountError = true
    }

    /// السجل خرج من شجرة الرجال: يُغلق المربّع وتُغلق تفاصيله (نفس إشعار الحذف)
    private func closeAfterMoveToWomen() {
        dismissAfterError = false
        let oldId = member.id
        dismiss()
        NotificationCenter.default.post(name: .memberDeleted, object: oldId)
    }

    // MARK: - Save Action (unchanged logic)
    private func saveAction() {
        guard !isSaving else { return }
        guard NetworkMonitor.shared.isConnected else {
            showOfflineAlert = true
            return
        }
        // «تسجيل الوفاة» لا يعرض الاسم ولا الرقم ولا يحفظهما (التواريخ فقط)
        guard deathOnly || isPhoneValid else { return }
        isSaving = true

        let capturedMemberId = member.id
        let capturedPhoneCountry = selectedPhoneCountry
        let capturedPhone = phoneNumber
        let capturedFatherId = selectedFatherId
        let capturedBirthDate = hasBirthDate ? birthDate : nil
        let capturedIsDeceased = isDeceased
        let capturedDeathDate = (isDeceased && hasDeathDate) ? deathDate : nil
        let capturedChildren = localChildren
        let capturedGender = selectedGender
        let capturedBioStations = bioStations.filter { !$0.title.isEmpty || !$0.details.isEmpty }

        let capturedFullName = composedFullName()

        guard deathOnly || !capturedFullName.isEmpty else {
            isSaving = false
            showEmptyNameAlert = true
            return
        }
        // الاسم الكامل لازم يبدأ بالاسم الأول (التنبيه ظاهر تحت الحقل)
        guard deathOnly || PersonName.startsWithFirstName(capturedFullName, firstName) else {
            isSaving = false
            return
        }

        // الاسم الأول = الحقل (القاعدة ١) — يتغيّر بروحه أيضاً (تصحيح «زين» ← «زين العابدين»)
        let capturedFirstName = PersonName.clean(firstName)
        let nameChanged = !deathOnly
            && (capturedFullName != member.fullName || capturedFirstName != PersonName.clean(member.firstName))
        let phoneChanged: Bool = {
            guard !deathOnly else { return false }
            let original = KuwaitPhone.detectCountryAndLocal(member.phoneNumber)
            return capturedPhoneCountry.id != original.country.id || capturedPhone != original.localDigits
        }()
        let phoneRemoved: Bool = {
            let originalDigits = KuwaitPhone.detectCountryAndLocal(member.phoneNumber).localDigits
            return phoneChanged && capturedPhone.isEmpty && !originalDigits.isEmpty
        }()
        let fatherChanged = !deathOnly && capturedFatherId != member.fatherId
        let datesChanged: Bool = {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            let origBirth = member.birthDate.flatMap { formatter.date(from: $0) }
            let origDeceased = member.isDeceased ?? false
            let origDeath = member.deathDate.flatMap { formatter.date(from: $0) }
            if capturedIsDeceased != origDeceased { return true }
            if (capturedBirthDate == nil) != (origBirth == nil) { return true }
            if let cb = capturedBirthDate, let ob = origBirth,
               formatter.string(from: cb) != formatter.string(from: ob) { return true }
            if (capturedDeathDate == nil) != (origDeath == nil) { return true }
            if let cd = capturedDeathDate, let od = origDeath,
               formatter.string(from: cd) != formatter.string(from: od) { return true }
            return false
        }()
        let genderChanged = !deathOnly && capturedGender != (member.gender ?? "male")
        let bioChanged: Bool = {
            guard !deathOnly else { return false }
            let oldKey = (member.bio ?? []).map { "\($0.year ?? "")|\($0.title)|\($0.details)" }.joined(separator: ";")
            let newKey = capturedBioStations.map { "\($0.year ?? "")|\($0.title)|\($0.details)" }.joined(separator: ";")
            return oldKey != newKey
        }()
        let deceasedJustMarked = capturedIsDeceased && !(member.isDeceased ?? false)
        let auditMemberName = member.fullName
        let childrenOrderChanged: Bool = {
            guard !deathOnly else { return false }
            let originalChildren = memberVM.allMembers
                .filter { $0.fatherId == capturedMemberId && $0.isCountable }
                .sortedForDisplay()
            if capturedChildren.count != originalChildren.count { return true }
            for (i, child) in capturedChildren.enumerated() {
                if child.id != originalChildren[i].id { return true }
            }
            return false
        }()

        guard nameChanged || phoneChanged || fatherChanged || datesChanged || genderChanged || childrenOrderChanged || bioChanged else {
            isSaving = false
            dismiss()
            return
        }

        // تغيير الجنس = نقل بين الشجرتين على السيرفر أولاً (بعد التأكيد)، ثم بقية الحقول (`performGenderMove`)
        let genderAlreadyMoved = genderMoved
        if genderChanged && !genderAlreadyMoved {
            isSaving = false
            guard !genderLockedByAccount else {
                selectedGender = member.gender ?? "male"
                return
            }
            // الأب يُحفظ قبل النقل لشجرة النساء — لا الاثنان في حفظة واحدة
            if capturedGender == "female" && fatherChanged {
                accountErrorText = L10n.t("احفظ تغيير الأب أولاً، ثم غيّر الجنس.",
                                          "Save the father change first, then change the gender.")
                accountError = true
                return
            }
            showGenderMoveConfirm = true
            return
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        if var updatedMember = memberVM.member(byId: capturedMemberId) {
            if nameChanged {
                updatedMember.fullName = capturedFullName
                updatedMember.firstName = capturedFirstName
            }
            if phoneChanged {
                if capturedPhone.isEmpty {
                    updatedMember.phoneNumber = nil
                } else {
                    let normalized = KuwaitPhone.normalizedForStorage(
                        country: capturedPhoneCountry,
                        rawLocalDigits: capturedPhone
                    )
                    updatedMember.phoneNumber = normalized ?? capturedPhone
                }
            }
            if fatherChanged {
                updatedMember.fatherId = capturedFatherId
                if let newFatherId = capturedFatherId,
                   let newFather = memberVM.member(byId: newFatherId) {
                    let firstName = updatedMember.firstName.trimmingCharacters(in: .whitespacesAndNewlines)
                    updatedMember.fullName = (firstName.isEmpty
                        ? newFather.fullName
                        : "\(firstName) \(newFather.fullName)")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    updatedMember.fullName = updatedMember.firstName
                }
            }
            if genderChanged { updatedMember.gender = capturedGender }
            if bioChanged {
                updatedMember.bio = capturedBioStations.isEmpty ? nil : capturedBioStations
            }
            if datesChanged {
                updatedMember.isDeceased = capturedIsDeceased
                updatedMember.birthDate = capturedBirthDate.map { formatter.string(from: $0) }
                updatedMember.deathDate = capturedDeathDate.map { formatter.string(from: $0) }
            }
            memberVM.upsertMemberLocally(updatedMember)

            if nameChanged || fatherChanged {
                memberVM.propagateNameToDescendantsLocally(of: capturedMemberId)
            }
        }

        dismiss()

        Log.info("[AdminEdit] ▶️ بدء حفظ تعديلات عضو: \(auditMemberName) — " +
                 "nameChanged=\(nameChanged), phoneChanged=\(phoneChanged), " +
                 "fatherChanged=\(fatherChanged), genderChanged=\(genderChanged), " +
                 "datesChanged=\(datesChanged), bioChanged=\(bioChanged), " +
                 "orderChanged=\(childrenOrderChanged)")
        Task {
            if nameChanged {
                Log.info("[AdminEdit] 📝 تعديل الاسم: \(capturedFullName)")
                await memberVM.updateMemberName(memberId: capturedMemberId, fullName: capturedFullName,
                                                firstName: capturedFirstName, silent: true)
                if let err = memberVM.errorMessage {
                    Log.error("[AdminEdit] ❌ فشل حفظ الاسم: \(err)")
                }
            }
            if phoneChanged {
                Log.info("[AdminEdit] 📞 تعديل الهاتف: \(capturedPhone.isEmpty ? "حذف" : "تعيين")")
                if capturedPhone.isEmpty {
                    await memberVM.clearMemberPhone(memberId: capturedMemberId)
                    if let err = memberVM.errorMessage { Log.error("[AdminEdit] ❌ فشل مسح الهاتف: \(err)") }
                } else {
                    let normalized = KuwaitPhone.normalizedForStorage(
                        country: capturedPhoneCountry,
                        rawLocalDigits: capturedPhone
                    )
                    let dup = memberVM.isPhoneDuplicate(normalized ?? capturedPhone, excludingMemberId: capturedMemberId)
                    if dup.isDuplicate, let oldMember = dup.existingMember {
                        await memberVM.clearMemberPhone(memberId: oldMember.id)
                        Log.info("[Admin] نقل الرقم من \(oldMember.firstName) إلى العضو الحالي")
                    }

                    await memberVM.updateMemberPhone(
                        memberId: capturedMemberId,
                        country: capturedPhoneCountry,
                        localPhone: capturedPhone,
                        silent: true
                    )
                    if let err = memberVM.errorMessage { Log.error("[AdminEdit] ❌ فشل تحديث الهاتف: \(err)") }
                }
            }
            if fatherChanged {
                Log.info("[AdminEdit] 🌳 تعديل الأب: \(capturedFatherId?.uuidString ?? "بدون")")
                await memberVM.updateMemberFather(memberId: capturedMemberId, fatherId: capturedFatherId, silent: true)
                if let err = memberVM.errorMessage { Log.error("[AdminEdit] ❌ فشل تحديث الأب: \(err)") }
            }
            // الجنس نُقل على السيرفر قبل هذا الحفظ (`moveChildGender`) — لا يُكتب العمود مرة ثانية
            if genderChanged && !genderAlreadyMoved {
                Log.info("[AdminEdit] ⚧ تعديل الجنس: \(capturedGender)")
                await memberVM.updateMemberGender(memberId: capturedMemberId, gender: capturedGender, silent: true)
                if let err = memberVM.errorMessage { Log.error("[AdminEdit] ❌ فشل تحديث الجنس: \(err)") }
            }
            if datesChanged {
                Log.info("[AdminEdit] 📅 تعديل التواريخ: deceased=\(capturedIsDeceased), birth=\(capturedBirthDate?.description ?? "—"), death=\(capturedDeathDate?.description ?? "—")")
                let datesSaved = await memberVM.updateMemberHealthAndBirth(
                    memberId: capturedMemberId,
                    birthDate: capturedBirthDate,
                    isDeceased: capturedIsDeceased,
                    deathDate: capturedDeathDate
                )
                if let err = memberVM.errorMessage { Log.error("[AdminEdit] ❌ فشل تحديث التواريخ: \(err)") }
                // وفاة سُجّلت الآن (كان حياً) → مربّع «إعلان وفاة» — الإداري يختار «نشر» أو «ليس الآن»
                if datesSaved, deceasedJustMarked {
                    let target = DeathAnnouncementTarget(
                        id: capturedMemberId,
                        name: nameChanged ? capturedFullName : auditMemberName,
                        isFemale: capturedGender == "female",
                        deathDate: DeathRecency.string(from: capturedDeathDate))
                    let canAnnounce = authVM.isAdmin   // إعلان الوفاة للمالك والمدير (السيرفر 20261007130000)
                    Task { await DeathAnnouncementPresenter.offer(target, canAnnounce: canAnnounce) }
                }
            }
            if bioChanged {
                Log.info("[AdminEdit] 📖 تعديل السيرة: \(capturedBioStations.count) محطّة")
                await memberVM.updateMemberBio(memberId: capturedMemberId, bio: capturedBioStations)
                if let err = memberVM.errorMessage { Log.error("[AdminEdit] ❌ فشل تحديث السيرة: \(err)") }
            }
            if childrenOrderChanged && !capturedChildren.isEmpty {
                Log.info("[AdminEdit] 🔢 تعديل ترتيب الأبناء (\(capturedChildren.count))")
                var updatedChildren = capturedChildren
                for i in 0..<updatedChildren.count {
                    updatedChildren[i].sortOrder = i
                }
                await memberVM.updateChildrenOrder(for: capturedMemberId, newOrder: updatedChildren)
                if let err = memberVM.errorMessage { Log.error("[AdminEdit] ❌ فشل تحديث الترتيب: \(err)") }
            }
            Log.info("[AdminEdit] ✅ انتهى حفظ تعديلات: \(auditMemberName)")

            if nameChanged {
                await adminRequestVM.logAdminDirectEdit(payload: TreeEditPayload.make(
                    action: .editName,
                    targetMemberId: capturedMemberId.uuidString,
                    targetMemberName: auditMemberName,
                    newName: capturedFullName,
                    isAdminDirectEdit: true
                ))
            }
            if phoneChanged && !phoneRemoved && !capturedPhone.isEmpty {
                let normalizedAudit = KuwaitPhone.normalizedForStorage(
                    country: capturedPhoneCountry,
                    rawLocalDigits: capturedPhone
                ) ?? capturedPhone
                await adminRequestVM.logAdminDirectEdit(payload: TreeEditPayload.make(
                    action: .editPhone,
                    targetMemberId: capturedMemberId.uuidString,
                    targetMemberName: auditMemberName,
                    newPhone: normalizedAudit,
                    isAdminDirectEdit: true
                ))
            }
            if deceasedJustMarked {
                let auditFormatter = ISO8601DateFormatter()
                auditFormatter.formatOptions = [.withFullDate]
                let dateStr = capturedDeathDate.map { auditFormatter.string(from: $0) }
                await adminRequestVM.logAdminDirectEdit(payload: TreeEditPayload.make(
                    action: .deceased,
                    targetMemberId: capturedMemberId.uuidString,
                    targetMemberName: auditMemberName,
                    deathDate: dateStr,
                    isAdminDirectEdit: true
                ))
            }

            let adminName = authVM.currentUser?.firstName ?? "مدير"
            let memberName = member.fullName
            var changedFields: [String] = []
            var changeEntries: [AppNotification.NotificationDetails.ChangeEntry] = []

            if nameChanged {
                changedFields.append(L10n.t("الاسم", "Name"))
                changeEntries.append(.init(field: "full_name", before: member.fullName, after: capturedFullName))
            }
            if phoneChanged {
                changedFields.append(phoneRemoved ? L10n.t("حذف الهاتف", "Phone removed") : L10n.t("الهاتف", "Phone"))
                let normalized = KuwaitPhone.normalizedForStorage(country: capturedPhoneCountry, rawLocalDigits: capturedPhone) ?? capturedPhone
                changeEntries.append(.init(field: "phone_number", before: member.phoneNumber, after: capturedPhone.isEmpty ? nil : normalized))
            }
            if fatherChanged {
                changedFields.append(L10n.t("الأب", "Father"))
                let oldFatherName = member.fatherId.flatMap { memberVM.member(byId: $0)?.firstName }
                let newFatherName = capturedFatherId.flatMap { memberVM.member(byId: $0)?.firstName }
                changeEntries.append(.init(field: "father_id", before: oldFatherName, after: newFatherName))
            }
            if genderChanged {
                changedFields.append(L10n.t("الجنس", "Gender"))
                changeEntries.append(.init(field: "gender", before: member.gender, after: capturedGender))
            }
            if datesChanged {
                changedFields.append(L10n.t("التواريخ", "Dates"))
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd"
                dateFormatter.locale = Locale(identifier: "en_US_POSIX")
                if (member.birthDate ?? "") != (capturedBirthDate.map { dateFormatter.string(from: $0) } ?? "") {
                    changeEntries.append(.init(
                        field: "birth_date",
                        before: member.birthDate,
                        after: capturedBirthDate.map { dateFormatter.string(from: $0) }
                    ))
                }
                if (member.isDeceased ?? false) != capturedIsDeceased {
                    changeEntries.append(.init(
                        field: "is_deceased",
                        before: (member.isDeceased ?? false) ? "متوفى" : "حيّ",
                        after: capturedIsDeceased ? "متوفى" : "حيّ"
                    ))
                }
                if (member.deathDate ?? "") != (capturedDeathDate.map { dateFormatter.string(from: $0) } ?? "") {
                    changeEntries.append(.init(
                        field: "death_date",
                        before: member.deathDate,
                        after: capturedDeathDate.map { dateFormatter.string(from: $0) }
                    ))
                }
            }
            if childrenOrderChanged { changedFields.append(L10n.t("ترتيب الأبناء", "Children order")) }
            if bioChanged { changedFields.append(L10n.t("السيرة الذاتية", "Biography")) }

            if !changedFields.isEmpty {
                let fieldsList = changedFields.joined(separator: "، ")
                let editKind: String = {
                    let changed = (
                        name: nameChanged, phone: phoneChanged,
                        father: fatherChanged, gender: genderChanged,
                        dates: datesChanged, order: childrenOrderChanged, bio: bioChanged
                    )
                    let count = [changed.name, changed.phone,
                                 changed.father, changed.gender, changed.dates,
                                 changed.order, changed.bio].filter { $0 }.count
                    guard count == 1 else { return "admin_edit" }
                    if changed.name   { return "admin_edit_name" }
                    if changed.dates  { return "admin_edit_dates" }
                    if changed.phone  { return phoneRemoved ? "admin_edit_phone_remove" : "admin_edit_phone" }
                    if changed.father { return "admin_edit_father" }
                    return "admin_edit"
                }()
                let body = L10n.t(
                    "\(adminName) عدّل (\(fieldsList)) لـ \(memberName)",
                    "\(adminName) updated (\(fieldsList)) for \(memberName)"
                )
                if !changeEntries.isEmpty {
                    await memberVM.notificationVM?.notifyAdminsWithChangesAndPush(
                        title: L10n.t("تعديل بيانات عضو", "Member Data Updated"),
                        body: body,
                        kind: editKind,
                        changes: changeEntries
                    )
                } else {
                    await memberVM.notificationVM?.notifyAdminsWithPush(
                        title: L10n.t("تعديل بيانات عضو", "Member Data Updated"),
                        body: body,
                        kind: editKind
                    )
                }
                Log.info("[Admin] \(adminName) عدّل بيانات \(memberName): \(fieldsList) (\(changeEntries.count) تفاصيل)")
            }

            await memberVM.fetchSingleMember(id: capturedMemberId)
            if childrenOrderChanged {
                for child in capturedChildren {
                    await memberVM.fetchSingleMember(id: child.id)
                }
            }
        }
    }
}

// MARK: - واجهة اختيار الأب
/// مربّع اختيار الأب بنفس تصميم المربّعات (طلب المالك ٢٠٢٦-٠٩-٢٦): رأس متدرّج، بحث،
/// صفوف الأعضاء بعلامة الاختيار، و«تأكيد» كحلي يمين / «إغلاق» رمادي يسار أسفل المربّع.
/// الضغط على صف يحدّده، و«تأكيد» يعرض رسالة التأكيد نفسها قبل الربط.
struct FatherPickerSheet: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @Binding var selectedId: UUID?
    /// معرّف العضو الذي يُحرَّر — يُستثنى هو وكل ذرّيته من قائمة المرشّحين
    /// (عشان ما يصير حلقة: ابن يصير أب لأبيه)
    var editingMemberId: UUID? = nil
    @Environment(\.dismiss) var dismiss
    /// لون القسم الذي فُتح منه (الشجرة، الإدارة، حسابي…) — كحلي «الإطار» يتبعه
    @Environment(\.dsSection) private var section
    private var chromeInk: Color { DS.Color.primary.dsChrome(in: section) }
    @State private var searchText = ""
    @State private var debouncedSearch = ""
    @State private var debounceTask: Task<Void, Never>? = nil
    @State private var pendingSelection: FamilyMember? = nil
    @State private var showUnlinkConfirm = false
    /// المحدَّد قبل «تأكيد» — nil = لم يُغيَّر بعد (العلامة على الأب الحالي)
    @State private var choice: FatherChoice? = nil
    /// «تقليل الحركة» (توصية أبل): علامة الاختيار تظهر بتلاشٍ فقط بلا تكبير
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var prepared: [(member: FamilyMember, words: [String])] = []

    private enum FatherChoice {
        case noFather
        case father(FamilyMember)
    }

    private func rebuildPrepared() {
        let exclude: Set<UUID>
        if let rootId = editingMemberId {
            var result: Set<UUID> = [rootId]
            var queue: [UUID] = [rootId]
            while let cur = queue.popLast() {
                for m in memberVM.allMembers where m.fatherId == cur {
                    if result.insert(m.id).inserted { queue.append(m.id) }
                }
            }
            exclude = result
        } else {
            exclude = []
        }

        prepared = memberVM.allMembers
            .filter { $0.isCountable && !exclude.contains($0.id) }
            .map { (member: $0, words: NameSearch.words($0.fullName)) }
            .sorted { $0.member.fullName < $1.member.fullName }
    }

    var filteredMembers: [FamilyMember] {
        // البحث الدقيق الواحد (`NameSearch`): كل كلمة بداية كلمة بالترتيب، والاسم الأول التام أولاً
        let q = NameSearch.words(debouncedSearch)
        if q.isEmpty {
            return prepared.map(\.member)
        }
        return prepared
            .compactMap { item -> (FamilyMember, Int)? in
                guard let r = NameSearch.score(queryWords: q, candidateWords: item.words) else { return nil }
                return (item.member, r)
            }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
                return lhs.0.fullName < rhs.0.fullName
            }
            .map(\.0)
    }

    /// هل على هذا الصف علامة الاختيار — المحدَّد الآن، وإلا الأب الحالي (nil = بدون أب)
    private func isChecked(_ id: UUID?) -> Bool {
        switch choice {
        case nil: return selectedId == id
        case .noFather?: return id == nil
        case .father(let m)?: return m.id == id
        }
    }

    /// «تأكيد» يعمل فقط لما يختلف المحدَّد عن الحالي
    private var hasChange: Bool {
        switch choice {
        case nil: return false
        case .noFather?: return selectedId != nil
        case .father(let m)?: return m.id != selectedId
        }
    }

    private func pick(_ c: FatherChoice) {
        withAnimation(DS.Anim.snappy) { choice = c }
    }

    /// «تأكيد» في شريط المربّع — يعرض رسالة التأكيد نفسها (ربط الأب / إزالة الربط)
    private func confirmChoice() {
        switch choice {
        case .noFather?: showUnlinkConfirm = true
        case .father(let m)?: pendingSelection = m
        case nil: break
        }
    }

    var body: some View {
        let list = filteredMembers
        return ScrollViewReader { proxy in
            DSComposer(
                title: L10n.t("الأب في الشجرة", "Father in Tree"),
                subtitle: L10n.t("اختر الاسم ثم اضغط «تأكيد»", "Pick a name, then tap Confirm"),
                icon: "link",
                tint: DS.Color.actionNavy,
                actionTitle: L10n.t("تأكيد", "Confirm"),
                actionIcon: "checkmark",
                cancelTitle: L10n.t("إغلاق", "Close"),
                canSubmit: hasChange,
                onSubmit: confirmChoice,
                onCancel: { dismiss() }
            ) {
                searchField
                    .id("top")
                    .dsStaggerIn(0)
                noFatherSection
                membersSection(list)
            }
            .onChange(of: searchText) { newValue in
                debounceTask?.cancel()
                debounceTask = Task {
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    if Task.isCancelled { return }
                    await MainActor.run {
                        debouncedSearch = newValue
                        withAnimation(DS.Anim.snappy) {
                            proxy.scrollTo("top", anchor: .top)
                        }
                    }
                }
            }
        }
        .task {
            rebuildPrepared()
        }
        .onChange(of: memberVM.allMembers) { _ in
            rebuildPrepared()
        }
        .tint(chromeInk)
        .dsAlert(
            L10n.t("تأكيد اختيار الأب", "Confirm Father Selection"),
            isPresented: Binding(
                get: { pendingSelection != nil },
                set: { if !$0 { pendingSelection = nil } }
            ),
            presenting: pendingSelection
        ) { member in
            Button(L10n.t("تأكيد", "Confirm")) {
                selectedId = member.id
                pendingSelection = nil
                dismiss()
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {
                pendingSelection = nil
            }
        } message: { member in
            Text(L10n.t(
                "هل تريد ربط هذا العضو بـ \(member.fullName) كأب؟",
                "Link this member to \(member.fullName) as father?"
            ))
        }
        .dsAlert(
            L10n.t("إزالة ربط الأب", "Remove Father Link"),
            isPresented: $showUnlinkConfirm
        ) {
            Button(L10n.t("تأكيد", "Confirm")) {
                selectedId = nil
                dismiss()
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.t(
                "هل تريد جعل هذا العضو رأس شجرة بدون أب؟",
                "Make this member a tree root with no father?"
            ))
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    // MARK: أجزاء المربّع

    /// البحث — نفس حقل المربّعات بأيقونة العدسة
    private var searchField: some View {
        DSComposerField(icon: "magnifyingglass",
                        label: L10n.t("بحث", "Search"),
                        placeholder: L10n.t("ابحث عن اسم...", "Search name..."),
                        text: $searchText)
    }

    /// «بدون أب» — يجعل العضو رأس شجرة (الخيار البديل)
    private var noFatherSection: some View {
        DSComposerSection(title: L10n.t("الخيار البديل", "Alternative"), icon: "link.badge.plus",
                          tint: DS.Color.warning, index: 1) {
            let checked = isChecked(nil)
            Button { pick(.noFather) } label: {
                HStack(spacing: DS.Spacing.sm) {
                    DSFieldIcon(name: "person.crop.circle.badge.minus", tint: DS.Color.warning)
                        .accessibilityHidden(true)   // زخرفة
                    VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                        Text(L10n.t("بدون أب", "No Father"))
                            .dsFieldFont(.label)
                            .foregroundColor(DS.Color.fieldLabel)
                        Text(L10n.t("رأس شجرة", "Tree root"))
                            .dsFieldFont(DSBox.fieldValueSize, weight: checked ? .bold : .regular)
                            .foregroundColor(DS.Color.fieldValue)
                    }
                    Spacer(minLength: 0)
                    if checked {
                        // primary: كحلي في الفاتح وأزرق فاتح في الداكن — التدرّج الكحلي كان
                        // قرصاً غامقاً لا يُرى على صف الداكن (مثل علامة «ربط الأب»)
                        Image(systemName: "checkmark.circle.fill")
                            .dsGlyph(DS.Glyph.xl, weight: .regular)
                            .foregroundStyle(chromeInk)
                            .transition(reduceMotion ? .opacity : .scale(scale: 0.5).combined(with: .opacity))
                            .accessibilityHidden(true)   // الاختيار يُقرأ من حالة الزر
                    }
                }
                .fatherPickerRowBox(selected: checked, tint: chromeInk)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(checked ? .isSelected : [])
        }
    }

    /// المرشّحون للأبوّة — صفوف كسولة لأن القائمة طويلة (مئات الأعضاء)
    private func membersSection(_ list: [FamilyMember]) -> some View {
        DSComposerSection(title: L10n.t("اختر الأب", "Choose Father"), icon: "person.2.fill",
                          tint: DS.Color.primary, trailing: "\(list.count)", index: 2) {
            LazyVStack(spacing: DS.Spacing.xsm) {
                ForEach(list) { m in
                    FatherPickerRow(
                        member: m,
                        isSelected: isChecked(m.id),
                        onTap: { pick(.father(m)) }
                    )
                }
            }
        }
    }
}

// MARK: - Father Picker Row (مُحسَّن للأداء)
private struct FatherPickerRow: View, Equatable {
    let member: FamilyMember
    let isSelected: Bool
    let onTap: () -> Void
    /// «تقليل الحركة» (توصية أبل): علامة الاختيار تظهر بتلاشٍ فقط بلا تكبير
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dsSection) private var section
    private var chromeInk: Color { DS.Color.primary.dsChrome(in: section) }

    static func == (lhs: FatherPickerRow, rhs: FatherPickerRow) -> Bool {
        lhs.member.id == rhs.member.id
            && lhs.member.fullName == rhs.member.fullName
            && lhs.isSelected == rhs.isSelected
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: DS.Spacing.sm) {
                // الحرف الأول في مربّع أيقونة الحقل — نفس صفوف المربّعات
                Text(String(member.fullName.prefix(1)))
                    .dsFont(.rowTitleCompact)
                    .foregroundColor(chromeInk)
                    .frame(width: DS.Icon.row, height: DS.Icon.row)
                    .background(RoundedRectangle(cornerRadius: DS.Icon.discRadius, style: .continuous)
                        .fill(chromeInk.opacity(DS.Opacity.tintFill)))
                    .accessibilityHidden(true)   // الحرف الأول زخرفة — الاسم بجانبه

                Text(member.displayFullName)
                    .dsFieldFont(DSBox.fieldValueSize, weight: isSelected ? .bold : .regular)
                    .foregroundColor(isSelected ? DS.Color.fieldLabel : DS.Color.fieldValue)
                    .dsNameLines()
                    .truncationMode(.tail)

                Spacer(minLength: DS.Spacing.xs)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .dsGlyph(DS.Glyph.xl, weight: .regular)
                        .foregroundStyle(chromeInk)
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.5).combined(with: .opacity))
                        .accessibilityHidden(true)   // الاختيار يُقرأ من حالة الزر
                }
            }
            .fatherPickerRowBox(selected: isSelected, tint: chromeInk)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private extension View {
    /// صف اختيار الأب: صندوق صفوف المربّعات + إطار بلون التطبيق للمختار (مثل الحقل النشط)
    func fatherPickerRowBox(selected: Bool, tint: Color) -> some View {
        dsRowBox()
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .strokeBorder(tint.opacity(selected ? DS.Opacity.selectedStroke : 0), lineWidth: DS.Border.widthBold)
            )
    }
}
