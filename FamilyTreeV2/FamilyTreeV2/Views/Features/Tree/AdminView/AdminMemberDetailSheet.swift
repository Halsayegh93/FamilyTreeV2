import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct AdminMemberDetailSheet: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    @Environment(\.dismiss) var dismiss

    let member: FamilyMember

    // MARK: - States
    @State private var selectedRole: FamilyMember.UserRole
    @State private var selectedPhoneCountry: KuwaitPhone.Country
    @State private var phoneNumber: String
    @State private var selectedFatherId: UUID?
    @State private var fullName: String
    @State private var familyName: String

    // البيانات الشخصية
    @State private var birthDate: Date
    @State private var hasBirthDate: Bool

    @State private var isDeceased: Bool
    @State private var deathDate: Date
    @State private var hasDeathDate: Bool
    @State private var selectedGender: String

    // حالات ترتيب الأبناء
    @State private var localChildren: [FamilyMember] = []
    @State private var isSortMode = false
    @State private var draggedChild: FamilyMember?

    // المحطات الحياتية
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

    private var canManageAccessPermissions: Bool {
        authVM.isAdmin
    }

    /// المراقب يشوف بيانات بس — بدون تعديل الأب أو الأبناء أو الدور أو الحذف
    private var isMonitorOnly: Bool {
        authVM.currentUser?.role == .monitor
    }

    init(member: FamilyMember) {
        self.member = member
        self._currentAvatarURL = State(initialValue: member.avatarUrl)
        self._selectedRole = State(initialValue: member.role)
        let detectedPhone = KuwaitPhone.detectCountryAndLocal(member.phoneNumber)
        self._selectedPhoneCountry = State(initialValue: detectedPhone.country)
        self._phoneNumber = State(initialValue: detectedPhone.localDigits)
        self._selectedFatherId = State(initialValue: member.fatherId)
        self._fullName = State(initialValue: member.fullName)
        // استخراج اسم العائلة من الاسم الكامل (آخر كلمة)
        let nameParts = member.fullName.trimmingCharacters(in: .whitespacesAndNewlines).split(whereSeparator: \.isWhitespace).map(String.init)
        self._familyName = State(initialValue: nameParts.count > 1 ? (nameParts.last ?? "") : "")

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

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

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: DS.Spacing.sm) {

                        // Profile header
                        memberHeader
                            .padding(.top, DS.Spacing.sm)

                        // Basic info section — الاسم (الكل يقدر يعدل)
                        basicInfoSection

                        // TODO: gender — re-enable when needed
                        // genderSection

                        // Birth date & health section (الكل يقدر يعدل)
                        datesSection

                        // Phone section (الكل يقدر يعدل)
                        phoneSection

                        // المحطات الحياتية (الكل يقدر يعدل)
                        bioStationsSection

                        // الأقسام التالية للمدير والمالك فقط — المراقب لا
                        if !isMonitorOnly {
                            // Father link section
                            fatherSection

                            // Children section
                            childrenSection

                            // Role section — المالك فقط
                            if authVM.isOwner {
                                roleSection
                            }

                            // Delete button (admin only)
                            if canManageAccessPermissions {
                                deleteSection
                            }
                        }
                    }
                    .padding(.bottom, DS.Spacing.xxxl)
                }
            }
            .navigationTitle(L10n.t("إدارة السجل", "Member Admin"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: saveAction) {
                        if isSaving {
                            ProgressView()
                                .tint(DS.Color.primary)
                        } else {
                            Text(L10n.t("حفظ", "Save"))
                                .font(DS.Font.caption1)
                                .fontWeight(.bold)
                                .foregroundColor(DS.Color.primary)
                        }
                    }
                    .disabled(isSaving)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.t("إغلاق", "Close")) { dismiss() }
                        .font(DS.Font.caption1)
                        .foregroundColor(DS.Color.textSecondary)
                }
            }
            .sheet(isPresented: $showBioEditor) {
                BioStationsEditorSheet(stations: $bioStations)
            }
            .sheet(isPresented: $showFatherPicker) {
                FatherPickerSheet(selectedId: $selectedFatherId)
            }
            .sheet(isPresented: $showAddSonSheet) {
                AddSonByAdminSheet(parent: member)
            }
            .sheet(item: $childToEdit) { child in
                AddSonByAdminSheet(parent: member, editingChild: child)
            }
            .onAppear { setupLocalChildren() }
            .onChange(of: memberVM.allMembers) { _ in
                setupLocalChildren()
            }
            // Live preview محذوف بالكامل — كل تغيير في memberVM.allMembers يسبب re-evaluation
            // للـ body و ScrollView يقفز. التحديث الفعلي بالشجرة يصير عند زر "حفظ" فقط.
            .alert(L10n.t("حذف نهائي", "Permanent Delete"), isPresented: $showDeleteConfirmation) {
                Button(L10n.t("حذف", "Delete"), role: .destructive) {
                    Task {
                        guard canManageAccessPermissions else { return }
                        await adminRequestVM.rejectOrDeleteMember(memberId: member.id)
                        dismiss()
                        // إغلاق شاشة تفاصيل العضو أيضاً
                        NotificationCenter.default.post(name: .memberDeleted, object: member.id)
                    }
                }
                Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { }
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    // MARK: - Member Header (Avatar + Name + Role)
    private var memberHeader: some View {
        VStack(spacing: DS.Spacing.xs) {
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
                        _ = authVM.currentUser?.firstName ?? "مدير"
                        await memberVM.notificationVM?.notifyAdminsWithPush(
                            title: L10n.t("تعديل بيانات عضو", "Member Data Updated"),
                            body: L10n.t(
                                "تم حذف صورة: \(member.fullName)",
                                "Photo removed: \(member.fullName)"
                            ),
                            kind: "admin_edit"
                        )
                    }
                }
            )
            .onChange(of: localAvatarPreview) { newImage in
                guard let newImage else { return }
                Task {
                    await memberVM.uploadAvatar(image: newImage, for: member.id)
                    // تحديث URL محلياً عشان يعرض الصورة الجديدة
                    if let updated = memberVM.member(byId: member.id) {
                        await MainActor.run { currentAvatarURL = updated.avatarUrl }
                    }
                    let adminName = authVM.currentUser?.firstName ?? "مدير"
                    await memberVM.notificationVM?.notifyAdminsWithPush(
                        title: L10n.t("تحديث صورة عضو", "Member Photo Updated"),
                        body: L10n.t(
                            "تم تحديث صورة: \(member.fullName)",
                            "Photo updated: \(member.fullName)"
                        ),
                        kind: "admin_edit"
                    )
                    Log.info("[Admin] \(adminName) عدّل صورة \(member.firstName)")
                }
            }

            VStack(spacing: 2) {
                Text(member.fullName)
                    .font(DS.Font.headline)
                    .foregroundColor(DS.Color.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                DSRoleBadge(title: member.roleName, color: member.roleColor)
            }
        }
    }

    // MARK: - Basic Info Section
    private var basicInfoSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            DSCard(padding: 0) {
                DSSectionHeader(
                    title: L10n.t("البيانات الأساسية", "Basic Information"),
                    icon: "person.text.rectangle.fill",
                    iconColor: DS.Color.primary
                )

                formField(
                    icon: "person.fill",
                    color: DS.Color.primary,
                    placeholder: L10n.t("الاسم الكامل", "Full Name"),
                    text: $fullName
                )
                .onChange(of: fullName) { _ in
                    if fullName.count > 100 {
                        fullName = String(fullName.prefix(100))
                    }
                }

                DSDivider()

                formField(
                    icon: "person.2.fill",
                    color: DS.Color.primary,
                    placeholder: L10n.t("اسم العائلة", "Family Name"),
                    text: $familyName
                )
                .onChange(of: familyName) { _ in
                    if familyName.count > 50 {
                        familyName = String(familyName.prefix(50))
                    }
                }
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
    }

    // MARK: - Gender Section
    private var genderSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            DSCard(padding: 0) {
                DSSectionHeader(
                    title: L10n.t("الجنس", "Gender"),
                    icon: "person.fill",
                    iconColor: DS.Color.primary
                )

                HStack(spacing: DS.Spacing.sm) {
                    genderOption(
                        title: L10n.t("ذكر", "Male"),
                        icon: "figure.stand",
                        value: "male"
                    )

                    genderOption(
                        title: L10n.t("أنثى", "Female"),
                        icon: "figure.stand.dress",
                        value: "female"
                    )
                }
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.xs)
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
    }

    private func genderOption(title: String, icon: String, value: String) -> some View {
        let isSelected = selectedGender == value
        return Button {
            withAnimation(DS.Anim.snappy) { selectedGender = value }
        } label: {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: icon)
                    .font(DS.Font.scaled(16, weight: .bold))
                Text(title)
                    .font(DS.Font.calloutBold)
            }
            .foregroundColor(isSelected ? DS.Color.textOnPrimary : DS.Color.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Spacing.xs)
            .background(
                isSelected
                    ? AnyShapeStyle(DS.Color.gradientPrimary)
                    : AnyShapeStyle(DS.Color.surface)
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .stroke(isSelected ? DS.Color.primary.opacity(0.3) : DS.Color.textTertiary.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bio Stations Section
    private var bioStationsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            DSCard(padding: 0) {
                HStack {
                    DSSectionHeader(
                        title: L10n.t("المحطات الحياتية", "Life Stations"),
                        icon: "book.pages.fill",
                        trailing: bioStations.isEmpty ? nil : "\(bioStations.count)",
                        iconColor: DS.Color.accent
                    )
                    Spacer()
                    Button {
                        showBioEditor = true
                    } label: {
                        HStack(spacing: DS.Spacing.xs) {
                            Image(systemName: bioStations.isEmpty ? "plus" : "pencil")
                            Text(bioStations.isEmpty ? L10n.t("إضافة", "Add") : L10n.t("تعديل", "Edit"))
                        }
                        .font(DS.Font.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(DS.Color.accent)
                        .padding(.horizontal, DS.Spacing.sm)
                        .padding(.vertical, DS.Spacing.xs)
                        .background(DS.Color.accent.opacity(0.1))
                        .clipShape(Capsule())
                    }
                    .padding(.trailing, DS.Spacing.md)
                }

                if bioStations.isEmpty {
                    Button {
                        showBioEditor = true
                    } label: {
                        HStack(spacing: DS.Spacing.sm) {
                            Image(systemName: "plus.circle.fill")
                                .font(DS.Font.scaled(16))
                                .foregroundColor(DS.Color.accent)
                            Text(L10n.t("إضافة محطة حياتية", "Add Life Station"))
                                .font(DS.Font.callout)
                                .foregroundColor(DS.Color.accent)
                            Spacer()
                        }
                        .padding(.horizontal, DS.Spacing.md)
                        .padding(.vertical, DS.Spacing.sm)
                    }
                    .buttonStyle(DSBoldButtonStyle())
                } else {
                    VStack(spacing: DS.Spacing.xs) {
                        ForEach(bioStations) { station in
                            HStack(alignment: .top, spacing: DS.Spacing.sm) {
                                VStack(alignment: .leading, spacing: 2) {
                                    if let year = station.year, !year.isEmpty {
                                        Text(year)
                                            .font(DS.Font.caption1)
                                            .foregroundColor(DS.Color.accent)
                                            .fontWeight(.bold)
                                    }
                                    Text(station.title)
                                        .font(DS.Font.callout)
                                        .fontWeight(.semibold)
                                        .foregroundColor(DS.Color.textPrimary)
                                    if !station.details.isEmpty {
                                        Text(station.details)
                                            .font(DS.Font.caption1)
                                            .foregroundColor(DS.Color.textSecondary)
                                            .lineLimit(2)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.horizontal, DS.Spacing.md)
                            .padding(.vertical, DS.Spacing.xs)

                            if station.id != bioStations.last?.id {
                                DSDivider()
                            }
                        }
                    }
                    .padding(.bottom, DS.Spacing.xs)
                }
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
    }

    // MARK: - Father Section
    private var fatherSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            DSCard(padding: 0) {
                DSSectionHeader(
                    title: L10n.t("ربط العضو بالأب", "Parent Link"),
                    icon: "link",
                    iconColor: DS.Color.accent
                )

                Button(action: { showFatherPicker = true }) {
                    HStack(spacing: DS.Spacing.sm) {
                        DSIcon("person.line.dotted.person.fill", color: DS.Color.accent, size: iconSm, iconSize: iconFontSm)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.t("الأب في الشجرة", "Father in Tree"))
                                .font(DS.Font.caption1)
                                .foregroundColor(DS.Color.textTertiary)

                            if let fId = selectedFatherId, let father = memberVM.member(byId: fId) {
                                Text(father.fullName)
                                    .font(DS.Font.calloutBold)
                                    .foregroundColor(DS.Color.textPrimary)
                            } else {
                                Text(L10n.t("رأس شجرة (غير مرتبط)", "Tree root (unlinked)"))
                                    .font(DS.Font.callout)
                                    .foregroundColor(DS.Color.textSecondary)
                            }
                        }

                        Spacer()

                        Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                            .font(DS.Font.scaled(11, weight: .bold))
                            .foregroundColor(DS.Color.textTertiary)
                            .frame(width: 24, height: 24)
                            .background(DS.Color.textTertiary.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.vertical, DS.Spacing.xs)
                }
                .buttonStyle(DSBoldButtonStyle())
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
    }

    // MARK: - Phone Section
    private var phoneSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            DSCard(padding: 0) {
                DSSectionHeader(
                    title: L10n.t("رقم الهاتف", "Phone Number"),
                    icon: "phone.fill",
                    iconColor: DS.Color.success
                )

                HStack(spacing: DS.Spacing.sm) {
                    Menu {
                        ForEach(KuwaitPhone.supportedCountries) { country in
                            Button {
                                selectedPhoneCountry = country
                            } label: {
                                Text("\(country.flag) \(country.nameArabic) \(country.dialingCode)")
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(selectedPhoneCountry.flag)
                            Text(selectedPhoneCountry.dialingCode)
                                .font(DS.Font.caption1)
                            Image(systemName: "chevron.down")
                                .font(DS.Font.scaled(9, weight: .semibold))
                        }
                        .foregroundColor(DS.Color.textSecondary)
                        .padding(.horizontal, DS.Spacing.sm)
                        .padding(.vertical, DS.Spacing.xs)
                        .background(DS.Color.surfaceElevated.opacity(0.5))
                        .clipShape(Capsule())
                    }

                    PhoneNumberTextField(
                        text: $phoneNumber,
                        placeholder: L10n.t("رقم الهاتف", "Phone Number"),
                        font: .systemFont(ofSize: 15),
                        keyboardType: .numberPad,
                        maxLength: 15
                    )
                    .frame(height: 30)

                    if !phoneNumber.isEmpty {
                        Button {
                            phoneNumber = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(DS.Font.scaled(16))
                                .foregroundColor(DS.Color.error.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.t("مسح الرقم", "Clear phone"))
                    }

                    DSIcon("phone.fill", color: DS.Color.success, size: iconSm, iconSize: iconFontSm)
                }
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.xs)
                .environment(\.layoutDirection, .leftToRight)
                .onChange(of: phoneNumber) { newValue in
                    phoneNumber = KuwaitPhone.userTypedDigits(newValue, maxDigits: selectedPhoneCountry.maxDigits)
                    checkPhoneDuplicate()
                }
                .onChange(of: selectedPhoneCountry) { newCountry in
                    phoneNumber = KuwaitPhone.userTypedDigits(phoneNumber, maxDigits: newCountry.maxDigits)
                    checkPhoneDuplicate()
                }

                // تحذير الرقم المكرر
                if let warning = phoneDuplicateWarning {
                    HStack(spacing: DS.Spacing.xs) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(DS.Font.scaled(13, weight: .bold))
                        Text(warning)
                            .font(DS.Font.caption1)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(DS.Color.error)
                    .padding(.horizontal, DS.Spacing.lg)
                    .transition(.opacity)
                }
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
    }

    // MARK: - Children Section
    private var childrenSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            DSCard(padding: 0) {
                // Header with sort button
                HStack {
                    DSSectionHeader(
                        title: L10n.t("الأبناء", "Children"),
                        icon: "person.2.fill",
                        trailing: localChildren.isEmpty ? nil : "\(localChildren.count)",
                        iconColor: DS.Color.primary
                    )

                    if !localChildren.isEmpty {
                        Spacer()

                        Button {
                            withAnimation(DS.Anim.snappy) { isSortMode.toggle() }
                        } label: {
                            HStack(spacing: DS.Spacing.xs) {
                                Image(systemName: isSortMode ? "checkmark" : "arrow.up.arrow.down")
                                Text(isSortMode ? L10n.t("تم", "Done") : L10n.t("ترتيب", "Sort"))
                            }
                            .font(DS.Font.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(isSortMode ? DS.Color.success : DS.Color.primary)
                            .padding(.horizontal, DS.Spacing.sm)
                            .padding(.vertical, DS.Spacing.xs)
                            .background((isSortMode ? DS.Color.success : DS.Color.primary).opacity(0.1))
                            .clipShape(Capsule())
                        }
                        .padding(.trailing, DS.Spacing.md)
                    }
                }

                if localChildren.isEmpty {
                    VStack(spacing: DS.Spacing.sm) {
                        Image(systemName: "person.2.slash")
                            .font(DS.Font.scaled(24))
                            .foregroundColor(DS.Color.textTertiary)
                        Text(L10n.t("لا يوجد أبناء حالياً", "No children yet"))
                            .font(DS.Font.caption1)
                            .foregroundColor(DS.Color.textSecondary)

                        Button { showAddSonSheet = true } label: {
                            HStack(spacing: DS.Spacing.xs) {
                                Image(systemName: "plus.circle.fill")
                                    .font(DS.Font.scaled(14, weight: .bold))
                                Text(L10n.t("إضافة ابن", "Add Child"))
                                    .font(DS.Font.caption1)
                                    .fontWeight(.bold)
                            }
                            .foregroundColor(DS.Color.success)
                            .padding(.horizontal, DS.Spacing.lg)
                            .padding(.vertical, DS.Spacing.xs)
                            .background(DS.Color.success.opacity(0.1))
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .strokeBorder(DS.Color.success.opacity(0.3), lineWidth: 1)
                            )
                        }
                        .buttonStyle(DSBoldButtonStyle())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(DS.Spacing.md)
                } else if isSortMode {
                    // Drag & drop reorder mode — vertical list
                    VStack(spacing: DS.Spacing.xs) {
                        ForEach(localChildren, id: \.id) { child in
                            childSortRow(child: child)
                        }
                    }
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.bottom, DS.Spacing.md)
                } else {
                    // Normal grid mode
                    let columns = [GridItem(.flexible()), GridItem(.flexible())]
                    LazyVGrid(columns: columns, spacing: DS.Spacing.sm) {
                        ForEach(localChildren, id: \.id) { child in
                            childGridCell(child: child)
                        }

                        // Add child as last grid cell
                        Button { showAddSonSheet = true } label: {
                            HStack(spacing: DS.Spacing.xs) {
                                Image(systemName: "plus")
                                    .font(DS.Font.scaled(13, weight: .bold))
                                    .foregroundColor(DS.Color.success)
                                    .frame(width: 28, height: 28)
                                    .background(DS.Color.success.opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))

                                Text(L10n.t("إضافة", "Add"))
                                    .font(DS.Font.caption2)
                                    .fontWeight(.bold)
                                    .foregroundColor(DS.Color.success)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(DS.Spacing.xs + 2)
                            .background(DS.Color.surface)
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [5]))
                                    .foregroundColor(DS.Color.success.opacity(0.3))
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.bottom, DS.Spacing.md)
                }
            }
            .alert(L10n.t("حذف الابن", "Delete Child"), isPresented: Binding(
                get: { childToDelete != nil },
                set: { if !$0 { childToDelete = nil } }
            )) {
                Button(L10n.t("حذف", "Delete"), role: .destructive) {
                    if let child = childToDelete {
                        Task {
                            await adminRequestVM.rejectOrDeleteMember(memberId: child.id)
                            localChildren.removeAll { $0.id == child.id }
                            childToDelete = nil
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
        .padding(.horizontal, DS.Spacing.lg)
    }

    // MARK: - Sort Row (Drag & Drop)
    private func childSortRow(child: FamilyMember) -> some View {
        let isChildDeceased = child.isDeceased ?? false
        let iconName = isChildDeceased ? "person.fill.xmark" : "person.fill"
        let iconColor = isChildDeceased ? DS.Color.error : DS.Color.primary

        return HStack(spacing: DS.Spacing.sm) {
            Image(systemName: "line.3.horizontal")
                .font(DS.Font.scaled(14, weight: .bold))
                .foregroundColor(DS.Color.textTertiary)

            Image(systemName: iconName)
                .font(DS.Font.scaled(13, weight: .bold))
                .foregroundColor(iconColor)
                .frame(width: 28, height: 28)
                .background(iconColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(child.firstName)
                    .font(DS.Font.callout)
                    .fontWeight(.bold)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)

                if let birth = child.birthDate, !birth.isEmpty {
                    Text(birth)
                        .font(DS.Font.caption1)
                        .foregroundColor(DS.Color.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let idx = localChildren.firstIndex(where: { $0.id == child.id }) {
                Text("\(idx + 1)")
                    .font(DS.Font.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(DS.Color.primary)
                    .frame(width: 24, height: 24)
                    .background(DS.Color.primary.opacity(0.1))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .fill(draggedChild?.id == child.id ? DS.Color.primary.opacity(0.08) : DS.Color.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .stroke(DS.Color.primary.opacity(0.2), lineWidth: 1)
        )
        .onDrag {
            draggedChild = child
            return NSItemProvider(object: child.id.uuidString as NSString)
        }
        .onDrop(of: [.text], delegate: ChildDropDelegate(
            child: child,
            localChildren: $localChildren,
            draggedChild: $draggedChild
        ))
    }

    // MARK: - Grid Cell (Normal Mode)
    private func childGridCell(child: FamilyMember) -> some View {
        let isChildDeceased = child.isDeceased ?? false
        let iconName = isChildDeceased ? "person.fill.xmark" : "person.fill"
        let iconColor = isChildDeceased ? DS.Color.error : DS.Color.primary

        return ZStack(alignment: .topTrailing) {
            Button {
                childToEdit = child
            } label: {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: iconName)
                        .font(DS.Font.scaled(13, weight: .bold))
                        .foregroundColor(iconColor)
                        .frame(width: 28, height: 28)
                        .background(iconColor.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))

                    VStack(alignment: .leading, spacing: 1) {
                        Text(child.firstName)
                            .font(DS.Font.caption1)
                            .fontWeight(.bold)
                            .foregroundColor(DS.Color.textPrimary)
                            .lineLimit(1)

                        if let birth = child.birthDate, !birth.isEmpty {
                            Text(birth)
                                .font(DS.Font.caption1)
                                .foregroundColor(DS.Color.textSecondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()
                    Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                        .font(DS.Font.scaled(9, weight: .bold))
                        .foregroundColor(DS.Color.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DS.Spacing.xs + 2)
                .background(DS.Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .stroke(iconColor.opacity(0.15), lineWidth: 1)
                )
            }
            .buttonStyle(DSBoldButtonStyle())

            // Delete button — admin/owner only
            if canManageAccessPermissions {
                Button {
                    childToDelete = child
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(DS.Font.scaled(16))
                        .foregroundColor(DS.Color.error.opacity(0.7))
                        .background(DS.Color.surface)
                        .clipShape(Circle())
                }
                .buttonStyle(PlainButtonStyle())
                .offset(x: 6, y: -6)
                .accessibilityLabel(L10n.t("حذف", "Delete"))
            }
        }
    }

    // MARK: - Dates Section (Birth + Deceased)
    private var datesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            DSCard(padding: 0) {
                DSSectionHeader(
                    title: L10n.t("التواريخ والحالة", "Dates & Status"),
                    icon: "calendar",
                    iconColor: DS.Color.accent
                )

                // Birth date toggle
                HStack(spacing: DS.Spacing.sm) {
                    DSIcon("calendar", color: DS.Color.accent, size: iconSm, iconSize: iconFontSm)

                    Text(L10n.t("تاريخ الميلاد متوفر", "Birth date available"))
                        .font(DS.Font.callout)
                        .foregroundColor(DS.Color.textPrimary)

                    Spacer()

                    Toggle("", isOn: $hasBirthDate)
                        .labelsHidden()
                        .tint(DS.Color.primary)
                }
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.xs)

                if hasBirthDate {
                    DSDivider()
                    VStack(spacing: DS.Spacing.xs) {
                        HStack(spacing: DS.Spacing.sm) {
                            DSIcon("calendar.badge.clock", color: DS.Color.accent, size: iconSm, iconSize: iconFontSm)
                            Text(L10n.t("التاريخ المختار:", "Selected:"))
                                .font(DS.Font.caption1)
                                .foregroundColor(DS.Color.textSecondary)
                            Spacer()
                            Text(formattedDate(birthDate))
                                .font(DS.Font.calloutBold)
                                .foregroundColor(DS.Color.accent)
                        }
                        .padding(.horizontal, DS.Spacing.md)

                        StableWheelDatePicker(selection: $birthDate, in: ...Date())
                            .padding(.horizontal, DS.Spacing.md)
                    }
                    .padding(.vertical, DS.Spacing.xs)
                }

                DSDivider()

                // Deceased toggle
                HStack(spacing: DS.Spacing.sm) {
                    DSIcon("heart.text.square.fill", color: DS.Color.error, size: iconSm, iconSize: iconFontSm)

                    Text(L10n.t("متوفي", "Deceased"))
                        .font(DS.Font.callout)
                        .foregroundColor(DS.Color.textPrimary)

                    Spacer()

                    Toggle("", isOn: $isDeceased)
                        .labelsHidden()
                        .tint(DS.Color.error)
                }
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.xs)

                if isDeceased {
                    DSDivider()

                    HStack(spacing: DS.Spacing.sm) {
                        DSIcon("calendar.badge.minus", color: DS.Color.error, size: iconSm, iconSize: iconFontSm)

                        Text(L10n.t("تاريخ الوفاة متوفر", "Death date available"))
                            .font(DS.Font.callout)
                            .foregroundColor(DS.Color.textPrimary)

                        Spacer()

                        Toggle("", isOn: $hasDeathDate)
                            .labelsHidden()
                            .tint(DS.Color.error)
                    }
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.vertical, DS.Spacing.xs)

                    if hasDeathDate {
                        DSDivider()
                        VStack(spacing: DS.Spacing.xs) {
                            HStack(spacing: DS.Spacing.sm) {
                                DSIcon("calendar.badge.exclamationmark", color: DS.Color.error, size: iconSm, iconSize: iconFontSm)
                                Text(L10n.t("التاريخ المختار:", "Selected:"))
                                    .font(DS.Font.caption1)
                                    .foregroundColor(DS.Color.textSecondary)
                                Spacer()
                                Text(formattedDate(deathDate))
                                    .font(DS.Font.calloutBold)
                                    .foregroundColor(DS.Color.error)
                            }
                            .padding(.horizontal, DS.Spacing.md)

                            StableWheelDatePicker(selection: $deathDate, in: ...Date())
                                .padding(.horizontal, DS.Spacing.md)
                        }
                        .padding(.vertical, DS.Spacing.xs)
                    }
                }
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
    }

    // MARK: - Role Section
    private var roleSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            DSCard(padding: 0) {
                DSSectionHeader(
                    title: L10n.t("صلاحيات الوصول", "Access Permissions"),
                    icon: "shield.fill",
                    iconColor: DS.Color.neonPurple
                )

                Picker("", selection: $selectedRole) {
                    Text(L10n.t("الإدارة", "Admin")).tag(FamilyMember.UserRole.admin)
                    Text(L10n.t("مشرف", "Supervisor")).tag(FamilyMember.UserRole.supervisor)
                    Text(L10n.t("عضو", "Member")).tag(FamilyMember.UserRole.member)
                }
                .pickerStyle(.segmented)
                .tint(DS.Color.primary)
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.xs)
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
    }

    // MARK: - Delete Section
    private var deleteSection: some View {
        Button {
            showDeleteConfirmation = true
        } label: {
            HStack(spacing: DS.Spacing.sm) {
                DSIcon("trash", color: DS.Color.error, size: iconSm, iconSize: iconFontSm)

                Text(L10n.t("حذف السجل", "Delete Record"))
                    .font(DS.Font.calloutBold)
                    .foregroundColor(DS.Color.error)

                Spacer()
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.xs)
            .background(DS.Color.error.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .stroke(DS.Color.error.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(DSBoldButtonStyle())
        .padding(.horizontal, DS.Spacing.lg)
    }

    // MARK: - Helpers

    private let iconSm: CGFloat = 30
    private let iconFontSm: CGFloat = 13

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: L10n.isArabic ? "ar" : "en_US")
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func formField(icon: String, color: Color, placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            DSIcon(icon, color: color, size: iconSm, iconSize: iconFontSm)

            TextField(placeholder, text: text)
                .font(DS.Font.callout)
                .foregroundColor(DS.Color.textPrimary)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.xs)
    }

    private func setupLocalChildren() {
        let newChildren = memberVM.allMembers
            .filter { $0.fatherId == member.id }
            .sorted(by: { $0.sortOrder < $1.sortOrder })

        // Only update if children actually changed (by id + sortOrder).
        // This prevents re-layout when we're just editing the CURRENT member's dates —
        // Updating memberVM.allMembers fires this observer, but children list itself
        // hasn't changed, so we skip the state update and avoid ScrollView auto-scroll.
        let currentKeys = localChildren.map { "\($0.id.uuidString)-\($0.sortOrder)" }
        let newKeys = newChildren.map { "\($0.id.uuidString)-\($0.sortOrder)" }
        if currentKeys != newKeys {
            localChildren = newChildren
        }
    }

    private func updateLocalMemberState() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        memberVM.updateMemberLocally(
            memberId: member.id,
            isDeceased: isDeceased,
            birthDate: hasBirthDate ? formatter.string(from: birthDate) : nil,
            deathDate: (isDeceased && hasDeathDate) ? formatter.string(from: deathDate) : nil
        )
    }

    @State private var isSaving = false

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

    private func saveAction() {
        guard !isSaving else { return }

        let capturedMemberId = member.id
        let capturedIsAdmin = canManageAccessPermissions
        let capturedRole = selectedRole
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
        if !cleanFamily.isEmpty && !finalFullName.hasSuffix(cleanFamily) {
            let parts = finalFullName.split(whereSeparator: \.isWhitespace).map(String.init)
            if parts.count > 1 {
                let nameWithoutLast = parts.dropLast().joined(separator: " ")
                finalFullName = nameWithoutLast + " " + cleanFamily
            } else {
                finalFullName = finalFullName + " " + cleanFamily
            }
        }
        let capturedFullName = finalFullName

        // Detect what actually changed
        let nameChanged = capturedFullName != member.fullName
        let roleChanged = capturedRole != member.role
        let phoneChanged: Bool = {
            let original = KuwaitPhone.detectCountryAndLocal(member.phoneNumber)
            return capturedPhoneCountry.id != original.country.id || capturedPhone != original.localDigits
        }()
        let fatherChanged = capturedFatherId != member.fatherId
        let datesChanged: Bool = {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
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
        let childrenOrderChanged: Bool = {
            let originalChildren = memberVM.allMembers
                .filter { $0.fatherId == capturedMemberId }
                .sorted(by: { $0.sortOrder < $1.sortOrder })
            if capturedChildren.count != originalChildren.count { return true }
            for (i, child) in capturedChildren.enumerated() {
                if child.id != originalChildren[i].id { return true }
            }
            return false
        }()

        // If nothing changed, just dismiss
        guard nameChanged || roleChanged || phoneChanged || fatherChanged || datesChanged || genderChanged || childrenOrderChanged || bioChanged else {
            dismiss()
            return
        }

        // ═══════════════════════════════════════════════════════════════
        // 1. تحديث محلي فوري لكل البيانات — الشجرة والتفاصيل تتحدّث مباشرة
        // ═══════════════════════════════════════════════════════════════
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        if var updatedMember = memberVM.member(byId: capturedMemberId) {
            if nameChanged { updatedMember.fullName = capturedFullName }
            if roleChanged { updatedMember.role = capturedRole }
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
            if fatherChanged { updatedMember.fatherId = capturedFatherId }
            if genderChanged { updatedMember.gender = capturedGender }
            if datesChanged {
                updatedMember.isDeceased = capturedIsDeceased
                updatedMember.birthDate = capturedBirthDate.map { formatter.string(from: $0) }
                updatedMember.deathDate = capturedDeathDate.map { formatter.string(from: $0) }
            }
            memberVM.upsertMemberLocally(updatedMember)
        }

        // ═══════════════════════════════════════════════════════════════
        // 2. إغلاق الشاشة فوراً — المستخدم يرجع للشجرة بدون انتظار
        // ═══════════════════════════════════════════════════════════════
        dismiss()

        // ═══════════════════════════════════════════════════════════════
        // 3. حفظ السيرفر في الخلفية (المستخدم ما ينتظر)
        // ═══════════════════════════════════════════════════════════════
        Task {
            if nameChanged {
                await memberVM.updateMemberName(memberId: capturedMemberId, fullName: capturedFullName)
            }
            if capturedIsAdmin && roleChanged {
                await memberVM.updateMemberRole(memberId: capturedMemberId, newRole: capturedRole)
            }
            if phoneChanged {
                if capturedPhone.isEmpty {
                    await memberVM.clearMemberPhone(memberId: capturedMemberId)
                } else {
                    // إذا الرقم مستخدم من عضو ثاني → امسحه منه أولاً
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
                        localPhone: capturedPhone
                    )
                }
            }
            if fatherChanged {
                await memberVM.updateMemberFather(memberId: capturedMemberId, fatherId: capturedFatherId)
            }
            if genderChanged {
                await memberVM.updateMemberGender(memberId: capturedMemberId, gender: capturedGender)
            }
            if datesChanged {
                await memberVM.updateMemberHealthAndBirth(
                    memberId: capturedMemberId,
                    birthDate: capturedBirthDate,
                    isDeceased: capturedIsDeceased,
                    deathDate: capturedDeathDate
                )
            }
            if bioChanged {
                await memberVM.updateMemberBio(memberId: capturedMemberId, bio: capturedBioStations)
            }
            if childrenOrderChanged && !capturedChildren.isEmpty {
                var updatedChildren = capturedChildren
                for i in 0..<updatedChildren.count {
                    updatedChildren[i].sortOrder = i
                }
                await memberVM.updateChildrenOrder(for: capturedMemberId, newOrder: updatedChildren)
            }

            // إشعار يوضح أي مدير عدّل + شنو عدّل
            let adminName = authVM.currentUser?.firstName ?? "مدير"
            let memberName = member.fullName
            var changedFields: [String] = []
            if nameChanged { changedFields.append(L10n.t("الاسم", "Name")) }
            if roleChanged { changedFields.append(L10n.t("مستوى الحساب", "Account Level")) }
            if phoneChanged { changedFields.append(L10n.t("الهاتف", "Phone")) }
            if fatherChanged { changedFields.append(L10n.t("الأب", "Father")) }
            if genderChanged { changedFields.append(L10n.t("الجنس", "Gender")) }
            if datesChanged { changedFields.append(L10n.t("التواريخ", "Dates")) }
            if childrenOrderChanged { changedFields.append(L10n.t("ترتيب الأبناء", "Children order")) }
            if bioChanged { changedFields.append(L10n.t("المحطات الحياتية", "Life Stations")) }

            if !changedFields.isEmpty {
                let fieldsList = changedFields.joined(separator: "، ")
                await memberVM.notificationVM?.notifyAdminsWithPush(
                    title: L10n.t("تعديل بيانات عضو", "Member Data Updated"),
                    body: L10n.t(
                        "\(adminName) عدّل (\(fieldsList)) لـ \(memberName)",
                        "\(adminName) updated (\(fieldsList)) for \(memberName)"
                    ),
                    kind: "admin_edit"
                )
                Log.info("[Admin] \(adminName) عدّل بيانات \(memberName): \(fieldsList)")
            }

            // مزامنة العضو الواحد فقط من السيرفر (بدل جلب 1723 عضو)
            // لو فيه اختلاف بين التحديث المحلي والسيرفر، سيُصحح هنا.
            await memberVM.fetchSingleMember(id: capturedMemberId)

            // لو ترتيب الأبناء اتغيّر، نجلبهم كمان
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
    @Environment(\.dismiss) var dismiss
    @State private var searchText = ""
    @State private var pendingSelection: FamilyMember? = nil
    @State private var showUnlinkConfirm = false

    var filteredMembers: [FamilyMember] {
        let sorted = memberVM.allMembers.sorted { $0.fullName < $1.fullName }
        if searchText.isEmpty { return sorted }
        return sorted.filter { $0.fullName.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: DS.Spacing.sm) {
                        // خيار إزالة الربط (رأس شجرة)
                        DSCard(padding: 0) {
                            Button {
                                showUnlinkConfirm = true
                            } label: {
                                HStack(spacing: DS.Spacing.sm) {
                                    Image(systemName: "person.crop.circle.badge.minus")
                                        .font(DS.Font.scaled(15, weight: .bold))
                                        .foregroundColor(DS.Color.warning)
                                        .frame(width: 30, height: 30)
                                        .background(DS.Color.warning.opacity(0.12))
                                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))

                                    Text(L10n.t("رأس شجرة (بدون أب)", "Tree root (no father)"))
                                        .font(DS.Font.calloutBold)
                                        .foregroundColor(DS.Color.textPrimary)

                                    Spacer()

                                    if selectedId == nil {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(DS.Font.scaled(18))
                                            .foregroundStyle(DS.Color.gradientPrimary)
                                    }
                                }
                                .padding(.horizontal, DS.Spacing.md)
                                .padding(.vertical, DS.Spacing.xs)
                            }
                            .buttonStyle(DSBoldButtonStyle())
                        }
                        .padding(.horizontal, DS.Spacing.lg)

                        // قائمة الأعضاء
                        DSCard(padding: 0) {
                            DSSectionHeader(
                                title: L10n.t("اختر الأب", "Choose Father"),
                                icon: "person.2.fill",
                                trailing: "\(filteredMembers.count)",
                                iconColor: DS.Color.accent
                            )

                            LazyVStack(spacing: 0) {
                                ForEach(filteredMembers) { m in
                                    Button {
                                        pendingSelection = m
                                    } label: {
                                        HStack(spacing: DS.Spacing.sm) {
                                            // Avatar
                                            ZStack {
                                                Circle()
                                                    .fill(DS.Color.surface)
                                                    .frame(width: 34, height: 34)

                                                if let urlStr = m.avatarUrl, let url = URL(string: urlStr) {
                                                    CachedAsyncImage(url: url) { img in img.resizable().scaledToFill() }
                                                    placeholder: { ProgressView() }
                                                    .frame(width: 30, height: 30).clipShape(Circle())
                                                } else {
                                                    Text(String(m.fullName.prefix(1)))
                                                        .font(DS.Font.scaled(13, weight: .bold))
                                                        .foregroundColor(DS.Color.primary)
                                                }
                                            }

                                            VStack(alignment: .leading, spacing: 1) {
                                                Text(m.fullName)
                                                    .font(DS.Font.callout)
                                                    .fontWeight(.medium)
                                                    .foregroundColor(DS.Color.textPrimary)
                                                    .lineLimit(1)

                                                Text(m.roleName)
                                                    .font(DS.Font.caption1)
                                                    .foregroundColor(DS.Color.textSecondary)
                                            }

                                            Spacer()

                                            if selectedId == m.id {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .font(DS.Font.scaled(18))
                                                    .foregroundStyle(DS.Color.gradientPrimary)
                                            }
                                        }
                                        .padding(.horizontal, DS.Spacing.md)
                                        .padding(.vertical, DS.Spacing.xs)
                                    }
                                    .buttonStyle(DSBoldButtonStyle())

                                    if m.id != filteredMembers.last?.id {
                                        DSDivider()
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, DS.Spacing.lg)
                    }
                    .padding(.top, DS.Spacing.sm)
                    .padding(.bottom, DS.Spacing.xxxl)
                }
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

// MARK: - Drag & Drop Delegate for Children Reorder
struct ChildDropDelegate: DropDelegate {
    let child: FamilyMember
    @Binding var localChildren: [FamilyMember]
    @Binding var draggedChild: FamilyMember?

    func performDrop(info: DropInfo) -> Bool {
        draggedChild = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let dragged = draggedChild, dragged.id != child.id else { return }
        guard let fromIndex = localChildren.firstIndex(where: { $0.id == dragged.id }),
              let toIndex = localChildren.firstIndex(where: { $0.id == child.id }) else { return }

        withAnimation(DS.Anim.snappy) {
            localChildren.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}
