import SwiftUI

/// «التسجيل والمنع» — صفحة واحدة في «الفريق والأمان» (الدفعة ج من «نفّذ كل المقترح»، ٢٠٢٦-١٠-٢٠): كانت «قواعد التسجيل»
/// (`AdminAppSettingsView(scope: .registration)`) و«الأرقام المحظورة» صفحتين. الرأس الكحلي (حالة التسجيل وعدد الأرقام
/// الممنوعة، و«＋ منع رقم» للمالك) ← «شروط التسجيل» (مفتاح «السماح بالتسجيل» في مكانه) ← «الأرقام الممنوعة من التسجيل»
/// صفوفاً بلا بحث (القائمة قصيرة). «عدد الأجهزة المسموح لكل عضو» انتقل إلى «الأجهزة ووصول الإشعارات».
/// المفتاح والمنع ورفعه للمالك فقط (`canManageSettings` / `canManageBannedPhones`) وبنفس النداءات والتأكيد والمربّع.
struct AdminRegistrationBansView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var appSettingsVM: AppSettingsViewModel

    private func t(_ ar: String, _ en: String) -> String { L10n.t(ar, en) }

    @State private var isLoading = true
    @State private var showAddSheet = false
    @State private var phoneToUnban: BannedPhone?
    @State private var isProcessing = false
    /// آخر جلب انتهى والجهاز غير متصل — لبطاقة «تعذّر التحميل» بدل «لا توجد أرقام ممنوعة» المضلِّلة
    @State private var lastFetchOffline = false

    private let pageTint = DS.Color.error

    private var isInitialLoading: Bool { isLoading && authVM.bannedPhones.isEmpty }
    private var loadFailed: Bool { !isLoading && authVM.bannedPhones.isEmpty && lastFetchOffline }

    /// نفس الجلب السابق تماماً (`fetchBannedPhones`) — ويحفظ هل انتهى بلا اتصال
    private func loadBans() async {
        isLoading = true
        await authVM.fetchBannedPhones()
        lastFetchOffline = !NetworkMonitor.shared.isConnected
        isLoading = false
    }

    var body: some View {
        AdminPage(header: header, lead: AnyView(rulesCard), content: phonesContent)
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
            .dsCenterBox(isPresented: $showAddSheet) {
                AddBanSheet(authVM: authVM)
            }
            .dsAlert(
                t("رفع المنع", "Unblock"),
                isPresented: Binding(
                    get: { phoneToUnban != nil },
                    set: { if !$0 { phoneToUnban = nil } }
                )
            ) {
                Button(t("إلغاء", "Cancel"), role: .cancel) { phoneToUnban = nil }
                Button(t("رفع المنع", "Unblock"), role: .destructive) {
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
                    Text(t("رفع منع الرقم \(phone.phoneNumber) من التسجيل؟", "Allow \(phone.phoneNumber) to sign up again?"))
                }
            }
            .task {
                async let settings: Void = appSettingsVM.fetchSettings()
                await loadBans()
                await settings
            }
    }

    // MARK: - الرأس الكحلي

    /// حالة التسجيل، وعدد الأرقام الممنوعة وما أُضيف هذا الشهر — «—» قبل اكتمال أول تحميل. «منع رقم» للمالك فقط
    private var header: AdminPageHeader {
        let pending = isInitialLoading || loadFailed
        let phones = authVM.bannedPhones
        let now = Date()
        let thisMonth = phones.compactMap { Self.parseDate($0.createdAt) }
            .filter { Calendar.current.isDate($0, equalTo: now, toGranularity: .month) }.count
        let ready = appSettingsVM.settings.updatedAt != nil
        let open = appSettingsVM.settings.allowNewRegistrations
        let canBan = authVM.canManageBannedPhones
        return AdminPageHeader(
            title: t("التسجيل والمنع", "Sign-up and blocking"),
            subtitle: t("من يقدر يسجّل في التطبيق، والأرقام الممنوعة من التسجيل",
                        "Who can sign up, and the numbers blocked from signing up"),
            glyph: "person.crop.circle.badge.checkmark",
            readOnly: !authVM.canManageSettings,
            kpis: [
                AdminPageKPI(ready ? (open ? t("مسموح", "Open") : t("مغلق", "Closed")) : "—", t("التسجيل", "Sign-up"),
                             icon: "person.badge.plus",
                             tint: ready ? (open ? DS.Hub.kpiMine : DS.Hub.kpiLate) : DS.Color.textOnPrimary),
                AdminPageKPI(pending ? "—" : "\(phones.count)", t("أرقام ممنوعة", "Blocked numbers"), icon: "phone.down.fill",
                             tint: !pending && !phones.isEmpty ? DS.Hub.kpiLate : DS.Color.textOnPrimary),
                AdminPageKPI(pending ? "—" : "\(thisMonth)", t("هذا الشهر", "This month"), icon: "calendar")
            ],
            actions: canBan ? [AdminPageAction(symbol: "plus", label: t("منع رقم من التسجيل", "Block a number"),
                                               tap: .action { showAddSheet = true })] : [])
    }

    // MARK: - شروط التسجيل

    /// «السماح بالتسجيل» — نفس المفتاح السابق (`allow_new_registrations`)، المالك يعدّل والمدير يقرأ
    private var rulesCard: some View {
        let s = appSettingsVM.settings
        return AdminSectionCard(title: t("شروط التسجيل", "Sign-up rules")) {
            AdminControlRow(icon: "person.badge.plus", tint: DS.Color.palm,
                            title: t("السماح بالتسجيل", "Allow sign-ups"),
                            subtitle: t("أعضاء جدد يسجّلون بأنفسهم، ويصل طلبهم «الوارد» للمراجعة",
                                        "New members sign up themselves; their request reaches the Inbox for review"),
                            control: AnyView(
                                Toggle("", isOn: Binding(
                                    get: { s.allowNewRegistrations },
                                    set: { on in
                                        Task { await appSettingsVM.updateSetting("allow_new_registrations", value: on,
                                                                                 updatedBy: authVM.currentUser?.id) }
                                    }))
                                .labelsHidden()
                                .tint(AppSection.admin.ink)
                                .accessibilityLabel(t("السماح بالتسجيل", "Allow sign-ups"))
                                .disabled(!authVM.canManageSettings)))
        }
    }

    // MARK: - الأرقام الممنوعة

    private var phonesContent: AnyView {
        if isInitialLoading {
            return AnyView(AdminPageStateCard(.loading(t("جارٍ تحميل الأرقام الممنوعة…", "Loading blocked numbers…"))))
        }
        if loadFailed {
            return AnyView(AdminPageStateCard(.error(t("تعذّر تحميل الأرقام الممنوعة", "Couldn't load blocked numbers"),
                                                     message: t("تحقّق من اتصالك وحاول مرة أخرى",
                                                                "Check your connection and try again"),
                                                     retry: { Task { await loadBans() } })))
        }
        let phones = authVM.bannedPhones
        if phones.isEmpty {
            return AnyView(AdminPageStateCard(.empty(t("لا توجد أرقام ممنوعة من التسجيل", "No blocked numbers"),
                                                     message: authVM.canManageBannedPhones
                                                        ? t("تمنع رقماً من زر ＋ في الأعلى، أو من ورقة العضو",
                                                            "Block a number with the + button above, or from the member sheet")
                                                        : nil,
                                                     tint: DS.Color.success)))
        }
        return AnyView(AdminSectionCard(title: t("الأرقام الممنوعة من التسجيل", "Numbers blocked from signing up"),
                                        tag: t("\(phones.count) رقم", phones.count == 1 ? "1 number" : "\(phones.count) numbers"),
                                        spacing: 0) {
            AdminLazyRows(items: phones) { AnyView(bannedPhoneRow($0)) }
        })
    }

    /// صفّ: مربّع المنع + الرقم (من اليسار) + السبب + تاريخ المنع، و«رفع المنع» في الطرف للمالك فقط
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

            if authVM.canManageBannedPhones {
                let number = formatPhoneDisplay(banned.phoneNumber)
                DSChipButton(t("رفع المنع", "Unblock"), icon: "lock.open.fill", tint: DS.Color.error) {
                    phoneToUnban = banned
                }
                .disabled(isProcessing)
                .accessibilityLabel(t("رفع منع \(number)", "Unblock \(number)"))
            }
        }
        .padding(.vertical, DS.Spacing.sm + 2)
        .frame(minHeight: DS.Icon.tapTarget)
    }

    // MARK: - Helpers

    private func formatPhoneDisplay(_ phone: String) -> String {
        phone.count == 8 ? "+965 \(phone)" : KuwaitPhone.display(phone)
    }

    /// الأرقام تبقى بترتيبها من اليسار داخل سطر عربي
    private static func isolatedLTR(_ text: String) -> String {
        "\u{2066}\(text)\u{2069}"
    }

    private static func parseDate(_ isoString: String) -> Date? {
        AdminDeviceReachStore.date(isoString)
    }

    private func formatDate(_ isoString: String) -> String {
        guard let date = Self.parseDate(isoString) else { return isoString }
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

    /// الرقم النهائي بصيغة E.164 (كود الدولة + المحلي) للمنع.
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
        // نفس هيكل مربّعات الإضافة (طلب المالك): رأس أحمر للمنع، قسم البيانات،
        // و«منع الرقم» كحلي يمين / «إلغاء» رمادي يسار
        DSComposer(
            title: t("منع رقم من التسجيل", "Block a number from signing up"),
            subtitle: t("لا يقدر صاحب الرقم يسجّل أو يدخل التطبيق", "The number can't sign up or sign in"),
            icon: "phone.down.fill",
            tint: DS.Color.error,
            actionTitle: t("منع الرقم", "Block number"),
            actionIcon: "phone.down.fill",
            canSubmit: isValid,
            isBusy: isLoading,
            hasUnsavedChanges: hasInput,
            onSubmit: { Task { await banAction() } },
            onCancel: { dismiss() }
        ) {
            DSComposerSection(title: t("بيانات المنع", "Block details"), icon: "phone.down.fill",
                              tint: DS.Color.error, index: 0) {
                // حقل الرقم
                phoneRow

                // سبب المنع
                DSComposerField(icon: "text.bubble.fill",
                                label: t("السبب (اختياري)", "Reason (optional)"),
                                placeholder: t("سبب المنع...", "Reason..."),
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
                "تعذّر منع الرقم. قد يكون ممنوعاً بالفعل.",
                "Couldn't block the number. It may already be blocked."
            )
        }
        isLoading = false
    }
}
