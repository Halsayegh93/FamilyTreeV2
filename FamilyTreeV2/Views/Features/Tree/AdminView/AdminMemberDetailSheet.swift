import SwiftUI

struct AdminMemberDetailSheet: View {
    @EnvironmentObject var authVM: AuthViewModel
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

    // حالات ترتيب الأبناء
    @State private var localChildren: [FamilyMember] = []
    @State private var isSortMode = false

    @State private var showAddSonSheet = false
    @State private var showFatherPicker = false
    @State private var showDeleteConfirmation = false
    @State private var childToDelete: FamilyMember?
    @State private var childToEdit: FamilyMember?

    private var canManageAccessPermissions: Bool {
        authVM.currentUser?.role == .admin
    }

    init(member: FamilyMember) {
        self.member = member
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
                DSDecorativeBackground()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: DS.Spacing.sm) {

                        // Profile header
                        memberHeader
                            .padding(.top, DS.Spacing.sm)

                        // Basic info section
                        basicInfoSection

                        // Father link section
                        fatherSection

                        // Phone section
                        phoneSection

                        // Children section
                        childrenSection

                        // Birth date & health section
                        datesSection

                        // Role section
                        if canManageAccessPermissions {
                            roleSection
                        }

                        // Delete button (admin only)
                        if canManageAccessPermissions {
                            deleteSection
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
                        Text(L10n.t("حفظ", "Save"))
                            .font(DS.Font.caption1)
                            .fontWeight(.bold)
                            .foregroundColor(DS.Color.primary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.t("إغلاق", "Close")) { dismiss() }
                        .font(DS.Font.caption1)
                        .foregroundColor(DS.Color.textSecondary)
                }
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
            .onChange(of: authVM.allMembers) { _, _ in
                setupLocalChildren()
            }
            .alert(L10n.t("حذف نهائي", "Permanent Delete"), isPresented: $showDeleteConfirmation) {
                Button(L10n.t("حذف", "Delete"), role: .destructive) {
                    Task {
                        guard canManageAccessPermissions else { return }
                        await authVM.rejectOrDeleteMember(memberId: member.id)
                        dismiss()
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
            ZStack {
                Circle()
                    .fill(DS.Color.surface)
                    .frame(width: 70, height: 70)
                    .shadow(color: .black.opacity(0.08), radius: 6, y: 3)

                if let urlStr = member.avatarUrl, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { img in img.resizable().scaledToFill() }
                    placeholder: { ProgressView() }
                    .frame(width: 62, height: 62).clipShape(Circle())
                } else {
                    Circle()
                        .fill(DS.Color.background)
                        .frame(width: 62, height: 62)
                        .overlay(
                            Text(String(member.fullName.prefix(1)))
                                .font(DS.Font.scaled(26, weight: .bold))
                                .foregroundColor(DS.Color.primary)
                        )
                }
            }

            VStack(spacing: 2) {
                Text(member.fullName)
                    .font(DS.Font.headline)
                    .foregroundColor(DS.Color.textPrimary)
                    .multilineTextAlignment(.center)

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

                DSDivider()

                formField(
                    icon: "person.2.fill",
                    color: DS.Color.accent,
                    placeholder: L10n.t("اسم العائلة", "Family Name"),
                    text: $familyName
                )
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
                                .font(DS.Font.caption2)
                                .foregroundColor(DS.Color.textTertiary)

                            if let fId = selectedFatherId, let father = authVM.allMembers.first(where: { $0.id == fId }) {
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
                    .padding(.vertical, DS.Spacing.sm)
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

                    TextField(L10n.t("رقم الهاتف", "Phone Number"), text: $phoneNumber)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.leading)
                        .font(DS.Font.callout)

                    DSIcon("phone.fill", color: DS.Color.success, size: iconSm, iconSize: iconFontSm)
                }
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.sm)
                .environment(\.layoutDirection, .leftToRight)
                .onChange(of: phoneNumber) { _, newValue in
                    phoneNumber = KuwaitPhone.userTypedDigits(newValue, maxDigits: selectedPhoneCountry.maxDigits)
                }
                .onChange(of: selectedPhoneCountry) { _, newCountry in
                    phoneNumber = KuwaitPhone.userTypedDigits(phoneNumber, maxDigits: newCountry.maxDigits)
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
                        iconColor: DS.Color.success
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
                    VStack(spacing: DS.Spacing.xs) {
                        Image(systemName: "person.2.slash")
                            .font(DS.Font.scaled(24))
                            .foregroundColor(DS.Color.textTertiary)
                        Text(L10n.t("لا يوجد أبناء حالياً", "No children yet"))
                            .font(DS.Font.caption1)
                            .foregroundColor(DS.Color.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(DS.Spacing.md)
                } else {
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
                                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5]))
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
                            await authVM.rejectOrDeleteMember(memberId: child.id)
                            localChildren.removeAll { $0.id == child.id }
                            childToDelete = nil
                        }
                    }
                }
                Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { childToDelete = nil }
            } message: {
                if let child = childToDelete {
                    Text(L10n.t("هل أنت متأكد من حذف \(child.firstName)؟", "Are you sure you want to delete \(child.firstName)?"))
                }
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
    }

    private func childGridCell(child: FamilyMember) -> some View {
        let isChildDeceased = child.isDeceased ?? false
        let iconName = isChildDeceased ? "person.fill.xmark" : "person.fill"
        let iconColor = isChildDeceased ? DS.Color.error : DS.Color.primary
        let childIndex = localChildren.firstIndex(where: { $0.id == child.id })

        return ZStack(alignment: .topTrailing) {
            Button {
                if !isSortMode {
                    childToEdit = child
                }
            } label: {
                HStack(spacing: DS.Spacing.xs) {
                    if isSortMode {
                        // Sort arrows
                        VStack(spacing: 2) {
                            Button {
                                if let i = childIndex, i > 0 {
                                    withAnimation(DS.Anim.snappy) {
                                        localChildren.swapAt(i, i - 1)
                                    }
                                }
                            } label: {
                                Image(systemName: "chevron.up")
                                    .font(DS.Font.scaled(9, weight: .bold))
                                    .foregroundColor(childIndex == 0 ? DS.Color.textTertiary.opacity(0.3) : DS.Color.primary)
                            }
                            .disabled(childIndex == 0)

                            Button {
                                if let i = childIndex, i < localChildren.count - 1 {
                                    withAnimation(DS.Anim.snappy) {
                                        localChildren.swapAt(i, i + 1)
                                    }
                                }
                            } label: {
                                Image(systemName: "chevron.down")
                                    .font(DS.Font.scaled(9, weight: .bold))
                                    .foregroundColor(childIndex == localChildren.count - 1 ? DS.Color.textTertiary.opacity(0.3) : DS.Color.primary)
                            }
                            .disabled(childIndex == localChildren.count - 1)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }

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
                                .font(DS.Font.caption2)
                                .foregroundColor(DS.Color.textSecondary)
                                .lineLimit(1)
                        }
                    }

                    if !isSortMode {
                        Spacer()
                        Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                            .font(DS.Font.scaled(9, weight: .bold))
                            .foregroundColor(DS.Color.textTertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DS.Spacing.xs + 2)
                .background(DS.Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .stroke(isSortMode ? DS.Color.primary.opacity(0.3) : iconColor.opacity(0.15), lineWidth: 1)
                )
            }
            .buttonStyle(DSBoldButtonStyle())
            .disabled(isSortMode)

            // Delete button
            if !isSortMode {
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
                    iconColor: DS.Color.warning
                )

                // Birth date toggle
                HStack(spacing: DS.Spacing.sm) {
                    DSIcon("calendar", color: DS.Color.primary, size: iconSm, iconSize: iconFontSm)

                    Text(L10n.t("تاريخ الميلاد متوفر", "Birth date available"))
                        .font(DS.Font.callout)
                        .foregroundColor(DS.Color.textPrimary)

                    Spacer()

                    Toggle("", isOn: $hasBirthDate.animation())
                        .labelsHidden()
                        .tint(DS.Color.primary)
                }
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.sm)

                if hasBirthDate {
                    DSDivider()
                    HStack(spacing: DS.Spacing.sm) {
                        DSIcon("calendar.badge.clock", color: DS.Color.info, size: iconSm, iconSize: iconFontSm)

                        DatePicker("", selection: $birthDate, in: ...Date(), displayedComponents: .date)
                            .labelsHidden()
                            .environment(\.locale, Locale(identifier: "en_US"))

                        Spacer()

                        Text(L10n.t("اختر التاريخ", "Pick Date"))
                            .font(DS.Font.caption1)
                            .foregroundColor(DS.Color.textSecondary)
                    }
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.vertical, DS.Spacing.sm)
                }

                DSDivider()

                // Deceased toggle
                HStack(spacing: DS.Spacing.sm) {
                    DSIcon("heart.text.square.fill", color: DS.Color.error, size: iconSm, iconSize: iconFontSm)

                    Text(L10n.t("متوفي", "Deceased"))
                        .font(DS.Font.callout)
                        .foregroundColor(DS.Color.textPrimary)

                    Spacer()

                    Toggle("", isOn: $isDeceased.animation())
                        .labelsHidden()
                        .tint(DS.Color.error)
                }
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.sm)

                if isDeceased {
                    DSDivider()

                    HStack(spacing: DS.Spacing.sm) {
                        DSIcon("calendar.badge.minus", color: DS.Color.error, size: iconSm, iconSize: iconFontSm)

                        Text(L10n.t("تاريخ الوفاة متوفر", "Death date available"))
                            .font(DS.Font.callout)
                            .foregroundColor(DS.Color.textPrimary)

                        Spacer()

                        Toggle("", isOn: $hasDeathDate.animation())
                            .labelsHidden()
                            .tint(DS.Color.error)
                    }
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.vertical, DS.Spacing.sm)

                    if hasDeathDate {
                        DSDivider()
                        HStack(spacing: DS.Spacing.sm) {
                            DSIcon("calendar.badge.exclamationmark", color: DS.Color.error, size: iconSm, iconSize: iconFontSm)

                            DatePicker("", selection: $deathDate, in: ...Date(), displayedComponents: .date)
                                .labelsHidden()
                                .environment(\.locale, Locale(identifier: "en_US"))

                            Spacer()

                            Text(L10n.t("تاريخ الوفاة", "Death Date"))
                                .font(DS.Font.caption1)
                                .foregroundColor(DS.Color.textSecondary)
                        }
                        .padding(.horizontal, DS.Spacing.md)
                        .padding(.vertical, DS.Spacing.sm)
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
                .padding(.vertical, DS.Spacing.sm)
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
            .padding(.vertical, DS.Spacing.sm)
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

    private func formField(icon: String, color: Color, placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            DSIcon(icon, color: color, size: iconSm, iconSize: iconFontSm)

            TextField(placeholder, text: text)
                .font(DS.Font.callout)
                .foregroundColor(DS.Color.textPrimary)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.sm)
    }

    private func setupLocalChildren() {
        localChildren = authVM.allMembers
            .filter { $0.fatherId == member.id }
            .sorted(by: { ($0.sortOrder ?? 0) < ($1.sortOrder ?? 0) })
    }

    private func saveAction() {
        // Capture all values before dismiss
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
        let vm = authVM

        // Dismiss immediately for snappy UX
        dismiss()

        // Fire-and-forget: all updates run in background
        Task {
            await vm.updateMemberName(memberId: capturedMemberId, fullName: capturedFullName)
            if capturedIsAdmin {
                await vm.updateMemberRole(memberId: capturedMemberId, newRole: capturedRole)
            }
            await vm.updateMemberPhone(
                memberId: capturedMemberId,
                country: capturedPhoneCountry,
                localPhone: capturedPhone
            )
            await vm.updateMemberFather(memberId: capturedMemberId, fatherId: capturedFatherId)
            await vm.updateMemberHealthAndBirth(
                memberId: capturedMemberId,
                birthDate: capturedBirthDate,
                isDeceased: capturedIsDeceased,
                deathDate: capturedDeathDate
            )

            if !capturedChildren.isEmpty {
                var updatedChildren = capturedChildren
                for i in 0..<updatedChildren.count {
                    updatedChildren[i].sortOrder = i
                }
                await vm.updateChildrenOrder(for: capturedMemberId, newOrder: updatedChildren)
            }
        }
    }
}

// MARK: - واجهة اختيار الأب
struct FatherPickerSheet: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Binding var selectedId: UUID?
    @Environment(\.dismiss) var dismiss
    @State private var searchText = ""

    var filteredMembers: [FamilyMember] {
        let sorted = authVM.allMembers.sorted { $0.fullName < $1.fullName }
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
                                selectedId = nil
                                dismiss()
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
                                .padding(.vertical, DS.Spacing.sm)
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
                                        selectedId = m.id
                                        dismiss()
                                    } label: {
                                        HStack(spacing: DS.Spacing.sm) {
                                            // Avatar
                                            ZStack {
                                                Circle()
                                                    .fill(DS.Color.surface)
                                                    .frame(width: 34, height: 34)

                                                if let urlStr = m.avatarUrl, let url = URL(string: urlStr) {
                                                    AsyncImage(url: url) { img in img.resizable().scaledToFill() }
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
                                                    .font(DS.Font.caption2)
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
                                        .padding(.vertical, DS.Spacing.sm)
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
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        }
    }
}
