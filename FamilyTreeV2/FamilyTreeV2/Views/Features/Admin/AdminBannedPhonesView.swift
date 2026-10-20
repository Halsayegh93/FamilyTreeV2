import SwiftUI

/// الأرقام المحظورة — بشكل «اليوم» (طلب المالك ٢٠٢٦-١٠-٢٠، `AdminPageKit`): رأس كحلي بأرقام حيّة وزرّ «حظر رقم»
/// للمالك (وشارة «للقراءة» لغيره) ← البحث يصعد فوقه ← بطاقة بيضاء فيها الأرقام صفوفاً مفصولة بخط
/// (الرقم من اليسار · السبب · تاريخ الحظر · «إلغاء»).
/// الحظر وإلغاؤه للمالك فقط (`canManageBannedPhones`) وبنفس التأكيد والمربّع كما كانا تماماً.
struct AdminBannedPhonesView: View {
    @EnvironmentObject var authVM: AuthViewModel

    private func t(_ ar: String, _ en: String) -> String { L10n.t(ar, en) }

    @State private var searchText = ""
    @State private var isLoading = true
    @State private var showAddSheet = false
    @State private var phoneToUnban: BannedPhone?
    @State private var isProcessing = false
    /// آخر جلب انتهى والجهاز غير متصل — لبطاقة «تعذّر التحميل» بدل «لا توجد أرقام محظورة» المضلِّلة
    /// (تبقى حتى جلب ناجح عبر «إعادة المحاولة»)
    @State private var lastFetchOffline = false

    /// لون بلاطة «الأرقام المحظورة» في إعدادات النظام — رأس الصفحة يطابق البلاطة التي ضُغطت
    private let pageTint = DS.Color.error

    // قائمة مفلترة بالبحث
    private var filteredPhones: [BannedPhone] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return authVM.bannedPhones
        }
        let query = searchText.lowercased()
        return authVM.bannedPhones.filter {
            $0.phoneNumber.contains(query) ||
            ($0.reason?.lowercased().contains(query) ?? false)
        }
    }

    // MARK: - حالة التحميل

    /// أول تحميل ولا أرقام محمّلة بعد (إن كانت محمّلة من لوحة الإدارة تظهر فوراً وتتحدّث)
    private var isInitialLoading: Bool {
        isLoading && authVM.bannedPhones.isEmpty
    }

    /// الجلب انتهى بلا أرقام والجهاز غير متصل — القائمة الفارغة هنا ليست «لا توجد أرقام محظورة»
    private var loadFailed: Bool {
        !isLoading && authVM.bannedPhones.isEmpty && lastFetchOffline
    }

    /// نفس الجلب السابق تماماً (`fetchBannedPhones`) — ويحفظ هل انتهى بلا اتصال
    private func loadBans() async {
        isLoading = true
        await authVM.fetchBannedPhones()
        lastFetchOffline = !NetworkMonitor.shared.isConnected
        isLoading = false
    }

    var body: some View {
        AdminPage(header: header, lead: leadCard, content: phonesContent)
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
            .dsCenterBox(isPresented: $showAddSheet) {
                AddBanSheet(authVM: authVM)
            }
            .dsAlert(
                t("إلغاء الحظر", "Remove Ban"),
                isPresented: Binding(
                    get: { phoneToUnban != nil },
                    set: { if !$0 { phoneToUnban = nil } }
                )
            ) {
                Button(t("إلغاء", "Cancel"), role: .cancel) { phoneToUnban = nil }
                Button(t("إلغاء الحظر", "Remove Ban"), role: .destructive) {
                    guard let phone = phoneToUnban else { return }
                    Task {
                        isProcessing = true
                        _ = await authVM.unbanPhone(phone.id)
                        isProcessing = false
                        phoneToUnban = nil
                    }
                }
            } message: {
                if let phone = phoneToUnban {
                    Text(t(
                        "هل تريد إلغاء حظر الرقم \(phone.phoneNumber)؟",
                        "Remove ban for \(phone.phoneNumber)?"
                    ))
                }
            }
            .task {
                await loadBans()
            }
    }

    // MARK: - الرأس الكحلي

    /// ٣ أرقام حيّة من القائمة المحمّلة أصلاً (بلا طلبات جديدة للسيرفر): كل المحظورة، وما أُضيف
    /// هذا الشهر وهذا الأسبوع — «—» قبل اكتمال أول تحميل. زرّ «حظر رقم» للمالك فقط (المدير يتصفّح للقراءة)
    private var header: AdminPageHeader {
        let pending = isInitialLoading || loadFailed
        let phones = authVM.bannedPhones
        let calendar = Calendar.current
        let now = Date()
        let dates = phones.compactMap { Self.parseDate($0.createdAt) }
        let thisMonth = dates.filter { calendar.isDate($0, equalTo: now, toGranularity: .month) }.count
        let thisWeek = dates.filter { calendar.isDate($0, equalTo: now, toGranularity: .weekOfYear) }.count
        let canBan = authVM.canManageBannedPhones
        return AdminPageHeader(
            title: t("الأرقام المحظورة", "Banned Numbers"),
            subtitle: t("أرقام ممنوعة من التسجيل واستخدام التطبيق", "Numbers blocked from signing up and using the app"),
            glyph: "phone.down.fill",
            readOnly: !canBan,
            kpis: [
                AdminPageKPI(pending ? "—" : "\(phones.count)", t("محظور", "Banned"), icon: "phone.down.fill",
                             tint: !pending && !phones.isEmpty ? DS.Hub.kpiLate : DS.Color.textOnPrimary),
                AdminPageKPI(pending ? "—" : "\(thisMonth)", t("هذا الشهر", "This month"), icon: "calendar"),
                AdminPageKPI(pending ? "—" : "\(thisWeek)", t("هذا الأسبوع", "This week"), icon: "clock.fill")
            ],
            actions: canBan ? [AdminPageAction(symbol: "plus", label: t("حظر رقم هاتف", "Ban Phone Number"),
                                               tap: .action { showAddSheet = true })] : [])
    }

    // MARK: - المحتوى

    /// أول بطاقة (تصعد فوق الرأس): التحميل، أو تعذّره، أو «لا توجد أرقام محظورة»، أو البحث
    private var leadCard: AnyView {
        if isInitialLoading {
            return AnyView(AdminPageStateCard(.loading(t("جارٍ تحميل الأرقام المحظورة…", "Loading banned numbers…"))))
        }
        if loadFailed {
            return AnyView(AdminPageStateCard(.error(t("تعذّر تحميل الأرقام المحظورة", "Couldn't load banned numbers"),
                                                     message: t("تحقّق من اتصالك وحاول مرة أخرى",
                                                                "Check your connection and try again"),
                                                     retry: { Task { await loadBans() } })))
        }
        if authVM.bannedPhones.isEmpty {
            return AnyView(AdminPageStateCard(.empty(t("لا توجد أرقام محظورة", "No Banned Numbers"),
                                                     message: authVM.canManageBannedPhones
                                                        ? t("يمكنك حظر أرقام هواتف من زر + في الأعلى",
                                                            "You can ban phone numbers using the + button above")
                                                        : nil,
                                                     tint: DS.Color.success)))
        }
        return AnyView(DSSearchField(text: $searchText,
                                     placeholder: t("بحث عن رقم...", "Search number..."),
                                     tint: pageTint)
            .adminCard(padding: DS.Spacing.md))
    }

    /// بطاقة الأرقام — عنوانها وعدد ما يظهر منها (مع البحث)، والصفوف مفصولة بخط
    private var phonesContent: AnyView {
        guard !isInitialLoading, !loadFailed, !authVM.bannedPhones.isEmpty else { return AnyView(EmptyView()) }
        let phones = filteredPhones
        if phones.isEmpty {
            return AnyView(AdminPageStateCard(.empty(t("لا توجد نتائج مطابقة", "No matching results"),
                                                     message: t("جرّب رقماً آخر أو كلمة من سبب الحظر",
                                                                "Try another number or a word from the reason"))))
        }
        return AnyView(AdminSectionCard(title: t("الأرقام المحظورة", "Banned Numbers"),
                                        tag: t("\(phones.count) رقم", phones.count == 1 ? "1 number" : "\(phones.count) numbers"),
                                        spacing: 0) {
            AdminLazyRows(items: phones) { AnyView(bannedPhoneRow($0)) }
        })
    }

    // MARK: - Row

    /// صفّ: مربّع الحظر + الرقم (من اليسار) + السبب + تاريخ الحظر، و«إلغاء» في الطرف للمالك فقط
    private func bannedPhoneRow(_ banned: BannedPhone) -> some View {
        HStack(spacing: DS.Spacing.md) {
            AdminIconSquare(symbol: "phone.down.fill", tint: pageTint)

            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(Self.isolatedLTR(formatPhoneDisplay(banned.phoneNumber)))
                    .dsFont(.hubRow)
                    .foregroundColor(DS.Color.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                if let reason = banned.reason, !reason.isEmpty {
                    Text(reason)
                        .dsFont(.footnote)
                        .foregroundColor(DS.Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // تاريخ الحظر
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "calendar")
                        .dsGlyph(DS.Glyph.micro, weight: .semibold)
                        .accessibilityHidden(true)
                    Text(formatDate(banned.createdAt))
                        .dsFont(.caption)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .foregroundColor(DS.Color.textTertiary)
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 0)

            // زر إلغاء الحظر — للمالك فقط (المدير يتصفّح بدون تعديل)
            if authVM.canManageBannedPhones {
                unbanButton(banned)
            }
        }
        .padding(.vertical, DS.Spacing.sm + 2)
        .frame(minHeight: DS.Icon.tapTarget)
    }

    /// «إلغاء» — الشريحة الواحدة بالأحمر (مساحة ضغط ٤٤)
    private func unbanButton(_ banned: BannedPhone) -> some View {
        let number = formatPhoneDisplay(banned.phoneNumber)
        return DSChipButton(t("إلغاء", "Unban"), icon: "lock.open.fill", tint: DS.Color.error) {
            phoneToUnban = banned
        }
        .accessibilityLabel(t("إلغاء حظر \(number)", "Unban \(number)"))
    }

    // MARK: - Helpers
    private func formatPhoneDisplay(_ phone: String) -> String {
        if phone.count == 8 {
            return "+965 \(phone)"
        }
        return KuwaitPhone.display(phone)
    }

    /// الأرقام تبقى بترتيبها من اليسار داخل سطر عربي
    private static func isolatedLTR(_ text: String) -> String {
        "\u{2066}\(text)\u{2069}"
    }

    private static let isoFull: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoBasic: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// تاريخ الحظر (بكسر ثوانٍ أو بدونها) — nil إن تعذّرت قراءته
    private static func parseDate(_ isoString: String) -> Date? {
        isoFull.date(from: isoString) ?? isoBasic.date(from: isoString)
    }

    private func formatDate(_ isoString: String) -> String {
        guard let date = Self.parseDate(isoString) else { return isoString }
        return dateDisplay(date)
    }

    private func dateDisplay(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: L10n.isArabic ? "ar" : "en")
        df.dateStyle = .medium
        df.timeStyle = .short
        return df.string(from: date)
    }
}

// MARK: - Add Ban Sheet

struct AddBanSheet: View {
    @ObservedObject var authVM: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    private func t(_ ar: String, _ en: String) -> String { L10n.t(ar, en) }

    @State private var phoneNumber = ""
    @State private var selectedPhoneCountry: KuwaitPhone.Country = KuwaitPhone.defaultCountry
    @State private var reason = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    /// الرقم المحلي (أرقام فقط) كما أُدخل.
    private var localDigits: String {
        KuwaitPhone.normalizeDigits(phoneNumber).filter(\.isNumber)
    }

    /// الرقم النهائي بصيغة E.164 (كود الدولة + المحلي) للحظر.
    private var cleanPhone: String {
        KuwaitPhone.normalizedForStorage(country: selectedPhoneCountry, rawLocalDigits: phoneNumber)
            ?? "\(selectedPhoneCountry.dialingCode)\(localDigits)"
    }

    private var isValid: Bool {
        localDigits.count >= 6
    }

    /// أي إدخال (رقم، سبب، أو دولة غير الافتراضية) → «إلغاء» يسأل قبل التجاهل (توصية أبل)
    private var hasInput: Bool {
        !phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || selectedPhoneCountry != KuwaitPhone.defaultCountry
    }

    var body: some View {
        // نفس هيكل مربّعات الإضافة (طلب المالك): رأس أحمر للحظر، قسم البيانات،
        // و«حظر الرقم» كحلي يمين / «إلغاء» رمادي يسار
        DSComposer(
            title: t("حظر رقم هاتف", "Ban Phone Number"),
            subtitle: t("يُمنع الرقم من استخدام التطبيق", "The number is blocked from using the app"),
            icon: "phone.down.fill",
            tint: DS.Color.error,
            actionTitle: t("حظر الرقم", "Ban Number"),
            actionIcon: "phone.down.fill",
            canSubmit: isValid,
            isBusy: isLoading,
            hasUnsavedChanges: hasInput,
            onSubmit: { Task { await banAction() } },
            onCancel: { dismiss() }
        ) {
            DSComposerSection(title: t("بيانات الحظر", "Ban details"), icon: "phone.down.fill",
                              tint: DS.Color.error, index: 0) {
                // حقل الرقم
                phoneRow

                // سبب الحظر
                DSComposerField(icon: "text.bubble.fill",
                                label: t("السبب (اختياري)", "Reason (optional)"),
                                placeholder: t("سبب الحظر...", "Ban reason..."),
                                text: $reason,
                                tint: DS.Color.error)
            }

            // رسالة خطأ
            if let error = errorMessage {
                errorRow(error)
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    /// صف الرقم بنفس شكل حقول المربّعات: أيقونة + العنوان فوق + حقل الهاتف الموحّد
    private var phoneRow: some View {
        HStack(spacing: DS.Spacing.sm) {
            DSFieldIcon(name: "phone.fill", tint: DS.Color.error)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(t("رقم الهاتف", "Phone Number"))
                    .dsFieldFont(.label)
                    .foregroundColor(DS.Color.fieldLabel)
                DSPhoneField(
                    country: $selectedPhoneCountry,
                    digits: $phoneNumber,
                    placeholder: t("مثال: 99123456", "e.g. 99123456"),
                    compact: true,
                    bordered: false
                )
            }
        }
        .dsRowBox()
    }

    private func errorRow(_ error: String) -> some View {
        DSNoteCard(error, icon: "exclamationmark.triangle.fill", tint: DS.Color.error)
    }

    private func banAction() async {
        errorMessage = nil
        isLoading = true

        let success = await authVM.banPhone(
            cleanPhone,
            reason: reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : reason.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        if success {
            dismiss()
        } else {
            errorMessage = t(
                "فشل حظر الرقم. قد يكون محظوراً بالفعل.",
                "Failed to ban number. It may already be banned."
            )
        }
        isLoading = false
    }
}
