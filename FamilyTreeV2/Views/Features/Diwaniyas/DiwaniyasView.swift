import SwiftUI


// MARK: - DiwaniyasView
struct DiwaniyasView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @StateObject private var viewModel = DiwaniyasViewModel()
    @Binding var selectedTab: Int
    @State private var showingNotifications = false
    @State private var showingAddRequest = false
    @State private var diwaniyaToEdit: Diwaniya? = nil
    @State private var diwaniyaToDelete: Diwaniya? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()

                DSDecorativeBackground()

                VStack(spacing: 0) {
                    MainHeaderView(
                        selectedTab: $selectedTab,
                        showingNotifications: $showingNotifications,
                        title: L10n.t("الديوانيات", "Diwaniyas"),
                        icon: "map.fill"
                    ) {
                        Button(action: { showingAddRequest = true }) {
                            Image(systemName: "plus")
                                .font(DS.Font.scaled(16, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 44, height: 44)
                                .background(Color.white.opacity(0.15))
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1.5))
                        }
                    }

                    if viewModel.isLoading && viewModel.diwaniyas.isEmpty {
                        Spacer()
                        ProgressView(L10n.t("جاري التحميل...", "Loading..."))
                        Spacer()
                    } else if viewModel.diwaniyas.isEmpty {
                        emptyStateView
                    } else {
                        ScrollView(showsIndicators: false) {
                            LazyVStack(spacing: DS.Spacing.md) {
                                ForEach(viewModel.diwaniyas) { diwaniya in
                                    diwaniyaCard(for: diwaniya)
                                }
                            }
                            .padding(DS.Spacing.lg)
                            .padding(.bottom, DS.Spacing.xxxl)
                        }
                        .refreshable {
                            await viewModel.fetchDiwaniyas()
                        }
                    }
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showingAddRequest) {
                AddDiwaniyaRequestView()
                    .environmentObject(viewModel)
                    .environmentObject(authVM)
            }
            .sheet(item: $diwaniyaToEdit) { diwaniya in
                EditDiwaniyaView(diwaniya: diwaniya)
                    .environmentObject(viewModel)
                    .environmentObject(authVM)
            }
            .alert(
                L10n.t("حذف الديوانية", "Delete Diwaniya"),
                isPresented: .init(
                    get: { diwaniyaToDelete != nil },
                    set: { if !$0 { diwaniyaToDelete = nil } }
                )
            ) {
                Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {
                    diwaniyaToDelete = nil
                }
                Button(L10n.t("حذف", "Delete"), role: .destructive) {
                    if let d = diwaniyaToDelete {
                        Task { await viewModel.deleteDiwaniya(id: d.id) }
                        diwaniyaToDelete = nil
                    }
                }
            } message: {
                Text(L10n.t(
                    "هل أنت متأكد من حذف \"\(diwaniyaToDelete?.title ?? "")\"؟",
                    "Are you sure you want to delete \"\(diwaniyaToDelete?.title ?? "")\"?"
                ))
            }
            .task { await viewModel.fetchDiwaniyas() }
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
            .alert(L10n.t("خطأ", "Error"), isPresented: .init(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button(L10n.t("حسناً", "OK"), role: .cancel) { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }



    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: DS.Spacing.xl) {
            Spacer()
            ZStack {
                Circle()
                    .fill(DS.Color.gridDiwaniya.opacity(0.10))
                    .frame(width: 120, height: 120)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                DS.Color.gridDiwaniya.opacity(0.20),
                                DS.Color.primary.opacity(0.10)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 96, height: 96)

                Image(systemName: "mappin.slash")
                    .font(DS.Font.scaled(40, weight: .bold))
                    .foregroundColor(DS.Color.gridDiwaniya)
            }

            VStack(spacing: DS.Spacing.sm) {
                Text(L10n.t("لا توجد ديوانيات مضافة", "No diwaniyas added yet"))
                    .font(DS.Font.title3)
                    .fontWeight(.black)
                    .foregroundColor(DS.Color.textPrimary)
                Text(L10n.t("اضغط + لإضافة ديوانية جديدة", "Tap + to add a new diwaniya"))
                    .font(DS.Font.callout)
                    .foregroundColor(DS.Color.textSecondary)
            }
            Spacer()
        }
    }

    // MARK: - Diwaniya Card
    private func diwaniyaCard(for item: Diwaniya) -> some View {
        let isClosed = item.isClosed == true
        let cardColor = isClosed ? DS.Color.textTertiary : DS.Color.gridDiwaniya
        
        return DSCard(padding: 0) {
            VStack(spacing: 0) {
                // شريط علوي ملون
                HStack(spacing: DS.Spacing.md) {
                    // أيقونة بتدرج
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: isClosed
                                        ? [DS.Color.textTertiary.opacity(0.3), DS.Color.textTertiary.opacity(0.1)]
                                        : [DS.Color.gridDiwaniya.opacity(0.2), DS.Color.primary.opacity(0.1)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 48, height: 48)
                        Image(systemName: item.imageUrl ?? "map.fill")
                            .font(DS.Font.scaled(20, weight: .bold))
                            .foregroundColor(cardColor)
                    }

                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                        HStack(spacing: DS.Spacing.sm) {
                            Text(item.title)
                                .font(DS.Font.headline)
                                .foregroundColor(isClosed ? DS.Color.textTertiary : DS.Color.textPrimary)

                            if isClosed {
                                HStack(spacing: 3) {
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 8))
                                    Text(L10n.t("مغلقة", "Closed"))
                                        .font(DS.Font.scaled(10, weight: .bold))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, DS.Spacing.sm)
                                .padding(.vertical, DS.Spacing.xs)
                                .background(DS.Color.error.opacity(0.8))
                                .clipShape(Capsule())
                            }
                        }
                        HStack(spacing: DS.Spacing.xs) {
                            Image(systemName: "person.fill")
                                .font(.system(size: 10))
                                .foregroundColor(DS.Color.textTertiary)
                            Text(item.ownerName)
                                .font(DS.Font.caption1)
                                .foregroundColor(DS.Color.textSecondary)
                        }
                    }

                    Spacer()

                    if authVM.currentUser?.role == .admin || authVM.currentUser?.id == item.ownerId {
                        Menu {
                            Button(action: { diwaniyaToEdit = item }) {
                                Label(L10n.t("تعديل", "Edit"), systemImage: "pencil")
                            }
                            Button(role: .destructive, action: { diwaniyaToDelete = item }) {
                                Label(L10n.t("حذف", "Delete"), systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(DS.Font.scaled(16, weight: .bold))
                                .foregroundColor(DS.Color.textSecondary)
                                .frame(width: 36, height: 36)
                                .background(DS.Color.textTertiary.opacity(0.08))
                                .clipShape(Circle())
                        }
                    }
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.md)

                // معلومات مدمجة في شبكة
                let infoItems = buildDiwaniyaInfoItems(item)
                if !infoItems.isEmpty {
                    DSDivider()
                    VStack(spacing: 0) {
                        ForEach(Array(infoItems.enumerated()), id: \.offset) { index, info in
                            HStack(spacing: DS.Spacing.md) {
                                Image(systemName: info.icon)
                                    .font(DS.Font.scaled(13, weight: .semibold))
                                    .foregroundColor(info.color)
                                    .frame(width: 20)
                                Text(info.text)
                                    .font(DS.Font.callout)
                                    .foregroundColor(DS.Color.textPrimary)
                                    .lineLimit(2)
                                Spacer()
                            }
                            .padding(.horizontal, DS.Spacing.lg)
                            .padding(.vertical, DS.Spacing.sm)
                            
                            if index < infoItems.count - 1 {
                                Divider().padding(.horizontal, DS.Spacing.xxxl)
                            }
                        }
                    }
                }

                // أزرار الإجراءات
                let hasLocation = item.mapsUrl?.isEmpty == false
                let hasPhone = item.contactPhone?.isEmpty == false
                if hasLocation || hasPhone {
                    DSDivider()
                    HStack(spacing: DS.Spacing.md) {
                        if let mapsStr = item.mapsUrl, !mapsStr.isEmpty, let url = URL(string: mapsStr) {
                            Button(action: { UIApplication.shared.open(url) }) {
                                HStack(spacing: DS.Spacing.xs) {
                                    Image(systemName: "location.fill")
                                    Text(L10n.t("الموقع", "Location"))
                                }
                                .font(DS.Font.caption1)
                                .fontWeight(.bold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, DS.Spacing.sm + 4)
                                .foregroundColor(.white)
                                .background(DS.Color.gradientPrimary)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(DSBoldButtonStyle())
                        }

                        if let phone = item.contactPhone, !phone.isEmpty, let callURL = KuwaitPhone.telURL(phone) {
                            Button(action: { UIApplication.shared.open(callURL) }) {
                                HStack(spacing: DS.Spacing.xs) {
                                    Image(systemName: "phone.fill")
                                    Text(L10n.t("اتصال", "Call"))
                                }
                                .font(DS.Font.caption1)
                                .fontWeight(.bold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, DS.Spacing.sm + 4)
                                .foregroundColor(DS.Color.success)
                                .background(DS.Color.success.opacity(0.08))
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(DS.Color.success.opacity(0.3), lineWidth: 1))
                            }
                            .buttonStyle(DSBoldButtonStyle())
                        }
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.vertical, DS.Spacing.md)
                }
            }
        }
    }
    
    private struct DiwaniyaInfoItem {
        let icon: String
        let color: Color
        let text: String
    }
    
    private func buildDiwaniyaInfoItems(_ item: Diwaniya) -> [DiwaniyaInfoItem] {
        var items: [DiwaniyaInfoItem] = []
        if let schedule = item.scheduleText, !schedule.isEmpty {
            items.append(DiwaniyaInfoItem(icon: "clock.fill", color: DS.Color.warning, text: schedule))
        }
        if let addr = item.address, !addr.isEmpty {
            items.append(DiwaniyaInfoItem(icon: "mappin.and.ellipse", color: DS.Color.accent, text: addr))
        }
        if let phone = item.contactPhone, !phone.isEmpty {
            items.append(DiwaniyaInfoItem(icon: "phone.fill", color: DS.Color.success, text: KuwaitPhone.display(phone)))
        }
        return items
    }
}

// MARK: - Add Diwaniya Request View
private struct AddDiwaniyaRequestView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var viewModel: DiwaniyasViewModel
    @EnvironmentObject var authVM: AuthViewModel

    @State private var name = ""
    @State private var ownerName = ""
    @State private var selectedDays: Set<Int> = []
    @State private var phoneNumber = ""
    @State private var locationURL = ""
    @State private var address = ""
    @State private var isSubmitting = false
    @State private var showError = false

    // Days of the week (Saturday-first for Arabic locale)
    private let weekDays: [(id: Int, ar: String, en: String)] = [
        (0, "السبت", "Saturday"),
        (1, "الأحد", "Sunday"),
        (2, "الإثنين", "Monday"),
        (3, "الثلاثاء", "Tuesday"),
        (4, "الأربعاء", "Wednesday"),
        (5, "الخميس", "Thursday"),
        (6, "الجمعة", "Friday"),
    ]

    private var isFormValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !ownerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Build schedule text from selected days
    private var scheduleText: String {
        let sorted = selectedDays.sorted()
        return sorted.map { id in
            let day = weekDays.first { $0.id == id }
            return L10n.t(day?.ar ?? "", day?.en ?? "")
        }.joined(separator: "، ")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()

                DSDecorativeBackground()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: DS.Spacing.xxl) {

                        // Header icon
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [DS.Color.gridDiwaniya.opacity(0.20), DS.Color.primary.opacity(0.10)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 80, height: 80)
                            Image(systemName: "map.fill")
                                .font(DS.Font.scaled(32, weight: .bold))
                                .foregroundColor(DS.Color.gridDiwaniya)
                        }
                        .padding(.top, DS.Spacing.lg)

                        // Basic info section
                            DSCard(padding: 0) {
                                DSSectionHeader(
                                    title: L10n.t("بيانات الديوانية", "Diwaniya Info"),
                                    icon: "info.circle.fill"
                                )

                                formField(
                                    icon: "building.columns.fill",
                                    iconColors: [DS.Color.gridDiwaniya, DS.Color.primary],
                                    placeholder: L10n.t("اسم الديوانية", "Diwaniya Name"),
                                    text: $name
                                )
                                .onChange(of: name) {
                                    if name.count > 100 {
                                        name = String(name.prefix(100))
                                    }
                                }

                                DSDivider()

                                formField(
                                    icon: "person.fill",
                                    iconColors: [DS.Color.primary, DS.Color.accent],
                                    placeholder: L10n.t("صاحب الديوانية", "Diwaniya Owner"),
                                    text: $ownerName
                                )
                                .onChange(of: ownerName) {
                                    if ownerName.count > 100 {
                                        ownerName = String(ownerName.prefix(100))
                                    }
                                }

                                DSDivider()

                                // Schedule dropdown
                                HStack(spacing: DS.Spacing.md) {
                                    DSIcon("clock.fill", color: DS.Color.warning)

                                    Menu {
                                        ForEach(weekDays, id: \.id) { day in
                                            Button {
                                                if selectedDays.contains(day.id) {
                                                    selectedDays.remove(day.id)
                                                } else {
                                                    selectedDays.insert(day.id)
                                                }
                                            } label: {
                                                HStack {
                                                    Text(L10n.t(day.ar, day.en))
                                                    if selectedDays.contains(day.id) {
                                                        Image(systemName: "checkmark")
                                                    }
                                                }
                                            }
                                        }
                                    } label: {
                                        HStack {
                                            Text(selectedDays.isEmpty
                                                ? L10n.t("مواعيد الديوانية (اختياري)", "Schedule (optional)")
                                                : scheduleText)
                                                .font(DS.Font.body)
                                                .foregroundColor(selectedDays.isEmpty ? DS.Color.textTertiary : DS.Color.textPrimary)
                                                .lineLimit(1)

                                            Spacer()

                                            Image(systemName: "chevron.up.chevron.down")
                                                .font(DS.Font.caption1)
                                                .foregroundColor(DS.Color.textTertiary)
                                        }
                                    }
                                }
                                .padding(.horizontal, DS.Spacing.lg)
                                .padding(.vertical, DS.Spacing.md)

                                DSDivider()

                                formField(
                                    icon: "phone.fill",
                                    iconColors: [DS.Color.success, DS.Color.success],
                                    placeholder: L10n.t("رقم الهاتف", "Phone Number"),
                                    text: $phoneNumber,
                                    keyboard: .phonePad
                                )

                                DSDivider()

                                formField(
                                    icon: "mappin.and.ellipse",
                                    iconColors: [DS.Color.accent, DS.Color.primary],
                                    placeholder: L10n.t("عنوان الديوانية (اختياري)", "Address (optional)"),
                                    text: $address
                                )

                                DSDivider()

                                formField(
                                    icon: "link",
                                    iconColors: [DS.Color.info, DS.Color.primary],
                                    placeholder: L10n.t("رابط موقع الديوانية (اختياري)", "Map URL (optional)"),
                                    text: $locationURL,
                                    keyboard: .URL
                                )
                            }
                            .padding(.horizontal, DS.Spacing.lg)

                        // Review note
                        HStack(spacing: DS.Spacing.sm) {
                            Image(systemName: "info.circle.fill")
                                .font(DS.Font.scaled(14))
                                .foregroundColor(DS.Color.gridDiwaniya)
                            Text(L10n.t(
                                "سيتم إضافة الديوانية بعد الموافقة.",
                                "Added upon approval."
                            ))
                            .font(DS.Font.footnote)
                            .foregroundColor(DS.Color.textSecondary)
                        }
                        .padding(.horizontal, DS.Spacing.lg)

                        // Submit button
                        DSPrimaryButton(
                            isSubmitting ? L10n.t("جاري الإرسال...", "Submitting...") : L10n.t("إضافة", "Add"),
                            icon: "paperplane.fill",
                            useGradient: false,
                            color: DS.Color.gridDiwaniya
                        ) {
                            Task { await submitDiwaniya() }
                        }
                        .disabled(!isFormValid || isSubmitting)
                        .opacity(isFormValid ? 1.0 : 0.5)
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.bottom, DS.Spacing.xxxl)
                    }
                }
            }
            .navigationTitle(L10n.t("إضافة ديوانية", "Add Diwaniya"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.t("إلغاء", "Cancel")) {
                        dismiss()
                    }
                    .foregroundColor(DS.Color.error)
                }
            }
            .alert(L10n.t("خطأ", "Error"), isPresented: $showError) {} message: {
                Text(viewModel.errorMessage ?? L10n.t("فشل إضافة الديوانية", "Failed to add diwaniya."))
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    private func submitDiwaniya() async {
        guard let user = authVM.currentUser else { return }
        isSubmitting = true
        let trimmedURL = locationURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let success = await viewModel.addDiwaniya(
            ownerId: user.id,
            ownerName: ownerName,
            title: name,
            scheduleText: selectedDays.isEmpty ? nil : scheduleText,
            contactPhone: phoneNumber,
            mapsUrl: trimmedURL.isEmpty ? nil : trimmedURL,
            address: trimmedAddress.isEmpty ? nil : trimmedAddress
        )
        isSubmitting = false
        if success {
            dismiss()
        } else {
            showError = true
        }
    }

    // MARK: - Form Field Helper
    private func formField(
        icon: String,
        iconColors: [Color],
        placeholder: String,
        text: Binding<String>,
        keyboard: UIKeyboardType = .default
    ) -> some View {
        HStack(spacing: DS.Spacing.md) {
            DSIcon(icon, color: iconColors.first ?? DS.Color.primary)

            TextField(placeholder, text: text)
                .font(DS.Font.body)
                .foregroundColor(DS.Color.textPrimary)
                .multilineTextAlignment(.leading)
                .keyboardType(keyboard)
                .textInputAutocapitalization(keyboard == .URL ? .never : .words)
                .autocorrectionDisabled(keyboard == .URL || keyboard == .phonePad)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.md)
    }
}

// MARK: - Edit Diwaniya View
private struct EditDiwaniyaView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var viewModel: DiwaniyasViewModel
    @EnvironmentObject var authVM: AuthViewModel

    let diwaniya: Diwaniya

    @State private var name: String
    @State private var ownerName: String
    @State private var selectedDays: Set<Int>
    @State private var phoneNumber: String
    @State private var locationURL: String
    @State private var address: String
    @State private var isClosed: Bool
    @State private var isSubmitting = false
    @State private var showError = false

    private let weekDays: [(id: Int, ar: String, en: String)] = [
        (0, "السبت", "Saturday"),
        (1, "الأحد", "Sunday"),
        (2, "الإثنين", "Monday"),
        (3, "الثلاثاء", "Tuesday"),
        (4, "الأربعاء", "Wednesday"),
        (5, "الخميس", "Thursday"),
        (6, "الجمعة", "Friday"),
    ]

    init(diwaniya: Diwaniya) {
        self.diwaniya = diwaniya
        _name = State(initialValue: diwaniya.title)
        _ownerName = State(initialValue: diwaniya.ownerName)
        _phoneNumber = State(initialValue: diwaniya.contactPhone ?? "")
        _locationURL = State(initialValue: diwaniya.mapsUrl ?? "")
        _address = State(initialValue: diwaniya.address ?? "")
        _isClosed = State(initialValue: diwaniya.isClosed ?? false)

        // Parse existing schedule text back into selected days
        var days = Set<Int>()
        if let schedule = diwaniya.scheduleText {
            let allDays: [(id: Int, ar: String, en: String)] = [
                (0, "السبت", "Saturday"),
                (1, "الأحد", "Sunday"),
                (2, "الإثنين", "Monday"),
                (3, "الثلاثاء", "Tuesday"),
                (4, "الأربعاء", "Wednesday"),
                (5, "الخميس", "Thursday"),
                (6, "الجمعة", "Friday"),
            ]
            for day in allDays {
                if schedule.contains(day.ar) || schedule.contains(day.en) {
                    days.insert(day.id)
                }
            }
        }
        _selectedDays = State(initialValue: days)
    }

    private var isFormValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !ownerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var scheduleText: String {
        let sorted = selectedDays.sorted()
        return sorted.map { id in
            let day = weekDays.first { $0.id == id }
            return L10n.t(day?.ar ?? "", day?.en ?? "")
        }.joined(separator: "، ")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()
                DSDecorativeBackground()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: DS.Spacing.xxl) {

                        // Header icon
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [DS.Color.gridDiwaniya.opacity(0.20), DS.Color.primary.opacity(0.10)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 80, height: 80)
                            Image(systemName: "pencil.circle.fill")
                                .font(DS.Font.scaled(32, weight: .bold))
                                .foregroundColor(DS.Color.gridDiwaniya)
                        }
                        .padding(.top, DS.Spacing.lg)

                        // Basic info section
                        DSCard(padding: 0) {
                            DSSectionHeader(
                                title: L10n.t("بيانات الديوانية", "Diwaniya Info"),
                                icon: "info.circle.fill"
                            )

                            formField(
                                icon: "building.columns.fill",
                                iconColors: [DS.Color.gridDiwaniya, DS.Color.primary],
                                placeholder: L10n.t("اسم الديوانية", "Diwaniya Name"),
                                text: $name
                            )

                            DSDivider()

                            formField(
                                icon: "person.fill",
                                iconColors: [DS.Color.primary, DS.Color.accent],
                                placeholder: L10n.t("صاحب الديوانية", "Diwaniya Owner"),
                                text: $ownerName
                            )

                            DSDivider()

                            // Schedule dropdown
                            HStack(spacing: DS.Spacing.md) {
                                DSIcon("clock.fill", color: DS.Color.warning)

                                Menu {
                                    ForEach(weekDays, id: \.id) { day in
                                        Button {
                                            if selectedDays.contains(day.id) {
                                                selectedDays.remove(day.id)
                                            } else {
                                                selectedDays.insert(day.id)
                                            }
                                        } label: {
                                            HStack {
                                                Text(L10n.t(day.ar, day.en))
                                                if selectedDays.contains(day.id) {
                                                    Image(systemName: "checkmark")
                                                }
                                            }
                                        }
                                    }
                                } label: {
                                    HStack {
                                        Text(selectedDays.isEmpty
                                            ? L10n.t("مواعيد الديوانية (اختياري)", "Schedule (optional)")
                                            : scheduleText)
                                            .font(DS.Font.body)
                                            .foregroundColor(selectedDays.isEmpty ? DS.Color.textTertiary : DS.Color.textPrimary)
                                            .lineLimit(1)

                                        Spacer()

                                        Image(systemName: "chevron.up.chevron.down")
                                            .font(DS.Font.caption1)
                                            .foregroundColor(DS.Color.textTertiary)
                                    }
                                }
                            }
                            .padding(.horizontal, DS.Spacing.lg)
                            .padding(.vertical, DS.Spacing.md)

                            DSDivider()

                            formField(
                                icon: "phone.fill",
                                iconColors: [DS.Color.success, DS.Color.success],
                                placeholder: L10n.t("رقم الهاتف", "Phone Number"),
                                text: $phoneNumber,
                                keyboard: .phonePad
                            )

                            DSDivider()

                            formField(
                                icon: "mappin.and.ellipse",
                                iconColors: [DS.Color.accent, DS.Color.primary],
                                placeholder: L10n.t("عنوان الديوانية (اختياري)", "Address (optional)"),
                                text: $address
                            )

                            DSDivider()

                            formField(
                                icon: "link",
                                iconColors: [DS.Color.info, DS.Color.primary],
                                placeholder: L10n.t("رابط موقع الديوانية (اختياري)", "Map URL (optional)"),
                                text: $locationURL,
                                keyboard: .URL
                            )

                            DSDivider()

                            // Closed toggle
                            HStack(spacing: DS.Spacing.md) {
                                DSIcon(isClosed ? "lock.fill" : "lock.open.fill", color: isClosed ? DS.Color.error : DS.Color.success)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(L10n.t("الديوانية مغلقة", "Diwaniya Closed"))
                                        .font(DS.Font.callout)
                                        .foregroundColor(DS.Color.textPrimary)
                                    Text(L10n.t(
                                        isClosed ? "الديوانية متوقفة حالياً" : "الديوانية مفتوحة ونشطة",
                                        isClosed ? "Currently inactive" : "Open and active"
                                    ))
                                    .font(DS.Font.caption1)
                                    .foregroundColor(DS.Color.textSecondary)
                                }

                                Spacer()

                                Toggle("", isOn: $isClosed)
                                    .tint(DS.Color.error)
                                    .labelsHidden()
                            }
                            .padding(.horizontal, DS.Spacing.lg)
                            .padding(.vertical, DS.Spacing.md)
                        }
                        .padding(.horizontal, DS.Spacing.lg)

                        // Save button
                        DSPrimaryButton(
                            isSubmitting ? L10n.t("جاري الحفظ...", "Saving...") : L10n.t("حفظ التعديلات", "Save Changes"),
                            icon: "checkmark.circle.fill",
                            useGradient: false,
                            color: DS.Color.gridDiwaniya
                        ) {
                            Task { await saveChanges() }
                        }
                        .disabled(!isFormValid || isSubmitting)
                        .opacity(isFormValid ? 1.0 : 0.5)
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.bottom, DS.Spacing.xxxl)
                    }
                }
            }
            .navigationTitle(L10n.t("تعديل الديوانية", "Edit Diwaniya"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.t("إلغاء", "Cancel")) {
                        dismiss()
                    }
                    .foregroundColor(DS.Color.error)
                }
            }
            .alert(L10n.t("خطأ", "Error"), isPresented: $showError) {} message: {
                Text(viewModel.errorMessage ?? L10n.t("فشل تحديث الديوانية", "Failed to update diwaniya."))
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    private func saveChanges() async {
        isSubmitting = true
        let trimmedURL = locationURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let success = await viewModel.updateDiwaniya(
            id: diwaniya.id,
            title: name,
            ownerName: ownerName,
            scheduleText: selectedDays.isEmpty ? nil : scheduleText,
            contactPhone: phoneNumber.isEmpty ? nil : phoneNumber,
            mapsUrl: trimmedURL.isEmpty ? nil : trimmedURL,
            address: trimmedAddress.isEmpty ? nil : trimmedAddress,
            isClosed: isClosed
        )
        isSubmitting = false
        if success {
            dismiss()
        } else {
            showError = true
        }
    }

    // MARK: - Form Field Helper
    private func formField(
        icon: String,
        iconColors: [Color],
        placeholder: String,
        text: Binding<String>,
        keyboard: UIKeyboardType = .default
    ) -> some View {
        HStack(spacing: DS.Spacing.md) {
            DSIcon(icon, color: iconColors.first ?? DS.Color.primary)

            TextField(placeholder, text: text)
                .font(DS.Font.body)
                .foregroundColor(DS.Color.textPrimary)
                .multilineTextAlignment(.leading)
                .keyboardType(keyboard)
                .textInputAutocapitalization(keyboard == .URL ? .never : .words)
                .autocorrectionDisabled(keyboard == .URL || keyboard == .phonePad)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.md)
    }
}
