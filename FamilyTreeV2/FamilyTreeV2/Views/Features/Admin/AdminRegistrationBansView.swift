import SwiftUI

/// «التسجيل والمنع» — صفحة واحدة في «الفريق والأمان» (الدفعة ج ٢٠٢٦-١٠-٢٠؛ إعادة التصميم ٢٠٢٦-١١-٢٦، الوحدة U16):
/// الرأس الكحلي (سطر الأرقام: الأرقام الممنوعة · هذا الشهر، و«＋ منع رقم» للمالك) ← «شروط التسجيل» (مفتاح «السماح
/// بالتسجيل» في مكانه؛ لمن يقرأ فقط كلمة «مفعّل/مطفأ») ← «الأرقام الممنوعة من التسجيل» صفوفاً بلا بحث (القائمة قصيرة).
/// المفتاح والمنع ورفعه للمالك فقط (`canManageSettings` / `canManageBannedPhones` × «يعدّل» في الجدول `team.registration`)
/// وبنفس النداءات والتأكيد والمربّع. هذه الصفحة بيت «منع رقم من التسجيل» الوحيد (spec B.7): صفّ «منع الرقم» في ورقة العضو
/// يفتحها برقمه (`prefillPhone`) — يُفتح مربّع المنع مملوءاً ولا يُرسل وحده أبداً؛ الرقم الممنوع من قبل يُقال ولا يُفتح له مربّع.
/// تجربة الأدوار (`-tmpAdminRole`/`-tmpRoleMatrix`): الكتابة هنا تجريبية (`DebugAdminProbe.dryRun`).
struct AdminRegistrationBansView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var appSettingsVM: AppSettingsViewModel

    /// رقم يُملأ في مربّع «منع رقم» (U13: من ورقة العضو، مطبَّعاً بـ`KuwaitPhone.normalizedForStorage`) — nil = لا شيء
    private let prefillPhone: String?

    init(prefillPhone: String? = nil) {
        self.prefillPhone = prefillPhone
    }

    private func t(_ ar: String, _ en: String) -> String { L10n.t(ar, en) }

    @State private var showAddSheet = false
    /// ما يبدأ به مربّع المنع (الرقم المملوء) — nil من زرّ ＋
    @State private var addPrefill: String?
    @State private var prefillHandled = false
    /// الرقم المملوء ممنوع من قبل — يُقال فوق، بلا مربّع
    @State private var alreadyBanned: BannedPhone?
    @State private var phoneToUnban: BannedPhone?
    @State private var isProcessing = false
    /// الأرقام الممنوعة (`fetchBannedPhones` لا يُبلغ الفشل — انتهى بلا اتصال = فشل، لا «لا توجد أرقام» مضلِّلة)
    @State private var bansHealth: AdminStoreHealth = .idle
    /// إعدادات التسجيل (وصلت = `updatedAt`)
    @State private var settingsHealth: AdminStoreHealth = .idle

    /// منع رقم ورفعه: صلاحية الدور × «يعدّل» في الجدول
    private var canBan: Bool { authVM.canManageBannedPhones && authVM.adminCanEdit(.teamRegistration) }
    /// مفتاح «السماح بالتسجيل»
    private var canEditRules: Bool { authVM.canManageSettings && authVM.adminCanEdit(.teamRegistration) }

    private func loadBans() async {
        bansHealth = AdminTeamLogic.seeded(bansHealth, hasData: !authVM.bannedPhones.isEmpty).beginning()
        await authVM.fetchBannedPhones()
        bansHealth = bansHealth.ending(success: NetworkMonitor.shared.isConnected)
    }

    private func loadSettings() async {
        settingsHealth = AdminTeamLogic.seeded(settingsHealth, hasData: appSettingsVM.settings.updatedAt != nil).beginning()
        await appSettingsVM.fetchSettings()
        settingsHealth = settingsHealth.ending(success: appSettingsVM.settings.updatedAt != nil)
    }

    /// ما في الذاكرة من صفحة أخرى يُعرض فوراً (لا «—» يومض قبل أول جلب هنا)
    private var bansShown: AdminStoreHealth {
        AdminTeamLogic.seeded(bansHealth, hasData: !authVM.bannedPhones.isEmpty)
    }

    var body: some View {
        AdminPage(header: header, lead: AnyView(lead), content: phonesContent, updatedAt: bansHealth.lastGood)
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
            .dsCenterBox(isPresented: $showAddSheet) {
                AddBanSheet(authVM: authVM, prefill: addPrefill)
            }
            .dsAlert(
                t("رفع منع الرقم؟", "Unblock the number?"),
                isPresented: Binding(
                    get: { phoneToUnban != nil },
                    set: { if !$0 { phoneToUnban = nil } }
                )
            ) {
                Button(t("إلغاء", "Cancel"), role: .cancel) { phoneToUnban = nil }
                Button(t("ارفع المنع", "Unblock"), role: .destructive) {
                    guard let phone = phoneToUnban else { return }
                    Task {
                        isProcessing = true
                        if !DebugAdminProbe.dryRun("banned_phones unban \(phone.id)") {
                            _ = await authVM.unbanPhone(phone.id)
                        }
                        isProcessing = false
                        phoneToUnban = nil
                    }
                }
            } message: {
                if let phone = phoneToUnban {
                    Text(verbatim: t("يقدر صاحب الرقم \(formatPhoneDisplay(phone.phoneNumber)) يسجّل من جديد.",
                                     "The owner of \(formatPhoneDisplay(phone.phoneNumber)) can sign up again."))
                }
            }
            .refreshable {
                async let settings: Void = loadSettings()
                await loadBans()
                await settings
            }
            .task {
                async let settings: Void = loadSettings()
                await loadBans()
                await settings
                handlePrefill()
            }
            .debugStackProbe("AdminRegistrationBansView")
    }

    /// الرقم من ورقة العضو: ممنوع من قبل ← يُقال فوق؛ وإلا يُفتح مربّع المنع مملوءاً (الإرسال بيد المالك دائماً). مرة واحدة
    private func handlePrefill() {
        guard !prefillHandled else { return }
        prefillHandled = true
        guard canBan, let raw = prefillPhone?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return }
        let key = KuwaitPhone.banKey(raw)
        if let match = authVM.bannedPhones.first(where: { KuwaitPhone.banKey($0.phoneNumber) == key }) {
            alreadyBanned = match
            return
        }
        addPrefill = raw
        showAddSheet = true
    }

    // MARK: - الرأس الكحلي

    /// سطر الأرقام: الأرقام الممنوعة وما أُضيف هذا الشهر — «—» قبل التحميل، «تعذّر» بإعادة المحاولة. «منع رقم» للمالك فقط
    private var header: AdminPageHeader {
        let phones = authVM.bannedPhones
        let now = Date()
        let thisMonth = phones.compactMap { Self.parseDate($0.createdAt) }
            .filter { Calendar.current.isDate($0, equalTo: now, toGranularity: .month) }.count
        let retry: () -> Void = { Task { await loadBans() } }
        return AdminPageHeader(
            title: t("التسجيل والمنع", "Sign-up and blocking"),
            subtitle: t("من يحق له التسجيل في التطبيق، والأرقام الممنوعة من التسجيل",
                        "Who can sign up, and the numbers blocked from signing up"),
            readOnly: !canEditRules,
            items: [
                AdminHeaderItem(id: "banned", value: phones.count, label: AdminTeamLogic.bannedLabel(phones.count),
                                health: bansShown, retry: retry,
                                spoken: AdminTeamLogic.bannedLine(phones.count)),
                AdminHeaderItem(id: "month", value: thisMonth, label: t("هذا الشهر", "This month"),
                                health: bansShown, retry: retry,
                                spoken: t("أُضيف هذا الشهر: \(thisMonth)", "Added this month: \(thisMonth)"))
            ],
            actions: canBan ? [AdminPageAction(symbol: "plus", label: t("منع رقم من التسجيل", "Block a number"),
                                               tap: .action { addPrefill = nil; showAddSheet = true })] : [])
    }

    // MARK: - أول البطاقات: الرقم الممنوع من قبل + شروط التسجيل

    private var lead: some View {
        VStack(spacing: DS.Hub.cardGap) {
            if let banned = alreadyBanned {
                alreadyBannedCard(banned)
            }
            rulesCard
        }
    }

    /// الرقم الذي جاء من ورقة العضو ممنوع من قبل — لا مربّع منع ثانٍ
    private func alreadyBannedCard(_ banned: BannedPhone) -> some View {
        AdminSectionCard(framed: true) {
            AdminInfoRow(icon: "checkmark.shield.fill", tint: DS.Color.success,
                         title: t("هذا الرقم ممنوع من التسجيل من قبل", "This number is already blocked"),
                         subtitle: Self.isolatedLTR(formatPhoneDisplay(banned.phoneNumber)) + " · "
                            + t("تجده في القائمة تحت", "It's in the list below"))
        }
    }

    /// «السماح بالتسجيل» — نفس المفتاح السابق (`allow_new_registrations`): المالك يعدّل، ومن يقرأ يرى كلمة. قبل وصول
    /// الإعدادات المفتاح معطّل (لا يُكتب الافتراضي)، والفشل «تعذّر التحميل ↻»
    private var rulesCard: some View {
        let s = appSettingsVM.settings
        let ready = s.updatedAt != nil
        let control: AnyView
        if !ready, settingsHealth.canRetry {
            control = AnyView(AdminStatePill(health: settingsHealth, title: "", tone: .off,
                                             retry: { Task { await loadSettings() } }).fixedSize())
        } else if !canEditRules {
            control = AnyView(AdminStatePill(health: ready ? .loaded(at: Date()) : .loading,
                                             title: s.allowNewRegistrations ? t("مفعّل", "On") : t("مطفأ", "Off"),
                                             tone: s.allowNewRegistrations ? .ok : .off).fixedSize())
        } else {
            control = AnyView(Toggle(t("السماح بالتسجيل", "Allow sign-ups"), isOn: Binding(
                get: { s.allowNewRegistrations },
                set: { on in setRegistrations(on) }))
                .labelsHidden()
                .tint(DS.Color.toggleOn)
                .accessibilityLabel(t("السماح بالتسجيل", "Allow sign-ups"))
                .disabled(!ready || appSettingsVM.isSaving))
        }
        return AdminSectionCard(title: t("شروط التسجيل", "Sign-up rules")) {
            AdminControlRow(icon: "person.badge.plus", tint: DS.Color.palm,
                            title: t("السماح بالتسجيل", "Allow sign-ups"),
                            subtitle: t("أعضاء جدد يسجّلون بأنفسهم، ويصل طلبهم «الوارد» للمراجعة",
                                        "New members sign up themselves; their request reaches the Inbox for review"),
                            control: control)
        }
    }

    /// نفس الكتابة السابقة — وفي تجربة الأدوار نجاح مصطنع محلي بلا كتابة
    private func setRegistrations(_ on: Bool) {
        if DebugAdminProbe.dryRun("app_settings allow_new_registrations=\(on)") {
            appSettingsVM.settings.allowNewRegistrations = on
            return
        }
        Task { await appSettingsVM.updateSetting("allow_new_registrations", value: on, updatedBy: authVM.currentUser?.id) }
    }

    // MARK: - الأرقام الممنوعة

    private var phonesContent: AnyView {
        let phones = authVM.bannedPhones
        if phones.isEmpty, let state = AdminPageStateCard(
            health: bansHealth,
            loading: t("جارٍ تحميل الأرقام الممنوعة…", "Loading blocked numbers…"),
            failed: t("تعذّر تحميل الأرقام الممنوعة", "Couldn't load blocked numbers"),
            message: t("تحقّق من اتصالك وحاول مرة أخرى", "Check your connection and try again"),
            retry: { Task { await loadBans() } }) {
            return AnyView(state)
        }
        if phones.isEmpty {
            return AnyView(AdminPageStateCard(.empty(t("لا أرقام ممنوعة من التسجيل", "No blocked numbers"),
                                                     message: canBan
                                                        ? t("تمنع رقماً من زر ＋ في الأعلى، أو من ورقة العضو",
                                                            "Block a number with the + button above, or from the member sheet")
                                                        : nil,
                                                     tint: DS.Color.success)))
        }
        return AnyView(AdminSectionCard(title: t("الأرقام الممنوعة من التسجيل", "Numbers blocked from signing up"),
                                        tag: AdminTeamLogic.bannedLine(phones.count),
                                        spacing: 0) {
            AdminLazyRows(items: phones) { AnyView(bannedPhoneRow($0)) }
        })
    }

    /// صفّ: مربّع المنع + الرقم (من اليسار) + السبب + تاريخ المنع، و«رفع المنع» في الطرف للمالك فقط
    private func bannedPhoneRow(_ banned: BannedPhone) -> some View {
        let number = formatPhoneDisplay(banned.phoneNumber)
        return HStack(spacing: DS.Spacing.md) {
            AdminIconSquare(symbol: "phone.down.fill", tint: DS.Color.error)

            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(verbatim: Self.isolatedLTR(number))
                    .dsFont(.body)
                    .foregroundColor(DS.Color.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                if let reason = banned.reason, !reason.isEmpty {
                    Text(verbatim: reason)
                        .dsFont(.subtitle)
                        .foregroundColor(DS.Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(verbatim: formatDate(banned.createdAt))
                    .dsFont(.subtitle)
                    .foregroundColor(DS.Color.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 0)

            if canBan {
                AdminPillButton(title: t("رفع المنع", "Unblock"), icon: "lock.open.fill", style: .reject) {
                    phoneToUnban = banned
                }
                .disabled(isProcessing)
                .accessibilityLabel(t("رفع منع \(number)", "Unblock \(number)"))
            }
        }
        .padding(.vertical, DS.Spacing.sm)
        .frame(minHeight: DS.Hub.rowMinHeightTwoLines)
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
        return DateHelper.displayDateTime(date)
    }
}

// MARK: - Add Ban Sheet

struct AddBanSheet: View {
    @ObservedObject var authVM: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    private func t(_ ar: String, _ en: String) -> String { L10n.t(ar, en) }

    @State private var phoneNumber: String
    @State private var selectedPhoneCountry: KuwaitPhone.Country
    @State private var reason = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    /// ما بدأ به المربّع (رقم مملوء من ورقة العضو) — «إلغاء» يسأل فقط إن تغيّر عنه شيء
    private let initialDigits: String
    private let initialCountry: KuwaitPhone.Country

    /// - prefill: رقم مطبَّع (`KuwaitPhone.normalizedForStorage`: ٨ أرقام كويتية أو «+رمز…») يُملأ في الحقل — لا يُرسل وحده
    init(authVM: AuthViewModel, prefill: String? = nil) {
        _authVM = ObservedObject(wrappedValue: authVM)
        let start = KuwaitPhone.detectCountryAndLocal(prefill)
        initialDigits = start.localDigits
        initialCountry = start.country
        _phoneNumber = State(initialValue: start.localDigits)
        _selectedPhoneCountry = State(initialValue: start.country)
    }

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

    /// أي إدخال غيّر ما بدأ به المربّع (رقم، سبب، أو دولة) → «إلغاء» يسأل قبل التجاهل (توصية أبل)
    private var hasInput: Bool {
        localDigits != KuwaitPhone.normalizeDigits(initialDigits).filter(\.isNumber)
            || !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || selectedPhoneCountry != initialCountry
    }

    var body: some View {
        // نفس هيكل مربّعات الإضافة (طلب المالك): رأس أحمر للمنع، قسم البيانات،
        // و«منع الرقم» كحلي يمين / «إلغاء» رمادي يسار
        DSComposer(
            title: t("منع رقم من التسجيل", "Block a number from signing up"),
            subtitle: t("لا يستطيع صاحب الرقم التسجيل أو الدخول إلى التطبيق", "The number can't sign up or sign in"),
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

        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        // تجربة الأدوار: لا كتابة، نجاح مصطنع
        if DebugAdminProbe.dryRun("banned_phones insert \(Log.masked(cleanPhone))") {
            isLoading = false
            dismiss()
            return
        }
        let success = await authVM.banPhone(cleanPhone, reason: trimmedReason.isEmpty ? nil : trimmedReason)

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
