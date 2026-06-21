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

    let member: FamilyMember

    // MARK: - States
    @State private var selectedPhoneCountry: KuwaitPhone.Country
    @State private var phoneNumber: String
    @State private var selectedFatherId: UUID?
    @State private var fullName: String
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
    @State private var showBioEditor = false

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

    private var canDeleteMember: Bool { authVM.canDeleteMembers }
    private var isMonitorOnly: Bool { authVM.currentUser?.role == .monitor }

    init(member: FamilyMember) {
        self.member = member
        self._currentAvatarURL = State(initialValue: member.avatarUrl)
        let detectedPhone = KuwaitPhone.detectCountryAndLocal(member.phoneNumber)
        self._selectedPhoneCountry = State(initialValue: detectedPhone.country)
        self._phoneNumber = State(initialValue: detectedPhone.localDigits)
        self._selectedFatherId = State(initialValue: member.fatherId)
        self._fullName = State(initialValue: member.fullName)
        let nameParts = member.fullName.trimmingCharacters(in: .whitespacesAndNewlines).split(whereSeparator: \.isWhitespace).map(String.init)
        self._familyName = State(initialValue: nameParts.count > 1 ? (nameParts.last ?? "") : "")

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        // IMPORTANT: لا تحذف هذا — بدونه parsing التواريخ يفشل على الأجهزة العربية
        formatter.locale = Locale(identifier: "en_US_POSIX")

        if let bDateStr = member.birthDate, !bDateStr.isEmpty, let date = formatter.date(from: bDateStr) {
            self._birthDate = State(initialValue: date)
            self._hasBirthDate = State(initialValue: true)
        } else {
            self._birthDate = State(initialValue: Date())
            self._hasBirthDate = State(initialValue: false)
        }

        self._bioStations = State(initialValue: member.bio ?? [])
        self._selectedGender = State(initialValue: member.gender ?? "male")
        self._isDeceased = State(initialValue: member.isDeceased ?? false)
        if let dDateStr = member.deathDate, !dDateStr.isEmpty, let date = formatter.date(from: dDateStr) {
            self._deathDate = State(initialValue: date)
            self._hasDeathDate = State(initialValue: true)
        } else {
            self._deathDate = State(initialValue: Date())
            self._hasDeathDate = State(initialValue: false)
        }
    }

    // MARK: - Body
    var body: some View {
        NavigationStack {
            Form {
                heroSection
                identitySection
                genderSection
                datesSection
                phoneSection
                bioSection
                if !isMonitorOnly {
                    fatherSection
                    childrenSection
                    if canDeleteMember { deleteSection }
                }
            }
            .scrollContentBackground(.hidden)
            .background(DS.Color.background)
            .environment(\.editMode, $editMode)
            .navigationTitle(L10n.t("إدارة السجل", "Member Admin"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.t("إغلاق", "Close")) { dismiss() }
                        .font(DS.Font.caption1)
                        .foregroundColor(DS.Color.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: saveAction) {
                        if isSaving {
                            ProgressView().tint(DS.Color.primary)
                        } else {
                            Text(L10n.t("حفظ", "Save"))
                                .font(DS.Font.callout)
                                .fontWeight(.bold)
                                .foregroundColor(DS.Color.primary)
                        }
                    }
                    .disabled(isSaving || !isPhoneValid)
                }
            }
            .sheet(isPresented: $showBioEditor) {
                BioStationsEditorSheet(stations: $bioStations)
            }
            .sheet(isPresented: $showFatherPicker) {
                FatherPickerSheet(selectedId: $selectedFatherId, editingMemberId: member.id)
            }
            .sheet(isPresented: $showAddSonSheet) {
                AddSonByAdminSheet(parent: member)
            }
            .sheet(item: $childToEdit) { child in
                AddSonByAdminSheet(parent: member, editingChild: child)
            }
            .onAppear { setupLocalChildren() }
            .onChange(of: showAddSonSheet) { isShowing in
                if !isShowing { setupLocalChildren() }
            }
            .onChange(of: childToEdit) { child in
                if child == nil { setupLocalChildren() }
            }
            .onChange(of: memberVM.membersVersion) { _ in
                setupLocalChildren()
            }
            .alert(
                L10n.t("اسم فارغ", "Empty Name"),
                isPresented: $showEmptyNameAlert
            ) {
                Button(L10n.t("حسناً", "OK"), role: .cancel) {}
            } message: {
                Text(L10n.t(
                    "لا يمكن حفظ عضو بدون اسم. اكتب الاسم أولاً.",
                    "Cannot save a member with an empty name. Please enter a name first."
                ))
            }
            .alert(
                L10n.t("لا يوجد اتصال بالإنترنت", "No Internet Connection"),
                isPresented: $showOfflineAlert
            ) {
                Button(L10n.t("حسناً", "OK"), role: .cancel) {}
            } message: {
                Text(L10n.t(
                    "لا يمكن حفظ التعديلات بدون اتصال بالإنترنت. تأكد من الاتصال ثم حاول مجدداً.",
                    "Changes cannot be saved without an internet connection. Check your connection and try again."
                ))
            }
            .alert(L10n.t("حذف نهائي", "Permanent Delete"), isPresented: $showDeleteConfirmation) {
                Button(L10n.t("حذف", "Delete"), role: .destructive) {
                    Task {
                        guard canDeleteMember else { return }
                        await adminRequestVM.rejectOrDeleteMember(memberId: member.id)
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
            .alert(L10n.t("حذف الابن", "Delete Child"), isPresented: Binding(
                get: { childToDelete != nil },
                set: { if !$0 { childToDelete = nil } }
            )) {
                Button(L10n.t("حذف", "Delete"), role: .destructive) {
                    if let child = childToDelete {
                        let capturedChild = child
                        Task {
                            await adminRequestVM.rejectOrDeleteMember(memberId: capturedChild.id)
                            localChildren.removeAll { $0.id == capturedChild.id }
                            childToDelete = nil
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
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    // MARK: - Hero Section (Avatar + Name + Role)
    private var heroSection: some View {
        Section {
            VStack(spacing: DS.Spacing.sm) {
                if selectedGender == "female" {
                    // قاعدة التطبيق: الأنثى بلا صورة شخصية — لا اختيار صورة.
                    FemaleAvatarView()
                        .frame(width: 96, height: 96)
                } else {
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
                        await memberVM.uploadAvatar(image: newImage, for: member.id)
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
                }

                VStack(spacing: 4) {
                    Text(member.fullName)
                        .font(DS.Font.callout)
                        .fontWeight(.semibold)
                        .foregroundColor(DS.Color.textPrimary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)

                    DSRoleBadge(title: member.roleName, color: member.roleColor)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Spacing.xs)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
    }

    // MARK: - Identity Section
    private var identitySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Label(L10n.t("الاسم الكامل", "Full Name"), systemImage: "person.fill")
                    .foregroundColor(DS.Color.textSecondary)
                    .font(DS.Font.caption1)
                TextField(L10n.t("الاسم الكامل", "Full Name"), text: $fullName)
                    .font(DS.Font.callout)
                    .onChange(of: fullName) { _ in
                        if fullName.count > 100 { fullName = String(fullName.prefix(100)) }
                    }
            }
            .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 4) {
                Label(L10n.t("اسم العائلة", "Family Name"), systemImage: "person.2.fill")
                    .foregroundColor(DS.Color.textSecondary)
                    .font(DS.Font.caption1)
                TextField(L10n.t("اسم العائلة", "Family Name"), text: $familyName)
                    .font(DS.Font.callout)
                    .onChange(of: familyName) { _ in
                        if familyName.count > 50 { familyName = String(familyName.prefix(50)) }
                    }
            }
            .padding(.vertical, 2)
        } header: {
            sectionHeader(L10n.t("الهوية", "Identity"), icon: "person.text.rectangle.fill", color: DS.Color.primary)
        }
    }

    // MARK: - Gender Section
    private var genderSection: some View {
        Section {
            Picker(L10n.t("الجنس", "Gender"), selection: $selectedGender) {
                Label(L10n.t("ذكر", "Male"), systemImage: "figure.stand").tag("male")
                Label(L10n.t("أنثى", "Female"), systemImage: "figure.stand.dress").tag("female")
            }
            .pickerStyle(.segmented)
            .padding(.vertical, DS.Spacing.xs)
        } header: {
            sectionHeader(L10n.t("الجنس", "Gender"), icon: "person.crop.circle", color: DS.Color.accent)
        }
    }

    // MARK: - Dates Section
    private var datesSection: some View {
        Section {
            Toggle(isOn: $hasBirthDate.animation(DS.Anim.snappy)) {
                Label(L10n.t("تاريخ الميلاد متوفر", "Birth date available"), systemImage: "calendar")
                    .foregroundColor(DS.Color.textPrimary)
            }
            .tint(DS.Color.primary)

            if hasBirthDate {
                DSDateField(
                    label: L10n.t("تاريخ الميلاد", "Birth Date"),
                    date: $birthDate,
                    icon: "calendar.badge.clock",
                    range: ...Date(),
                    compact: true
                )
            }

            Toggle(isOn: $isDeceased.animation(DS.Anim.snappy)) {
                Label(L10n.t("متوفي", "Deceased"), systemImage: "heart.text.square.fill")
                    .foregroundColor(DS.Color.textPrimary)
            }
            .tint(DS.Color.neonPink)

            if isDeceased {
                Toggle(isOn: $hasDeathDate.animation(DS.Anim.snappy)) {
                    Label(L10n.t("تاريخ الوفاة متوفر", "Death date available"), systemImage: "calendar.badge.minus")
                        .foregroundColor(DS.Color.textPrimary)
                }
                .tint(DS.Color.neonPink)

                if hasDeathDate {
                    DSDateField(
                        label: L10n.t("تاريخ الوفاة", "Death Date"),
                        date: $deathDate,
                        icon: "calendar.badge.exclamationmark",
                        range: ...Date(),
                        compact: true
                    )
                }
            }
        } header: {
            sectionHeader(L10n.t("التواريخ والحالة", "Dates & Status"), icon: "calendar", color: DS.Color.secondary)
        }
    }

    // MARK: - Phone Section — حقل موحّد مع كود الدولة على الجهة المقابلة
    private var phoneSection: some View {
        Section {
            DSPhoneField(
                country: $selectedPhoneCountry,
                digits: $phoneNumber,
                placeholder: L10n.t("الرقم", "Number")
            )
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .onChange(of: phoneNumber) { _ in checkPhoneDuplicate() }
            .onChange(of: selectedPhoneCountry) { _ in checkPhoneDuplicate() }

            if let warning = phoneDuplicateWarning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(DS.Font.caption1)
                    .foregroundColor(DS.Color.warning)
            }

            if !isPhoneValid {
                Label(
                    L10n.t(
                        "أدخل رقماً صحيحاً للدولة أو اترك الحقل فارغاً.",
                        "Enter a valid number or leave it empty."
                    ),
                    systemImage: "exclamationmark.circle.fill"
                )
                .font(DS.Font.caption1)
                .foregroundColor(DS.Color.error)
            }
        } header: {
            sectionHeader(L10n.t("رقم الهاتف", "Phone Number"), icon: "phone.fill", color: DS.Color.secondary)
        }
    }

    // MARK: - Bio Section
    private var bioSection: some View {
        Section {
            if bioStations.isEmpty {
                Button {
                    showBioEditor = true
                } label: {
                    Label(L10n.t("إضافة محطة حياتية", "Add Life Station"), systemImage: "plus.circle.fill")
                        .foregroundColor(DS.Color.accent)
                        .font(DS.Font.callout)
                }
            } else {
                ForEach(bioStations) { station in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: DS.Spacing.xs) {
                            if let year = station.year, !year.isEmpty {
                                Text(year)
                                    .font(DS.Font.caption1)
                                    .fontWeight(.bold)
                                    .foregroundColor(DS.Color.accent)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(DS.Color.accent.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                            Text(station.title)
                                .font(DS.Font.callout)
                                .fontWeight(.semibold)
                                .foregroundColor(DS.Color.textPrimary)
                        }
                        if !station.details.isEmpty {
                            Text(station.details)
                                .font(DS.Font.caption1)
                                .foregroundColor(DS.Color.textSecondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(.vertical, 2)
                }

                Button {
                    showBioEditor = true
                } label: {
                    Label(
                        L10n.t("تعديل المحطات (\(bioStations.count))", "Edit Stations (\(bioStations.count))"),
                        systemImage: "pencil"
                    )
                    .foregroundColor(DS.Color.accent)
                    .font(DS.Font.callout)
                }
            }
        } header: {
            sectionHeader(L10n.t("المحطات الحياتية", "Life Stations"), icon: "book.pages.fill", color: DS.Color.accent)
        }
    }

    // MARK: - Father Section
    private var fatherSection: some View {
        Section {
            Button {
                showFatherPicker = true
            } label: {
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: "person.line.dotted.person.fill")
                        .font(DS.Font.scaled(15, weight: .semibold))
                        .foregroundColor(DS.Color.primary)
                        .frame(width: 28, height: 28)
                        .background(DS.Color.primary.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 7))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t("الأب في الشجرة", "Father in Tree"))
                            .font(DS.Font.caption1)
                            .foregroundColor(DS.Color.textTertiary)

                        if let fId = selectedFatherId, let father = memberVM.member(byId: fId) {
                            Text(father.fullName)
                                .font(DS.Font.callout)
                                .fontWeight(.semibold)
                                .foregroundColor(DS.Color.textPrimary)
                                .lineLimit(1)
                        } else {
                            Text(L10n.t("رأس شجرة (غير مرتبط)", "Tree root (unlinked)"))
                                .font(DS.Font.callout)
                                .foregroundColor(DS.Color.textSecondary)
                        }
                    }

                    Spacer()

                    Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                        .font(DS.Font.scaled(12, weight: .bold))
                        .foregroundColor(DS.Color.textTertiary)
                }
            }
            .buttonStyle(.plain)

            if selectedFatherId != member.fatherId, descendantCount > 0 {
                Label(
                    L10n.t(
                        "سيُعاد بناء أسماء \(descendantCount) من الذرّية.",
                        "\(descendantCount) descendant names will be rebuilt."
                    ),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(DS.Font.caption1)
                .foregroundColor(DS.Color.warning)
            }
        } header: {
            sectionHeader(L10n.t("ربط الأب", "Parent Link"), icon: "link", color: DS.Color.primary)
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

    // MARK: - Children Section
    private var childrenSection: some View {
        Section {
            if localChildren.isEmpty {
                Button {
                    showAddSonSheet = true
                } label: {
                    Label(L10n.t("إضافة ابن", "Add Child"), systemImage: "plus.circle.fill")
                        .foregroundColor(DS.Color.secondary)
                        .font(DS.Font.callout)
                }
            } else {
                ForEach(localChildren, id: \.id) { child in
                    childRow(child: child)
                }
                .onMove { source, destination in
                    localChildren.move(fromOffsets: source, toOffset: destination)
                }
                .onDelete { offsets in
                    guard canDeleteMember, let idx = offsets.first else { return }
                    childToDelete = localChildren[idx]
                }

                Button {
                    showAddSonSheet = true
                } label: {
                    Label(L10n.t("إضافة ابن آخر", "Add Another Child"), systemImage: "plus.circle.fill")
                        .foregroundColor(DS.Color.secondary)
                        .font(DS.Font.callout)
                }
            }
        } header: {
            HStack {
                sectionHeader(L10n.t("الأبناء", "Children"), icon: "person.2.fill", color: DS.Color.secondary)
                Spacer()
                if !localChildren.isEmpty {
                    Button {
                        withAnimation(DS.Anim.snappy) {
                            editMode = (editMode == .active) ? .inactive : .active
                        }
                    } label: {
                        Text(editMode == .active ? L10n.t("تم", "Done") : L10n.t("ترتيب", "Sort"))
                            .font(DS.Font.caption1)
                            .fontWeight(.bold)
                            .foregroundColor(editMode == .active ? DS.Color.secondary : DS.Color.primary)
                            .textCase(nil)
                    }
                }
            }
        }
    }

    private func childRow(child: FamilyMember) -> some View {
        let isChildDeceased = child.isDeceased ?? false
        let iconName = isChildDeceased ? "person.fill.xmark" : "person.fill"
        let iconColor = isChildDeceased ? DS.Color.error : DS.Color.primary

        return Button {
            if editMode != .active { childToEdit = child }
        } label: {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: iconName)
                    .font(DS.Font.scaled(14, weight: .bold))
                    .foregroundColor(iconColor)
                    .frame(width: 30, height: 30)
                    .background(iconColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 1) {
                    Text(child.firstName)
                        .font(DS.Font.callout)
                        .fontWeight(.semibold)
                        .foregroundColor(DS.Color.textPrimary)
                        .lineLimit(1)

                    if let birth = child.birthDate, !birth.isEmpty {
                        Text(birth)
                            .font(DS.Font.caption1)
                            .foregroundColor(DS.Color.textSecondary)
                    }
                }

                Spacer()

                if editMode != .active {
                    Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                        .font(DS.Font.scaled(11, weight: .bold))
                        .foregroundColor(DS.Color.textTertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Delete Section
    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                HStack {
                    Spacer()
                    Label(L10n.t("حذف السجل نهائياً", "Permanently Delete"), systemImage: "trash.fill")
                        .font(DS.Font.callout)
                        .fontWeight(.bold)
                    Spacer()
                }
            }
        }
    }

    // MARK: - Section Header Helper
    private func sectionHeader(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(DS.Font.scaled(11, weight: .bold))
                .foregroundColor(color)
            Text(title)
                .font(DS.Font.caption1)
                .fontWeight(.bold)
                .foregroundColor(DS.Color.textSecondary)
                .textCase(nil)
        }
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
                    "⚠️ الرقم مستخدم من: \(existing.firstName) — \(existingPhone) (\(existing.fullName))",
                    "⚠️ Used by: \(existing.firstName) — \(existingPhone) (\(existing.fullName))"
                )
            } else {
                phoneDuplicateWarning = nil
            }
        }
    }

    // MARK: - Save Action (unchanged logic)
    private func saveAction() {
        guard !isSaving else { return }
        guard NetworkMonitor.shared.isConnected else {
            showOfflineAlert = true
            return
        }
        guard isPhoneValid else { return }
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
        let capturedFullName = finalFullName

        guard !capturedFullName.isEmpty else {
            isSaving = false
            showEmptyNameAlert = true
            return
        }

        let nameChanged = capturedFullName != member.fullName
        let phoneChanged: Bool = {
            let original = KuwaitPhone.detectCountryAndLocal(member.phoneNumber)
            return capturedPhoneCountry.id != original.country.id || capturedPhone != original.localDigits
        }()
        let phoneRemoved: Bool = {
            let originalDigits = KuwaitPhone.detectCountryAndLocal(member.phoneNumber).localDigits
            return phoneChanged && capturedPhone.isEmpty && !originalDigits.isEmpty
        }()
        let fatherChanged = capturedFatherId != member.fatherId
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
        let genderChanged = capturedGender != (member.gender ?? "male")
        let bioChanged: Bool = {
            let oldKey = (member.bio ?? []).map { "\($0.year ?? "")|\($0.title)|\($0.details)" }.joined(separator: ";")
            let newKey = capturedBioStations.map { "\($0.year ?? "")|\($0.title)|\($0.details)" }.joined(separator: ";")
            return oldKey != newKey
        }()
        let deceasedJustMarked = capturedIsDeceased && !(member.isDeceased ?? false)
        let auditMemberName = member.fullName
        let childrenOrderChanged: Bool = {
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

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        if var updatedMember = memberVM.member(byId: capturedMemberId) {
            if nameChanged {
                updatedMember.fullName = capturedFullName
                updatedMember.firstName = capturedFullName
                    .components(separatedBy: " ")
                    .first ?? capturedFullName
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
                await memberVM.updateMemberName(memberId: capturedMemberId, fullName: capturedFullName, silent: true)
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
            if genderChanged {
                Log.info("[AdminEdit] ⚧ تعديل الجنس: \(capturedGender)")
                await memberVM.updateMemberGender(memberId: capturedMemberId, gender: capturedGender, silent: true)
                if let err = memberVM.errorMessage { Log.error("[AdminEdit] ❌ فشل تحديث الجنس: \(err)") }
            }
            if datesChanged {
                Log.info("[AdminEdit] 📅 تعديل التواريخ: deceased=\(capturedIsDeceased), birth=\(capturedBirthDate?.description ?? "—"), death=\(capturedDeathDate?.description ?? "—")")
                await memberVM.updateMemberHealthAndBirth(
                    memberId: capturedMemberId,
                    birthDate: capturedBirthDate,
                    isDeceased: capturedIsDeceased,
                    deathDate: capturedDeathDate
                )
                if let err = memberVM.errorMessage { Log.error("[AdminEdit] ❌ فشل تحديث التواريخ: \(err)") }
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
                        before: (member.isDeceased ?? false) ? "متوفّى" : "حيّ",
                        after: capturedIsDeceased ? "متوفّى" : "حيّ"
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
            if bioChanged { changedFields.append(L10n.t("المحطات الحياتية", "Life Stations")) }

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
struct FatherPickerSheet: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @Binding var selectedId: UUID?
    /// معرّف العضو الذي يُحرَّر — يُستثنى هو وكل ذرّيته من قائمة المرشّحين
    /// (عشان ما يصير حلقة: ابن يصير أب لأبيه)
    var editingMemberId: UUID? = nil
    @Environment(\.dismiss) var dismiss
    @State private var searchText = ""
    @State private var debouncedSearch = ""
    @State private var debounceTask: Task<Void, Never>? = nil
    @State private var pendingSelection: FamilyMember? = nil
    @State private var showUnlinkConfirm = false

    @State private var prepared: [(member: FamilyMember, normalized: String)] = []

    private static func normalizeArabicFast(_ s: String) -> String {
        var out = String()
        out.reserveCapacity(s.count)
        for ch in s {
            switch ch {
            case "أ", "إ", "آ", "ٱ": out.append("ا")
            case "ى": out.append("ي")
            case "ة": out.append("ه")
            case "\u{064B}", "\u{064C}", "\u{064D}",
                 "\u{064E}", "\u{064F}", "\u{0650}",
                 "\u{0651}", "\u{0652}", "\u{0670}":
                continue
            default:
                if ch.isLetter {
                    out.append(contentsOf: String(ch).lowercased())
                } else {
                    out.append(ch)
                }
            }
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func matchRank(normalized: String, query: String) -> Int? {
        if query.isEmpty { return 0 }
        if normalized.hasPrefix(query) { return 0 }
        for word in normalized.split(separator: " ") {
            if word.hasPrefix(query) { return 1 }
        }
        if normalized.contains(query) { return 2 }
        return nil
    }

    private func sectionHeader(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(DS.Font.scaled(11, weight: .bold))
                .foregroundColor(color)
            Text(title)
                .font(DS.Font.caption1)
                .fontWeight(.bold)
                .foregroundColor(DS.Color.textSecondary)
                .textCase(nil)
        }
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
            .map { (member: $0, normalized: Self.normalizeArabicFast($0.fullName)) }
            .sorted { $0.member.fullName < $1.member.fullName }
    }

    var filteredMembers: [FamilyMember] {
        let q = Self.normalizeArabicFast(debouncedSearch)
        if q.isEmpty {
            return prepared.map(\.member)
        }
        return prepared
            .compactMap { item -> (FamilyMember, Int)? in
                guard let r = Self.matchRank(normalized: item.normalized, query: q) else { return nil }
                return (item.member, r)
            }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
                return lhs.0.fullName < rhs.0.fullName
            }
            .map(\.0)
    }

    var body: some View {
        let list = filteredMembers
        return NavigationStack {
            ScrollViewReader { proxy in
                List {
                    Section {
                        Button {
                            showUnlinkConfirm = true
                        } label: {
                            HStack(spacing: DS.Spacing.sm) {
                                Image(systemName: "person.crop.circle.badge.minus")
                                    .font(DS.Font.scaled(15, weight: .semibold))
                                    .foregroundColor(DS.Color.warning)
                                    .frame(width: 28, height: 28)
                                    .background(DS.Color.warning.opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(L10n.t("بدون أب", "No Father"))
                                        .font(DS.Font.caption1)
                                        .foregroundColor(DS.Color.textTertiary)
                                    Text(L10n.t("رأس شجرة", "Tree root"))
                                        .font(DS.Font.callout)
                                        .fontWeight(.semibold)
                                        .foregroundColor(DS.Color.textPrimary)
                                }

                                Spacer()

                                if selectedId == nil {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(DS.Font.scaled(18))
                                        .foregroundStyle(DS.Color.gradientPrimary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .id("top")
                    } header: {
                        sectionHeader(L10n.t("الخيار البديل", "Alternative"), icon: "link.badge.plus", color: DS.Color.warning)
                    }

                    Section {
                        ForEach(list) { m in
                            FatherPickerRow(
                                member: m,
                                isSelected: selectedId == m.id,
                                onTap: { pendingSelection = m }
                            )
                        }
                    } header: {
                        HStack(spacing: 6) {
                            Image(systemName: "person.2.fill")
                                .font(DS.Font.scaled(11, weight: .bold))
                                .foregroundColor(DS.Color.primary)
                            Text(L10n.t("اختر الأب", "Choose Father"))
                                .font(DS.Font.caption1)
                                .fontWeight(.bold)
                                .foregroundColor(DS.Color.textSecondary)
                            Spacer()
                            Text("\(list.count)")
                                .font(DS.Font.caption1)
                                .fontWeight(.bold)
                                .foregroundColor(DS.Color.textTertiary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(DS.Color.surfaceElevated)
                                .clipShape(Capsule())
                        }
                        .textCase(nil)
                    }
                }
                .scrollContentBackground(.hidden)
                .background(DS.Color.background)
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
            .navigationTitle(L10n.t("اختر الأب", "Choose Father"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: L10n.t("ابحث عن اسم...", "Search name..."))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.t("إغلاق", "Close")) { dismiss() }
                        .font(DS.Font.caption1)
                        .foregroundColor(DS.Color.textSecondary)
                }
            }
            .tint(DS.Color.primary)
            .alert(
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
            .alert(
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
    }
}

// MARK: - Father Picker Row (مُحسَّن للأداء)
private struct FatherPickerRow: View, Equatable {
    let member: FamilyMember
    let isSelected: Bool
    let onTap: () -> Void

    static func == (lhs: FatherPickerRow, rhs: FatherPickerRow) -> Bool {
        lhs.member.id == rhs.member.id
            && lhs.member.fullName == rhs.member.fullName
            && lhs.isSelected == rhs.isSelected
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: DS.Spacing.sm) {
                ZStack {
                    Circle()
                        .fill(DS.Color.primary.opacity(0.10))
                        .frame(width: 30, height: 30)
                    Text(String(member.fullName.prefix(1)))
                        .font(DS.Font.scaled(13, weight: .bold))
                        .foregroundColor(DS.Color.primary)
                }

                Text(member.fullName)
                    .font(DS.Font.callout)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: DS.Spacing.xs)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(DS.Font.scaled(18))
                        .foregroundStyle(DS.Color.gradientPrimary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
