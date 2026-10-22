import SwiftUI
import UniformTypeIdentifiers

struct SmsAttemptCase: Identifiable {
    let id = UUID()
    let item: SmsLoginAttempts.Item
    let days: Int
}

/// The SMS case has its own modal; member names never navigate to a member record.
struct SmsAttemptDetailsBox: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model: SmsAttemptDetailsStore

    init(item: SmsLoginAttempts.Item, days: Int) {
        _model = StateObject(wrappedValue: SmsAttemptDetailsStore(item: item, days: days))
    }

    var body: some View {
        DSComposer(title: L10n.t("تفاصيل طلبات SMS", "SMS request details"),
                   subtitle: L10n.t("\(SmsAttemptsText.period(model.detail?.days ?? model.days)) · توقيت الكويت", "\(SmsAttemptsText.period(model.detail?.days ?? model.days)) · Kuwait time"),
                   icon: "message.fill", tint: DS.Color.actionNavy, actionTitle: "", showsAction: false,
                   cancelTitle: L10n.t("إغلاق", "Close"), canSubmit: false,
                   onSubmit: {}, onCancel: { dismiss() }) {
            AnyView(identity)
            if authVM.isOwner && !model.denied {
                AnyView(SmsCaseCodeSection(model: model))
            }
            AnyView(SmsCaseSummary(item: visibleItem, days: model.detail?.days ?? model.days))
            if authVM.isOwner && !model.denied {
                AnyView(history)
                AnyView(codeAudit)
            } else {
                DSNoteCard(L10n.t("الرقم الكامل ورمز الدخول وسجل الطلبات التفصيلي تظهر للمالك فقط.",
                                  "Full numbers, sign-in codes and detailed request history are visible only to the owner."),
                           icon: "lock.fill", tint: DS.Color.slate)
            }
        }
        .accessibilityIdentifier("sms.case-details")
        .task { await model.refresh(isOwner: authVM.isOwner, revealAvailableCode: true) }
        .task(id: model.code?.expiresAt) { await model.expireCode() }
        .task(id: model.code?.status == "shown" ? model.code?.sentAt : nil) {
            guard authVM.isOwner, model.code?.status == "shown" else { return }
            while !Task.isCancelled, model.code?.status == "shown" {
                do { try await Task.sleep(nanoseconds: 15_000_000_000) } catch { return }
                await model.validateDisplayedCode(isOwner: authVM.isOwner)
            }
        }
        .onChange(of: authVM.isOwner) { owner in
            model.clearSensitive()
            if owner { Task { await model.refresh(isOwner: true) } }
        }
        .onChange(of: authVM.currentUser?.id) { _ in model.clearSensitive(); dismiss() }
        .onChange(of: model.denied) { denied in
            if denied {
                SmsLoginAttemptsStore.shared.activate(user: nil, isOwner: false)
                Task {
                    await authVM.checkUserProfile()
                    let store = SmsLoginAttemptsStore.shared
                    store.activate(user: authVM.currentUser?.id, isOwner: authVM.isOwner)
                    await store.refresh(force: true)
                }
                dismiss()
            }
        }
        .onChange(of: scenePhase) { phase in if phase != .active { model.clearCode() } }
        .onDisappear { model.clearSensitive() }
    }

    private var visibleItem: SmsLoginAttempts.Item { model.detail?.summary ?? model.item }

    private var identity: some View {
        DSComposerSection(title: L10n.t("صاحب الطلب", "Requester"), icon: "person.fill", index: 0) {
            Text(visibleItem.name ?? L10n.t("رقم غير مسجّل", "Unregistered number"))
                .dsFont(.headline).foregroundColor(DS.Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            let phone = authVM.isOwner && !model.denied ? visibleItem.phone : SmsAttemptsText.maskedPhone(visibleItem.phone)
            Text(verbatim: phone).dsFont(.body).monospacedDigit()
                .foregroundColor(DS.Color.textSecondary).environment(\.layoutDirection, .leftToRight)
                .textSelection(.enabled).accessibilityIdentifier("sms.case-phone")
            SmsCaseField(label: L10n.t("حالة العضوية", "Membership"), value: memberStatus)
            if authVM.isOwner, !model.denied, let phone = visibleItem.phoneE164 {
                DSChipButton(L10n.t("نسخ الرقم", "Copy number"), icon: "doc.on.doc", size: .small) {
                    UIPasteboard.general.string = phone
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            }
        }
    }

    private var memberStatus: String {
        guard visibleItem.isMember else { return L10n.t("بلا ملف عضو", "No member profile") }
        switch visibleItem.memberStatus {
        case "active": return L10n.t("فعّال", "Active")
        case "frozen": return L10n.t("مجمّد", "Frozen")
        case "pending": return L10n.t("بانتظار التفعيل", "Pending activation")
        default: return visibleItem.memberStatus ?? L10n.t("غير مسجّل", "Not recorded")
        }
    }

    private var history: some View {
        DSComposerSection(title: L10n.t("سجل طلبات الرمز", "Code request history"), icon: "clock.arrow.circlepath", index: 3) {
            DSChipButton(L10n.t("تحديث التفاصيل", "Refresh details"), icon: "arrow.clockwise", size: .small,
                         isLoading: model.loading) {
                Task { await model.refresh(isOwner: authVM.isOwner, revealAvailableCode: true) }
            }
            if model.denied {
                DSNoteCard(L10n.t("التفاصيل الكاملة للمالك فقط.", "Full details are for the owner only."),
                           icon: "lock.fill", tint: DS.Color.warning)
            } else if let detail = model.detail {
                Text(L10n.t("\(detail.attempts.count) من \(detail.total) طلب · \(SmsAttemptsText.period(detail.days))",
                            "\(detail.attempts.count) of \(detail.total) requests · \(SmsAttemptsText.period(detail.days))"))
                    .dsFont(.footnote).foregroundColor(DS.Color.textSecondary)
                if detail.attempts.isEmpty {
                    Text(L10n.t("لا طلبات مسجّلة في هذه الفترة.", "No recorded requests in this period."))
                        .dsFont(.body).foregroundColor(DS.Color.textSecondary)
                }
                ForEach(detail.attempts) { attempt in
                    AnyView(SmsCaseAttemptRow(attempt: attempt, model: model,
                        initiallyExpanded: attempt.id == detail.attempts.first?.id))
                }
                if detail.nextBefore != nil {
                    DSChipButton(L10n.t("تحميل طلبات أقدم", "Load older requests"), icon: "clock", size: .small,
                                 isLoading: model.loadingMore) { Task { await model.more(isOwner: authVM.isOwner) } }
                        .accessibilityIdentifier("sms.case-load-more")
                }
            } else if model.loading {
                DSPageLoader(L10n.t("جاري جلب تفاصيل الطلبات…", "Loading request details…"),
                             size: DS.Icon.loaderArtInline, fillsSpace: false)
            }
            if model.failed && !model.denied {
                DSNoteCard(L10n.t("تعذّر تحديث التفاصيل. يمكنك إعادة المحاولة من زر التحديث.",
                                  "Couldn't refresh details. Use the refresh button to retry."),
                           icon: "wifi.exclamationmark", tint: DS.Color.warning)
            }
            Text(L10n.t("التفاصيل الإضافية تُسجّل للطلبات الجديدة. الطلبات القديمة تعرض وقت تسجيل النتيجة والنتيجة المتاحة.",
                        "Additional metadata is recorded for new requests. Older entries show their recorded result and time."))
                .dsFont(.footnote).foregroundColor(DS.Color.textTertiary).fixedSize(horizontal: false, vertical: true)
            Text(L10n.t("فحص KWT يوضح حالة الإرسال في بوابته؛ لا يؤكد استلام الرسالة على الهاتف الكويتي.",
                        "KWT status describes its sending queue; it does not confirm receipt on a Kuwait handset."))
                .dsFont(.footnote).foregroundColor(DS.Color.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var codeAudit: some View {
        if let detail = model.detail {
            DSComposerSection(title: L10n.t("سجل عرض الرمز", "Code access history"), icon: "eye", index: 4) {
                Text(L10n.t("إجمالي العروض: \(detail.codeViewCount) · يظهر أحدث 20 عرضاً",
                            "Total views: \(detail.codeViewCount) · Latest 20 shown"))
                    .dsFont(.footnote).foregroundColor(DS.Color.textSecondary)
                ForEach(detail.codeViews) { view in
                    VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                        Text(SmsAttemptsText.fullTime(view.at)).dsFont(.footnote).monospacedDigit()
                        Text("\(view.by ?? L10n.t("المالك", "Owner")) · \(SmsCaseCodeSection.statusTitle(view.result))")
                            .dsFont(.caption).foregroundColor(DS.Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, DS.Spacing.xs)
                }
                if detail.codeViews.isEmpty {
                    Text(L10n.t("لم يُعرض الرمز خلال الفترة.", "The code was not viewed in this period."))
                        .dsFont(.footnote).foregroundColor(DS.Color.textSecondary)
                }
                Text(L10n.t("السجل يُحفظ \(detail.retentionDays) يوماً. رمز الدخول نفسه يُزال عند انتهاء صلاحيته أو تسجيل الدخول.",
                            "History is kept for \(detail.retentionDays) days. The code itself is removed after expiry or sign-in."))
                    .dsFont(.footnote).foregroundColor(DS.Color.textTertiary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct SmsCaseSummary: View {
    let item: SmsLoginAttempts.Item
    let days: Int

    var body: some View {
        DSComposerSection(title: L10n.t("ملخّص الفترة", "Period summary"), icon: "chart.bar", index: 2) {
            SmsCaseField(label: L10n.t("طلبات اليوم", "Requests today"), value: "\(item.attemptsToday)")
            SmsCaseField(label: L10n.t("الطلبات · \(SmsAttemptsText.period(days))", "Requests · \(SmsAttemptsText.period(days))"),
                         value: "\(item.attemptsInWindow)")
            OccasionFlowLayout(spacing: DS.Spacing.xs) {
                metric(L10n.t("قَبِلها المزوّد", "Provider accepted"), item.sent, DS.Color.success)
                metric(L10n.t("محجوبة بالحدود", "Rate limited"), item.blocked, DS.Color.warning)
                metric(L10n.t("فشل", "Failed"), item.failed, DS.Color.error)
                metric(L10n.t("غير معروف", "Unknown"), item.unknown, DS.Color.slate)
                metric(L10n.t("تجريبي", "Test"), item.test, DS.Color.info)
            }
            SmsCaseField(label: L10n.t("أول طلب مسجّل بالفترة", "First recorded request"), value: SmsAttemptsText.fullTime(item.firstAt))
            SmsCaseField(label: L10n.t("آخر طلب مسجّل بالفترة", "Latest recorded request"), value: SmsAttemptsText.fullTime(item.lastAt))
            SmsCaseField(label: L10n.t("آخر دخول مسجّل للحساب", "Last account sign-in"), value: SmsAttemptsText.fullTime(item.lastSignInAt))
            SmsCaseField(label: L10n.t("أعلى عدد طلبات في ساعة", "Most requests in one hour"), value: "\(item.maxInHour)")
        }
    }

    private func metric(_ label: String, _ value: Int, _ tint: Color) -> some View {
        DSStatusChip(text: "\(label): \(value)", tint: value > 0 ? tint : DS.Color.slate, size: .mini)
    }
}

private struct SmsCaseCodeSection: View {
    @ObservedObject var model: SmsAttemptDetailsStore
    @EnvironmentObject private var authVM: AuthViewModel
    @State private var copied = false

    var body: some View {
        DSComposerSection(title: L10n.t("رمز الدخول · للمالك فقط", "Sign-in code · Owner only"), icon: "key.fill", index: 1) {
            if let reply = model.code, reply.status == "shown", let code = reply.code, let expiry = reply.expiresAt {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    if expiry > context.date {
                        codeContent(code, expiry: expiry, now: context.date)
                    } else {
                        Text(Self.statusTitle("expired")).dsFont(.body).foregroundColor(DS.Color.textSecondary)
                    }
                }
            } else if model.revealing || (model.detail == nil && !model.failed) {
                ProgressView().frame(maxWidth: .infinity)
            } else if model.detail == nil {
                Text(L10n.t("لم تُحمّل حالة الرمز. حدّث التفاصيل للمحاولة مجدداً.", "Code status couldn't be loaded. Refresh details to retry."))
                    .dsFont(.footnote).foregroundColor(DS.Color.textSecondary)
            } else if let reply = model.code {
                Text(Self.statusTitle(reply.status)).dsFont(.body).foregroundColor(DS.Color.textSecondary)
            } else if let expiry = model.detail?.activeCodeExpiresAt, expiry > Date() {
                DSChipButton(L10n.t("عرض الرمز", "Show code"), icon: "key.fill", size: .small) {
                    Task { await model.reveal(isOwner: authVM.isOwner) }
                }.accessibilityIdentifier("sms.case-reveal-code")
            } else {
                Text(L10n.t("لا يوجد رمز صالح الآن. الرمز صالح لمدة 5 دقائق، ويختفي بعد الدخول أو انتهاء المدة.",
                            "No valid code right now. Codes last 5 minutes and disappear after sign-in or expiry."))
                    .dsFont(.footnote).foregroundColor(DS.Color.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
            if model.codeFailed {
                Text(L10n.t("تعذّر تحديث حالة الرمز. حدّث التفاصيل للمحاولة مجدداً.", "Couldn't refresh the code status. Refresh details to retry."))
                    .dsFont(.footnote).foregroundColor(DS.Color.warning.dsReadableGlyph)
            }
            Text(L10n.t("كل عرض للرمز يُسجّل باسم المالك ووقته.", "Every code view records the owner and time."))
                .dsFont(.caption).foregroundColor(DS.Color.textTertiary)
        }
        .onChange(of: model.code?.code) { _ in copied = false }
    }

    private func codeContent(_ code: String, expiry: Date, now: Date) -> some View {
        let seconds = max(0, Int(expiry.timeIntervalSince(now).rounded(.up)))
        return VStack(spacing: DS.Spacing.sm) {
            Text(verbatim: code).dsFont(.codeDigit).monospacedDigit().tracking(DS.Spacing.xs)
                .lineLimit(1).minimumScaleFactor(0.45).foregroundColor(DS.Color.textPrimary)
                .environment(\.layoutDirection, .leftToRight).frame(maxWidth: .infinity)
                .accessibilityIdentifier("sms.case-code")
                .accessibilityLabel(code.map(String.init).joined(separator: " "))
            Text(L10n.t("ينتهي بعد \(seconds / 60):\(String(format: "%02d", seconds % 60))",
                        "Expires in \(seconds / 60):\(String(format: "%02d", seconds % 60))"))
                .dsFont(.footnote).monospacedDigit().foregroundColor(DS.Color.textSecondary)
            SmsCaseField(label: L10n.t("وقت إرسال الرمز", "Code sent at"), value: SmsAttemptsText.fullTime(model.code?.sentAt))
            SmsCaseField(label: L10n.t("انتهاء الصلاحية", "Expires at"), value: SmsAttemptsText.fullTime(expiry))
            DSChipButton(copied ? L10n.t("تم النسخ", "Copied") : L10n.t("نسخ الرمز", "Copy code"),
                         icon: copied ? "checkmark" : "doc.on.doc", size: .small) {
                guard authVM.isOwner, expiry > Date() else { return }
                UIPasteboard.general.setItems([[UTType.plainText.identifier: code]],
                                              options: [.localOnly: true, .expirationDate: expiry])
                UINotificationFeedbackGenerator().notificationOccurred(.success); copied = true
            }
        }
    }

    static func statusTitle(_ status: String) -> String {
        switch status {
        case "shown": return L10n.t("عُرض الرمز", "Code viewed")
        case "used": return L10n.t("دخل صاحب الرقم بعد إرسال الرمز؛ لم يعد صالحاً للعرض.", "A sign-in followed this code; it is no longer available.")
        case "expired": return L10n.t("انتهت صلاحية الرمز.", "Code expired.")
        default: return L10n.t("لا يوجد رمز صالح محفوظ.", "No valid stored code.")
        }
    }
}

private struct SmsCaseAttemptRow: View {
    let attempt: SmsAttemptDetails.Attempt
    @ObservedObject var model: SmsAttemptDetailsStore
    @EnvironmentObject private var authVM: AuthViewModel
    @State private var expanded: Bool

    init(attempt: SmsAttemptDetails.Attempt, model: SmsAttemptDetailsStore, initiallyExpanded: Bool) {
        self.attempt = attempt; self.model = model
        _expanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        let outcome = SmsAttemptsText.outcome(attempt.outcome)
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                SmsCaseField(label: L10n.t("رقم الطلب", "Request ID"), value: "\(attempt.id)")
                SmsCaseField(label: L10n.t("وقت طلب الرمز", "Code requested at"),
                             value: attempt.requestedAt.map { SmsAttemptsText.fullTime($0) }
                                ?? L10n.t("غير مسجّل في الطلب القديم", "Not recorded for this older request"))
                SmsCaseField(label: L10n.t("وقت تسجيل النتيجة", "Result recorded at"), value: SmsAttemptsText.fullTime(attempt.recordedAt))
                if let sender = attempt.sender { SmsCaseField(label: L10n.t("اسم المرسل", "Sender"), value: sender) }
                if let points = attempt.points { SmsCaseField(label: L10n.t("النقاط المخصومة", "Points charged"), value: SmsText.number(points)) }
                if let balance = attempt.balanceAfter { SmsCaseField(label: L10n.t("الرصيد بعد الإرسال", "Balance after send"), value: SmsBalanceText.points(balance)) }
                if let retry = attempt.retryAfter { SmsCaseField(label: L10n.t("مهلة إعادة الطلب", "Retry wait"), value: L10n.t("\(retry) ثانية", "\(retry) seconds")) }
                if let error = attempt.errorCode { SmsCaseField(label: L10n.t("سبب الفشل", "Failure reason"), value: SmsText.errorLine(error)) }
                if let http = attempt.httpStatus { SmsCaseField(label: L10n.t("رد المزوّد (HTTP)", "Provider HTTP response"), value: "\(http)") }
                if attempt.alerted {
                    Text(L10n.t("أُرسل تنبيه إداري لكثرة الطلبات.", "A suspicious-request alert was sent to administrators."))
                        .dsFont(.footnote).foregroundColor(DS.Color.warning.dsReadableGlyph)
                }
                if let msgid = attempt.msgid {
                    SmsCaseField(label: L10n.t("معرّف الرسالة لدى KWT", "KWT message ID"), value: msgid)
                    SmsCaseField(label: L10n.t("حالة بوابة الإرسال", "Sending queue status"),
                                 value: attempt.queueStatus.map(SmsText.deliveryStatus) ?? L10n.t("لم تُفحص بعد", "Not checked yet"))
                    if let at = attempt.queueCheckedAt { SmsCaseField(label: L10n.t("آخر فحص للحالة", "Last status check"), value: SmsAttemptsText.fullTime(at)) }
                    DSChipButton(L10n.t("فحص حالة الرسالة", "Check message status"), icon: "arrow.clockwise", size: .small,
                                 isLoading: model.checking.contains(msgid)) { Task { await model.check(msgid, isOwner: authVM.isOwner) } }
                    if model.checkFailed.contains(msgid) {
                        Text(L10n.t("تعذّر فحص الحالة الآن.", "Couldn't check the status now."))
                            .dsFont(.footnote).foregroundColor(DS.Color.warning.dsReadableGlyph)
                    }
                } else if attempt.outcome == "blocked" {
                    Text(L10n.t("حُجب الطلب قبل إرسال رسالة.", "The request was blocked before a message was sent."))
                        .dsFont(.footnote).foregroundColor(DS.Color.textSecondary)
                }
            }.padding(.top, DS.Spacing.sm)
        } label: {
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text(SmsAttemptsText.fullTime(attempt.requestedAt ?? attempt.recordedAt))
                    .dsFont(.footnote).monospacedDigit().foregroundColor(DS.Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                DSStatusChip(text: outcome.title, icon: outcome.icon, tint: outcome.tint, size: .mini)
            }
        }
        .tint(DS.Color.primary).padding(DS.Spacing.sm)
        .background(RoundedRectangle(cornerRadius: DS.Radius.md).fill(DS.Color.textTertiary.opacity(DS.Opacity.tintFillSoft)))
        .accessibilityIdentifier("sms.case-request.\(attempt.id)")
    }
}

private struct SmsCaseField: View {
    let label: String
    let value: String
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize >= .xxLarge {
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) { labelText; valueText }
            } else {
                HStack(alignment: .top, spacing: DS.Spacing.md) {
                    labelText; Spacer(minLength: DS.Spacing.xs); valueText.multilineTextAlignment(.trailing)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, DS.Spacing.xs)
        .accessibilityElement(children: .combine)
    }

    private var labelText: some View { Text(label).dsFont(.footnote).foregroundColor(DS.Color.textSecondary).fixedSize(horizontal: false, vertical: true) }
    private var valueText: some View { Text(verbatim: value).dsFont(.footnote).monospacedDigit().foregroundColor(DS.Color.textPrimary).fixedSize(horizontal: false, vertical: true).textSelection(.enabled) }
}
