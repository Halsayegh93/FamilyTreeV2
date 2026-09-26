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
            .filter { $0.role != .pending && !($0.isDeceased ?? false) && $0.status != .frozen }
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
        // الكويت والسعودية تظهران دائماً أولاً (طلب المالك) — ثم باقي الدول الموجودة
        let pinned = ["KW", "SA"]
        let pinnedItems = pinned.compactMap { iso in
            KuwaitPhone.supportedCountries.first { $0.isoCode == iso }.map { ($0, counts[iso] ?? 0) }
        }
        let others = KuwaitPhone.supportedCountries
            .filter { !pinned.contains($0.isoCode) }
            .compactMap { c in counts[c.isoCode].map { (c, $0) } }
            .sorted { $0.1 > $1.1 }
        return (pinnedItems + others).map { (country: $0.0, count: $0.1) }
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

    /// زر إجراء مضغوط (٤٤ نقطة) بألوان التطبيق — ممتلئ أو فاتح
    private func compactActionButton(_ title: String, icon: String, filled: Bool, loading: Bool,
                                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if loading {
                    ProgressView().tint(filled ? DS.Color.textOnPrimary : DS.Color.primary)
                } else {
                    Image(systemName: icon).font(DS.Font.scaled(14, weight: .bold))
                }
                Text(title).font(DS.Font.plex(14, weight: .bold))
            }
            .foregroundColor(filled ? DS.Color.textOnPrimary : DS.Color.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .fill(filled ? DS.Color.primary : DS.Color.primary.opacity(0.12))
            )
        }
        .buttonStyle(DSScaleButtonStyle())
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
            .padding(.horizontal, DS.Spacing.sm + 2)
            .frame(height: 26)
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
                    .frame(height: 38)
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
                                    .frame(minHeight: 36, maxHeight: 56)
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
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.vertical, DS.Spacing.sm)
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
                        .padding(.horizontal, DS.Spacing.md)
                        .padding(.vertical, DS.Spacing.sm)
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
                    // زرّان أصغر بألوان التطبيق (طلب المالك): إرسال أزرق ممتلئ، جدولة أزرق فاتح
                    let noTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    HStack(spacing: DS.Spacing.sm) {
                        compactActionButton(
                            L10n.t("إرسال الآن", "Send Now"), icon: "paperplane.fill",
                            filled: true, loading: notificationVM.isLoading
                        ) {
                            scheduleEnabled = false
                            showSendConfirm = true
                        }
                        .disabled(noTitle)

                        compactActionButton(
                            L10n.t("جدولة", "Schedule"), icon: "clock.badge",
                            filled: false, loading: false
                        ) {
                            showScheduleComposer = true
                        }
                        .disabled(noTitle)
                    }
                    .opacity(noTitle ? 0.55 : 1)

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
        // مربّعات بمنتصف الشاشة بدل الورقة السفلية (طلب المالك ٢٠٢٦-٠٩-٢٦)
        .dsCenterBox(isPresented: $showScheduleComposer) {
            ScheduleComposerSheet(scheduledDate: $scheduledDate) {
                scheduleEnabled = true
                showScheduleComposer = false
                Task { await sendNotification() }
            }
            .environmentObject(notificationVM)
        }
        .dsCenterBox(isPresented: $showScheduledSheet) {
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
        .dsAlert(L10n.t("تعذّر الإرسال", "Send Failed"), isPresented: $showSendError) {
            Button(L10n.t("حسناً", "OK")) {}
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
                .font(DS.Font.scaled(17))
                .foregroundStyle(
                    selectedMemberIds.contains(member.id)
                        ? AnyShapeStyle(DS.Color.gradientPrimary)
                        : AnyShapeStyle(DS.Color.textTertiary)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(member.displayFullName)
                    .font(DS.Font.plex(13, weight: .bold))
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)

                if let phone = member.phoneNumber, !phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    HStack(spacing: 2) {
                        Image(systemName: "phone.fill")
                            .font(DS.Font.scaled(11))
                        Text(KuwaitPhone.display(phone))
                    }
                    .font(DS.Font.caption1)
                    .foregroundColor(DS.Color.textSecondary)
                }
            }

            Spacer()
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.sm)
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

// MARK: - مربّع الجدولة (تحديد الوقت + المجدولة الحالية)

/// نفس هيكل مربّعات الإضافة (طلب المالك ٢٠٢٦-٠٩-٢٦): رأس متدرّج، أقسام تدخل تباعاً،
/// و«تأكيد الجدولة» كحلي يمين / «إلغاء» رمادي يسار أسفل المربّع.
private struct ScheduleComposerSheet: View {
    @EnvironmentObject var notificationVM: NotificationViewModel
    @Environment(\.dismiss) private var dismiss
    @Binding var scheduledDate: Date
    let onConfirm: () -> Void
    /// الوقت الذي فُتح عليه المربّع — «إلغاء» يسأل فقط إذا تغيّر (توصية أبل)
    @State private var startDate: Date? = nil

    private var confirmTitle: String { L10n.t("تأكيد الجدولة", "Confirm schedule") }

    /// وقت مختلف (بالدقيقة — العجلة لا تختار الثواني) عمّا فُتح عليه المربّع
    private var hasChanges: Bool {
        guard let startDate else { return false }
        return Calendar.current.compare(scheduledDate, to: startDate, toGranularity: .minute) != .orderedSame
    }

    var body: some View {
        DSComposer(
            title: L10n.t("جدولة الإشعار", "Schedule"),
            subtitle: L10n.t("اختر وقت إرسال الإشعار", "Pick when the notification goes out"),
            icon: "clock.badge",
            tint: DS.Color.actionNavy,
            actionTitle: confirmTitle,
            actionIcon: "clock.badge.checkmark",
            canSubmit: true,
            isBusy: notificationVM.isLoading,
            hasUnsavedChanges: hasChanges,
            onSubmit: {
                // نفس حماية الضغط المكرّر التي كانت في زر التأكيد السابق (DSPrimaryButton)
                if TapDebouncer.shared.canFire("DSPrimary_\(confirmTitle)") { onConfirm() }
            },
            onCancel: { dismiss() }
        ) {
            timeSection
            pendingSection
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .onAppear { if startDate == nil { startDate = scheduledDate } }
        .task { await notificationVM.fetchScheduledNotifications() }
    }

    // MARK: وقت الإرسال

    private var timeSection: some View {
        DSComposerSection(title: L10n.t("وقت الإرسال", "Send time"), icon: "calendar.badge.clock",
                          tint: DS.Color.primary, index: 0) {
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
            .frame(maxWidth: .infinity)
            .frame(maxHeight: 190)
            .clipped()
            // العجلة بعرض البطاقة كاملاً — عرضها ثابت تقريباً فلا تُقصّ أعمدتها على الشاشات الصغيرة
            .padding(.horizontal, -DS.Spacing.md)

            // ملخّص الوقت المختار — صف هادئ بنفس صفوف المربّعات
            HStack(spacing: DS.Spacing.sm) {
                DSFieldIcon(name: "paperplane.fill", tint: DS.Color.primary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("سيُرسل", "Sends"))
                        .font(DS.Font.plex(12, weight: .heavy))
                        .foregroundColor(DS.Color.fieldLabel)
                    Text(summaryDateText)
                        .font(DS.Font.plex(14.5))
                        .foregroundColor(DS.Color.fieldValue)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
            }
            .dsRowBox()
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: المجدولة المعلّقة

    /// قائمة مدمجة بعناوين المجدولة — تظهر فقط عند وجود إشعارات معلّقة
    @ViewBuilder
    private var pendingSection: some View {
        let items = notificationVM.scheduledNotifications
        if !items.isEmpty {
            DSComposerSection(title: L10n.t("مجدولة بانتظار الإرسال", "Pending"),
                              icon: "clock.badge", tint: DS.Color.warning,
                              trailing: "\(items.count)", index: 1) {
                VStack(alignment: .leading, spacing: DS.Spacing.xs + 2) {
                    ForEach(items) { item in
                        HStack(spacing: DS.Spacing.sm) {
                            Circle()
                                .fill(DS.Color.warning.opacity(0.6))
                                .frame(width: 6, height: 6)
                            Text(item.title)
                                .font(DS.Font.plex(13))
                                .foregroundColor(DS.Color.fieldValue)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .dsRowBox()
            }
        }
    }

    /// وقت الإرسال المختار — «الجمعة ٢٦ سبتمبر • ٨:٠٠ م»
    private var summaryDateText: String {
        let f = DateFormatter()
        f.locale = LanguageManager.shared.locale
        f.dateFormat = L10n.isArabic ? "EEEE d MMMM • h:mm a" : "EEEE d MMM • h:mm a"
        return f.string(from: scheduledDate)
    }
}

// MARK: - مربّع الإشعارات المجدولة (عرض/إلغاء)

/// مربّع عرض بنفس تصميم المربّعات: رأس متدرّج، المجدولة صفوفاً في قسم واحد،
/// و«إغلاق» أسفل المربّع. «إلغاء الجدولة» داخل كل صف كما كان.
private struct ScheduledNotificationsSheet: View {
    @EnvironmentObject var notificationVM: NotificationViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var cancellingId: UUID? = nil

    var body: some View {
        let items = notificationVM.scheduledNotifications
        return DSComposer(
            title: L10n.t("الإشعارات المجدولة", "Scheduled"),
            subtitle: L10n.t("تُرسل تلقائياً في موعدها", "Sent automatically on time"),
            icon: "clock.badge.fill",
            tint: DS.Color.actionNavy,
            actionTitle: "",
            showsAction: false,
            cancelTitle: L10n.t("إغلاق", "Close"),
            canSubmit: false,
            onSubmit: {},
            onCancel: { dismiss() }
        ) {
            if items.isEmpty {
                emptyState.dsStaggerIn(0)
            } else {
                DSComposerSection(title: L10n.t("مجدولة بانتظار الإرسال", "Pending"),
                                  icon: "clock.badge", tint: DS.Color.warning,
                                  trailing: "\(items.count)", index: 0) {
                    VStack(spacing: DS.Spacing.sm) {
                        ForEach(items) { item in row(item) }
                    }
                }
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .task { await notificationVM.fetchScheduledNotifications() }
    }

    private var emptyState: some View {
        VStack(spacing: DS.Spacing.md) {
            Image(systemName: "clock.badge.checkmark")
                .font(.system(size: 36, weight: .regular))
                .foregroundColor(DS.Color.textTertiary)
                .accessibilityHidden(true)
            Text(L10n.t("لا توجد إشعارات مجدولة", "No scheduled notifications"))
                .font(DS.Font.plex(14, weight: .semibold))
                .foregroundColor(DS.Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.xxl)
        .background(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous).fill(DS.Color.surface))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
            .strokeBorder(DS.Color.textTertiary.opacity(0.10), lineWidth: 1))
    }

    /// صف إشعار مجدول: العنوان والنص، ثم الوقت والجمهور، ثم «إلغاء الجدولة»
    private func row(_ item: NotificationViewModel.ScheduledNotification) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(alignment: .top, spacing: DS.Spacing.sm) {
                DSFieldIcon(name: "bell.badge.fill", tint: DS.Color.warning)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    // العنوان
                    Text(item.title)
                        .font(DS.Font.plex(14.5, weight: .bold))
                        .foregroundColor(DS.Color.fieldLabel)
                        .fixedSize(horizontal: false, vertical: true)
                    // النص (إن اختلف عن العنوان)
                    if !item.body.isEmpty && item.body != item.title {
                        Text(item.body)
                            .font(DS.Font.plex(13))
                            .foregroundColor(DS.Color.fieldValue)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }

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
                Spacer(minLength: 0)
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
                            .font(.system(size: 12.5, weight: .bold))
                    }
                    Text(L10n.t("إلغاء الجدولة", "Cancel schedule"))
                        .font(DS.Font.plex(13, weight: .bold))
                }
                .foregroundColor(DS.Color.error)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(DS.Color.error.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                // مساحة ضغط ٤٤ (توصية أبل) — الشكل والارتفاع في الصف كما هما
                .frame(height: 44)
                .contentShape(Rectangle())
                .padding(.vertical, -2)
            }
            .buttonStyle(DSScaleButtonStyle())
            .disabled(cancellingId != nil)
        }
        .dsRowBox()
    }

    private func metaChip(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: DS.Spacing.xs) {
            Image(systemName: icon).font(.system(size: 11, weight: .semibold))
                .accessibilityHidden(true)
            Text(text)
                .font(DS.Font.plex(11.5, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .foregroundColor(color)
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, DS.Spacing.xs)
        .background(color.opacity(0.10), in: Capsule())
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
