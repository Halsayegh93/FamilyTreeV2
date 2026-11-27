import SwiftUI
import Supabase

// MARK: - «استكمال التسجيل» بعد قبول الانضمام «من خارج العائلة» (موافقة المالك ٢٠٢٦-١١-٢٧، الوحدة R1 — boxes.png)
//
// مربّع واحد تفتحه بوابة «أكمل حسابك» نفسها (`LineageGateStore` + «لاحقاً» من `daughter_sons_allow_later`):
// «هل الأم من العائلة؟»
//   نعم ← في المربّع نفسه: «اسم الوالدة الرباعي» + سطر الوالد للاطلاع (من الاسم المسجّل) + «إرسال إلى الإدارة»
//         = `submit_outside_lineage` (20261127160000) ← الإدارة تختار الوالدة من بنات العائلة وتعتمد ← شجرة النساء.
//   لا  ← `mark_outside_mother` مباشرة: لا اسم ولا طلب، والحساب «بصلاحيات محدودة» بلا أي رسالة له، ويُغلق المربّع.

enum OutsideLineage {
    static func submit(motherName: String) async throws {
        _ = try await SupabaseConfig.client
            .rpc("submit_outside_lineage", params: ["p_mother_name": SignupOriginRules.tidy(motherName)]).execute()
    }

    /// «هل الأم من العائلة؟» لا
    static func markOutsideMother() async throws {
        _ = try await SupabaseConfig.client.rpc("mark_outside_mother").execute()
    }

    static func message(_ error: Error) -> String {
        switch (error as? PostgrestError)?.hint ?? "" {
        case "name_required": return L10n.t("يُرجى كتابة اسم الوالدة.", "Type your mother's name.")
        case "father_name_missing": return L10n.t(SignupOriginRules.Ar.fatherMissing, "Your father's name is incomplete — contact the admins.")
        default: return DaughterSons.message(error)
        }
    }
}

struct CompleteRegistrationPage: View {
    let status: DaughterSons.Status?
    /// «طلب استكمال البيانات» من الإدارة على الطلب المعلّق (R2): «اسم الوالدة» مميّزاً ويُرسل للطلب نفسه
    var ask: CompletionAsk.Open? = nil
    var onSent: () -> Void
    /// nil = لا «لاحقاً» (الإعداد مطفأ)
    var onLater: (() -> Void)?
    /// «لا» سُجّلت على السيرفر ← الدخول إلى التطبيق
    var onLimited: () -> Void = {}

    @EnvironmentObject private var authVM: AuthViewModel
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var sent: Bool
    @State private var inFamily: Bool?
    @State private var motherName = ""
    /// خطأ الاسم يظهر بعد التوقّف عن الكتابة
    @State private var motherSettled = true
    @State private var busy = false
    @State private var errorText: String?

    init(status: DaughterSons.Status?, ask: CompletionAsk.Open? = nil, onSent: @escaping () -> Void, onLater: (() -> Void)?,
         onLimited: @escaping () -> Void = {}) {
        self.status = status
        self.ask = ask
        self.onSent = onSent
        self.onLater = onLater
        self.onLimited = onLimited
        _sent = State(initialValue: status?.pending == true && ask == nil)
    }

    private typealias T = SignupOriginRules.Ar
    private typealias R = SignupOriginRules

    private var fatherName: String? { R.derivedFatherName(fullName: authVM.currentUser?.fullName ?? "") }
    private var canSend: Bool { R.canSendCompletion(motherInFamily: inFamily, motherName: motherName, fatherName: fatherName) }

    var body: some View {
        SignupBoxShell(subtitle: L10n.t(T.completeTitle, "Complete registration")) {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                // السؤال ← «قيد المراجعة» في المربّع نفسه: انزلاق قصير للأمام (A1)؛ و«طلب استكمال البيانات» من الإدارة (R2)
                ZStack(alignment: .top) {
                    if sent {
                        VStack(alignment: .leading, spacing: DS.Spacing.md) { sentContent }
                            .transition(stepTransition)
                    } else if ask != nil {
                        VStack(alignment: .leading, spacing: DS.Spacing.md) { askContent }
                            .transition(stepTransition)
                    } else {
                        VStack(alignment: .leading, spacing: DS.Spacing.md) { questionContent }
                            .transition(stepTransition)
                    }
                }
                .onChange(of: motherName) { _ in settleMother() }
                if let errorText {
                    Text(errorText).dsFont(.footnote).foregroundColor(DS.Color.error)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func settleMother() {
        let snapshot = motherName
        motherSettled = false
        DispatchQueue.main.asyncAfter(deadline: .now() + DSMotionRules.Timing.settle) {
            guard motherName == snapshot else { return }
            withAnimation(reduceMotion ? DSMotion.fade : DSMotion.reveal) { motherSettled = true }
        }
    }

    private var stepTransition: AnyTransition {
        .dsStep(forward: true, rtl: LanguageManager.shared.layoutDirection == .rightToLeft, reduceMotion: reduceMotion)
    }

    // MARK: السؤال (+ اسم الوالدة عند «نعم»)

    @ViewBuilder private var questionContent: some View {
        SignupBoxTitle(icon: "person.2.fill", title: L10n.t(T.motherQuestion, "Is your mother from the family?"),
                       tint: DS.Color.femaleFill)
        if status?.wasRejected == true {
            Text(status?.rejectedReason.map { L10n.t("السبب: ", "Reason: ") + $0 }
                 ?? L10n.t(T.rejectedBody, "Review your details and send them again."))
                .dsFont(.footnote).foregroundColor(DS.Color.warning)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(L10n.t(T.approvedLine, "Your request was approved. Answer to complete registration."))
                .dsFont(.footnote).foregroundColor(DS.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: DS.Spacing.sm)) : AnyLayout(HStackLayout(spacing: DS.Spacing.sm))
        layout {
            answerTile(L10n.t(T.yes, "Yes"), icon: "checkmark", tint: DS.Color.palmFill, selected: inFamily == true) {
                withAnimation(reduceMotion ? DSMotion.fade : DSMotion.reveal) { inFamily = true }
            }
            answerTile(L10n.t(T.no, "No"), icon: "xmark", tint: DS.Color.slateFill, selected: inFamily == false) {
                markLimited()
            }
            .disabled(busy)
        }
        if inFamily == true {
            // «نعم» تكشف الاسم والوالد والإرسال في المربّع نفسه — تنزل قليلاً مع تلاشٍ (A1)
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
            motherField
            // خطأ تحت الحقل بعد انتهاء الكتابة، ثم سطر الشرح الدائم (الأجزاء، والمطابقة)
            if motherSettled, let e = R.motherNameError(motherName) {
                Label {
                    Text(L10n.t(e, "Write at least three parts of her name, without the family name."))
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.circle.fill").dsGlyph(DS.Glyph.sm)
                }
                .dsFont(.footnote).foregroundColor(DS.Color.error)
                .transition(.dsReveal(reduceMotion: reduceMotion))
            }
            Text(L10n.t(T.motherNameHelp, "Her first name, her father's, grandfather's and great-grandfather's — without the family name."))
                .dsFont(.footnote).foregroundColor(DS.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(L10n.t(T.motherNameHint, "Without the family name. The admins match it to your mother's record."))
                .dsFont(.footnote).foregroundColor(DS.Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            if let f = fatherName {
                Text(verbatim: L10n.t(T.fatherLine(f), "Father: \(f) — from your registered name."))
                    .dsFont(.footnote).foregroundColor(DS.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(L10n.t(T.fatherMissing, "Your father's name is incomplete — contact the admins."))
                    .dsFont(.footnote).foregroundColor(DS.Color.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // لماذا الزرّ معطّل
            if !canSend, fatherName != nil {
                Label {
                    Text(L10n.t(T.missingLine([T.motherName]), "To send, complete: mother's four-part name"))
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "info.circle").dsGlyph(DS.Glyph.sm)
                }
                .dsFont(.footnote).foregroundColor(DS.Color.textSecondary)
            }
            DSButton(L10n.t(T.send, "Send to the admins"), icon: "paperplane.fill", isLoading: busy) { send() }
                .disabled(!canSend || busy)
            }
            .transition(.dsReveal(reduceMotion: reduceMotion))
        }
        if let onLater {
            DSButton(L10n.t(T.later, "Later"), role: .cancel) { onLater() }
        }
    }

    private var motherField: some View {
        DSComposerField(icon: "person.fill", label: L10n.t(T.motherName, "Mother's four-part name"),
                        placeholder: L10n.t(T.motherNameExample, "e.g. Fatima Ahmad Ali Hassan"),
                        text: $motherName, tint: DS.Color.female, limit: 120, required: true)
    }

    // MARK: «طلب استكمال البيانات» (R2)

    @ViewBuilder private var askContent: some View {
        SignupBoxTitle(icon: "exclamationmark.circle.fill",
                       title: L10n.t(AdminJoinBoxRules.Ar.memberAskTitle, "Please complete your details"),
                       tint: DS.Color.warningFill)
        Text(L10n.t(AdminJoinBoxRules.Ar.memberAskBody, "The admins asked you to complete:")
             + " " + (ask?.missing.map { AdminJoinBoxRules.fieldLabel($0) }.joined(separator: "، ") ?? ""))
            .dsFont(.footnote).foregroundColor(DS.Color.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        if let note = ask?.note, !note.isEmpty {
            Text(verbatim: note).dsFont(.footnote).foregroundColor(DS.Color.warning)
                .fixedSize(horizontal: false, vertical: true)
        }
        motherField.completionAskHighlight(true)
        if AdminJoinBoxRules.motherNameMissing(motherInFamily: true, motherName: motherName) {
            Text(L10n.t(AdminJoinBoxRules.Ar.motherNameRequired, "Type your mother's four-part name (at least three words)."))
                .dsFont(.footnote).foregroundColor(DS.Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        DSButton(L10n.t(T.send, "Send to the admins"), icon: "paperplane.fill", isLoading: busy) { sendAsk() }
            .disabled(AdminJoinBoxRules.motherNameMissing(motherInFamily: true, motherName: motherName) || busy)
        if let onLater {
            DSButton(L10n.t(T.later, "Later"), role: .cancel) { onLater() }
        }
    }

    private func sendAsk() {
        guard !busy else { return }
        busy = true
        errorText = nil
        Task {
            do {
                try await CompletionAsk.answer(["mother_name": SignupOriginRules.tidy(motherName)])
                DSMomentToast.show(L10n.t(T.sentMoment, "Request sent"), moment: .success, section: nil)
                withAnimation(reduceMotion ? DSMotion.fade : DSMotion.stepIn) { sent = true }
            } catch {
                errorText = CompletionAsk.message(error)
            }
            busy = false
        }
    }

    private func answerTile(_ title: String, icon: String, tint: Color, selected: Bool,
                            action: @escaping () -> Void) -> some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
        return Button(action: action) {
            VStack(spacing: DS.Spacing.sm) {
                Image(systemName: icon)
                    .dsGlyph(DS.Glyph.xl, weight: .semibold)
                    .foregroundColor(DS.Color.textOnPrimary)
                    .frame(width: DS.Icon.state, height: DS.Icon.state)
                    .background(Circle().fill(tint))
                    .accessibilityHidden(true)
                Text(title).dsFont(.rowTitle).foregroundColor(DS.Color.textPrimary)
            }
            .frame(maxWidth: .infinity, minHeight: DS.Icon.tapTarget * 3)
            .background(shape.fill(selected ? DS.Color.cardBackgroundSoft : DS.Color.cardBackground))
            .overlay(shape.strokeBorder(selected ? DS.Color.accentLight : DS.Color.cardBorder,
                                        lineWidth: selected ? DS.Border.width * 2 : DS.Border.width))
            .overlay(alignment: .topTrailing) { if selected { SignupCheckBadge() } }
            .animation(DSMotion.tap, value: selected)
            // قفزة الاختيار (A1) — «تقليل الحركة»: الإطار وحده
            .dsSelectPop(selected)
            .contentShape(shape)
        }
        .buttonStyle(AdminTilePressStyle())
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: أُرسل

    @ViewBuilder private var sentContent: some View {
        SignupBoxTitle(icon: "clock.fill", title: L10n.t(T.pendingTitle, "Your registration is under review"))
        Text(L10n.t(T.sentBody, "You'll be notified once approved; then you're added to the tree."))
            .dsFont(.footnote).foregroundColor(DS.Color.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        DSButton(L10n.t(T.goToApp, "Go to the app")) { onSent() }
    }

    // MARK: البيانات

    private func send() {
        guard canSend, !busy else { return }
        busy = true
        errorText = nil
        Task {
            do {
                try await OutsideLineage.submit(motherName: motherName)
                // لحظة النجاح ثم «قيد المراجعة» (A1)
                DSMomentToast.show(L10n.t(T.sentMoment, "Request sent"), moment: .success, section: nil)
                withAnimation(reduceMotion ? DSMotion.fade : DSMotion.stepIn) { sent = true }
            } catch {
                errorText = OutsideLineage.message(error)
            }
            busy = false
        }
    }

    /// «لا»: صلاحيات محدودة مباشرة — بلا طلب ولا رسالة عنها
    private func markLimited() {
        guard !busy, R.afterQuestion(motherInFamily: false) == .limited else { return }
        inFamily = false
        busy = true
        errorText = nil
        Task {
            do {
                try await OutsideLineage.markOutsideMother()
                onLimited()
            } catch {
                errorText = OutsideLineage.message(error)
                inFamily = nil
            }
            busy = false
        }
    }
}

#if DEBUG
#Preview("استكمال التسجيل") {
    CompleteRegistrationPage(status: nil, onSent: {}, onLater: {})
        .environmentObject(AuthViewModel())
}
#endif
