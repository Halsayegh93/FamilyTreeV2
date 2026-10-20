import SwiftUI

// MARK: - «إعدادات الإرسال» في صفحة «رسائل رمز الدخول (KWT SMS)» (السيرفر الحي ٢٠٢٦-١٠-٢٠)
//
// المكان الوحيد لكل إعدادات الإرسال (الدفعة ج): الحدود الأربعة + الحدّ الثابت بالثانية، اسم المرسل (تغييره للمالك، وعرض
// المعتمدين للمدير)، الدول المتاحة (والقائمة الحية من KWT)، ونص الرسالة — كانت مكرّرة في بطاقتي «الحدود» و«الإعداد» وصفّي
// «المرسلون/التغطية» في الأدوات و«طريقة العمل».
//
// الحدود الأربعة (`app_settings`: الانتظار ٦٠–٦٠٠ ث · لنفس الرقم بالساعة ١–٢٠ · للجميع بالساعة ٢٠–١٠٠٠ · حفظ
// «محاولات الدخول» ٧–٩٠ يوماً): تُقرأ من النظرة (`limits`/`retention`)، المالك يعدّل (تُحفظ الأربعة معاً بعد توقّف الضغط —
// `updateSmsLimits`)، المدير يقرأ. سيرفر أقدم بلا `wait_seconds` أو النظرة لم تصل ← للقراءة.
// «اسم المرسل»: من `sms_admin_overview().sender`؛ المالك يغيّره من قائمة KWT المعتمدة عبر `kwtsms-admin`
// (`senderid` ثم `set_sender`) — لا يُكتب في `app_settings` من التطبيق أبداً. بطاقة نوع مستقل خلف `AnyView` (حارس المكدس).

/// الحدود القابلة للتعديل كما تُعرض وتُحفظ
struct SmsSendingLimits: Equatable {
    var waitSeconds: Int
    var perNumberHour: Int
    var allHour: Int
    var retentionDays: Int

    /// درجات «−/+» — الانتظار بدرجات مفهومة، والباقي بقفزات معقولة داخل مدى السيرفر
    static let waitLadder = [60, 90, 120, 180, 300, 600]
    static let allHourLadder = [20, 30, 50, 75, 100, 150, 200, 300, 500, 750, 1000]
    static let retentionLadder = [7, 14, 21, 30, 45, 60, 90]
}

struct SmsSendingSettingsCard: View {
    let overview: SmsOverview?
    @ObservedObject var actions: SmsPageActions
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var appSettingsVM: AppSettingsViewModel
    /// تعديل المالك قبل الحفظ (يظهر فوراً)
    @State private var draft: SmsSendingLimits?
    @State private var generation = 0
    @State private var saveFailed = false

    var body: some View {
        let value = draft ?? saved
        // لا تعديل قبل معرفة القيم الحالية (النظرة) ولا على سيرفر أقدم بلا الأعمدة
        let canEdit = authVM.canManageSettings && overview?.limitsEditable == true
        AdminRowsCard(title: L10n.t("إعدادات الإرسال", "Sending settings"), footnote: footnote(canEdit: canEdit)) {
            if canEdit {
                stepperRow("hourglass", DS.Color.info, L10n.t("الانتظار بين رمزين", "Wait between two codes"),
                           note: L10n.t("أقل من دقيقة غير ممكن — حد خدمة الدخول \(SmsText.isolate("Supabase")).",
                                        "Under a minute isn't possible — a Supabase sign-in limit."),
                           value.waitSeconds, AppSettingsViewModel.smsWaitRange, .seconds, ladder: SmsSendingLimits.waitLadder) {
                    var v = value; v.waitSeconds = $0; save(v)
                }
                stepperRow("phone.fill", DS.Color.sea, L10n.t("رموز لنفس الرقم بالساعة", "Codes per number per hour"),
                           value.perNumberHour, AppSettingsViewModel.smsPerNumberHourRange, .count) {
                    var v = value; v.perNumberHour = $0; save(v)
                }
                stepperRow("person.3.fill", DS.Color.primary, L10n.t("رموز للجميع بالساعة", "Codes for everyone per hour"),
                           value.allHour, AppSettingsViewModel.smsAllHourRange, .count, ladder: SmsSendingLimits.allHourLadder) {
                    var v = value; v.allHour = $0; save(v)
                }
                stepperRow("archivebox.fill", DS.Color.slate, L10n.t("حفظ «طلبات رمز الدخول»", "Keep “Sign-in code requests”"),
                           note: L10n.t("التقليل يحذف الأقدم تدريجياً، والزيادة لا تعيد ما انحذف.",
                                        "Lowering deletes older rows gradually; raising doesn't bring them back."),
                           value.retentionDays, AppSettingsViewModel.loginAttemptsRetentionRange, .days,
                           ladder: SmsSendingLimits.retentionLadder) {
                    var v = value; v.retentionDays = $0; save(v)
                }
            } else {
                SmsKVRow(icon: "hourglass", label: L10n.t("الانتظار بين رمزين", "Wait between two codes"),
                         value: L10n.t("\(value.waitSeconds) ثانية", "\(value.waitSeconds) s"), tint: DS.Color.info)
                SmsKVRow(icon: "phone.fill", label: L10n.t("رموز لنفس الرقم بالساعة", "Codes per number per hour"),
                         value: L10n.t("حتى \(value.perNumberHour)", "Up to \(value.perNumberHour)"), tint: DS.Color.sea)
                SmsKVRow(icon: "person.3.fill", label: L10n.t("رموز للجميع بالساعة", "Codes for everyone per hour"),
                         value: L10n.t("حتى \(value.allHour)", "Up to \(value.allHour)"), tint: DS.Color.primary)
                SmsKVRow(icon: "archivebox.fill", label: L10n.t("حفظ «طلبات رمز الدخول»", "Keep “Sign-in code requests”"),
                         value: SmsText.days(value.retentionDays), tint: DS.Color.slate)
            }
            // ثابت في السيرفر (كان في بطاقة «الحدود» المكررة)
            SmsKVRow(icon: "speedometer", label: L10n.t("رموز للجميع بالثانية", "Codes for everyone per second"),
                     value: L10n.t("حتى \(overview?.limits.allPerSecond ?? SmsOverview.Limits().allPerSecond)",
                                   "Up to \(overview?.limits.allPerSecond ?? SmsOverview.Limits().allPerSecond)"),
                     note: L10n.t("ثابت في السيرفر", "Fixed on the server"), tint: DS.Color.slate)
            SmsSenderRow(sender: sender, canChange: authVM.isOwner) {
                actions.box = authVM.isOwner ? .sender : .senders
            }
            SmsKVRow(icon: "globe", label: L10n.t("الدول المتاحة", "Available countries"),
                     note: L10n.t("أرقام جوال الكويت (+965) التي تبدأ بـ 4 أو 5 أو 6 أو 9.",
                                  "+965 mobile numbers starting with 4, 5, 6 or 9."),
                     tint: DS.Color.primary, combines: false) {
                HStack(spacing: DS.Spacing.xs) {
                    SmsKVValue(text: L10n.t("الكويت فقط", "Kuwait only"))
                    DSChipButton(L10n.t("عرض", "View"), icon: "list.bullet", size: .small) { actions.box = .coverage }
                        .accessibilityHint(L10n.t("يعرض الدول المتاحة في حساب KWT SMS", "Shows the countries enabled on the KWT SMS account"))
                }
            }
            SmsMessagePreviewRow()
        }
    }

    /// المحفوظ: من النظرة (تُحدَّث فوراً بعد الحفظ ثم تُعاد) وإلا الافتراضي
    private var saved: SmsSendingLimits {
        let limits = overview?.limits ?? SmsOverview.Limits()
        return SmsSendingLimits(waitSeconds: limits.waitSeconds, perNumberHour: limits.phonePerHour,
                                allHour: limits.allPerHour, retentionDays: overview?.loginAttemptsDays ?? 30)
    }

    /// المرسل: من النظرة، وإلا الافتراضي
    private var sender: SmsOverview.Sender { overview?.sender ?? SmsOverview.Sender() }

    private func footnote(canEdit: Bool) -> String {
        if saveFailed {
            return L10n.t("تعذّر الحفظ — رجعت القيم المحفوظة. تأكد من الاتصال وجرّب مرة ثانية.",
                          "Couldn't save — the saved values are back. Check the connection and retry.")
        }
        return canEdit ? L10n.t("تُحفظ تلقائياً بعد توقّف الضغط، وتسري على الطلب التالي.",
                                "Saved automatically when you stop tapping; applies to the next request.")
                       : AdminPageHeader.readOnlyText + "."
    }

    private func stepperRow(_ icon: String, _ tint: Color, _ label: String, note: String? = nil, _ value: Int,
                            _ range: ClosedRange<Int>, _ unit: ApprovalHoursStepper.Unit, ladder: [Int]? = nil,
                            onChange: @escaping (Int) -> Void) -> some View {
        SmsKVRow(icon: icon, label: label, note: note, tint: tint, combines: false) {
            ApprovalHoursStepper(value: value, range: range, step: 1, label: label, onChange: onChange, unit: unit,
                                 ladder: ladder)
        }
    }

    /// يظهر فوراً، ويُحفظ بعد توقّف الضغط ثلثي ثانية (الأربعة في تحديث واحد)، ثم تُعاد النظرة (والمحاولات إن تغيّر الحفظ)
    private func save(_ next: SmsSendingLimits) {
        let before = draft ?? saved
        draft = next
        saveFailed = false
        generation += 1
        let mine = generation
        Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard mine == generation else { return }
            let ok = await appSettingsVM.updateSmsLimits(waitSeconds: next.waitSeconds, perNumberHour: next.perNumberHour,
                                                         allHour: next.allHour, retentionDays: next.retentionDays,
                                                         updatedBy: authVM.currentUser?.id)
            guard mine == generation else { return }
            if ok { SmsBalanceStore.shared.applyLimits(next) }
            draft = nil
            saveFailed = !ok
            guard ok else { return }
            await SmsBalanceStore.shared.refresh(force: true)
            if next.retentionDays != before.retentionDays {
                await SmsLoginAttemptsStore.shared.refresh(force: true)
            }
        }
    }
}

/// «نص الرسالة» ومعاينتها (كانت في بطاقة «الإعداد» المكررة)
private struct SmsMessagePreviewRow: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            SmsKVRow(icon: "text.bubble.fill", label: L10n.t("نص الرسالة", "Message text"),
                     value: L10n.t("53 حرفاً · نقطة واحدة", "53 characters · 1 point"))
            Text(verbatim: "عائلة المحمدعلي: رمز الدخول 123456. لا تشاركه مع أحد.")
                .dsFont(.callout)
                .foregroundColor(DS.Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(DS.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .fill(DS.Color.cardBackgroundSoft))
                .environment(\.layoutDirection, .rightToLeft)
                .padding(.bottom, DS.Spacing.sm)
                .accessibilityLabel(L10n.t("معاينة الرسالة", "Message preview"))
        }
    }
}

/// «اسم المرسل»: الاسم + «افتراضي»، و«تغيير» للمالك أو «المعتمدون» للمدير (قائمة KWT للقراءة)
private struct SmsSenderRow: View {
    let sender: SmsOverview.Sender
    let canChange: Bool
    let onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            HStack(spacing: DS.Spacing.sm) {
                Image(dsSymbol: "tag.fill")
                    .dsGlyph(DS.Glyph.md, weight: .semibold)
                    .foregroundColor(DS.Color.accent.dsReadableGlyph)
                    .frame(width: DS.Icon.section)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(L10n.t("اسم المرسل", "Sender name"))
                        .dsFont(.subtitle)
                        .foregroundColor(DS.Color.textSecondary)
                    HStack(spacing: DS.Spacing.xsm) {
                        Text(verbatim: sender.current)
                            .dsFont(.hubRow)
                            .foregroundColor(DS.Color.textPrimary)
                            .lineLimit(1)
                        if sender.isDefault {
                            DSStatusChip(text: L10n.t("افتراضي", "Default"), tint: DS.Color.slate, size: .mini)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: DS.Spacing.sm)
                if canChange {
                    DSChipButton(L10n.t("تغيير", "Change"), icon: "arrow.left.arrow.right", size: .small, action: onChange)
                        .accessibilityHint(L10n.t("يختار اسم مرسل من القائمة المعتمدة في حساب KWT SMS",
                                                  "Picks a sender name from the approved list on the KWT SMS account"))
                } else {
                    DSChipButton(L10n.t("المعتمدة", "Approved"), icon: "list.bullet", size: .small, action: onChange)
                        .accessibilityHint(L10n.t("يعرض أسماء المرسل المعتمدة في حساب KWT SMS",
                                                  "Shows the approved sender names on the KWT SMS account"))
                }
            }
            Text(note)
                .dsFont(.footnote)
                .foregroundColor(DS.Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, DS.Icon.section + DS.Spacing.sm)
        }
        .padding(.vertical, DS.Spacing.sm + 1)
        .frame(minHeight: DS.Icon.tapTarget)
    }

    private var note: String {
        sender.isDefault
            ? L10n.t("مرسل مشترك: أبطأ قليلاً وقد لا يصل لأرقام حجب الإعلانات.",
                     "Shared sender: a bit slower and may miss numbers that block promotions.")
            : L10n.t("مرسل خاص معتمد في حسابك على KWT SMS.", "Your own sender, approved on the KWT SMS account.")
    }
}

// MARK: - مربّع «اسم المرسل» (المالك)

/// القائمة من KWT (`senderid`)، اختيار واحد ← `set_sender`؛ «الرجوع للافتراضي» ← `set_sender` null.
/// `preloaded` = قائمة جاهزة (للمعاينة) بلا سؤال KWT.
struct SmsSenderBox: View {
    var preloaded: SmsBalanceStore.SendersReply? = nil
    var actions: SmsPageActions? = nil
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = SmsBalanceStore.shared
    @State private var reply: SmsBalanceStore.SendersReply?
    @State private var failure: String?
    @State private var selection: String?
    /// save · default — ما يعمل الآن
    @State private var busy: String?
    @State private var error: String?

    /// نفس قيد السيرفر — KWT قد ترجع أسماء بنقطة أو شرطة سفلية لا تُقبل
    static func isAcceptable(_ name: String) -> Bool {
        name.range(of: #"^[A-Za-z0-9 -]{1,11}$"#, options: .regularExpression) != nil
    }

    private var current: SmsOverview.Sender { store.overview?.sender ?? SmsOverview.Sender() }

    var body: some View {
        let list = reply ?? preloaded
        DSComposer(title: L10n.t("اسم المرسل", "Sender name"),
                   subtitle: L10n.t("اختر من المرسلين المعتمدين في حسابك على KWT SMS",
                                    "Pick from the senders approved on your KWT SMS account"),
                   icon: "tag.fill", tint: DS.Color.actionNavy,
                   actionTitle: L10n.t("حفظ المرسل", "Save sender"), actionIcon: "checkmark",
                   canSubmit: canSave, isBusy: busy == "save",
                   extraActions: current.isDefault ? [] : [
                       DSComposerAction(id: "default",
                                        title: L10n.t("الرجوع للافتراضي (\(current.defaultName))",
                                                      "Back to default (\(current.defaultName))"),
                                        icon: "arrow.uturn.backward", isEnabled: busy == nil, fullRow: true) { reset() }
                   ],
                   onSubmit: save, onCancel: { dismiss() }) {
            DSNoteCard(L10n.t("مرسل غير معتمد يوقف رسائل الدخول — القائمة من حسابك في KWT فقط.",
                              "An unapproved sender stops sign-in messages — the list comes from your KWT account only."),
                       icon: "exclamationmark.triangle.fill", tint: DS.Color.warning)
            if let list {
                DSComposerSection(title: L10n.t("المعتمدون في الحساب", "Approved on the account"), icon: "tag.fill",
                                  trailing: "\(list.senders.count)", index: 0) {
                    if list.senders.isEmpty {
                        DSEmptyView(L10n.t("لا مرسلين في الحساب", "No sender IDs on the account"), style: .inline)
                    }
                    ForEach(list.senders, id: \.self) { name in
                        option(name, inUse: name == (list.inUse ?? current.current))
                    }
                }
            } else if let failure {
                DSNoteCard(failure, icon: "exclamationmark.triangle.fill", tint: DS.Color.warning)
            } else {
                DSPageLoader(L10n.t("جاري السؤال من KWT SMS…", "Asking KWT SMS…"),
                             size: DS.Icon.loaderArtInline, fillsSpace: false)
            }
            if let error {
                DSNoteCard(error, icon: "xmark.octagon.fill", tint: DS.Color.error)
            }
        }
        .task {
            guard preloaded == nil, reply == nil else { return }
            do { reply = try await store.call("senderid", as: SmsBalanceStore.SendersReply.self) }
            catch {
                guard !ErrorHelper.isCancellation(error) else { return }
                failure = (error as? SmsAdminError ?? SmsAdminError(code: "network")).message
            }
        }
    }

    private var canSave: Bool {
        guard busy == nil, let selection, Self.isAcceptable(selection) else { return false }
        return current.isDefault || selection != current.current
    }

    private func option(_ name: String, inUse: Bool) -> some View {
        let ok = Self.isAcceptable(name)
        let selected = selection == name
        return Button {
            guard ok else { return }
            error = nil
            selection = name
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            DSRow(icon: "tag.fill", tint: ok ? DS.Color.primary : DS.Color.textTertiary, title: name,
                  subtitle: !ok ? L10n.t("غير مقبول: النقطة والشرطة السفلية غير مسموحة", "Not accepted: dots and underscores aren't allowed")
                                : inUse ? L10n.t("المستخدم الآن", "In use now") : nil) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .dsGlyph(DS.Glyph.lg, weight: .semibold)
                    .foregroundColor(selected ? DS.Color.success.dsReadableGlyph : DS.Color.textTertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!ok || busy != nil)
        .opacity(ok ? 1 : DSActionFill.disabledOpacity)
        .accessibilityLabel(name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func save() {
        guard canSave, let selection else { return }
        apply(selection, key: "save")
    }

    private func reset() {
        guard busy == nil else { return }
        apply(nil, key: "default")
    }

    /// حفظ ثم إغلاق المربّع واقتراح «اختبار إرسال لرقمي» — الخطأ يبقى داخل المربّع (لا يُحفظ شيء)
    private func apply(_ name: String?, key: String) {
        busy = key
        error = nil
        Task {
            defer { busy = nil }
            do {
                let result = try await store.setSender(name)
                let now = result.inUse ?? name ?? current.defaultName
                dismiss()
                let notice = SmsNotice(
                    title: name == nil ? L10n.t("رجع المرسل للافتراضي", "Sender back to default")
                                       : L10n.t("تم تغيير المرسل", "Sender changed"),
                    message: L10n.t("رموز الدخول تُرسل الآن باسم «\(SmsText.isolate(now))». جرّب الآن: «إرسال رسالة تجريبية لرقمي» — تصلك رسالة بالاسم الجديد.",
                                    "Sign-in codes now go out as “\(now)”. Try it now: “Send a test message to my number” — you'll get a message with the new name."),
                    offersTest: true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { actions?.notice = notice }
            } catch {
                guard !ErrorHelper.isCancellation(error) else { return }
                let e = error as? SmsAdminError ?? SmsAdminError(code: "network")
                self.error = e.senderMessage
            }
        }
    }
}
