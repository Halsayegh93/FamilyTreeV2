import SwiftUI

struct AdminNotificationsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @Environment(\.dismiss) var dismiss

    @State private var title = "عائلة المحمدعلي 🌿"
    @State private var bodyText = ""
    @State private var selectedMemberIds: Set<UUID> = []
    @State private var searchText = ""
    @State private var displayLimit = 20
    /// تصفية حسب دولة التسجيل (ISO) — nil = الكل
    @State private var countryFilter: String? = nil

    // جدولة الإرسال
    @State private var scheduleEnabled = false
    @State private var scheduledDate = Date().addingTimeInterval(3600)
    @State private var showScheduledSheet = false
    /// شاشة تحديد وقت الجدولة (منتقي الوقت + المجدولة الحالية)
    @State private var showScheduleComposer = false
    /// البحث مخفي خلف زر — يظهر عند الطلب
    @State private var showSearchField = false
    /// العنوان: قائمة جاهزة افتراضياً، ويمكن كتابة عنوان مخصّص
    @State private var useCustomTitle = false
    static let presetTitles = [
        "عائلة المحمدعلي 🌿",
        "إعلان من الإدارة",
        "تذكير",
        "دعوة",
        "تهنئة",
        "تنبيه مهم"
    ]
    @FocusState private var searchFocused: Bool
    @State private var showSendConfirm = false
    @State private var showSendError = false

    /// المستلمون المحتملون — بلا المعلّقين وبلا المتوفّين (طلب المالك):
    /// المتوفّى لا جهاز له ولا معنى لإرسال إشعار باسمه.
    private var activeMembers: [FamilyMember] {
        memberVM.allMembers
            .filter { $0.role != .pending && !($0.isDeceased ?? false) }
            .filter { m in
                guard let iso = countryFilter else { return true }
                // بلا رقم هاتف = بلا دولة معروفة (٩٨٪ من الأعضاء) فلا يدخل الشريحة
                let phone = (m.phoneNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !phone.isEmpty else { return false }
                return KuwaitPhone.detectCountryAndLocal(phone).country.isoCode == iso
            }
            .sorted { $0.fullName < $1.fullName }
    }

    /// الدول المتاحة للتصفية — فقط التي يوجد بها أعضاء فعلاً.
    private var availableCountries: [(country: KuwaitPhone.Country, count: Int)] {
        let base = memberVM.allMembers.filter { $0.role != .pending && !($0.isDeceased ?? false) }
        var counts: [String: Int] = [:]
        for m in base where !(m.phoneNumber ?? "").isEmpty {
            let iso = KuwaitPhone.detectCountryAndLocal(m.phoneNumber).country.isoCode
            counts[iso, default: 0] += 1
        }
        return KuwaitPhone.supportedCountries
            .compactMap { c in counts[c.isoCode].map { (c, $0) } }
            .sorted { $0.count > $1.count }
    }

    private var filteredMembers: [FamilyMember] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return activeMembers }
        return activeMembers.filter {
            $0.fullName.localizedCaseInsensitiveContains(trimmed) ||
            $0.firstName.localizedCaseInsensitiveContains(trimmed) ||
            ($0.phoneNumber ?? "").contains(trimmed)
        }
    }

    /// شريط تصفية حسب دولة التسجيل (رقم الهاتف) — طلب المالك.
    private var countryFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Spacing.sm) {
                countryChip(title: L10n.t("كل الدول", "All"), iso: nil, count: nil)
                ForEach(availableCountries, id: \.country.isoCode) { item in
                    countryChip(title: "\(item.country.flag) \(L10n.isArabic ? item.country.nameArabic : item.country.isoCode)",
                                iso: item.country.isoCode, count: item.count)
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
        }
    }

    private func countryChip(title: String, iso: String?, count: Int?) -> some View {
        let active = countryFilter == iso
        return Button {
            withAnimation(DS.Anim.snappy) {
                countryFilter = iso
                selectedMemberIds = []      // التحديد يخصّ الشريحة الحالية
            }
        } label: {
            HStack(spacing: 4) {
                Text(title).font(DS.Font.scaled(12, weight: .bold))
                if let count { Text("\(count)").font(DS.Font.scaled(11, weight: .heavy)).opacity(0.8) }
            }
            .foregroundColor(active ? DS.Color.textOnPrimary : DS.Color.textSecondary)
            .padding(.horizontal, DS.Spacing.md)
            .frame(height: 30)
            .background(Capsule().fill(active ? DS.Color.primary : DS.Color.surface))
            .overlay(Capsule().stroke(DS.Color.mutedBackground, lineWidth: active ? 0 : 1))
        }
        .buttonStyle(DSScaleButtonStyle())
    }

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            VStack(spacing: 0) {
                VStack(spacing: DS.Spacing.sm) {
                    // بانر الإشعارات المجدولة — يظهر فقط عند وجود إشعارات معلّقة
                    if !notificationVM.scheduledNotifications.isEmpty {
                        Button {
                            showScheduledSheet = true
                        } label: {
                            HStack(spacing: DS.Spacing.sm) {
                                Image(systemName: "clock.badge.fill")
                                    .font(DS.Font.scaled(16, weight: .semibold))
                                    .foregroundColor(DS.Color.warning)
                                Text(L10n.t(
                                    "\(notificationVM.scheduledNotifications.count) إشعار مجدول بانتظار الإرسال",
                                    "\(notificationVM.scheduledNotifications.count) scheduled — pending send"
                                ))
                                .font(DS.Font.calloutBold)
                                .foregroundColor(DS.Color.textPrimary)
                                .lineLimit(1)
                                Spacer()
                                Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                                    .font(DS.Font.scaled(12, weight: .bold))
                                    .foregroundColor(DS.Color.textTertiary)
                            }
                            .padding(DS.Spacing.md)
                            .background(DS.Color.warning.opacity(0.10))
                            .overlay(
                                RoundedRectangle(cornerRadius: DS.Radius.md)
                                    .stroke(DS.Color.warning.opacity(0.30), lineWidth: 1)
                            )
                            .cornerRadius(DS.Radius.md)
                        }
                        .buttonStyle(.plain)
                    }

                    // العنوان — قائمة منسدلة بعناوين جاهزة (مضغوطة) مع خيار «عنوان مخصّص»
                    HStack(spacing: DS.Spacing.sm) {
                        Image(systemName: "bell.badge")
                            .foregroundColor(DS.Color.textTertiary)
                            .font(DS.Font.scaled(13, weight: .medium))

                        if useCustomTitle {
                            TextField(L10n.t("عنوان الإشعار", "Notification title"), text: $title)
                                .font(DS.Font.callout)
                                .onChange(of: title) { _ in
                                    if title.count > 100 { title = String(title.prefix(100)) }
                                }
                            Button {
                                withAnimation(DS.Anim.snappy) {
                                    useCustomTitle = false
                                    title = Self.presetTitles.first ?? title
                                }
                            } label: {
                                Image(systemName: "list.bullet")
                                    .font(DS.Font.scaled(13, weight: .bold))
                                    .foregroundColor(DS.Color.primary)
                            }
                            .accessibilityLabel(L10n.t("عناوين جاهزة", "Preset titles"))
                        } else {
                            Menu {
                                ForEach(Self.presetTitles, id: \.self) { preset in
                                    Button(preset) { title = preset }
                                }
                                Divider()
                                Button(L10n.t("عنوان مخصّص…", "Custom title…")) {
                                    withAnimation(DS.Anim.snappy) { useCustomTitle = true }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Text(title.isEmpty ? L10n.t("اختر عنواناً", "Choose a title") : title)
                                        .font(DS.Font.callout)
                                        .foregroundColor(title.isEmpty ? DS.Color.textTertiary : DS.Color.textPrimary)
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(DS.Font.scaled(11, weight: .bold))
                                        .foregroundColor(DS.Color.textTertiary)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, DS.Spacing.md)
                    .frame(height: 44)
                    .background(DS.Color.surface)
                    .cornerRadius(DS.Radius.md)

                    VStack(alignment: .trailing, spacing: DS.Spacing.xs) {
                        HStack(alignment: .top, spacing: DS.Spacing.sm) {
                            Image(systemName: "text.alignright")
                                .foregroundColor(DS.Color.textTertiary)
                                .font(DS.Font.scaled(14, weight: .medium))
                                .padding(.top, DS.Spacing.sm)
                            ZStack(alignment: L10n.isArabic ? .topTrailing : .topLeading) {
                                if bodyText.isEmpty {
                                    Text(L10n.t("تفاصيل (اختياري)", "Details (optional)"))
                                        .font(DS.Font.callout)
                                        .foregroundColor(DS.Color.textTertiary)
                                        .padding(.top, DS.Spacing.sm)
                                        .allowsHitTesting(false)
                                }
                                TextEditor(text: $bodyText)
                                    .font(DS.Font.callout)
                                    .frame(minHeight: 44, maxHeight: 72)
                                    .scrollContentBackground(.hidden)
                                    .background(Color.clear)
                                    .onChange(of: bodyText) { _ in
                                        if bodyText.count > 500 { bodyText = String(bodyText.prefix(500)) }
                                    }
                            }
                        }
                        Text("\(bodyText.count)/500")
                            .font(DS.Font.caption2)
                            .foregroundColor(bodyText.count > 450 ? DS.Color.error : DS.Color.textTertiary)
                    }
                    .padding(DS.Spacing.md)
                    .background(DS.Color.surface)
                    .cornerRadius(DS.Radius.md)

                    // (الجدولة انتقلت لشاشتها المستقلة — زر «الإشعارات المجدولة» أعلى الصفحة)

                    // تصفية حسب دولة التسجيل — طلب المالك
                    countryFilterBar

                    // البحث خلف زر — لا يشغل مساحة إلا عند الحاجة (طلب المالك)
                    if showSearchField {
                        HStack(spacing: DS.Spacing.sm) {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(DS.Color.textTertiary)
                                .font(DS.Font.scaled(14, weight: .medium))
                            TextField(L10n.t("بحث بالاسم أو الرقم...", "Search by name or phone..."), text: $searchText)
                                .font(DS.Font.callout)
                                .focused($searchFocused)
                                .onChange(of: searchText) { _ in displayLimit = 20 }
                            Button {
                                withAnimation(DS.Anim.snappy) {
                                    searchText = ""
                                    showSearchField = false
                                }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(DS.Color.textTertiary)
                            }
                            .accessibilityLabel(L10n.t("إغلاق البحث", "Close search"))
                        }
                        .padding(DS.Spacing.md)
                        .background(DS.Color.surface)
                        .cornerRadius(DS.Radius.md)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    HStack(spacing: DS.Spacing.sm) {
                        // زر البحث — يفتح حقل البحث عند الحاجة فقط
                        Button {
                            withAnimation(DS.Anim.snappy) { showSearchField.toggle() }
                            if showSearchField { searchFocused = true }
                        } label: {
                            Image(systemName: showSearchField ? "magnifyingglass.circle.fill" : "magnifyingglass")
                                .font(DS.Font.scaled(13, weight: .bold))
                                .foregroundColor(DS.Color.primary)
                                .padding(.horizontal, DS.Spacing.md)
                                .padding(.vertical, DS.Spacing.xs)
                                .background(DS.Color.primary.opacity(0.1))
                                .clipShape(Capsule())
                        }
                        .accessibilityLabel(L10n.t("بحث", "Search"))

                        Button {
                            selectedMemberIds = Set(filteredMembers.map(\.id))
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(DS.Font.scaled(11))
                                Text(L10n.t("الكل", "All"))
                                    .font(DS.Font.scaled(12, weight: .bold))
                            }
                            .foregroundColor(DS.Color.primary)
                            .padding(.horizontal, DS.Spacing.md)
                            .padding(.vertical, DS.Spacing.xs)
                            .background(DS.Color.primary.opacity(0.1))
                            .clipShape(Capsule())
                        }

                        Button {
                            selectedMemberIds.removeAll()
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(DS.Font.scaled(11))
                                Text(L10n.t("إلغاء", "Clear"))
                                    .font(DS.Font.scaled(12, weight: .bold))
                            }
                            .foregroundColor(DS.Color.error)
                            .padding(.horizontal, DS.Spacing.md)
                            .padding(.vertical, DS.Spacing.xs)
                            .background(DS.Color.error.opacity(0.1))
                            .clipShape(Capsule())
                        }

                        Spacer()

                        Text(L10n.t(
                            "\(selectedMemberIds.isEmpty ? filteredMembers.count : selectedMemberIds.count) عضو",
                            "\(selectedMemberIds.isEmpty ? filteredMembers.count : selectedMemberIds.count) members"
                        ))
                        .font(DS.Font.caption1)
                        .foregroundColor(DS.Color.textTertiary)
                    }
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.sm)

                if filteredMembers.isEmpty {
                    Spacer()
                    VStack(spacing: DS.Spacing.sm) {
                        Image(systemName: "person.2.slash")
                            .font(DS.Font.scaled(36, weight: .regular))
                            .foregroundColor(DS.Color.textTertiary)
                        Text(L10n.t("لا يوجد أعضاء", "No members found"))
                            .font(DS.Font.callout)
                            .foregroundColor(DS.Color.textSecondary)
                    }
                    Spacer()
                } else {
                    List {
                        let visible = Array(filteredMembers.prefix(displayLimit))
                        ForEach(visible) { member in
                            Button {
                                toggleSelection(member.id)
                            } label: {
                                memberRow(member: member)
                            }
                            .buttonStyle(.plain)
                            .listRowInsets(EdgeInsets(top: 4, leading: DS.Spacing.lg, bottom: 4, trailing: DS.Spacing.lg))
                        }

                        if displayLimit < filteredMembers.count {
                            Button {
                                displayLimit += 20
                            } label: {
                                HStack {
                                    Spacer()
                                    Text(L10n.t(
                                        "عرض المزيد (\(filteredMembers.count - displayLimit) متبقي)",
                                        "Show more (\(filteredMembers.count - displayLimit) remaining)"
                                    ))
                                    .font(DS.Font.caption1)
                                    .foregroundColor(DS.Color.primary)
                                    Spacer()
                                }
                                .padding(.vertical, DS.Spacing.sm)
                            }
                            .listRowInsets(EdgeInsets(top: 0, leading: DS.Spacing.lg, bottom: 0, trailing: DS.Spacing.lg))
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }

                VStack(spacing: DS.Spacing.xs) {
                    // زر الجدولة جنب زر الإرسال — طلب المالك
                    // زرّان متطابقان — الإرسال أولاً ثم الجدولة (معكوسان — طلب المالك)
                    HStack(spacing: DS.Spacing.sm) {
                        DSPrimaryButton(
                            L10n.t("إرسال الآن", "Send Now"),
                            icon: "paperplane.fill",
                            isLoading: notificationVM.isLoading
                        ) {
                            scheduleEnabled = false
                            showSendConfirm = true
                        }
                        .disabled(
                            title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )

                        DSPrimaryButton(
                            L10n.t("جدولة", "Schedule"),
                            icon: "clock.badge",
                            isLoading: false,
                            useGradient: false,
                            color: DS.Color.accent
                        ) {
                            showScheduleComposer = true
                        }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    let targetText = selectedMemberIds.isEmpty
                        ? L10n.t("للجميع", "to all")
                        : L10n.t("لـ \(selectedMemberIds.count) عضو محدد",
                                 "to \(selectedMemberIds.count) selected members")
                    if scheduleEnabled {
                        Text(L10n.t(
                            "سيُجدول الإرسال \(targetText) في \(scheduledDateText)",
                            "Will be scheduled \(targetText) at \(scheduledDateText)"
                        ))
                        .font(DS.Font.caption2)
                        .foregroundColor(DS.Color.textTertiary)
                        .multilineTextAlignment(.center)
                    } else {
                        Text(L10n.t("سيُرسل \(targetText)", "Will be sent \(targetText)"))
                            .font(DS.Font.caption2)
                            .foregroundColor(DS.Color.textTertiary)
                    }
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.md)
                .background(DS.Color.background)
            }
        }
        .navigationTitle(L10n.t("إرسال إشعار", "Send Notification"))
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .task {
            if memberVM.allMembers.isEmpty {
                await memberVM.fetchAllMembers()
            }
            await notificationVM.fetchScheduledNotifications()
        }
        .sheet(isPresented: $showScheduleComposer) {
            ScheduleComposerSheet(scheduledDate: $scheduledDate) {
                scheduleEnabled = true
                showScheduleComposer = false
                Task { await sendNotification() }
            }
            .environmentObject(notificationVM)
        }
        .sheet(isPresented: $showScheduledSheet) {
            ScheduledNotificationsSheet()
                .environmentObject(notificationVM)
                .environmentObject(memberVM)
        }
        // تأكيد الإرسال — يذكر الجمهور صراحةً (البثّ للجميع إجراء لا رجعة فيه)
        .confirmationDialog(
            scheduleEnabled ? L10n.t("تأكيد الجدولة", "Confirm Schedule")
                            : L10n.t("تأكيد الإرسال", "Confirm Send"),
            isPresented: $showSendConfirm, titleVisibility: .visible
        ) {
            Button(
                isBroadcastSend
                    ? L10n.t("إرسال للجميع (\(sendAudienceCount))", "Send to all (\(sendAudienceCount))")
                    : L10n.t("إرسال لـ \(sendAudienceCount) عضو", "Send to \(sendAudienceCount) members"),
                role: isBroadcastSend ? .destructive : nil
            ) {
                Task { await sendNotification() }
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
        } message: {
            Text(isBroadcastSend
                 ? L10n.t("سيصل هذا الإشعار إلى جميع الأعضاء (\(sendAudienceCount)).",
                          "This will reach all \(sendAudienceCount) members.")
                 : L10n.t("سيصل إلى \(sendAudienceCount) عضو محدّد.",
                          "Will reach \(sendAudienceCount) selected members."))
        }
        .alert(L10n.t("تعذّر الإرسال", "Send Failed"), isPresented: $showSendError) {
            Button(L10n.t("حسناً", "OK"), role: .cancel) {}
        } message: {
            Text(L10n.t("حدث خطأ أثناء الإرسال. حاول مرة أخرى.", "Something went wrong. Please try again."))
        }
    }

    /// هل الإرسال بثّ للجميع (تحديد فارغ أو كل النشطين).
    private var isBroadcastSend: Bool {
        let activeMemberIds = Set(activeMembers.map(\.id))
        return selectedMemberIds.isEmpty || selectedMemberIds == activeMemberIds
    }
    /// عدد المستلمين للإرسال الحالي.
    private var sendAudienceCount: Int {
        isBroadcastSend ? activeMembers.count : selectedMemberIds.count
    }

    // MARK: - Member Row

    private func memberRow(member: FamilyMember) -> some View {
        HStack(spacing: DS.Spacing.md) {
            Image(systemName: selectedMemberIds.contains(member.id) ? "checkmark.circle.fill" : "circle")
                .font(DS.Font.scaled(20))
                .foregroundStyle(
                    selectedMemberIds.contains(member.id)
                        ? AnyShapeStyle(DS.Color.gradientPrimary)
                        : AnyShapeStyle(DS.Color.textTertiary)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(member.fullName)
                    .font(DS.Font.calloutBold)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)

                if let phone = member.phoneNumber, !phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    HStack(spacing: 2) {
                        Image(systemName: "phone.fill")
                            .font(DS.Font.scaled(10))
                        Text(KuwaitPhone.display(phone))
                    }
                    .font(DS.Font.caption1)
                    .foregroundColor(DS.Color.textSecondary)
                }
            }

            Spacer()
        }
        .padding(DS.Spacing.md)
    }

    // MARK: - Helpers

    private func toggleSelection(_ id: UUID) {
        if selectedMemberIds.contains(id) {
            selectedMemberIds.remove(id)
        } else {
            selectedMemberIds.insert(id)
        }
    }

    /// وقت الجدولة منسّقاً حسب لغة الواجهة.
    private var scheduledDateText: String {
        let f = DateFormatter()
        f.locale = LanguageManager.shared.locale
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: scheduledDate)
    }

    private func sendNotification() async {
        let trimmedBody = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalBody = trimmedBody.isEmpty ? title : trimmedBody

        // إذا كل الأعضاء محددين، نرسل broadcast (nil) بدل إرسال كل الـ IDs
        let activeMemberIds = Set(activeMembers.map(\.id))
        // مهم: البثّ العام (nil) يصل لكل الأعضاء — فلا يُستخدم إطلاقاً عند
        // تفعيل تصفية الدولة، وإلا خرج الإشعار خارج الشريحة المختارة.
        let targetIds: [UUID]?
        if countryFilter != nil {
            targetIds = selectedMemberIds.isEmpty ? Array(activeMemberIds) : Array(selectedMemberIds)
        } else if selectedMemberIds.isEmpty || selectedMemberIds == activeMemberIds {
            targetIds = nil
        } else {
            targetIds = Array(selectedMemberIds)
        }

        if scheduleEnabled {
            // الإرسال المجدول — يتولّاه الخادم في الوقت المحدد
            let ok = await notificationVM.scheduleNotification(
                title: title,
                body: finalBody,
                targetMemberIds: targetIds,
                scheduledFor: scheduledDate,
                kind: "admin_broadcast"
            )
            if ok {
                await notificationVM.fetchScheduledNotifications()
                dismiss()
            }
        } else {
            let ok = await notificationVM.sendNotification(
                title: title,
                body: finalBody,
                targetMemberIds: targetIds,
                kind: "admin_broadcast"
            )
            if ok { dismiss() } else { showSendError = true }
        }
    }
}

// MARK: - شاشة الجدولة (تحديد الوقت + المجدولة الحالية)

private struct ScheduleComposerSheet: View {
    @EnvironmentObject var notificationVM: NotificationViewModel
    @Environment(\.dismiss) private var dismiss
    @Binding var scheduledDate: Date
    let onConfirm: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()

                VStack(spacing: DS.Spacing.md) {
                    // عجلة واحدة (تاريخ + وقت) — الشكل السابق المرتّب (طلب المالك)
                    DatePicker(
                        "",
                        selection: $scheduledDate,
                        in: Date()...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .tint(DS.Color.primary)
                    .environment(\.locale, LanguageManager.shared.locale)
                    .frame(maxHeight: 190)

                    // ملخّص الوقت المختار — سطر واحد هادئ
                    Text(summaryText)
                        .font(DS.Font.caption1)
                        .foregroundColor(DS.Color.textSecondary)

                    DSPrimaryButton(L10n.t("تأكيد الجدولة", "Confirm schedule"),
                                    icon: "clock.badge.checkmark",
                                    isLoading: notificationVM.isLoading) {
                        onConfirm()
                    }
                    .padding(.horizontal, DS.Spacing.lg)

                    // المجدولة المعلّقة — قائمة مدمجة تحت خط فاصل
                    if !notificationVM.scheduledNotifications.isEmpty {
                        DSDivider()
                        HStack(spacing: 6) {
                            Image(systemName: "clock.badge")
                                .font(DS.Font.scaled(11, weight: .semibold))
                            Text(L10n.t("مجدولة بانتظار الإرسال (\(notificationVM.scheduledNotifications.count))",
                                        "Pending (\(notificationVM.scheduledNotifications.count))"))
                                .font(DS.Font.caption1)
                        }
                        .foregroundColor(DS.Color.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, DS.Spacing.lg)

                        ScrollView(showsIndicators: false) {
                            VStack(spacing: DS.Spacing.xs) {
                                ForEach(notificationVM.scheduledNotifications) { item in
                                    HStack(spacing: DS.Spacing.sm) {
                                        Circle()
                                            .fill(DS.Color.primary.opacity(0.5))
                                            .frame(width: 6, height: 6)
                                        Text(item.title)
                                            .font(DS.Font.caption1)
                                            .foregroundColor(DS.Color.textPrimary)
                                            .lineLimit(1)
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.horizontal, DS.Spacing.lg)
                                }
                            }
                        }
                        .frame(maxHeight: 96)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.top, DS.Spacing.sm)
            }
            .navigationTitle(L10n.t("جدولة الإشعار", "Schedule"))
            .navigationBarTitleDisplayMode(.inline)
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.t("إلغاء", "Cancel")) { dismiss() }
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.primary)
                }
            }
            .task { await notificationVM.fetchScheduledNotifications() }
        }
        .presentationDetents([.height(420)])
        .presentationDragIndicator(.visible)
    }




    private var summaryText: String {
        let f = DateFormatter()
        f.locale = LanguageManager.shared.locale
        f.dateFormat = L10n.isArabic ? "EEEE d MMMM • h:mm a" : "EEEE d MMM • h:mm a"
        return L10n.t("سيُرسل: ", "Sends: ") + f.string(from: scheduledDate)
    }
}

// MARK: - شيت الإشعارات المجدولة (عرض/إلغاء)

private struct ScheduledNotificationsSheet: View {
    @EnvironmentObject var notificationVM: NotificationViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var cancellingId: UUID? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()

                if notificationVM.scheduledNotifications.isEmpty {
                    VStack(spacing: DS.Spacing.md) {
                        Image(systemName: "clock.badge.checkmark")
                            .font(DS.Font.scaled(40, weight: .regular))
                            .foregroundColor(DS.Color.textTertiary)
                        Text(L10n.t("لا توجد إشعارات مجدولة", "No scheduled notifications"))
                            .font(DS.Font.callout)
                            .foregroundColor(DS.Color.textSecondary)
                    }
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: DS.Spacing.md) {
                            ForEach(notificationVM.scheduledNotifications) { item in
                                card(item)
                            }
                        }
                        .padding(DS.Spacing.lg)
                    }
                }
            }
            .navigationTitle(L10n.t("الإشعارات المجدولة", "Scheduled"))
            .navigationBarTitleDisplayMode(.inline)
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.t("إغلاق", "Close")) { dismiss() }
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.primary)
                }
            }
            .task { await notificationVM.fetchScheduledNotifications() }
        }
    }

    private func card(_ item: NotificationViewModel.ScheduledNotification) -> some View {
        DSCard {
            VStack(alignment: .trailing, spacing: DS.Spacing.sm) {
                // العنوان
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: "bell.badge.fill")
                        .font(DS.Font.scaled(14, weight: .semibold))
                        .foregroundColor(DS.Color.warning)
                    Text(item.title)
                        .font(DS.Font.bodyBold)
                        .foregroundColor(DS.Color.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // النص (إن اختلف عن العنوان)
                if !item.body.isEmpty && item.body != item.title {
                    Text(item.body)
                        .font(DS.Font.callout)
                        .foregroundColor(DS.Color.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .multilineTextAlignment(.trailing)
                }

                DSDivider()

                // الوقت + الجمهور
                HStack(spacing: DS.Spacing.sm) {
                    metaChip(icon: "calendar", text: timeText(item), color: DS.Color.primary)
                    metaChip(
                        icon: item.isBroadcast ? "person.3.fill" : "person.2.fill",
                        text: item.isBroadcast
                            ? L10n.t("للجميع", "Everyone")
                            : L10n.t("\(item.targetCount) عضو", "\(item.targetCount) members"),
                        color: DS.Color.accent
                    )
                    Spacer()
                }

                // إلغاء الجدولة
                Button {
                    Task {
                        cancellingId = item.id
                        await notificationVM.cancelScheduledNotification(item.id)
                        cancellingId = nil
                    }
                } label: {
                    HStack(spacing: DS.Spacing.xs) {
                        if cancellingId == item.id {
                            ProgressView().tint(DS.Color.error)
                        } else {
                            Image(systemName: "trash")
                                .font(DS.Font.scaled(13, weight: .semibold))
                        }
                        Text(L10n.t("إلغاء الجدولة", "Cancel schedule"))
                            .font(DS.Font.calloutBold)
                    }
                    .foregroundColor(DS.Color.error)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.Spacing.sm)
                    .background(DS.Color.error.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
                }
                .buttonStyle(.plain)
                .disabled(cancellingId != nil)
            }
        }
    }

    private func metaChip(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: DS.Spacing.xs) {
            Image(systemName: icon).font(DS.Font.scaled(11, weight: .semibold))
            Text(text).font(DS.Font.caption1).fontWeight(.semibold)
        }
        .foregroundColor(color)
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, DS.Spacing.xs)
        .background(color.opacity(0.10))
        .clipShape(Capsule())
    }

    private func timeText(_ item: NotificationViewModel.ScheduledNotification) -> String {
        guard let d = item.scheduledDate else { return item.scheduledFor }
        let f = DateFormatter()
        f.locale = LanguageManager.shared.locale
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: d)
    }
}
