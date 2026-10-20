import SwiftUI

// MARK: - بطاقات صفحة «رسائل رمز الدخول (KWT SMS)» السفلى ومربّعات أدواتها
//
// آخر الإرسالات (فحص الحالة) · أدوات · التنبيهات (المالك يعدّل، المدير يقرأ) · الحدود · الإعداد، ومربّعات
// «فحص رقم» و«المرسلون» و«التغطية». كل بطاقة نوع مستقل يُرسم خلف `AnyView` في `AdminSmsView` (حارس المكدس).

// MARK: آخر الإرسالات

struct SmsRecentCard: View {
    let overview: SmsOverview
    @ObservedObject var actions: SmsPageActions
    @State private var showsAll = false
    /// الصفوف الظاهرة قبل «الكل»
    private static let collapsedCount = 8

    var body: some View {
        let all = overview.recent
        let rows = showsAll ? all : Array(all.prefix(Self.collapsedCount))
        VStack(alignment: .leading, spacing: 0) {
            AdminCardHeader(title: L10n.t("آخر الإرسالات", "Recent sends")) {
                if all.count > Self.collapsedCount {
                    Button { showsAll.toggle() } label: {
                        AdminCardLinkLabel(title: showsAll ? L10n.t("عرض أقل", "Show less")
                                                           : L10n.t("الكل (\(all.count))", "All (\(all.count))"),
                                           showsChevron: !showsAll)
                    }
                    .buttonStyle(.plain)
                }
            }
            if rows.isEmpty {
                Text(L10n.t("لا إرسال خلال آخر يومين.", "No sends in the last two days."))
                    .dsFont(.subtitle)
                    .foregroundColor(DS.Color.textTertiary)
                    .padding(.vertical, DS.Spacing.sm)
            } else {
                ForEach(rows) { send in
                    SmsSendRow(send: send, actions: actions)
                    if send.id != rows.last?.id { AdminRowDivider() }
                }
            }
            Text(L10n.t("السجل التفصيلي يبقى \(SmsText.days(overview.retentionDays)) ثم يُحذف، والأرقام اليومية تبقى. الرقم نفسه لا يُحفظ — الظاهر آخر 4 خانات من بصمته للتمييز فقط.",
                        "Detailed rows are kept \(overview.retentionDays) days, daily numbers stay. The number itself is never stored — you see the last 4 characters of its fingerprint only."))
                .dsFont(.footnote)
                .foregroundColor(DS.Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, DS.Spacing.sm)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .adminCard()
    }
}

/// صفّ إرسال: الوقت والنتيجة، البصمة والنقاط والرصيد بعده، سبب الفشل، حالة المزوّد، و«فحص الحالة»
private struct SmsSendRow: View {
    let send: SmsOverview.Send
    @ObservedObject var actions: SmsPageActions
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // الخط الكبير: الزر تحت النص بدل الطرف
        let stacked = typeSize >= .xxLarge
        HStack(alignment: .top, spacing: DS.Spacing.sm) {
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: DS.Spacing.xsm) { timeText; SmsOutcomeChips(send: send) }
                    VStack(alignment: .leading, spacing: DS.Spacing.xxs) { timeText; SmsOutcomeChips(send: send) }
                }
                if !meta.isEmpty {
                    Text(verbatim: meta)
                        .dsFont(.footnote)
                        .foregroundColor(DS.Color.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let code = send.errorCode {
                    Text(verbatim: SmsText.errorLine(code))
                        .dsFont(.footnote)
                        .foregroundColor(DS.Color.error)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let status = send.deliveryStatus {
                    Text(verbatim: statusLine(status))
                        .dsFont(.footnote)
                        .foregroundColor(DS.Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if stacked, let msgid = send.msgid { checkButton(msgid) }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            if !stacked, let msgid = send.msgid { checkButton(msgid) }
        }
        .padding(.vertical, DS.Spacing.sm + 2)
    }

    private var timeText: some View {
        Text(verbatim: SmsText.time(send.at))
            .dsFont(.hubRow)
            .monospacedDigit()
            .foregroundColor(DS.Color.textPrimary)
            .lineLimit(1)
    }

    /// «١ نقطة · الرصيد بعدها ١٧ · ••••7c2e» — البصمة اللاتينية معزولة حتى لا تقلب ترتيب السطر العربي
    private var meta: String {
        var parts: [String] = []
        if let points = send.points { parts.append(L10n.t("\(SmsText.number(points)) نقطة", "\(SmsText.number(points)) pts")) }
        if let after = send.balanceAfter {
            parts.append(L10n.t("الرصيد بعدها \(SmsBalanceText.points(after))", "balance after \(SmsBalanceText.points(after))"))
        }
        if let tail = send.phoneTail, !tail.isEmpty { parts.append(SmsText.isolate("••••\(tail)")) }
        return parts.joined(separator: " · ")
    }

    private func statusLine(_ status: String) -> String {
        let readable = SmsText.deliveryStatus(status)
        let when = send.deliveryCheckedAt.map { " · " + DateHelper.relativeTime(from: $0) } ?? ""
        return L10n.t("عند المزوّد: \(readable)\(when)", "At the provider: \(readable)\(when)")
    }

    private func checkButton(_ msgid: String) -> some View {
        DSChipButton(L10n.t("فحص الحالة", "Check status"), icon: "magnifyingglass", size: .small,
                     isLoading: actions.isBusy("status:\(msgid)")) {
            actions.checkStatus(msgid)
        }
        .accessibilityHint(L10n.t("يسأل KWT SMS عن حالة هذه الرسالة", "Asks KWT SMS about this message"))
    }
}

/// شارة النتيجة (+ «تجريبي» أو «اختبار المالك»)
private struct SmsOutcomeChips: View {
    let send: SmsOverview.Send

    var body: some View {
        HStack(spacing: DS.Spacing.xs) {
            DSStatusChip(text: outcome.title, icon: outcome.icon, tint: outcome.tint, size: .mini)
            if send.adminTest {
                DSStatusChip(text: L10n.t("اختبار المالك", "Owner test"), icon: "person.fill.checkmark",
                             tint: DS.Color.info, size: .mini)
            } else if send.test {
                DSStatusChip(text: L10n.t("تجريبي", "Test"), icon: "flask.fill", tint: DS.Color.slate, size: .mini)
            }
        }
    }

    private var outcome: (title: String, icon: String, tint: Color) {
        switch send.outcome {
        case "accepted": return (L10n.t("مقبول", "Accepted"), "checkmark.circle.fill", DS.Color.success)
        case "failed":   return (L10n.t("فشل", "Failed"), "xmark.circle.fill", DS.Color.error)
        case "pending":  return (L10n.t("قيد الإرسال", "Sending"), "clock.fill", DS.Color.info)
        default:         return (L10n.t("غير معروف", "Unknown"), "questionmark.circle.fill", DS.Color.warning)
        }
    }
}

// MARK: الأدوات

struct SmsToolsCard: View {
    @ObservedObject var actions: SmsPageActions
    /// الرسالة التجريبية للمالك فقط (السيرفر يرفض غيره `owner_only`)
    let isOwner: Bool

    var body: some View {
        // «اسم المرسل» و«الدول المتاحة» صارا صفّين في «إعدادات الإرسال» (كانا مكرّرين هنا وهناك — الدفعة ج)
        AdminRowsCard(title: L10n.t("الأدوات", "Tools"),
                      footnote: isOwner ? L10n.t("الرسالة التجريبية وحدها ترسل رسالة فعلية وتخصم نقطة.",
                                                 "Only the test message is really sent and costs a point.") : nil) {
            if isOwner {
                let busy = actions.isBusy("test")
                Button { actions.confirmTest = true } label: {
                    AdminListRow(icon: "paperplane.fill", tint: DS.Color.sea,
                                 title: L10n.t("إرسال رسالة تجريبية لرقمي", "Send a test message to my number"),
                                 subtitle: busy ? L10n.t("جارٍ الإرسال…", "Sending…")
                                                : L10n.t("رسالة لرقم ملفك · نقطة واحدة · مرة كل 10 دقائق",
                                                         "To your profile number · 1 point · once every 10 minutes"))
                }
                .buttonStyle(.plain)
                .disabled(busy)
            }
            Button { actions.box = .validate } label: {
                AdminListRow(icon: "phone.fill", tint: DS.Color.sea,
                             title: L10n.t("التحقق من رقم", "Check a number"),
                             subtitle: L10n.t("هل يصل رمز الدخول لرقم كويتي؟", "Will a sign-in code reach a Kuwaiti number?"))
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: تنبيهات الرصيد

/// عتبات تنبيه الرصيد وفواصله — المالك يعدّل (تُحفظ الأربعة معاً بعد توقّف الضغط)، المدير يقرأ. مكانها الوحيد
/// (كانت تُشرح ثانيةً في «طريقة العمل»)، ومعها «آخر تنبيه»
struct SmsAlertsCard: View {
    /// من النظرة (الأحدث من السيرفر) — احتياط إن لم تصل أعمدة `app_settings` بعد
    let alerts: SmsOverview.Alerts?
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var appSettingsVM: AppSettingsViewModel
    @EnvironmentObject private var notificationVM: NotificationViewModel
    /// تعديل المالك قبل الحفظ (يظهر فوراً)
    @State private var draft: SmsOverview.Alerts?
    @State private var generation = 0
    @State private var saveFailed = false
    /// أعلى «منخفض» يصل له المبدّل (السيرفر يقبل أكثر)
    private static let lowMax = 2000

    var body: some View {
        let value = draft ?? saved
        let canEdit = authVM.canManageSettings && appSettingsVM.settings.smsLowThreshold != nil
        // حدود المبدّل صالحة دائماً (أدنى ≤ أعلى) ولو وصلت قيم غريبة
        let lowUpper = max(Self.lowMax, value.lowThreshold, value.urgentThreshold)
        AdminRowsCard(title: L10n.t("تنبيهات الرصيد", "Balance alerts"), footnote: footnote(canEdit: canEdit)) {
            if canEdit {
                stepperRow("exclamationmark.triangle.fill", DS.Color.warning, L10n.t("منخفض تحت", "Low below"),
                           value.lowThreshold, min(value.urgentThreshold, lowUpper)...lowUpper, 10, .points) {
                    var a = value; a.lowThreshold = $0; save(a)
                }
                stepperRow("flame.fill", DS.Color.error, L10n.t("عاجل تحت", "Urgent below"),
                           value.urgentThreshold, 0...max(0, value.lowThreshold), 5, .points) {
                    var a = value; a.urgentThreshold = $0; save(a)
                }
                stepperRow("clock.arrow.circlepath", DS.Color.warning, L10n.t("تكرار المنخفض كل", "Repeat low every"),
                           value.lowRepeatHours, 6...168, 6, .hours) {
                    var a = value; a.lowRepeatHours = $0; save(a)
                }
                stepperRow("clock.arrow.circlepath", DS.Color.error, L10n.t("تكرار العاجل كل", "Repeat urgent every"),
                           value.urgentRepeatHours, 1...168, 1, .hours) {
                    var a = value; a.urgentRepeatHours = $0; save(a)
                }
            } else {
                SmsKVRow(icon: "exclamationmark.triangle.fill", label: L10n.t("منخفض", "Low"),
                         value: value.lowThreshold == 0 ? L10n.t("مطفأ", "Off")
                                                        : L10n.t("أقل من \(value.lowThreshold) · كل \(value.lowRepeatHours) ساعة",
                                                                 "Below \(value.lowThreshold) · every \(value.lowRepeatHours) h"),
                         tint: DS.Color.warning)
                SmsKVRow(icon: "flame.fill", label: L10n.t("عاجل", "Urgent"),
                         value: value.urgentThreshold == 0 ? L10n.t("مطفأ", "Off")
                                                           : L10n.t("أقل من \(value.urgentThreshold) · كل \(value.urgentRepeatHours) ساعة",
                                                                    "Below \(value.urgentThreshold) · every \(value.urgentRepeatHours) h"),
                         tint: DS.Color.error)
            }
            SmsKVRow(icon: "person.2.fill", label: L10n.t("يستلمها", "Sent to"), value: L10n.t("المالك والمدراء", "Owner and admins"))
            if let last = lastAlert.flatMap({ AdminTodayText.since($0) }) {
                SmsKVRow(icon: "bell.badge.fill", label: L10n.t("آخر تنبيه", "Last alert"), value: last)
            }
        }
    }

    /// آخر تنبيه «رصيد الرسائل منخفض» وصل هذا المستخدم — nil إن لم يُحمَّل شيء
    private var lastAlert: Date? {
        notificationVM.notifications.filter { $0.kind == "sms_balance_low" }.map(\.createdDate).max()
    }

    /// المحفوظ: أعمدة `app_settings` (تُحدَّث بعد الحفظ) وإلا النظرة وإلا الافتراضي
    private var saved: SmsOverview.Alerts {
        let s = appSettingsVM.settings
        let d = alerts ?? SmsOverview.Alerts()
        return SmsOverview.Alerts(lowThreshold: s.smsLowThreshold ?? d.lowThreshold,
                                  urgentThreshold: s.smsUrgentThreshold ?? d.urgentThreshold,
                                  lowRepeatHours: s.smsLowRepeatHours ?? d.lowRepeatHours,
                                  urgentRepeatHours: s.smsUrgentRepeatHours ?? d.urgentRepeatHours)
    }

    private func footnote(canEdit: Bool) -> String {
        if saveFailed {
            return L10n.t("تعذّر الحفظ — رجعت القيم المحفوظة. تأكد من الاتصال وجرّب مرة ثانية.",
                          "Couldn't save — the saved values are back. Check the connection and retry.")
        }
        let rule = L10n.t("يصل التنبيه بعد أي رمز دخول مقبول والرصيد تحت العتبة. «منخفض» صفر يطفئ التنبيه.",
                          "The alert follows any accepted sign-in code while the balance is below the threshold. Low = 0 turns it off.")
        return canEdit ? rule : AdminPageHeader.readOnlyText + ". " + rule
    }

    private func stepperRow(_ icon: String, _ tint: Color, _ label: String, _ value: Int, _ range: ClosedRange<Int>,
                            _ step: Int, _ unit: ApprovalHoursStepper.Unit, onChange: @escaping (Int) -> Void) -> some View {
        SmsKVRow(icon: icon, label: label, tint: tint, combines: false) {
            ApprovalHoursStepper(value: value, range: range, step: step, label: label, onChange: onChange, unit: unit)
        }
    }

    /// يظهر فوراً، ويُحفظ بعد توقّف الضغط ثلثي ثانية (الأربعة في تحديث واحد)، ثم تُعاد نظرة الرصيد
    private func save(_ next: SmsOverview.Alerts) {
        draft = next
        saveFailed = false
        generation += 1
        let mine = generation
        Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard mine == generation else { return }
            let ok = await appSettingsVM.updateSmsAlerts(low: next.lowThreshold, urgent: next.urgentThreshold,
                                                         lowHours: next.lowRepeatHours, urgentHours: next.urgentRepeatHours,
                                                         updatedBy: authVM.currentUser?.id)
            guard mine == generation else { return }
            draft = nil
            saveFailed = !ok
            if ok { await SmsBalanceStore.shared.refresh(force: true) }
        }
    }
}

// MARK: - طريقة العمل

/// «طريقة العمل» (كانت «كيف تشتغل رسائل الدخول») — بطاقة مطويّة آخر الصفحة (سطر ملخّص وهي مطويّة): المسار، ما يُحفظ، ما
/// لا يُحفظ أبداً، من يرى ماذا، معنى «ناجحة» و«مشبوهة»، ورابط الشحن. الحدود والتنبيهات لم تعد تُشرح هنا ثانيةً — مكانهما
/// «إعدادات الإرسال» و«تنبيهات الرصيد» (الدفعة ج). النص نفسه سيُنقل للأندرويد
struct SmsHowItWorksCard: View {
    let overview: SmsOverview?
    @ObservedObject private var attempts = SmsLoginAttemptsStore.shared
    @State private var open = false

    private var sender: SmsOverview.Sender { overview?.sender ?? SmsOverview.Sender() }

    var body: some View {
        AdminSectionCard(title: L10n.t("طريقة العمل", "How it works"),
                         isOpen: $open,
                         summary: L10n.t("المسار · ما يُحفظ وما لا يُحفظ · من يرى ماذا",
                                         "The path · what's kept and what never is · who sees what")) {
            AdminRowsCardBody {
                SmsHowRow(icon: "paperplane.fill", tint: DS.Color.sea,
                          title: L10n.t("المسار", "The path"),
                          text: pathText)
                SmsHowRow(icon: "tray.full.fill", tint: DS.Color.primary,
                          title: L10n.t("ما يُحفظ", "What's kept"),
                          text: keptText)
                SmsHowRow(icon: "lock.shield.fill", tint: DS.Color.success,
                          title: L10n.t("ما لا يُحفظ أبداً", "What's never kept"),
                          text: L10n.t("رمز الدخول — لا في جداولنا ولا في سجلات الخدمة؛ \(SmsText.isolate("Supabase")) يحفظه مشفّراً تشفيراً لا ينفك لدقائق فقط للمقارنة.",
                                       "The sign-in code — not in our tables, not in the service logs; Supabase keeps it one-way hashed for a few minutes only, to compare."),
                          warning: L10n.t("تنبيه: لوحة حساب \(SmsText.isolate("KWT SMS")) قد تعرض نص الرسائل المرسلة — احمِ كلمة سر حساب \(SmsText.isolate("KWT")) وفعّل التحقق بخطوتين إن وُجد.",
                                          "Heads-up: the KWT SMS account dashboard may show sent message text — protect the KWT password and turn on two-step verification if offered."))
                SmsHowRow(icon: "eye.fill", tint: DS.Color.info,
                          title: L10n.t("من يرى ماذا", "Who sees what"),
                          text: L10n.t("المالك يرى أرقام «طلبات رمز الدخول» كاملة، والمدير يراها مخفية جزئياً، وغيرهما لا يرى الصفحة.",
                                       "The owner sees full numbers in “Sign-in code requests”, admins see them partly masked, and no one else sees this page."))
                SmsHowRow(icon: "checkmark.seal.fill", tint: DS.Color.success,
                          title: L10n.t("«ناجحة» و«مشبوهة»", "“Signed in” and “Suspicious”"),
                          text: L10n.t("شارة «ناجحة» (بعلامة صح) تعني أن الرقم سجّل دخولاً بعد أول طلب في الفترة؛ «مشبوهة» = 5 طلبات أو أكثر في ساعة.",
                                       "The “Signed in” chip (with a tick) means the number signed in after its first request in the period; “Suspicious” = 5 or more requests in an hour."))
                // «شحن الرصيد» زرّ الرأس وحده (كان رابطاً ثانياً هنا)
            }
        }
    }

    /// المسار باسم المرسل الفعلي (المحفوظ أو الافتراضي المشترك)
    private var pathText: String {
        let name = SmsText.isolate(sender.current)
        if sender.isDefault {
            return L10n.t("العضو يطلب الرمز ← يصله \(SmsText.isolate("SMS")) من المرسل «\(name)» (مرسل مشترك: أبطأ وقد لا يصل لأرقام حجب الإعلانات) ← كل رسالة = نقطة واحدة (الرسالة 53 حرفاً).",
                          "A member asks for a code → it arrives by SMS from the sender “\(sender.current)” (a shared sender: slower, and may miss numbers that block promotions) → each message = 1 point (53 characters).")
        }
        return L10n.t("العضو يطلب الرمز ← يصله \(SmsText.isolate("SMS")) من المرسل «\(name)» (مرسل خاص معتمد في حساب \(SmsText.isolate("KWT"))، يغيّره المالك من «إعدادات الإرسال») ← كل رسالة = نقطة واحدة (الرسالة 53 حرفاً).",
                      "A member asks for a code → it arrives by SMS from the sender “\(sender.current)” (your own sender approved on the KWT account; the owner changes it in “Sending settings”) → each message = 1 point (53 characters).")
    }

    private var keptText: String {
        let recent = SmsText.days(overview?.retentionDays ?? 2)
        // إعداد المالك (النظرة الأحدث بعد الحفظ)، وإلا ما رجع مع «طلبات رمز الدخول»
        let tries = SmsText.days(overview?.loginAttemptsDays ?? attempts.current?.retentionDays ?? 30)
        return L10n.t("السجل اليومي دائم (عدد الرسائل والمقبولة والفاشلة والنقاط والرصيد). تفاصيل آخر الإرسالات \(recent) فقط (النتيجة، سبب الفشل، رقم الرسالة عند \(SmsText.isolate("KWT"))، الرصيد بعدها — الرقم مخفي). «طلبات رمز الدخول» \(tries) (الرقم والنتيجة وهل سجّل الدخول).",
                      "The daily log is permanent (messages, accepted, failed, points, balance). Recent-send details are kept \(recent) only (result, failure reason, KWT message id, balance after — number hidden). “Sign-in attempts” are kept \(tries) (number, result, signed in or not).")
    }
}

/// صفّ شرح: رمز ملوّن + عنوان عريض + نص (+ تحذير كهرماني، + سطر صغير)
private struct SmsHowRow: View {
    let icon: String
    let tint: Color
    let title: String
    let text: String
    var warning: String? = nil
    var note: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: DS.Spacing.md) {
            AdminIconSquare(symbol: icon, tint: tint, side: DS.Hub.miniIcon, radius: DS.Hub.miniIconRadius,
                            glyph: DS.Glyph.md)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(title)
                    .dsFont(.hubRow)
                    .foregroundColor(DS.Color.textPrimary)
                Text(verbatim: text)
                    .dsFont(.footnote)
                    .foregroundColor(DS.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let warning {
                    Label {
                        Text(verbatim: warning).fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").dsGlyph(DS.Glyph.sm)
                    }
                    .dsFont(.footnote)
                    .foregroundColor(DS.Color.warning.dsReadableGlyph)
                    .padding(.top, DS.Spacing.xxs)
                }
                if let note {
                    Text(verbatim: note)
                        .dsFont(.caption)
                        .monospacedDigit()
                        .foregroundColor(DS.Color.textTertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, DS.Spacing.sm)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - مربّعات الأدوات

struct SmsToolBoxView: View {
    let kind: SmsToolBox
    /// لنتيجة «اسم المرسل» (نافذة اقتراح الاختبار) — nil في المعاينة
    var actions: SmsPageActions? = nil

    var body: some View {
        switch kind {
        case .validate: SmsValidateBox()
        case .senders:  SmsSendersBox()
        case .coverage: SmsCoverageBox()
        case .sender:   SmsSenderBox(actions: actions)
        }
    }
}

/// نتيجة فحص أو خطأ داخل مربّع
private struct SmsBoxResult: Equatable {
    let text: String
    let icon: String
    let tint: Color

    static func failure(_ error: Error) -> SmsBoxResult {
        let e = error as? SmsAdminError ?? SmsAdminError(code: "network")
        return SmsBoxResult(text: e.message, icon: "exclamationmark.triangle.fill", tint: DS.Color.warning)
    }
}

/// «فحص رقم»: رقم كويتي واحد ← KWT `validate`
private struct SmsValidateBox: View {
    @Environment(\.dismiss) private var dismiss
    @State private var phone = ""
    @State private var busy = false
    @State private var result: SmsBoxResult?

    private var local: String { KuwaitPhone.localEightDigits(phone) }
    private var isValid: Bool { local.count == 8 && "4569".contains(local.prefix(1)) }

    var body: some View {
        DSComposer(title: L10n.t("التحقق من رقم", "Check a number"),
                   subtitle: L10n.t("هل يصل رمز الدخول لهذا الرقم؟", "Will a sign-in code reach this number?"),
                   icon: "phone.fill", tint: DS.Color.sea,
                   actionTitle: L10n.t("افحص", "Check"), actionIcon: "magnifyingglass",
                   cancelTitle: L10n.t("إغلاق", "Close"),
                   canSubmit: isValid && !busy, isBusy: busy,
                   onSubmit: check, onCancel: { dismiss() }) {
            DSComposerSection(title: L10n.t("الرقم", "Number"), icon: "phone.fill", tint: DS.Color.sea, index: 0) {
                DSComposerField(icon: "phone.fill", label: L10n.t("رقم الجوال", "Mobile number"),
                                placeholder: "5XXXXXXX", text: $phone, tint: DS.Color.sea,
                                keyboard: .phonePad, ltr: true)
                Text(L10n.t("أرقام الكويت فقط: 8 أرقام تبدأ بـ 4 أو 5 أو 6 أو 9.",
                            "Kuwait numbers only: 8 digits starting with 4, 5, 6 or 9."))
                    .dsFont(.footnote)
                    .foregroundColor(DS.Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let result {
                DSNoteCard(result.text, icon: result.icon, tint: result.tint)
            }
        }
        .onChange(of: phone) { _ in result = nil }
    }

    private func check() {
        guard isValid, !busy else { return }
        busy = true
        result = nil
        let number = "965" + local
        Task {
            defer { busy = false }
            do {
                let reply = try await SmsBalanceStore.shared.call("validate", phone: number, as: SmsBalanceStore.ValidateReply.self)
                result = verdict(reply.verdict)
            } catch {
                guard !ErrorHelper.isCancellation(error) else { return }
                result = .failure(error)
            }
        }
    }

    private func verdict(_ raw: String) -> SmsBoxResult {
        switch raw {
        case "valid":
            return SmsBoxResult(text: L10n.t("الرقم صالح ويصله رمز الدخول.", "Valid — the sign-in code reaches it."),
                                icon: "checkmark.circle.fill", tint: DS.Color.success)
        case "no_route":
            return SmsBoxResult(text: L10n.t("الرقم صحيح لكن لا يوجد مسار إرسال له الآن — قد لا يصله الرمز.",
                                             "The number is fine but has no route right now — the code may not arrive."),
                                icon: "exclamationmark.triangle.fill", tint: DS.Color.warning)
        case "invalid":
            return SmsBoxResult(text: L10n.t("الرقم غير صالح عند المزوّد.", "The provider says the number is invalid."),
                                icon: "xmark.circle.fill", tint: DS.Color.error)
        default:
            return SmsBoxResult(text: L10n.t("لم يحدّد المزوّد نتيجة لهذا الرقم.", "The provider gave no verdict for this number."),
                                icon: "questionmark.circle.fill", tint: DS.Color.info)
        }
    }
}

/// «المرسلون»: أسماء المرسل في الحساب، والمستخدم الآن
private struct SmsSendersBox: View {
    @Environment(\.dismiss) private var dismiss
    @State private var reply: SmsBalanceStore.SendersReply?
    @State private var failure: SmsBoxResult?

    var body: some View {
        DSComposer(title: L10n.t("أسماء المرسل المعتمدة", "Approved sender names"),
                   subtitle: L10n.t("أسماء المرسل المعتمدة في حساب KWT SMS", "Approved sender names on the KWT SMS account"),
                   icon: "tag.fill", tint: DS.Color.actionNavy,
                   actionTitle: "", showsAction: false, cancelTitle: L10n.t("إغلاق", "Close"),
                   canSubmit: false, onSubmit: {}, onCancel: { dismiss() }) {
            if let reply {
                DSComposerSection(title: L10n.t("في الحساب", "On the account"), icon: "tag.fill",
                                  trailing: "\(reply.senders.count)", index: 0) {
                    if reply.senders.isEmpty {
                        DSEmptyView(L10n.t("لا مرسلين في الحساب", "No sender IDs on the account"), style: .inline)
                    }
                    ForEach(reply.senders, id: \.self) { sender in
                        HStack(spacing: DS.Spacing.sm) {
                            Text(verbatim: sender)
                                .dsFont(.hubRow)
                                .foregroundColor(DS.Color.textPrimary)
                                .environment(\.layoutDirection, .leftToRight)
                            Spacer(minLength: DS.Spacing.sm)
                            if sender == reply.inUse {
                                DSStatusChip(text: L10n.t("المستخدم الآن", "In use"), icon: "checkmark",
                                             tint: DS.Color.success, size: .mini)
                            }
                        }
                        .frame(minHeight: DS.Icon.tapTarget)
                    }
                }
                if reply.inUseListed == false, let inUse = reply.inUse {
                    DSNoteCard(L10n.t("المرسل المستخدم في التطبيق (\(inUse)) ليس في قائمة الحساب — قد تفشل الرسائل.",
                                      "The app's sender (\(inUse)) isn't on the account's list — messages may fail."),
                               icon: "exclamationmark.triangle.fill", tint: DS.Color.warning)
                }
            } else if let failure {
                DSNoteCard(failure.text, icon: failure.icon, tint: failure.tint)
            } else {
                DSPageLoader(L10n.t("جاري السؤال من KWT SMS…", "Asking KWT SMS…"),
                             size: DS.Icon.loaderArtInline, fillsSpace: false)
            }
        }
        .task {
            do { reply = try await SmsBalanceStore.shared.call("senderid", as: SmsBalanceStore.SendersReply.self) }
            catch { if !ErrorHelper.isCancellation(error) { failure = .failure(error) } }
        }
    }
}

/// «التغطية»: هل الكويت مفعّلة، وكل البادئات المفعّلة في الحساب
private struct SmsCoverageBox: View {
    @Environment(\.dismiss) private var dismiss
    @State private var reply: SmsBalanceStore.CoverageReply?
    @State private var failure: SmsBoxResult?

    var body: some View {
        DSComposer(title: L10n.t("الدول المتاحة", "Available countries"),
                   subtitle: L10n.t("الدول المتاحة في حساب KWT SMS", "Countries enabled on the KWT SMS account"),
                   icon: "globe", tint: DS.Color.actionNavy,
                   actionTitle: "", showsAction: false, cancelTitle: L10n.t("إغلاق", "Close"),
                   canSubmit: false, onSubmit: {}, onCancel: { dismiss() }) {
            if let reply {
                DSNoteCard(reply.kuwait ? L10n.t("الكويت (+965) متاحة — رموز الدخول تصل.", "Kuwait (+965) is enabled — sign-in codes go out.")
                                        : L10n.t("الكويت (+965) غير متاحة في الحساب — رموز الدخول لن تصل!", "Kuwait (+965) is NOT enabled — sign-in codes won't go out!"),
                           icon: reply.kuwait ? "checkmark.circle.fill" : "exclamationmark.octagon.fill",
                           tint: reply.kuwait ? DS.Color.success : DS.Color.error)
                DSComposerSection(title: L10n.t("رموز الدول المتاحة", "Enabled country codes"), icon: "globe",
                                  trailing: "\(reply.prefixes.count)", index: 1) {
                    Text(verbatim: reply.prefixes.isEmpty ? "—" : reply.prefixes.map { "+\($0)" }.joined(separator: " · "))
                        .dsFont(.callout)
                        .monospacedDigit()
                        .foregroundColor(DS.Color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .environment(\.layoutDirection, .leftToRight)
                    Text(L10n.t("التطبيق يرسل لأرقام الكويت فقط مهما كانت الدول المتاحة.", "The app sends to Kuwaiti numbers only, whatever the coverage."))
                        .dsFont(.footnote)
                        .foregroundColor(DS.Color.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if let failure {
                DSNoteCard(failure.text, icon: failure.icon, tint: failure.tint)
            } else {
                DSPageLoader(L10n.t("جاري السؤال من KWT SMS…", "Asking KWT SMS…"),
                             size: DS.Icon.loaderArtInline, fillsSpace: false)
            }
        }
        .task {
            do { reply = try await SmsBalanceStore.shared.call("coverage", as: SmsBalanceStore.CoverageReply.self) }
            catch { if !ErrorHelper.isCancellation(error) { failure = .failure(error) } }
        }
    }
}
