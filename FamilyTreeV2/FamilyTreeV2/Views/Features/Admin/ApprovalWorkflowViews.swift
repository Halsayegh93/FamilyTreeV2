import SwiftUI

// MARK: - «مسار الموافقات» — قطع الواجهة المشتركة (طلب المالك ٢٠٢٦-١٠-١٥)
//
// نفس رحلة التجربة التي اعتمدها المالك (approvals-trial): شارة المرحلة و«متأخر» في الصفوف، ومتتبّع
// الخطوات الخمس، وصندوق «توصية المختص»، وسؤال المختص للعضو، وسجل الطلب، وأزرار كل دور بحسب المرحلة —
// بشكل التطبيق نفسه (`DSComposer`، `DSStatusChip`، `DSNoteCard`، الزرّ الواحد).

// MARK: نصوص المراحل وألوانها

/// لمن يُعرض المسار: الطاقم يرى الأدوار (المختص/المدير)، وصاحب الطلب يُخاطَب بـ«الإدارة» رسمياً
/// (طلب المالك ٢٠٢٦-١٠-١٥ «رد على المختص خلها رد على الإدارة بشكل رسمي»)
enum ApprovalAudience { case staff, member }

extension ApprovalStage {
    /// اسم المرحلة لصاحب الطلب — بلا أدوار
    var memberTitle: String {
        switch self {
        case .review: return L10n.t("قيد المراجعة", "Under review")
        case .info: return L10n.t("بانتظار ردّك", "Waiting for your reply")
        case .approve: return L10n.t("قيد الاعتماد", "Awaiting approval")
        case .execute: return L10n.t("قيد التنفيذ", "Being carried out")
        }
    }

    /// «بانتظار ردّك» بلون «بانتظارك» نفسه (مطلوب منك شيء)، والباقي بألوان المراحل
    var memberIcon: String { self == .info ? "bell.badge.fill" : icon }
    var memberTint: Color { self == .info ? DS.Color.accent : tint }

    /// اسم المرحلة في الشارة
    var title: String {
        switch self {
        case .review: return L10n.t("عند المختص للمراجعة", "With the specialist for review")
        case .info: return L10n.t("بانتظار معلومات من العضو", "Waiting for the member's info")
        case .approve: return L10n.t("عند المدير للاعتماد", "With the manager for approval")
        case .execute: return L10n.t("معتمد · عند المختص للتنفيذ", "Approved · with the specialist to carry out")
        }
    }

    var icon: String {
        switch self {
        case .review: return "magnifyingglass"
        case .info: return "questionmark.bubble.fill"
        case .approve: return "person.badge.shield.checkmark.fill"
        case .execute: return "checkmark.seal.fill"
        }
    }

    /// ألوان معانٍ: المراجعة بلون القسم، المعلومات أزرق المراسلة، الاعتماد تنبيه، المعتمد أخضر
    var tint: Color {
        switch self {
        case .review: return DS.Color.primary
        case .info: return DS.Color.composerDiwaniya
        case .approve: return DS.Color.warning
        case .execute: return DS.Color.success
        }
    }
}

extension ApprovalInfoField {
    var title: String {
        switch self {
        case .phone: return L10n.t("رقم الهاتف", "Phone number")
        case .birthDate: return L10n.t("تاريخ الميلاد", "Birth date")
        case .deathDate: return L10n.t("تاريخ الوفاة", "Death date")
        case .fullName: return L10n.t("الاسم الكامل", "Full name")
        case .text: return L10n.t("توضيح مكتوب", "Written note")
        }
    }

    var icon: String {
        switch self {
        case .phone: return "phone.fill"
        case .birthDate: return "gift.fill"
        case .deathDate: return "calendar.badge.minus"
        case .fullName: return "person.text.rectangle.fill"
        case .text: return "text.bubble.fill"
        }
    }

    /// ألوان معانٍ ثابتة لكل حقل (الميلاد كهرماني والوفاة رمادي كصفوف التواريخ في النماذج)
    var tint: Color {
        switch self {
        case .phone: return DS.Color.composerDiwaniya
        case .birthDate: return DS.Color.warning
        case .deathDate: return DS.Color.newsDeath
        case .fullName: return DS.Color.composerProject
        case .text: return DS.Color.info
        }
    }

    /// القيمة كما تُقرأ: الرقم بصيغة العرض والتاريخ «١٥ مارس ١٩٩٠»
    func display(_ raw: String) -> String {
        switch self {
        case .phone: return KuwaitPhone.display(raw)
        case .birthDate, .deathDate: return ApprovalInfoDraft.isoDate(raw).map(DSDateText.display) ?? raw
        case .fullName, .text: return raw
        }
    }
}

extension AdminRequestStep {
    /// وصف الخطوة في سجل الطلب (بعد اسم من قام بها)
    var actionTitle: String {
        switch action {
        case "submitted": return L10n.t("قدّم الطلب", "submitted the request")
        case "recommend_approve": return L10n.t("رفع للمدير بتوصية الموافقة", "sent it up recommending approval")
        case "recommend_reject": return L10n.t("رفع للمدير بتوصية الرفض", "sent it up recommending rejection")
        case "request_info": return L10n.t("طلب معلومات من العضو", "asked the member for info")
        case "provide_info": return L10n.t("أضاف المعلومات المطلوبة", "added the requested info")
        case "approve": return L10n.t("اعتمد الطلب ورجّعه للمختص للتنفيذ", "approved it and sent it back to carry out")
        case "return": return L10n.t("رجّع الطلب للمختص", "returned it to the specialist")
        case "executed": return L10n.t("نفّذ الطلب وبلّغ العضو", "carried it out and told the member")
        case "rejected": return L10n.t("رفض الطلب", "rejected the request")
        // «مسار الموافقات ٢» (طلب المالك ٢٠٢٦-١٠-١٦)
        case "claim": return L10n.t("تولّى الطلب", "took the request")
        case "release": return L10n.t("ترك الطلب", "released the request")
        case "priority": return L10n.t("غيّر الأولوية", "changed the priority")
        case "escalated": return L10n.t("تصعّد للمدير لتأخره", "escalated to the manager for being late")
        case "reminded": return L10n.t("تذكير بالتأخير", "late reminder")
        case "fast_track": return L10n.t("مسار سريع — مباشرة للمدير", "fast track — straight to the manager")
        default: return action
        }
    }

    /// الوصف مع صاحب الشأن («مسار ٢»: `subject_id`) — «أخذ الطلب من حسين»، «تذكير بالتأخير لحسين»
    func actionTitle(subject: String?) -> String {
        guard let subject, !subject.isEmpty else { return actionTitle }
        switch action {
        case "claim": return L10n.t("أخذ الطلب من \(subject)", "took the request over from \(subject)")
        case "release": return L10n.t("رفع تولّي \(subject) للطلب", "released \(subject)'s hold")
        case "reminded": return L10n.t("تذكير بالتأخير لـ\(subject)", "late reminder to \(subject)")
        case "escalated": return L10n.t("تصعّد للمدير لتأخره عند \(subject)", "escalated to the manager — late with \(subject)")
        default: return actionTitle
        }
    }
}

// MARK: الشارات

/// شارات الطلب: «مستعجل» ← «بانتظارك» ← المرحلة ← «مسار سريع» ← «تصعّد»/«متأخر» ← «عند فلان» —
/// تلتفّ لسطر ثانٍ إذا ضاق العرض («مسار الموافقات ٢»، طلب المالك ٢٠٢٦-١٠-١٦). العضو يرى «مستعجل» ومرحلته فقط.
struct ApprovalStageChips: View {
    let snapshot: ApprovalSnapshot
    var waitingForMe: Bool = false
    var audience: ApprovalAudience = .staff
    /// «عندك» / «عند حسين» — للطاقم فقط (العضو لا يرى من استلم طلبه)
    var holderLabel: String? = nil

    var body: some View {
        ChangedWordsFlow(spacing: DS.Spacing.xs) { chips }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var chips: some View {
        // «مستعجل» بلون المعنى الأحمر — للعضو أيضاً (طلبه مستعجل)
        if snapshot.isUrgent {
            DSStatusChip(text: L10n.t("عاجل", "Urgent"), icon: "flame.fill", tint: DS.Color.error, size: .mini)
        }
        if waitingForMe {
            DSStatusChip(text: L10n.t("بانتظار قرارك", "Waiting for you"), icon: "bell.badge.fill",
                         tint: DS.Color.accent, size: .mini)
        }
        if audience == .member {
            DSStatusChip(text: snapshot.stage.memberTitle, icon: snapshot.stage.memberIcon,
                         tint: snapshot.stage.memberTint, size: .mini)
        } else {
            DSStatusChip(text: snapshot.stage.title, icon: snapshot.stage.icon, tint: snapshot.stage.tint, size: .mini)
            if snapshot.fastTrack {
                DSStatusChip(text: L10n.t("مسار سريع", "Fast track"), icon: "bolt.fill",
                             tint: DS.Color.info, size: .mini)
            }
            // «تصعّد» بدل «متأخر» إذا وصل المدير — للطاقم فقط، العضو يرى مرحلته بلا ضغط
            if snapshot.isEscalated {
                DSStatusChip(text: L10n.t("تصعّد", "Escalated"), icon: "arrow.up.forward.circle.fill",
                             tint: DS.Color.error, size: .mini)
            } else if snapshot.isLate {
                DSStatusChip(text: L10n.t("متأخر", "Late"), icon: "exclamationmark.circle.fill",
                             tint: DS.Color.error, size: .mini)
            }
            if let holderLabel {
                DSStatusChip(text: holderLabel, icon: "person.crop.circle.badge.checkmark",
                             tint: DS.Color.composerDiwaniya, size: .mini)
            }
        }
    }
}

// MARK: متتبّع الخطوات

/// الخطوات الخمس: تقديم ← مراجعة المختص ← اعتماد المدير ← تنفيذ ← مكتمل (يتبع اتجاه اللغة).
/// لصاحب الطلب بلا أدوار: تقديم ← المراجعة ← الاعتماد ← التنفيذ ← مكتمل
struct ApprovalTracker: View {
    let stage: ApprovalStage
    var audience: ApprovalAudience = .staff
    @Environment(\.dsSection) private var section

    private var steps: [String] {
        switch audience {
        case .staff:
            return [L10n.t("تقديم", "Submitted"), L10n.t("مراجعة المختص", "Specialist review"),
                    L10n.t("اعتماد المدير", "Manager approval"), L10n.t("تنفيذ", "Carry out"), L10n.t("مكتمل", "Done")]
        case .member:
            return [L10n.t("تقديم", "Submitted"), L10n.t("المراجعة", "Review"),
                    L10n.t("الاعتماد", "Approval"), L10n.t("التنفيذ", "Carrying out"), L10n.t("مكتمل", "Done")]
        }
    }

    var body: some View {
        let current = stage.trackerStep
        let titles = steps
        return HStack(alignment: .top, spacing: 0) {
            ForEach(titles.indices, id: \.self) { i in
                VStack(spacing: DS.Spacing.xs) {
                    ZStack {
                        HStack(spacing: 0) {
                            connector(visible: i > 0, done: i <= current)
                            connector(visible: i < titles.count - 1, done: i < current)
                        }
                        dot(i, current: current)
                    }
                    .frame(height: DS.Icon.inline + DS.Spacing.xsm)
                    Text(titles[i])
                        .dsFont(i == current ? DS.TextRole.badge : DS.TextRole.micro)
                        .foregroundColor(i == current ? DS.Color.fieldLabel : DS.Color.textTertiary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.t("مراحل الطلب، الآن: \(titles[current])", "Request stages, now: \(titles[current])"))
    }

    private var ink: Color { DS.Color.primary.dsChrome(in: section) }

    private func connector(visible: Bool, done: Bool) -> some View {
        Rectangle()
            .fill(visible ? (done ? DS.Color.success : DS.Color.textTertiary.opacity(DS.Opacity.divider)) : Color.clear)
            .frame(height: DS.Border.widthBold)
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder private func dot(_ i: Int, current: Int) -> some View {
        if i < current {
            Circle()
                .fill(DS.Color.successFill)   // تحت علامة بيضاء — التعبئة الثابتة (الهوية)
                .frame(width: DS.Icon.inline, height: DS.Icon.inline)
                .overlay(Image(systemName: "checkmark").dsGlyph(DS.Glyph.micro).foregroundColor(DS.Color.textOnPrimary))
        } else if i == current {
            Circle()
                .fill(ink)
                .frame(width: DS.Icon.inline, height: DS.Icon.inline)
                .background(Circle().fill(ink.opacity(DS.Opacity.tintFillStrong))
                    .frame(width: DS.Icon.inline + DS.Spacing.xsm, height: DS.Icon.inline + DS.Spacing.xsm))
        } else {
            Circle()
                .fill(DS.Color.surface)
                .overlay(Circle().strokeBorder(DS.Color.textTertiary.opacity(DS.Opacity.tintStroke),
                                               lineWidth: DS.Border.widthBold))
                .frame(width: DS.Icon.inline, height: DS.Icon.inline)
        }
    }
}

// MARK: ملخّص المسار

/// محتوى قسم «مسار الطلب»: المتتبّع، الشارات، المختص وعمر المرحلة، التوصية، سؤال العضو، ملاحظة المدير،
/// ومن بيده الطلب الآن (إن لم يكن بانتظارك)
struct ApprovalPathSummary: View {
    let snapshot: ApprovalSnapshot
    let waitingForMe: Bool
    /// «المراقب» / «المشرف»
    let specialistTitle: String
    /// من بيده الطلب الآن
    let holderTitle: String
    /// طلبك أنت — يعالجه مسؤول آخر
    var isOwnRequest: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            ApprovalTracker(stage: snapshot.stage)
            ApprovalStageChips(snapshot: snapshot, waitingForMe: waitingForMe)
            Text(metaLine)
                .dsFieldFont(.footnote)
                .foregroundColor(DS.Color.fieldValue)
                .fixedSize(horizontal: false, vertical: true)

            if let approves = snapshot.recommendsApproval {
                DSNoteCard(nonEmpty(snapshot.recommendationNote) ?? L10n.t("بدون ملاحظة", "No note"),
                           title: approves ? L10n.t("توصية المختص: الموافقة", "Specialist recommends: approve")
                                           : L10n.t("توصية المختص: الرفض", "Specialist recommends: reject"),
                           icon: approves ? "hand.thumbsup.fill" : "hand.thumbsdown.fill",
                           tint: approves ? DS.Color.success : DS.Color.reject)
            }
            if snapshot.stage == .info {
                if let ask = nonEmpty(snapshot.infoRequest) {
                    DSNoteCard(ask, title: L10n.t("المختص يطلب من العضو", "The specialist asks the member"),
                               icon: "questionmark.bubble.fill", tint: DS.Color.composerDiwaniya)
                }
                if !snapshot.infoFields.isEmpty {
                    ApprovalRequestedFields(fields: snapshot.infoFields,
                                            title: L10n.t("المطلوب من العضو", "Asked from the member"))
                }
            } else if !snapshot.infoReply.values.isEmpty {
                // بعد ردّ العضو: ما طُلب وما أدخله (القيم كما فحصها السيرفر)
                ApprovalInfoReplyCard(snapshot: snapshot)
            }
            if let managerNote = nonEmpty(snapshot.approvalNote) {
                DSNoteCard(managerNote, title: L10n.t("ملاحظة المدير", "Manager's note"),
                           icon: "text.bubble.fill", tint: DS.Color.warning)
            }
            if isOwnRequest || !waitingForMe {
                HStack(alignment: .top, spacing: DS.Spacing.xsm) {
                    Image(systemName: "hourglass")
                        .dsGlyph(DS.Glyph.sm)
                        .foregroundColor(DS.Color.textTertiary)
                        .accessibilityHidden(true)
                    Text(isOwnRequest
                         ? L10n.t("هذا طلبك — يعالجه مسؤول آخر.", "This is your request — another admin handles it.")
                         : L10n.t("الطلب الحين عند \(holderTitle).", "The request is now with \(holderTitle)."))
                        .dsFieldFont(.subtitle)
                        .foregroundColor(DS.Color.fieldValue)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var metaLine: String {
        var parts = [L10n.t("المختص: \(specialistTitle)", "Specialist: \(specialistTitle)")]
        if let since = snapshot.stageSince ?? snapshot.createdAt {
            parts.append(L10n.t("في المرحلة \(DateHelper.relativeTime(from: since))",
                                "In this stage \(DateHelper.relativeTime(from: since))"))
        }
        return parts.joined(separator: " · ")
    }

    private func nonEmpty(_ s: String?) -> String? {
        let t = s?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return t.isEmpty ? nil : t
    }
}

// MARK: سجل الطلب

/// الخطوات بالترتيب: من قام بها، ماذا فعل، متى، وملاحظته
struct ApprovalStepsLog: View {
    let steps: [AdminRequestStep]
    let actorTitle: (AdminRequestStep) -> String
    /// اسم صاحب الشأن (`subject_id`) — nil = الوصف وحده
    var subjectName: (AdminRequestStep) -> String? = { _ in nil }
    @Environment(\.dsSection) private var section

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                row(step, isLast: index == steps.count - 1)
            }
        }
    }

    private func row(_ step: AdminRequestStep, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: DS.Spacing.sm) {
            Circle()
                .fill(DS.Color.primary.dsChrome(in: section))
                .frame(width: DS.Icon.legendDot, height: DS.Icon.legendDot)
                .padding(.top, DS.Spacing.xsm)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                (Text(actorTitle(step)).font(DS.Font.role(.rowTitle))
                 + Text(" ") + Text(step.actionTitle(subject: subjectName(step))).font(DS.Font.role(.subtitle)))
                    .foregroundColor(DS.Color.fieldLabel)
                    .fixedSize(horizontal: false, vertical: true)
                if let date = ApprovalWorkflow.date(step.createdAt) {
                    Text(DateHelper.relativeTime(from: date))
                        .dsFont(.caption)
                        .foregroundColor(DS.Color.textTertiary)
                }
                if let note = step.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                    Text(note)
                        .dsFieldFont(.subtitle)
                        .foregroundColor(DS.Color.fieldValue)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, DS.Spacing.sm)
                        .padding(.vertical, DS.Spacing.xs)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                            .fill(DS.Color.textTertiary.opacity(DS.Opacity.tintFill)))
                }
            }
            .padding(.bottom, isLast ? 0 : DS.Spacing.md)
        }
        // الخط الواصل بين النقاط — خلف الصف بطول ارتفاعه
        .background(alignment: .topLeading) {
            if !isLast {
                Rectangle()
                    .fill(DS.Color.textTertiary.opacity(DS.Opacity.divider))
                    .frame(width: DS.Border.widthBold)
                    .frame(maxHeight: .infinity)
                    .padding(.top, DS.Spacing.xsm + DS.Icon.legendDot)
                    .padding(.leading, (DS.Icon.legendDot - DS.Border.widthBold) / 2)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: مربّع الطلب بالمسار (للطاقم)

/// تفاصيل طلب والمسار شغّال: «مسار الطلب» (+ الاستلام والأولوية) ← بيانات الطلب (من الشاشة التي فتحته) ←
/// «سجل الطلب» ← «ملاحظات الإدارة» ← قرار الدور بحسب المرحلة. التنفيذ والرفض النهائي بمسارات الموافقة/الرفض
/// القديمة (`onExecute`/`onReject`)، وباقي الخطوات `advance_admin_request`.
///
/// «بسّط أزرار النظام داخل الموافقات» (طلب المالك ٢٠٢٦-١٠-١٦): في أي مربّع زرّ واحد بعرض كامل + «إغلاق» —
/// المدير في الاعتماد «اعتماد» ومبدّل صغير فوقه «يرجع للمختص للتنفيذ | تنفيذ الحين»، و«رفض»/«إرجاع للمختص»
/// شرائح صغيرة تحت الملاحظة، والمختص في التنفيذ «تنفيذ» وحده، وغير القرار («حذف نهائي»، تعديل الرقم) شرائح
/// صغيرة أسفل المربّع.
struct ApprovalRequestBox<Details: View>: View {
    @ObservedObject var adminRequestVM: AdminRequestViewModel
    @ObservedObject var memberVM: MemberViewModel
    let snapshot: ApprovalSnapshot
    let title: String
    let subtitle: String
    let icon: String
    /// «تنفيذ» و«اعتماد» بخيار «تنفيذ الحين» — مسار الموافقة القديم نفسه (يغلق المربّع بنفسه)
    let onExecute: () -> Void
    /// «رفض» المدير — مسار الرفض القديم بالسبب (يغلق المربّع بنفسه)
    let onReject: (String) -> Void
    let onClose: () -> Void
    /// إجراءات لا تخصّ القرار (تعديل رقم فعلي، حذف نهائي) — شرائح صغيرة أسفل المربّع
    var otherActions: [DSComposerAction] = []
    @ViewBuilder let details: () -> Details

    @State private var note = ""
    @State private var noteError: String?
    @State private var busy = false
    /// توصية المختص: مبدّل واحد بدل زرّين (طلب المالك ٢٠٢٦-١٠-١٥ «أقلل الأزرار»)
    @State private var recommendApprove = true
    /// «اسأل العضو عن ناقص» (طلب المالك ٢٠٢٦-١٠-١٥ «الادارة تختار الناقص»): الشريحة تحوّل القرار لسؤال العضو —
    /// الزرّ الواحد يصير «إرسال للعضو»
    @State private var askOpen = false
    @State private var askFields: Set<ApprovalInfoField> = []
    @State private var askNote = ""
    @State private var askError: String?
    /// المدير في الاعتماد: يرجع للمختص لينفّذه (false، الافتراضي) أو «تنفيذ الحين» (true)
    @State private var executeNow = false
    /// استلام/ترك/أولوية أثناء الإرسال
    @State private var housekeeping: ApprovalAction?
    @State private var housekeepingError: String?

    /// القرار الرئيسي (الزرّ الواحد بجانب «إغلاق»)
    private enum Primary { case recommend, ask, approve, execute }

    // MARK: من يقدر على ماذا الآن

    /// اللقطة الحيّة — بعد الاستلام أو تغيير الأولوية يتحدّث المربّع وهو مفتوح
    private var flow: ApprovalSnapshot { adminRequestVM.liveApprovalSnapshot(requestId: snapshot.requestId) ?? snapshot }

    private var isOwn: Bool { adminRequestVM.isOwnApprovalRequest(flow) }
    /// استلمه غيرك — قرارات المرحلة له (المالك يأخذه بشريحة «أخذه»)
    private var isLocked: Bool { adminRequestVM.isApprovalDecisionLocked(flow) }
    /// المختص (أو المالك/المدير والطلب متصعّد له)
    private var isSpecialist: Bool { !isOwn && !isLocked && adminRequestVM.canActAsApprovalSpecialist(flow) }
    private var isManager: Bool { !isOwn && adminRequestVM.isApprovalManager }

    private var primary: Primary? {
        switch flow.stage {
        case .review: return isSpecialist ? (askOpen ? .ask : .recommend) : nil
        case .approve: return isManager && !isLocked ? .approve : nil
        case .execute: return isSpecialist ? .execute : nil
        case .info: return nil
        }
    }

    /// «رفض» المدير — شريحة صغيرة في أي مرحلة (في الاعتماد: ما لم يستلمه مدير آخر)
    private var showsRejectChip: Bool {
        isManager && !askOpen && (flow.stage != .approve || !isLocked)
    }

    /// «إرجاع للمختص» — المدير في الاعتماد
    private var showsReturnChip: Bool { flow.stage == .approve && isManager && !isLocked }

    /// المختص في مرحلة المراجعة — يظهر له مبدّل التوصية وشريحة سؤال العضو
    private var isSpecialistReview: Bool { flow.stage == .review && isSpecialist }

    /// حقل الملاحظة يظهر لمن عنده قرار يستعملها
    private var showsNote: Bool {
        if askOpen { return false }
        return isSpecialistReview || primary == .approve || showsRejectChip
    }

    private var showsDecisionSection: Bool {
        showsNote || isSpecialistReview || primary == .approve
    }

    private var noteTitle: String {
        if isSpecialistReview { return L10n.t("مراجعتك", "Your review") }
        return L10n.t("قرارك", "Your decision")
    }

    /// عنوان الحقل يقول متى الملاحظة مطلوبة، والنص الباهت ماذا يُكتب فيه
    private var noteLabel: String {
        if isSpecialistReview {
            return recommendApprove
                ? L10n.t("ملاحظتك للمدير (اختياري)", "Your note for the manager (optional)")
                : L10n.t("سبب التوصية بالرفض — مطلوب", "Why you recommend rejection — required")
        }
        if primary == .approve {
            return L10n.t("ملاحظتك — مطلوبة للرفض أو الإرجاع", "Your note — required to reject or return")
        }
        return L10n.t("سبب الرفض — مطلوب للرفض", "Reason — required to reject")
    }

    private var notePlaceholder: String {
        if isSpecialistReview { return L10n.t("رأيك للمدير", "Your view for the manager") }
        if primary == .approve { return L10n.t("ملاحظة للمختص أو سبب الرفض", "A note for the specialist, or the reason") }
        return L10n.t("يوصل للعضو مع الرفض", "Sent to the member with the rejection")
    }

    /// أنواع الردود الجاهزة فوق الحقل بحسب القرار الحالي
    private var noteTemplateKinds: [ApprovalTemplateKind] {
        if isSpecialistReview { return recommendApprove ? [.recommend] : [.reject] }
        if primary == .approve { return [.note, .returnBack, .reject] }
        return [.reject]
    }

    private var primaryTitle: String {
        switch primary {
        case .recommend: return L10n.t("رفع للمدير", "Send to manager")
        case .ask: return L10n.t("إرسال للعضو", "Send to the member")
        case .approve: return L10n.t("اعتماد", "Approve")
        case .execute: return L10n.t("تنفيذ", "Carry out")
        case nil: return ""
        }
    }

    private var primaryIcon: String {
        switch primary {
        case .recommend: return "arrow.up.circle.fill"
        case .ask: return "paperplane.fill"
        case .approve: return executeNow ? "bolt.fill" : "checkmark.seal.fill"
        case .execute: return "checkmark.circle.fill"
        case nil: return "checkmark"
        }
    }

    var body: some View {
        DSComposer(
            title: title,
            subtitle: subtitle,
            icon: icon,
            tint: DS.Color.actionNavy,
            actionTitle: primaryTitle,
            actionIcon: primaryIcon,
            showsAction: primary != nil,
            cancelTitle: L10n.t("إغلاق", "Close"),
            canSubmit: !busy && !adminRequestVM.isLoading,
            isBusy: busy,
            onSubmit: runPrimary,
            onCancel: onClose
        ) {
            DSComposerSection(title: L10n.t("مسار الطلب", "Request path"),
                              icon: "point.topleft.down.to.point.bottomright.curvepath.fill",
                              tint: DS.Color.actionNavy,
                              index: 0) {
                ApprovalPathSummary(snapshot: flow,
                                    waitingForMe: adminRequestVM.isApprovalWaitingForMe(flow),
                                    specialistTitle: specialistTitle,
                                    holderTitle: holderTitle,
                                    isOwnRequest: isOwn)
                assignmentRow
                if adminRequestVM.isEscalatedToMe(flow) {
                    DSNoteCard(L10n.t("تصعّد لك لتأخره — تقدر تتصرف بدل المختص.",
                                      "Escalated to you for being late — you can act for the specialist."),
                               icon: "arrow.up.forward.circle.fill", tint: DS.Color.warning)
                }
            }

            details()

            if let steps = adminRequestVM.approvalSteps[flow.requestId], !steps.isEmpty {
                DSComposerSection(title: L10n.t("سجل الطلب", "Request log"),
                                  icon: "list.bullet.rectangle.fill",
                                  tint: DS.Color.actionNavy,
                                  trailing: "\(steps.count)",
                                  index: 3) {
                    ApprovalStepsLog(steps: steps, actorTitle: actorTitle) { step in
                        step.subjectId.flatMap { memberVM.member(byId: $0)?.firstName }
                    }
                }
            }

            // ملاحظات الإدارة لا تظهر لمن الطلب له أو عنه (إلا المالك) — السيرفر يخفيها عنه أيضاً
            if !adminRequestVM.hidesApprovalNotes(flow) {
                ApprovalInternalNotes(adminRequestVM: adminRequestVM, memberVM: memberVM, requestId: flow.requestId)
            }

            if primary == .execute {
                DSNoteCard(L10n.t("اعتمد المدير الطلب — «تنفيذ» يطبّقه كالموافقة المعتادة ويبلّغ العضو.",
                                  "The manager approved it — «Carry out» applies it like a normal approval and tells the member."),
                           title: L10n.t("التنفيذ", "Carry out"), icon: "checkmark.seal.fill", tint: DS.Color.success)
            }

            if showsDecisionSection || askOpen {
                DSComposerSection(title: askOpen ? L10n.t("سؤال العضو", "Ask the member") : noteTitle,
                                  icon: askOpen ? "questionmark.bubble.fill" : "text.bubble.fill",
                                  tint: askOpen ? DS.Color.composerDiwaniya : DS.Color.actionNavy, index: 5) {
                    decisionContent
                }
            }

            if !otherActions.isEmpty {
                otherActionsRow
            }
        }
        .task {
            await adminRequestVM.fetchApprovalSteps(for: snapshot.requestId)
            // «مسار ٢»: الملاحظات الداخلية والردود الجاهزة (جدول غير موجود = تختفي بهدوء)
            if !adminRequestVM.hidesApprovalNotes(snapshot) {
                await adminRequestVM.fetchApprovalNotes(for: snapshot.requestId)
            }
            await adminRequestVM.fetchApprovalTemplates()
        }
    }

    // MARK: القرار

    @ViewBuilder private var decisionContent: some View {
        if isSpecialistReview && !askOpen {
            DSSegmentedSwitch(
                options: [
                    DSSegmentOption(id: true, title: L10n.t("أوصي بالموافقة", "Recommend approval"),
                                    icon: "hand.thumbsup.fill"),
                    DSSegmentOption(id: false, title: L10n.t("أوصي بالرفض", "Recommend rejection"),
                                    icon: "hand.thumbsdown.fill")
                ],
                selection: $recommendApprove,
                size: .regular
            )
        }
        if showsNote {
            ApprovalTemplateChips(adminRequestVM: adminRequestVM, kinds: noteTemplateKinds) { insert($0, into: $note) }
            DSComposerField(icon: "text.bubble",
                            label: noteLabel,
                            placeholder: notePlaceholder,
                            text: $note,
                            tint: DS.Color.actionNavy,
                            multiline: true,
                            limit: 500)
            errorText(noteError)
        }
        if askOpen { askPanel }
        // شرائح القرار الصغيرة تحت الملاحظة: سؤال العضو (المختص)، إرجاع ورفض (المدير)
        let askChip = isSpecialistReview && ApprovalWorkflow.canAskRequester(flow.requestType)
        if askChip || showsReturnChip || showsRejectChip {
            ChangedWordsFlow(spacing: DS.Spacing.xs) {
                if askChip {
                    DSChipButton(askOpen ? L10n.t("رجوع للتوصية", "Back to recommendation")
                                         : L10n.t("اسأل العضو عن ناقص", "Ask the member for missing info"),
                                 icon: askOpen ? "chevron.backward" : "questionmark.bubble.fill",
                                 tint: DS.Color.composerDiwaniya, isSelected: askOpen, size: .small) {
                        withAnimation(DS.Anim.snappy) { askOpen.toggle() }
                        noteError = nil
                    }
                }
                if showsReturnChip {
                    DSChipButton(L10n.t("إرجاع للمختص", "Return to specialist"), icon: "arrow.uturn.backward",
                                 tint: DS.Color.composerDiwaniya, size: .small,
                                 isLoading: busy && pendingChip == .returnBack) {
                        runReturn()
                    }
                }
                if showsRejectChip {
                    // الرفض برتقالي — نفس لون رفض تفاصيل الطلب القديمة (طلب المالك)
                    DSChipButton(L10n.t("رفض", "Reject"), icon: "xmark", tint: DS.Color.reject, size: .small) {
                        runReject()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .disabled(busy)
        }
        if primary == .approve {
            // المبدّل الصغير فوق «اعتماد» مباشرة (طلب المالك ٢٠٢٦-١٠-١٦)
            DSSegmentedSwitch(
                options: [
                    DSSegmentOption(id: false, title: L10n.t("يرجع للمختص للتنفيذ", "Back to specialist"),
                                    icon: "arrow.uturn.backward"),
                    DSSegmentOption(id: true, title: L10n.t("تنفيذ الحين", "Carry out now"), icon: "bolt.fill")
                ],
                selection: $executeNow,
                size: .regular
            )
            Text(executeNow
                 ? L10n.t("«اعتماد» يُنفّذ الطلب الحين ويبلّغ العضو بدون الرجوع للمختص.",
                          "«Approve» carries it out now and tells the member, without the specialist.")
                 : L10n.t("«اعتماد» يرجّعه للمختص لينفّذه.", "«Approve» sends it back to the specialist to carry out."))
                .dsFieldFont(.footnote)
                .foregroundColor(DS.Color.fieldValue)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// أيّ شريحة قيد الإرسال (لدوّارتها)
    @State private var pendingChip: ApprovalTemplateKind?

    // MARK: الاستلام والأولوية («مسار ٢»)

    /// «استلام» / «ترك» (أو «عند فلان» و«أخذه» للمالك) + «مستعجل» — شرائح صغيرة تحت المسار
    @ViewBuilder private var assignmentRow: some View {
        let f = flow
        let canClaim = adminRequestVM.canClaimApproval(f)
        let canRelease = adminRequestVM.canReleaseApproval(f)
        let heldByOther = adminRequestVM.isApprovalHeldByOther(f)
        let canTake = adminRequestVM.canTakeOverApproval(f)
        let canPriority = adminRequestVM.canSetApprovalPriority(f)
        if f.hasV2 && (canClaim || canRelease || heldByOther || canPriority) {
            ChangedWordsFlow(spacing: DS.Spacing.xs) {
                if canClaim {
                    DSChipButton(L10n.t("تولّي الطلب", "Take it"), icon: "hand.raised.fill", size: .small,
                                 isLoading: housekeeping == .claim) { runHousekeeping(.claim) }
                        .accessibilityHint(L10n.t("تستلم الطلب فلا يتصرف فيه غيرك", "You hold the request so no one else acts on it"))
                }
                if canRelease {
                    DSStatusChip(text: L10n.t("عندك", "With you"), icon: "person.crop.circle.badge.checkmark",
                                 tint: DS.Color.composerDiwaniya)
                    DSChipButton(L10n.t("ترك", "Release"), icon: "hand.raised.slash", tint: DS.Color.textSecondary,
                                 size: .small, isLoading: housekeeping == .release) { runHousekeeping(.release) }
                }
                if heldByOther {
                    DSStatusChip(text: holderChipText(f), icon: "person.crop.circle.badge.checkmark",
                                 tint: DS.Color.composerDiwaniya)
                    if canTake {
                        DSChipButton(L10n.t("أخذه", "Take over"), icon: "arrow.down.circle.fill", size: .small,
                                     isLoading: housekeeping == .claim) { runHousekeeping(.claim) }
                    }
                }
                if canPriority {
                    DSChipButton(L10n.t("عاجل", "Urgent"), icon: "flame.fill", tint: DS.Color.error,
                                 isSelected: f.isUrgent, size: .small,
                                 isLoading: housekeeping == .markUrgent || housekeeping == .markNormal) {
                        runHousekeeping(f.isUrgent ? .markNormal : .markUrgent)
                    }
                    .accessibilityHint(f.isUrgent ? L10n.t("يرجّعه عادياً", "Makes it normal again")
                                                  : L10n.t("يقدّمه أول القائمة بمهلة أقصر", "Moves it to the top with a shorter deadline"))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .disabled(housekeeping != nil || busy)
            errorText(housekeepingError)
        }
    }

    private func holderChipText(_ f: ApprovalSnapshot) -> String {
        guard let name = adminRequestVM.approvalHolder(f)?.firstName, !name.isEmpty else {
            return L10n.t("عند مسؤول آخر", "With another admin")
        }
        return L10n.t("عند \(name)", "With \(name)")
    }

    /// «الطلب الحين عند …» — باسم المستلم إن وُجد
    private var holderTitle: String {
        if adminRequestVM.isApprovalHeldByOther(flow), let holder = adminRequestVM.approvalHolder(flow) {
            let role = AdminRequestViewModel.approvalRoleTitle(holder.role)
            return "\(holder.firstName) (\(role))"
        }
        return adminRequestVM.approvalHolderTitle(flow)
    }

    private func runHousekeeping(_ action: ApprovalAction) {
        housekeepingError = nil
        housekeeping = action
        Task {
            let error = await adminRequestVM.advanceApproval(flow, action: action, note: nil)
            housekeeping = nil
            if let error {
                housekeepingError = error
            } else {
                UISelectionFeedbackGenerator().selectionChanged()
            }
        }
    }

    // MARK: إجراءات أخرى

    /// غير القرار (تعديل الرقم، حذف نهائي) — شرائح صغيرة أسفل المربّع بنفس الصلاحيات
    private var otherActionsRow: some View {
        HStack(alignment: .center, spacing: DS.Spacing.xs) {
            Text(L10n.t("إجراءات أخرى", "Other actions"))
                .dsFont(.caption)
                .foregroundColor(DS.Color.textTertiary)
            ChangedWordsFlow(spacing: DS.Spacing.xs) {
                ForEach(otherActions) { item in
                    DSChipButton(item.title, icon: item.icon,
                                 tint: item.role == .destructive ? (item.tint ?? DS.Color.error) : (item.tint ?? DS.Color.primary),
                                 size: .small) {
                        item.action()
                    }
                    .disabled(!item.isEnabled || busy)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: سؤال العضو عن ناقص

    /// شرائح ملوّنة متعددة الاختيار (رقم الهاتف، تاريخ الميلاد، تاريخ الوفاة، الاسم الكامل) + سؤال اختياري
    /// مع اختيار شريحة (مطلوب بدونها) — الإرسال بالزرّ الواحد «إرسال للعضو»
    private var askPanel: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            DSFieldLabel(text: L10n.t("اختر الناقص", "Choose what's missing"))
            LazyVGrid(columns: [GridItem(.flexible(), spacing: DS.Spacing.xs), GridItem(.flexible(), spacing: DS.Spacing.xs)],
                      alignment: .leading, spacing: DS.Spacing.xs) {
                ForEach(ApprovalInfoField.askable) { field in
                    DSChipButton(field.title, icon: askFields.contains(field) ? "checkmark" : field.icon,
                                 tint: field.tint, isSelected: askFields.contains(field), size: .small, fillsWidth: true) {
                        withAnimation(DS.Anim.snappy) {
                            if askFields.contains(field) { askFields.remove(field) } else { askFields.insert(field) }
                        }
                        askError = nil
                    }
                    .accessibilityAddTraits(askFields.contains(field) ? .isSelected : [])
                }
            }
            ApprovalTemplateChips(adminRequestVM: adminRequestVM, kinds: [.info]) { insert($0, into: $askNote) }
            DSComposerField(icon: "questionmark.bubble",
                            label: askFields.isEmpty
                                ? L10n.t("سؤالك للعضو — مطلوب بلا اختيار", "Your question — required without a choice")
                                : L10n.t("سؤالك للعضو (اختياري)", "Your question (optional)"),
                            placeholder: L10n.t("مثلاً: أرفق صورة البطاقة", "e.g. attach a photo of the ID"),
                            text: $askNote,
                            tint: DS.Color.composerDiwaniya,
                            multiline: true,
                            limit: 500)
            errorText(askError)
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func sendAsk() {
        askError = nil
        let text = askNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let fields = ApprovalInfoField.askable.filter(askFields.contains)
        guard !fields.isEmpty || !text.isEmpty else {
            askError = L10n.t("اختر الناقص أو اكتب سؤالك للعضو.", "Choose what's missing or write your question.")
            return
        }
        busy = true
        Task {
            let error = await adminRequestVM.advanceApproval(flow, action: .requestInfo, note: text, fields: fields)
            busy = false
            if let error {
                askError = error
            } else {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onClose()
            }
        }
    }

    // MARK: نصوص مساعدة

    @ViewBuilder private func errorText(_ text: String?) -> some View {
        if let text {
            Text(text)
                .dsFieldFont(.footnote)
                .foregroundColor(DS.Color.error)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// الرد الجاهز يُضاف للحقل (سطر جديد إن كان فيه كلام)
    private func insert(_ body: String, into text: Binding<String>) {
        let current = text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        text.wrappedValue = current.isEmpty ? body : current + "\n" + body
        noteError = nil
        askError = nil
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private var specialistTitle: String {
        guard let role = ApprovalWorkflow.specialistRole(for: flow.requestType) else { return "—" }
        let base = AdminRequestViewModel.approvalRoleTitle(role)
        // لا أحد مفعّل بالدور → المالك/المدير يقوم بخطواته
        return adminRequestVM.hasActiveHolder(of: role)
            ? base
            : L10n.t("\(base) (يقوم بها المدير)", "\(base) (done by the manager)")
    }

    /// «الاسم (الدور)» لمن قام بالخطوة
    private func actorTitle(_ step: AdminRequestStep) -> String {
        let role = step.actorRole.flatMap(FamilyMember.UserRole.init(rawValue:))
        let roleTitle = role.map(AdminRequestViewModel.approvalRoleTitle)
        // خطوات السيرفر الآلية («مسار ٢»: تذكير، تصعيد، مسار سريع) بلا فاعل
        guard step.actorId != nil else { return roleTitle ?? L10n.t("النظام", "System") }
        guard let name = step.actorId.flatMap({ memberVM.member(byId: $0)?.firstName }) else {
            return roleTitle ?? L10n.t("—", "—")
        }
        guard let roleTitle, role != .member, role != .pending else { return name }
        return "\(name) (\(roleTitle))"
    }

    // MARK: التنفيذ

    private func runPrimary() {
        noteError = nil
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        switch primary {
        case .recommend:
            let action: ApprovalAction = recommendApprove ? .recommendApprove : .recommendReject
            if action.requiresNote && text.isEmpty {
                noteError = L10n.t("اكتب سبب التوصية بالرفض عشان يشوفه المدير.",
                                   "Write why you recommend rejection so the manager sees it.")
                return
            }
            advance(action, note: text)
        case .ask:
            sendAsk()
        case .approve:
            if executeNow { onExecute() } else { advance(.approve, note: text) }
        case .execute:
            onExecute()
        case nil:
            break
        }
    }

    private func runReturn() {
        noteError = nil
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            noteError = L10n.t("اكتب للمختص شنو المطلوب منه.", "Tell the specialist what you need from them.")
            return
        }
        pendingChip = .returnBack
        advance(.returnToSpecialist, note: text)
    }

    private func runReject() {
        noteError = nil
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            noteError = L10n.t("اكتب سبب الرفض، يوصل للعضو.", "Write the reason — it goes to the member.")
            return
        }
        onReject(text)
    }

    private func advance(_ action: ApprovalAction, note text: String) {
        busy = true
        Task {
            let error = await adminRequestVM.advanceApproval(flow, action: action, note: text)
            busy = false
            pendingChip = nil
            if let error {
                noteError = error
            } else {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onClose()
            }
        }
    }
}

// MARK: الردود الجاهزة («مسار ٢»)

/// صفّ أفقي من شرائح صغيرة فوق حقل الملاحظة — ردود القرار الحالي؛ الضغط يضيف النص للحقل.
/// لا ردود (أو الجدول غير موجود على السيرفر) = لا شيء
struct ApprovalTemplateChips: View {
    @ObservedObject var adminRequestVM: AdminRequestViewModel
    let kinds: [ApprovalTemplateKind]
    let onPick: (String) -> Void

    var body: some View {
        let items = adminRequestVM.approvalTemplates(of: kinds)
        if !items.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "text.badge.plus")
                        .dsGlyph(DS.Glyph.sm)
                        .foregroundColor(DS.Color.textTertiary)
                        .accessibilityHidden(true)
                    ForEach(items) { item in
                        DSChipButton(Self.short(item.body), size: .small) { onPick(item.body) }
                            .accessibilityLabel(L10n.t("رد جاهز: \(item.body)", "Ready reply: \(item.body)"))
                    }
                }
                .padding(.horizontal, DS.Border.width)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(L10n.t("ردود جاهزة", "Ready replies"))
        }
    }

    /// الشريحة تعرض بداية الرد فقط
    static func short(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        return line.count > 26 ? String(line.prefix(25)) + "…" : line
    }
}

// MARK: ملاحظات الإدارة الداخلية («مسار ٢»)

/// «ملاحظات الإدارة (لا يراها العضو)»: القائمة (الاسم الأول، الوقت) + سطر إدخال وإرسال، وحذف ملاحظتك.
/// الجدول غير موجود على السيرفر = القسم مخفي
struct ApprovalInternalNotes: View {
    @ObservedObject var adminRequestVM: AdminRequestViewModel
    @ObservedObject var memberVM: MemberViewModel
    let requestId: UUID

    @State private var draft = ""
    @State private var sending = false
    @State private var error: String?
    @FocusState private var focused: Bool
    @Environment(\.dsSection) private var section

    private var notes: [AdminRequestNote] { adminRequestVM.approvalNotes[requestId] ?? [] }
    private var me: UUID? { adminRequestVM.authVM?.currentUser?.id }

    var body: some View {
        if adminRequestVM.approvalNotesAvailable == true {
            DSComposerSection(title: L10n.t("ملاحظات الإدارة (لا يراها العضو)", "Admin notes (hidden from the member)"),
                              icon: "lock.doc.fill",
                              tint: DS.Color.actionNavy,
                              trailing: notes.isEmpty ? nil : "\(notes.count)",
                              index: 4) {
                if !notes.isEmpty {
                    VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                        ForEach(notes) { row($0) }
                    }
                }
                inputRow
                if let error {
                    Text(error)
                        .dsFieldFont(.footnote)
                        .foregroundColor(DS.Color.error)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func row(_ note: AdminRequestNote) -> some View {
        let mine = note.authorId != nil && note.authorId == me
        let name = note.authorId.flatMap { memberVM.member(byId: $0)?.firstName } ?? L10n.t("مسؤول", "Admin")
        return HStack(alignment: .top, spacing: DS.Spacing.sm) {
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                HStack(spacing: DS.Spacing.xs) {
                    Text(mine ? L10n.t("أنت", "You") : name)
                        .dsFieldFont(.rowTitleCompact)
                        .foregroundColor(DS.Color.fieldLabel)
                    if let date = ApprovalWorkflow.date(note.createdAt) {
                        Text("· " + DateHelper.relativeTime(from: date))
                            .dsFont(.caption)
                            .foregroundColor(DS.Color.textTertiary)
                    }
                }
                Text(note.body)
                    .dsFieldFont(.subtitle)
                    .foregroundColor(DS.Color.fieldValue)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            if mine {
                Button {
                    Task {
                        error = await adminRequestVM.deleteApprovalNote(note)
                    }
                } label: {
                    Image(systemName: "trash")
                        .dsGlyph(DS.Glyph.sm)
                        .foregroundColor(DS.Color.error)
                        .dsTapArea(width: DS.Icon.tapTarget, height: DS.Icon.inline)
                }
                .buttonStyle(DSPressStyle())
                .accessibilityLabel(L10n.t("حذف ملاحظتك", "Delete your note"))
            }
        }
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, DS.Spacing.xs)
        .background(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
            .fill(DS.Color.textTertiary.opacity(DS.Opacity.tintFill)))
    }

    private var canSend: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !sending }

    /// سطر واحد + إرسال (نفس شريط التعليقات بمقاس الزرّ الواحد)
    private var inputRow: some View {
        let ink = DS.Color.primary.dsChrome(in: section)
        return HStack(spacing: DS.Spacing.sm) {
            TextField(L10n.t("ملاحظة للإدارة…", "A note for the admins…"), text: $draft)
                .dsFieldFont(.callout)
                .foregroundColor(DS.Color.textPrimary)
                .focused($focused)
                .submitLabel(.send)
                .onSubmit(send)
                .padding(.horizontal, DS.Spacing.md)
                .frame(minHeight: DSBox.buttonHeight)
                .background(DSBox.buttonShape.fill(DS.Color.surface))
                .overlay(DSBox.buttonShape
                    .strokeBorder(focused ? ink.opacity(DS.Opacity.selectedStroke)
                                          : DS.Color.textTertiary.opacity(DS.Opacity.fieldStroke),
                                  lineWidth: focused ? DS.Border.widthBold : DS.Border.width))
            Button(action: send) {
                ZStack {
                    if sending {
                        ProgressView().tint(DS.Color.textOnPrimary).scaleEffect(DS.Spinner.buttonScale)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .dsGlyph(DSButtonSize.regular.glyph)
                            .foregroundColor(DSActionFill.label(enabled: canSend))
                    }
                }
                .frame(width: DSBox.buttonHeight, height: DSBox.buttonHeight)
                .background(DSActionFill.style(enabled: canSend || sending), in: DSBox.buttonShape)
            }
            .buttonStyle(DSScaleButtonStyle())
            .disabled(!canSend)
            .accessibilityLabel(L10n.t("إرسال الملاحظة", "Send the note"))
        }
    }

    private func send() {
        guard canSend else { return }
        error = nil
        sending = true
        let text = draft
        Task {
            let failure = await adminRequestVM.addApprovalNote(requestId: requestId, body: text)
            sending = false
            if let failure { error = failure } else { draft = "" }
        }
    }
}

// MARK: ردّ العضو على طلب الإدارة

/// شرائح ما طلبته الإدارة/المختص — تلتفّ لسطرين إذا ضاق العرض
struct ApprovalRequestedFields: View {
    let fields: [ApprovalInfoField]
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            DSFieldLabel(text: title)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: DS.Spacing.xs) { chips }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: DS.Spacing.xs), GridItem(.flexible(), spacing: DS.Spacing.xs)],
                          alignment: .leading, spacing: DS.Spacing.xs) { chips }
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var chips: some View {
        ForEach(fields) { field in
            DSStatusChip(text: field.title, icon: field.icon, tint: field.tint, size: .mini)
        }
    }
}

/// ردّ العضو المنظّم للطاقم: «الحقل: القيمة» بوضوح (كما فحصها السيرفر) ثم توضيحه المكتوب
struct ApprovalInfoReplyCard: View {
    let snapshot: ApprovalSnapshot
    @Environment(\.dsSection) private var section

    private struct Row: Identifiable {
        let field: ApprovalInfoField
        let value: String
        var id: String { field.rawValue }
    }

    /// ما طُلب أولاً بترتيبه، ثم أي حقل آخر في الرد
    private var rows: [Row] {
        let order = snapshot.infoFields + ApprovalInfoField.askable.filter { !snapshot.infoFields.contains($0) }
        return order.filter { $0 != .text }.compactMap { field in snapshot.infoReply[field].map { Row(field: field, value: $0) } }
    }

    var body: some View {
        let ink = DS.Color.success.dsChrome(in: section).dsReadableGlyph
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.sm) {
                DSStateIcon("checkmark.bubble.fill", tint: ink, size: DS.Icon.section, mapsChrome: false)
                Text(L10n.t("ردّ العضو", "The member's reply"))
                    .dsFieldFont(.rowTitle)
                    .foregroundColor(ink)
            }
            ForEach(rows) { row in
                let field = row.field, value = row.value
                HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.xsm) {
                    Image(dsSymbol: field.icon)
                        .dsGlyph(DS.Glyph.sm)
                        .foregroundColor(field.tint.dsChrome(in: section).dsReadableGlyph)
                        .accessibilityHidden(true)
                    Text(field.title + ":")
                        .dsFieldFont(.subtitle)
                        .foregroundColor(DS.Color.fieldValue)
                    // الرقم يبقى من اليسار لليمين داخل السطر العربي
                    Text(field == .phone ? "\u{2066}\(field.display(value))\u{2069}" : field.display(value))
                        .dsFieldFont(.bodySemibold)
                        .foregroundColor(DS.Color.textPrimary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
            if let text = snapshot.infoReply[.text] {
                Text(text)
                    .dsFieldFont(.callout)
                    .foregroundColor(DS.Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(DS.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DS.Card.radius, style: .continuous)
            .fill(ink.opacity(DS.Opacity.tintFill)))
    }
}

/// مسودة ردّ العضو على ما طلبته الإدارة — نفس قواعد السيرفر (`advance_admin_request`: provide_info)
struct ApprovalInfoDraft: Equatable {
    var country: KuwaitPhone.Country = KuwaitPhone.defaultCountry
    var phoneDigits = ""
    var birthDate: Date?
    var deathDate: Date?
    var fullName = ""
    var text = ""

    /// yyyy-mm-dd بالتقويم الميلادي وأرقام لاتينية (صيغة السيرفر)
    private static let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func isoDate(_ raw: String) -> Date? { isoFormatter.date(from: raw) }

    private var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var normalizedName: String { fullName.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
    private var localDigits: String { KuwaitPhone.normalizeDigits(phoneDigits).filter(\.isNumber) }

    /// القيمة كما تُرسل للسيرفر — nil = ناقصة أو غير صالحة
    func value(_ field: ApprovalInfoField) -> String? {
        switch field {
        case .phone:
            let digits = localDigits
            guard digits.count >= country.minDigits, digits.count <= country.maxDigits else { return nil }
            return country.dialingCode + digits
        case .birthDate: return birthDate.map(Self.isoFormatter.string(from:))
        case .deathDate: return deathDate.map(Self.isoFormatter.string(from:))
        case .fullName:
            let name = normalizedName
            return name.split(separator: " ").count >= 2 ? name : nil
        case .text:
            return trimmedText.isEmpty ? nil : trimmedText
        }
    }

    /// أول ناقص بنفس قواعد السيرفر — nil = جاهز للإرسال
    func problem(asked: [ApprovalInfoField], textRequired: Bool) -> String? {
        for field in asked where field != .text {
            switch field {
            case .phone:
                if localDigits.isEmpty { return L10n.t("أدخل رقم الهاتف.", "Enter the phone number.") }
                if value(.phone) == nil {
                    return L10n.t("رقم الهاتف غير مكتمل — \(country.minDigits) أرقام لـ\(country.nameArabic).",
                                  "The phone number is incomplete — \(country.minDigits) digits.")
                }
            case .birthDate, .deathDate:
                guard let date = field == .birthDate ? birthDate : deathDate else {
                    return L10n.t("اختر \(field.title).", "Choose the \(field.title.lowercased()).")
                }
                if Calendar.current.startOfDay(for: date) > Calendar.current.startOfDay(for: Date()) {
                    return L10n.t("\(field.title) لا يكون في المستقبل.", "The \(field.title.lowercased()) can't be in the future.")
                }
            case .fullName:
                if normalizedName.isEmpty { return L10n.t("أدخل الاسم الكامل.", "Enter the full name.") }
                if value(.fullName) == nil {
                    return L10n.t("اكتب الاسم الكامل (الاسم واسم الأب على الأقل).", "Write the full name (at least two names).")
                }
            case .text:
                break
            }
        }
        if textRequired && trimmedText.isEmpty {
            return asked.contains(where: { $0 != .text })
                ? L10n.t("اكتب التوضيح المطلوب.", "Write the requested note.")
                : L10n.t("اكتب ردّك للإدارة.", "Write your reply to the administration.")
        }
        return nil
    }

    /// القيم للسيرفر: المطلوب فقط + النص إن كُتب
    func values(asked: [ApprovalInfoField]) -> [String: String] {
        var result: [String: String] = [:]
        for field in asked where field != .text {
            if let v = value(field) { result[field.rawValue] = v }
        }
        if let t = value(.text) { result[ApprovalInfoField.text.rawValue] = t }
        return result
    }

    /// ملخّص مقروء («رقم الهاتف: …» سطراً سطراً ثم النص) — ملاحظة الخطوة (السيرفر يكتب ملخّصه بنفسه أيضاً)
    func summary(asked: [ApprovalInfoField]) -> String {
        var lines = asked.filter { $0 != .text }.compactMap { field in value(field).map { "\(field.title): \($0)" } }
        if let t = value(.text) { lines.append(t) }
        return lines.joined(separator: "\n")
    }

    var hasInput: Bool {
        !localDigits.isEmpty || birthDate != nil || deathDate != nil
            || !normalizedName.isEmpty || !trimmedText.isEmpty
    }
}

/// حقل لكل ما طلبته الإدارة: الهاتف بحقل الهاتف الموحّد (كود الدولة)، التاريخ بمربّع التاريخ الموحّد،
/// الاسم بحقل نص — ثم ردّ مكتوب (مطلوب إذا لم تُطلب حقول)
struct ApprovalInfoInputs: View {
    let asked: [ApprovalInfoField]
    @Binding var draft: ApprovalInfoDraft
    let textRequired: Bool

    private var fields: [ApprovalInfoField] { asked.filter { $0 != .text } }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            ForEach(fields) { field in input(field) }
            DSComposerField(icon: "text.bubble",
                            label: textLabel,
                            placeholder: L10n.t("اكتب ردّك للإدارة", "Write your reply to the administration"),
                            text: $draft.text,
                            tint: DS.Color.actionNavy,
                            multiline: true,
                            limit: 500)
        }
    }

    private var textLabel: String {
        if !textRequired { return L10n.t("ملاحظة للإدارة (اختياري)", "A note for the administration (optional)") }
        return fields.isEmpty ? L10n.t("ردّك", "Your reply") : L10n.t("التوضيح المطلوب", "The requested note")
    }

    @ViewBuilder private func input(_ field: ApprovalInfoField) -> some View {
        switch field {
        case .phone:
            DSFieldBox(field.title) {
                DSPhoneField(country: $draft.country,
                             digits: $draft.phoneDigits,
                             placeholder: L10n.t("أدخل الرقم", "Enter the number"),
                             compact: true,
                             bordered: false)
            }
        case .birthDate:
            dateRow(field, date: $draft.birthDate)
        case .deathDate:
            dateRow(field, date: $draft.deathDate)
        case .fullName:
            DSComposerField(icon: "person.text.rectangle",
                            label: field.title,
                            placeholder: L10n.t("الاسم واسم الأب والجد", "First, father's and grandfather's names"),
                            text: $draft.fullName,
                            tint: field.tint,
                            limit: 120)
        case .text:
            EmptyView()
        }
    }

    /// صفّ تاريخ يفتح مربّع التاريخ الموحّد بالمنتصف (نفس صفّ تاريخ الميلاد في «إضافة ابن»)
    private func dateRow(_ field: ApprovalInfoField, date: Binding<Date?>) -> some View {
        Button {
            dsPresentDatePicker(title: field.title, initial: date.wrappedValue, allowClear: false) { picked in
                if let picked { date.wrappedValue = picked }
            }
        } label: {
            DSRow(icon: field.icon, tint: field.tint, title: field.title,
                  subtitle: date.wrappedValue.map(DSDateText.display) ?? L10n.t("اختر التاريخ", "Choose the date")) {
                DSStateIcon(date.wrappedValue == nil ? "plus" : "pencil", tint: DS.Color.primary, size: DSBox.fieldIcon)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(L10n.t("يفتح اختيار التاريخ", "Opens the date picker"))
    }
}

/// بطاقة «مطلوب منك لإكمال الطلب»: سؤال الإدارة إن وُجد — بلا أدوار (الحقول المطلوبة تحتها مباشرة)
struct ApprovalAdminAskCard: View {
    let snapshot: ApprovalSnapshot
    /// داخل قسم يحمل العنوان نفسه (مربّع الرد): النص وحده بلا بطاقة
    var plain = false

    static var title: String { L10n.t("مطلوب منك لإكمال الطلب", "Needed from you to complete the request") }

    private var text: String {
        let ask = snapshot.infoRequest?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard ask.isEmpty else { return ask }
        return snapshot.asksFields
            ? L10n.t("أكمل البيانات المطلوبة وأرسلها للإدارة.", "Complete the requested details and send them to the administration.")
            : L10n.t("الإدارة تحتاج معلومات إضافية لإكمال طلبك.", "The administration needs more information to complete your request.")
    }

    var body: some View {
        if plain {
            Text(text)
                .dsFieldFont(.callout)
                .foregroundColor(DS.Color.fieldLabel)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            DSNoteCard(text, title: Self.title, icon: "questionmark.bubble.fill", tint: DS.Color.composerDiwaniya)
        }
    }
}

/// الرد داخل «طلباتي» نفسها (مرحلة «بانتظار ردّك»): ما تطلبه الإدارة، حقل لكل مطلوب، و«إرسال للإدارة»
struct ApprovalMemberReplyCard: View {
    @ObservedObject var adminRequestVM: AdminRequestViewModel
    let snapshot: ApprovalSnapshot
    /// بعد الإرسال الناجح (تأكيد «وصل ردّك» عند الشاشة الأم — البطاقة نفسها تختفي مع تغيّر المرحلة)
    var onSent: () -> Void = {}

    @State private var draft = ApprovalInfoDraft()
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            ApprovalAdminAskCard(snapshot: snapshot)
            ApprovalInfoInputs(asked: snapshot.infoFields, draft: $draft,
                               textRequired: ApprovalReplySender.textRequired(snapshot))
            if let error {
                Text(error)
                    .dsFieldFont(.footnote)
                    .foregroundColor(DS.Color.error)
                    .fixedSize(horizontal: false, vertical: true)
            }
            DSButton(L10n.t("إرسال للإدارة", "Send to the administration"), icon: "paperplane.fill", isLoading: busy) {
                send()
            }
            .disabled(busy)
        }
        .onChange(of: draft) { _ in error = nil }
    }

    private func send() {
        error = nil
        busy = true
        Task {
            let failure = await ApprovalReplySender.send(draft, snapshot: snapshot, adminRequestVM: adminRequestVM)
            busy = false
            if let failure {
                error = failure
            } else {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onSent()
            }
        }
    }
}

/// إرسال ردّ العضو (المكان الواحد لـ«طلباتي» ومربّع الإشعار): فحص محلي بقواعد السيرفر ثم `provide_info`
@MainActor
enum ApprovalReplySender {
    /// النص الحرّ مطلوب: سؤال بلا حقول (كما كان) أو طُلب «توضيح مكتوب»
    static func textRequired(_ snapshot: ApprovalSnapshot) -> Bool {
        !snapshot.asksFields || snapshot.infoFields.contains(.text)
    }

    static func send(_ draft: ApprovalInfoDraft, snapshot: ApprovalSnapshot,
                     adminRequestVM: AdminRequestViewModel) async -> String? {
        let asked = snapshot.infoFields
        if let problem = draft.problem(asked: asked, textRequired: textRequired(snapshot)) { return problem }
        let structured = snapshot.asksFields || asked.contains(.text)
        return await adminRequestVM.advanceApproval(snapshot, action: .provideInfo,
                                                    note: structured ? draft.summary(asked: asked) : draft.value(.text),
                                                    values: structured ? draft.values(asked: asked) : nil)
    }
}

/// مربّع العضو من الإشعار: مسار طلبه، ما تطلبه الإدارة، وحقل لكل مطلوب (`provide_info`) — يرجع الطلب للمراجعة
struct ApprovalReplyBox: View {
    @ObservedObject var adminRequestVM: AdminRequestViewModel
    let snapshot: ApprovalSnapshot
    /// نوع الطلب («تغيير رقم الهاتف»…)
    let requestTitle: String
    let onClose: () -> Void
    /// بعد الإرسال الناجح — الشاشة الأم تغلق المربّع وتؤكّد «وصل ردّك»
    var onSent: (() -> Void)? = nil

    @State private var draft = ApprovalInfoDraft()
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        DSComposer(
            title: L10n.t("الإدارة تطلب منك", "The administration asks you"),
            subtitle: requestTitle,
            icon: "questionmark.bubble.fill",
            tint: DS.Color.actionNavy,
            actionTitle: L10n.t("إرسال للإدارة", "Send to the administration"),
            actionIcon: "paperplane.fill",
            canSubmit: !busy,
            isBusy: busy,
            hasUnsavedChanges: draft.hasInput,
            onSubmit: send,
            onCancel: onClose
        ) {
            DSComposerSection(title: L10n.t("مسار طلبك", "Your request's path"),
                              icon: "point.topleft.down.to.point.bottomright.curvepath.fill",
                              tint: DS.Color.actionNavy, index: 0) {
                ApprovalTracker(stage: snapshot.stage, audience: .member)
            }
            DSComposerSection(title: ApprovalAdminAskCard.title,
                              icon: "questionmark.bubble.fill", tint: DS.Color.composerDiwaniya, index: 1) {
                ApprovalAdminAskCard(snapshot: snapshot, plain: true)
            }
            DSComposerSection(title: L10n.t("ردّك على الإدارة", "Your reply to the administration"), icon: "text.bubble.fill",
                              tint: DS.Color.actionNavy, index: 2) {
                ApprovalInfoInputs(asked: snapshot.infoFields, draft: $draft,
                                   textRequired: ApprovalReplySender.textRequired(snapshot))
                if let error {
                    Text(error)
                        .dsFieldFont(.footnote)
                        .foregroundColor(DS.Color.error)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onChange(of: draft) { _ in error = nil }
    }

    private func send() {
        error = nil
        busy = true
        Task {
            let failure = await ApprovalReplySender.send(draft, snapshot: snapshot, adminRequestVM: adminRequestVM)
            busy = false
            if let failure {
                error = failure
            } else {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                if let onSent { onSent() } else { onClose() }
            }
        }
    }
}
