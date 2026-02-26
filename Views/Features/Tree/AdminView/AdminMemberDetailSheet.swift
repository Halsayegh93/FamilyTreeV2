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

    // البيانات الشخصية
    @State private var birthDate: Date
    @State private var hasBirthDate: Bool

    @State private var isDeceased: Bool
    @State private var deathDate: Date
    @State private var hasDeathDate: Bool

    // حالات ترتيب الأبناء
    @State private var localChildren: [FamilyMember] = []
    @State private var editMode: EditMode = .inactive

    @State private var showAddSonSheet = false
    @State private var showFatherPicker = false
    @State private var showDeleteConfirmation = false

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

                ScrollView(showsIndicators: false) {
                    VStack(spacing: DS.Spacing.md) {
                        compactMemberHeader

                        // تم دمج البيانات الأساسية داخل الهيدر العلوي
                        adminSection(title: "ربط العضو بالأب", icon: "person.2.fill", color: .orange) {
                            fatherLinkComponent
                        }

                        // قسم الأبناء المحدث
                        childrenSection

                        adminSection(title: L10n.t("تاريخ الميلاد", "Birth Date"), icon: "calendar", color: DS.Color.primary.opacity(0.8)) {
                            birthDateInput
                        }

                        adminSection(title: "تفعيل الهاتف", icon: "phone.fill", color: DS.Color.success) {
                            phoneInput
                        }

                        adminSection(title: "الحالة الصحية", icon: "heart.text.square.fill", color: DS.Color.error) {
                            deceasedStatusInput
                        }

                        if canManageAccessPermissions {
                            adminSection(title: "صلاحيات الوصول", icon: "shield.fill", color: DS.Color.accent) {
                                rolePicker
                            }
                        }

                        footerButtons

                        Spacer(minLength: 16)
                    }
                    .padding(.top, DS.Spacing.xs)
                }
            }
            .navigationTitle("إدارة السجل")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.t("إغلاق", "Close")) { dismiss() }
                        .font(DS.Font.caption1)
                        .foregroundColor(DS.Color.primary)
                }
            }
            .sheet(isPresented: $showFatherPicker) {
                FatherPickerSheet(selectedId: $selectedFatherId)
            }
            .sheet(isPresented: $showAddSonSheet) {
                AddSonByAdminSheet(parent: member)
            }
            .onAppear { setupLocalChildren() }
            .alert("حذف نهائي", isPresented: $showDeleteConfirmation) {
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

    // MARK: - المكونات الفرعية

    private var fullNameInput: some View {
        HStack {
            TextField(L10n.t("الاسم الكامل", "Full Name"), text: $fullName)
                .multilineTextAlignment(.leading)
                .font(DS.Font.caption1)
        }
        .padding(DS.Spacing.md)
        .background(DS.Color.surfaceElevated.opacity(0.5))
        .cornerRadius(DS.Radius.md)
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md)
                .stroke(DS.Color.primary.opacity(0.15), lineWidth: 1)
        )
    }

    private var birthDateInput: some View {
        VStack(spacing: DS.Spacing.md) {
            Toggle(isOn: $hasBirthDate.animation()) {
                HStack {
                    Text("تاريخ الميلاد معروف؟").font(DS.Font.caption1)
                    Spacer()
                }
            }
            .tint(DS.Color.primary)

            if hasBirthDate {
                DSDivider()
                HStack {
                    DatePicker("", selection: $birthDate, in: ...Date(), displayedComponents: .date)
                        .labelsHidden()
                        .environment(\.locale, Locale(identifier: "en_US"))
                    Spacer()
                    Text(L10n.t("اختر التاريخ", "Pick Date")).font(DS.Font.caption1).foregroundColor(DS.Color.textSecondary)
                }
            }
        }
        .padding(.vertical, DS.Spacing.xs)
    }

    private var deceasedStatusInput: some View {
        VStack(spacing: DS.Spacing.md) {
            Toggle(isOn: $isDeceased.animation()) {
                HStack {
                    Text("انتقل إلى رحمة الله (متوفى)").font(DS.Font.caption1)
                    Spacer()
                }
            }
            .tint(DS.Color.error)

            if isDeceased {
                DSDivider()
                Toggle(isOn: $hasDeathDate.animation()) {
                    HStack {
                        Text("تاريخ الوفاة معروف؟").font(DS.Font.caption1)
                        Spacer()
                    }
                }
                .tint(DS.Color.error)

                if hasDeathDate {
                    HStack {
                        DatePicker("", selection: $deathDate, in: ...Date(), displayedComponents: .date)
                            .labelsHidden()
                            .environment(\.locale, Locale(identifier: "en_US"))
                        Spacer()
                        Text("تاريخ الوفاة").font(DS.Font.caption1).foregroundColor(DS.Color.textSecondary)
                    }
                }
            }
        }
        .padding(.vertical, DS.Spacing.xs)
    }

    // MARK: - قسم الأبناء مع الترتيب اليدوي الصحيح
    private var childrenSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack {
                // زر الترتيب
                Button(action: {
                    withAnimation {
                        editMode = (editMode == .active) ? .inactive : .active
                    }
                }) {
                    HStack(spacing: DS.Spacing.xs) {
                        Image(systemName: editMode == .active ? "checkmark" : "arrow.up.arrow.down")
                        Text(editMode == .active ? "حفظ الترتيب" : "ترتيب")
                    }
                    .font(DS.Font.caption1)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, DS.Spacing.md).padding(.vertical, DS.Spacing.xs + 2)
                    .background(
                        editMode == .active
                            ? LinearGradient(colors: [DS.Color.success, DS.Color.success], startPoint: .leading, endPoint: .trailing)
                            : DS.Color.gradientPrimary
                    )
                    .cornerRadius(DS.Radius.sm)
                }

                // زر الإضافة
                Button(action: { showAddSonSheet = true }) {
                    Label(L10n.t("إضافة", "Add"), systemImage: "plus.circle.fill")
                        .font(DS.Font.caption1)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, DS.Spacing.md).padding(.vertical, DS.Spacing.xs + 2)
                        .background(DS.Color.gradientPrimary)
                        .cornerRadius(DS.Radius.sm)
                }

                Spacer()
                Text("قائمة الأبناء (\(localChildren.count))")
                    .font(DS.Font.caption1)
                    .fontWeight(.bold)
                    .foregroundColor(DS.Color.textSecondary)
            }
            .padding(.horizontal, DS.Spacing.lg)

            // القائمة القابلة للسحب
            VStack(spacing: 0) {
                if localChildren.isEmpty {
                    Text("لا يوجد أبناء حالياً")
                        .font(DS.Font.caption1)
                        .foregroundColor(DS.Color.textSecondary)
                        .padding()
                        .frame(maxWidth: .infinity)
                } else {
                    List {
                        ForEach(localChildren, id: \.id) { child in
                            HStack {
                                Text(child.firstName)
                                    .font(DS.Font.caption1)

                                Spacer()
                            }
                            .listRowBackground(DS.Color.surface)
                        }
                        .onMove(perform: moveChild)
                    }
                    .listStyle(.plain)
                    .scrollDisabled(true)
                    .frame(height: CGFloat(max(localChildren.count * 44, 44)))
                    .environment(\.editMode, $editMode)
                }
            }
            .background(DS.Color.surface)
            .cornerRadius(DS.Radius.lg)
            .dsCardShadow()
            .padding(.horizontal, DS.Spacing.md)
        }
    }

    private var compactMemberHeader: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.xs + 2) {
                Image(systemName: "person.text.rectangle")
                    .foregroundColor(.white)
                    .font(.system(size: 10))
                    .frame(width: 22, height: 22)
                    .background(
                        LinearGradient(
                            colors: [DS.Color.primary, DS.Color.accent],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(Circle())
                Text(L10n.t("البيانات الأساسية", "Basic Information"))
                    .font(DS.Font.caption1)
                    .fontWeight(.bold)
                    .foregroundColor(DS.Color.textSecondary)
                Spacer()
            }
            .padding(.horizontal, DS.Spacing.lg)

            DSCard {
                VStack(alignment: .leading, spacing: DS.Spacing.md) {
                    HStack(spacing: DS.Spacing.md) {
                        Circle()
                            .fill(DS.Color.gradientPrimary)
                            .frame(width: 45, height: 45)
                            .overlay(
                                Text(fullName.prefix(1))
                                    .font(DS.Font.caption1)
                                    .foregroundColor(.white)
                            )
                            .dsGlowShadow()
                            .offset(x: 1)

                        VStack(alignment: .trailing, spacing: 2) {
                            Text(fullName)
                                .font(DS.Font.caption1)
                            Text("تعديل البيانات والصلاحيات")
                                .font(DS.Font.caption1)
                                .foregroundColor(DS.Color.textSecondary)
                        }
                        Spacer()
                    }

                    fullNameInput
                }
                .padding(DS.Spacing.sm)
            }
            .padding(.horizontal, DS.Spacing.md)
        }
    }

    private var fatherLinkComponent: some View {
        HStack {
            Button(action: { showFatherPicker = true }) {
                Text("تغيير")
                    .font(DS.Font.caption1)
                    .fontWeight(.bold)
                    .foregroundColor(DS.Color.primary)
            }
            Spacer()
            if let fId = selectedFatherId, let father = authVM.allMembers.first(where: { $0.id == fId }) {
                Text(father.fullName).font(DS.Font.caption1).fontWeight(.bold)
            } else {
                Text("رأس شجرة (غير مرتبط)").font(DS.Font.caption1).foregroundColor(DS.Color.textSecondary)
            }
        }
        .padding(DS.Spacing.sm)
        .background(DS.Color.surfaceElevated.opacity(0.5))
        .cornerRadius(DS.Radius.md)
    }

    private var phoneInput: some View {
        HStack {
            Menu {
                ForEach(KuwaitPhone.supportedCountries) { country in
                    Button {
                        selectedPhoneCountry = country
                    } label: {
                        Text("\(country.flag) \(country.nameArabic) \(country.dialingCode)")
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(selectedPhoneCountry.flag)
                    Text(selectedPhoneCountry.dialingCode)
                        .font(DS.Font.caption1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundColor(DS.Color.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(DS.Color.surface)
                .cornerRadius(DS.Radius.sm)
            }

            TextField(L10n.t("رقم الهاتف", "Phone Number"), text: $phoneNumber)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.leading)
                .font(DS.Font.caption1)
        }
        .onChange(of: phoneNumber) { _, newValue in
            phoneNumber = KuwaitPhone.userTypedDigits(newValue, maxDigits: selectedPhoneCountry.maxDigits)
        }
        .onChange(of: selectedPhoneCountry) { _, newCountry in
            phoneNumber = KuwaitPhone.userTypedDigits(phoneNumber, maxDigits: newCountry.maxDigits)
        }
        .environment(\.layoutDirection, .leftToRight)
        .padding(DS.Spacing.sm)
        .background(DS.Color.surfaceElevated.opacity(0.5))
        .cornerRadius(DS.Radius.md)
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md)
                .stroke(DS.Color.primary.opacity(0.15), lineWidth: 1)
        )
    }

    private var rolePicker: some View {
        Picker("الرتبة", selection: $selectedRole) {
            Text(L10n.t("الإدارة", "Admin")).tag(FamilyMember.UserRole.admin)
            Text(L10n.t("مشرف", "Supervisor")).tag(FamilyMember.UserRole.supervisor)
            Text(L10n.t("عضو", "Member")).tag(FamilyMember.UserRole.member)
        }
        .pickerStyle(.segmented)
        .tint(DS.Color.primary)
    }

    private var footerButtons: some View {
        VStack(spacing: DS.Spacing.md) {
            DSPrimaryButton(
                L10n.t("حفظ التغييرات", "Save Changes"),
                isLoading: authVM.isLoading,
                action: saveAction
            )

            if canManageAccessPermissions {
                Button("حذف السجل") { showDeleteConfirmation = true }
                    .font(DS.Font.caption1)
                    .fontWeight(.bold)
                    .foregroundColor(DS.Color.error)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(DS.Color.error.opacity(0.06))
                    .cornerRadius(DS.Radius.md)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.md)
                            .stroke(DS.Color.error.opacity(0.2), lineWidth: 1)
                    )
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.top, DS.Spacing.sm)
    }

    private func adminSection<Content: View>(title: String, icon: String, color: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.xs + 2) {
                Image(systemName: icon)
                    .foregroundColor(.white)
                    .font(.system(size: 10))
                    .frame(width: 22, height: 22)
                    .background(
                        LinearGradient(
                            colors: [DS.Color.primary, DS.Color.accent],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(Circle())
                Text(title)
                    .font(DS.Font.caption1)
                    .fontWeight(.bold)
                    .foregroundColor(DS.Color.textSecondary)
                Spacer()
            }
            .padding(.horizontal, DS.Spacing.lg)

            DSCard {
                VStack { content() }
                    .padding(DS.Spacing.sm)
            }
            .padding(.horizontal, DS.Spacing.md)
        }
    }

    private func setupLocalChildren() {
        localChildren = authVM.allMembers
            .filter { $0.fatherId == member.id }
            .sorted(by: { ($0.sortOrder ?? 0) < ($1.sortOrder ?? 0) })
    }

    // دالة التحريك وتحديث الترتيب محلياً
    private func moveChild(from source: IndexSet, to destination: Int) {
        localChildren.move(fromOffsets: source, toOffset: destination)
    }

    private func saveAction() {
        Task {
            let finalBirthDate = hasBirthDate ? birthDate : nil
            let finalDeathDate = (isDeceased && hasDeathDate) ? deathDate : nil

            await authVM.updateMemberName(memberId: member.id, fullName: fullName)
            if canManageAccessPermissions {
                await authVM.updateMemberRole(memberId: member.id, newRole: selectedRole)
            }
            await authVM.updateMemberPhone(
                memberId: member.id,
                country: selectedPhoneCountry,
                localPhone: phoneNumber
            )
            await authVM.updateMemberFather(memberId: member.id, fatherId: selectedFatherId)

            await authVM.updateMemberHealthAndBirth(
                memberId: member.id,
                birthDate: finalBirthDate,
                isDeceased: isDeceased,
                deathDate: finalDeathDate
            )

            // تحديث أرقام الترتيب (sortOrder) قبل الإرسال للقاعدة
            if !localChildren.isEmpty {
                var updatedChildren = localChildren
                for i in 0..<updatedChildren.count {
                    updatedChildren[i].sortOrder = i
                }

                await authVM.updateChildrenOrder(for: member.id, newOrder: updatedChildren)
            }

            dismiss()
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
        if searchText.isEmpty { return authVM.allMembers.sorted { $0.fullName < $1.fullName } }
        return authVM.allMembers.filter { $0.fullName.contains(searchText) }
    }

    var body: some View {
        NavigationStack {
            List(filteredMembers) { m in
                Button {
                    selectedId = m.id
                    dismiss()
                } label: {
                    HStack {
                        if selectedId == m.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(DS.Color.gradientPrimary)
                        }
                        Spacer()
                        VStack(alignment: .leading) {
                            Text(m.fullName).font(DS.Font.caption1)
                            Text(m.roleName).font(DS.Font.caption1).foregroundColor(DS.Color.textSecondary)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("اختر الأب")
            .searchable(text: $searchText, prompt: "ابحث عن اسم...")
            .tint(DS.Color.primary)
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        }
    }
}
