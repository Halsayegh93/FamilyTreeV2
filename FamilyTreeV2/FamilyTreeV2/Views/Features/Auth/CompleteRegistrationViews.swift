import SwiftUI
import Supabase

// MARK: - «استكمال التسجيل» بعد قبول الانضمام «من خارج العائلة» (موافقة المالك ٢٠٢٦-١١-٢٧، الوحدة R1؛ العيّنة spouse2 ٢٠٢٦-١١-٢٨)
//
// مربّع واحد تفتحه بوابة «أكمل حسابك» (`LineageGateStore` + «لاحقاً» من `daughter_sons_allow_later`)، بثلاث نقاط:
// ١) «هل الوالدة من العائلة؟»
//      نعم ← في المربّع نفسه: «اسم الوالدة الرباعي» + «إرسال إلى الإدارة» = `submit_outside_lineage` (20261127160000).
//      لا  ← الخطوة ٢ (بلا تأكيد).
// ٢) «هل أحد أفراد أسرتك من العائلة؟» (رمز الأسرة): «الزوجة» (للرجل) / «الزوج» (للمرأة) + «من عائلة المحمدعلي» · «لا يوجد».
//      «لا يوجد» ← تأكيد ثم `mark_outside_mother` (صلاحيات محدودة، بلا رسالة عنها — السلوك السابق لـ«لا»).
// ٣) «بيانات الزوجة/الزوج» (رمز الخاتمين): «اسم الزوجة الرباعي» والعائلة «المحمدعلي» ثابتة في طرف الحقل ← «رجوع» /
//      «إرسال إلى الإدارة» = `submit_spouse_link` (20261128150000) ← «تم إرسال البيانات» بالصلة والاسم و«تعديل البيانات».
// زرّ الرجوع في الرأس يرجع خطوة (٢ ← ١، ٣ ← ٢)، و«تسجيل الخروج» في الطرف الآخر. نص رسمي: «الوالد/الوالدة/الزوج/الزوجة».

enum OutsideLineage {
    static func submit(motherName: String) async throws {
        _ = try await SupabaseConfig.client
            .rpc("submit_outside_lineage", params: ["p_mother_name": SignupOriginRules.tidy(motherName)]).execute()
    }

    /// «لا يوجد» على «هل أحد أفراد أسرتك من العائلة؟» (كانت «لا» على الوالدة)
    static func markOutsideMother() async throws {
        _ = try await SupabaseConfig.client.rpc("mark_outside_mother").execute()
    }

    static func message(_ error: Error) -> String {
        switch (error as? PostgrestError)?.hint ?? "" {
        case "name_required": return L10n.t("يُرجى كتابة الاسم.", "Type the name.")
        case "father_name_missing": return L10n.t(SignupOriginRules.Ar.fatherMissing, "Your father's name is incomplete — contact the admins.")
        default: return DaughterSons.message(error)
        }
    }
}

/// طلب ربط الزوج/الزوجة المعلّق (`my_spouse_request`) — لشاشة «تم إرسال البيانات» و«تعديل البيانات»
enum SpouseLink {
    nonisolated struct Pending: Decodable, Equatable, Sendable {
        let requestId: UUID
        let relation: SignupOriginRules.Relation
        let typedName: String
        let spouseName: String
        enum CodingKeys: String, CodingKey {
            case requestId = "request_id", relation, typedName = "spouse_typed_name", spouseName = "spouse_name"
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            requestId = try c.decode(UUID.self, forKey: .requestId)
            relation = SignupOriginRules.Relation(rawValue: (try? c.decode(String.self, forKey: .relation)) ?? "") ?? .wife
            typedName = (try? c.decode(String.self, forKey: .typedName)) ?? ""
            spouseName = (try? c.decode(String.self, forKey: .spouseName)) ?? typedName
        }
        init(relation: SignupOriginRules.Relation, typedName: String) {
            requestId = UUID(); self.relation = relation; self.typedName = typedName
            spouseName = typedName + " " + SignupOriginRules.familyName
        }
    }

    /// إرسال أو تعديل (الطلب المعلّق نفسه) — ويغلق «طلب المعلومات» المفتوح عليه
    static func submit(name: String) async throws {
        _ = try await SupabaseConfig.client
            .rpc("submit_spouse_link", params: ["p_name": SignupOriginRules.spouseNameToSend(name)]).execute()
    }

    static func mine() async -> Pending? {
        do {
            let data = try await SupabaseConfig.client.rpc("my_spouse_request").execute().data
            guard let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty, text != "null" else { return nil }
            return try JSONDecoder().decode(Pending.self, from: data)
        } catch {
            if !ErrorHelper.isCancellation(error) { Log.warning("[SpouseLink] my_spouse_request: \(error.localizedDescription)") }
            return nil
        }
    }
}

struct CompleteRegistrationPage: View {
    let status: DaughterSons.Status?
    /// «طلب استكمال البيانات» من الإدارة على الطلب المعلّق (R2): «اسم الوالدة» أو «اسم الزوج/الزوجة» مميّزاً
    var ask: CompletionAsk.Open? = nil
    var onSent: () -> Void
    /// nil = لا «لاحقاً» (الإعداد مطفأ)
    var onLater: (() -> Void)?
    /// «لا يوجد» سُجّلت على السيرفر ← الدخول إلى التطبيق
    var onLimited: () -> Void = {}
    #if DEBUG
    /// معاينة التصوير: الخطوة والجنس وحالة «أُرسل» بلا سيرفر
    var previewStep: SignupOriginRules.CompletionStep? = nil
    var previewGender: String? = nil
    var previewSent: SpouseLink.Pending? = nil
    #endif

    @EnvironmentObject private var authVM: AuthViewModel
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var sent: Bool
    @State private var step: SignupOriginRules.CompletionStep = .mother
    @State private var forward = true
    @State private var inFamily: Bool?
    @State private var motherName = ""
    @State private var spouseName = ""
    /// خطأ الاسم يظهر بعد التوقّف عن الكتابة
    @State private var motherSettled = true
    @State private var spouseSettled = true
    @State private var busy = false
    @State private var errorText: String?
    /// تأكيد «لا يوجد» قبل إرسالها (لا رجوع عنها من التطبيق)
    @State private var confirmNone = false
    /// طلب الزوج/الزوجة المعلّق — شاشة «تم إرسال البيانات»
    @State private var spouseSent: SpouseLink.Pending?
    @State private var familyPick: Bool?

    init(status: DaughterSons.Status?, ask: CompletionAsk.Open? = nil, onSent: @escaping () -> Void, onLater: (() -> Void)?,
         onLimited: @escaping () -> Void = {}) {
        self.status = status
        self.ask = ask
        self.onSent = onSent
        self.onLater = onLater
        self.onLimited = onLimited
        _sent = State(initialValue: status?.pending == true && ask == nil)
    }

    #if DEBUG
    /// `-uiPreviewSignup family|spouse|spouse-f|sent` — للتصوير بلا سيرفر
    init(preview step: SignupOriginRules.CompletionStep, gender: String, sent: SpouseLink.Pending? = nil) {
        self.init(status: nil, onSent: {}, onLater: nil)
        previewStep = step
        previewGender = gender
        previewSent = sent
    }
    #endif

    private typealias T = SignupOriginRules.Ar
    private typealias R = SignupOriginRules

    private var gender: String? {
        #if DEBUG
        if let previewGender { return previewGender }
        #endif
        return authVM.currentUser?.gender
    }
    private var relation: R.Relation { R.relation(gender: gender) }
    private var fatherName: String? { R.derivedFatherName(fullName: authVM.currentUser?.fullName ?? "") }
    private var canSend: Bool { R.canSendCompletion(motherInFamily: inFamily, motherName: motherName, fatherName: fatherName) }
    /// النقاط في خطوات الأسئلة وحدها (لا في «أُرسل» ولا «طلب المعلومات»)
    private var showsSteps: Bool { !sent && spouseSent == nil && ask == nil }

    var body: some View {
        SignupBoxShell(subtitle: L10n.t(T.completeTitle, "Complete registration"),
                       step: showsSteps ? step.rawValue : nil,
                       onSignOut: { Task { await authVM.signOut() } },
                       onBack: showsSteps && R.back(from: step) != nil ? { goBack() } as (() -> Void)? : nil,
                       lift: DSBox.signupBoxLift) {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                // الخطوات تنزلق في المربّع نفسه (A1)؛ «أُرسل» و«طلب استكمال البيانات» من الإدارة (R2)
                ZStack(alignment: .top) {
                    if let pending = spouseSent {
                        VStack(alignment: .leading, spacing: DS.Spacing.md) { spouseSentContent(pending) }
                            .transition(stepTransition)
                    } else if sent {
                        VStack(alignment: .leading, spacing: DS.Spacing.md) { sentContent }
                            .transition(stepTransition)
                    } else if let ask {
                        VStack(alignment: .leading, spacing: DS.Spacing.md) {
                            if ask.isSpouse { askSpouseContent } else { askContent }
                        }
                        .transition(stepTransition)
                    } else {
                        switch step {
                        case .mother:
                            VStack(alignment: .leading, spacing: DS.Spacing.md) { questionContent }
                                .transition(stepTransition)
                        case .family:
                            VStack(alignment: .leading, spacing: DS.Spacing.md) { familyContent }
                                .transition(stepTransition)
                        case .spouse:
                            VStack(alignment: .leading, spacing: DS.Spacing.md) { spouseContent }
                                .transition(stepTransition)
                        }
                    }
                }
                .onChange(of: motherName) { _ in settle(mother: true) }
                .onChange(of: spouseName) { _ in settle(mother: false) }
                .dsAlert(L10n.t(T.confirmNoTitle, "Confirm your choice"), isPresented: $confirmNone) {
                    Button(L10n.t(T.confirm, "Confirm"), role: .destructive) { markLimited() }
                    Button(L10n.t(T.back, "Back"), role: .cancel) { familyPick = nil }
                } message: {
                    Text(L10n.t(T.confirmNoneBody,
                                "No member of your family is from the Al-Mohammad Ali family. This choice can't be changed later in the app."))
                }
                if let errorText {
                    Text(errorText).dsFont(.footnote).foregroundColor(DS.Color.error)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .task { await loadPending() }
    }

    /// «أُرسل» وطلب الزوج/الزوجة معلّق ← «تم إرسال البيانات» باسمه
    private func loadPending() async {
        #if DEBUG
        if let previewStep { step = previewStep; if previewStep == .spouse { familyPick = true } }
        if let previewSent { spouseSent = previewSent; return }
        if previewStep != nil { return }
        #endif
        guard sent || ask?.isSpouse == true else { return }
        if let p = await SpouseLink.mine() {
            spouseName = p.typedName
            if sent { spouseSent = p }
        }
    }

    private func settle(mother: Bool) {
        let snapshot = mother ? motherName : spouseName
        if mother { motherSettled = false } else { spouseSettled = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + DSMotionRules.Timing.settle) {
            guard (mother ? motherName : spouseName) == snapshot else { return }
            withAnimation(reduceMotion ? DSMotion.fade : DSMotion.reveal) {
                if mother { motherSettled = true } else { spouseSettled = true }
            }
        }
    }

    private var stepTransition: AnyTransition {
        .dsStep(forward: forward, rtl: LanguageManager.shared.layoutDirection == .rightToLeft, reduceMotion: reduceMotion)
    }

    /// إلى خطوة (للأمام أو الخلف): الاتجاه أولاً بلا حركة، ثم التبديل في الدورة التالية
    private func go(to next: R.CompletionStep) {
        forward = next.rawValue > step.rawValue
        errorText = nil
        DispatchQueue.main.async {
            withAnimation(reduceMotion ? DSMotion.fade : DSMotion.stepIn) { step = next }
        }
    }

    private func goBack() {
        guard let prev = R.back(from: step) else { return }
        if prev == .mother { inFamily = nil }
        if prev == .family { familyPick = nil }
        go(to: prev)
    }

    private var tilesLayout: AnyLayout {
        typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: DS.Spacing.sm)) : AnyLayout(HStackLayout(spacing: DS.Spacing.sm))
    }

    // MARK: ١) الوالدة (+ اسمها عند «نعم»)

    @ViewBuilder private var questionContent: some View {
        SignupBoxTitle(icon: "person.fill", title: L10n.t(T.motherQuestion, "Is your mother from the family?"),
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
        tilesLayout {
            SignupChoiceTile(title: L10n.t(T.yes, "Yes"), glyph: .symbol("checkmark"), tint: DS.Color.palmFill,
                             selected: inFamily == true) {
                withAnimation(reduceMotion ? DSMotion.fade : DSMotion.reveal) { inFamily = true }
            }
            // «لا» ← «هل أحد أفراد أسرتك من العائلة؟» بعد لحظة الاختيار
            SignupChoiceTile(title: L10n.t(T.no, "No"), glyph: .symbol("xmark"), tint: DS.Color.slateFill,
                             selected: inFamily == false) {
                guard !busy, inFamily != false else { return }
                inFamily = false
                DispatchQueue.main.asyncAfter(deadline: .now() + DSMotionRules.selectHold(reduceMotion: reduceMotion)) {
                    if R.afterQuestion(motherInFamily: false) == .familyQuestion { go(to: .family) }
                }
            }
            .disabled(busy)
        }
        if inFamily == true {
            // «نعم» تكشف الاسم والإرسال في المربّع نفسه — تنزل قليلاً مع تلاشٍ (A1)
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                motherField
                if motherSettled, let e = R.motherNameError(motherName) {
                    fieldError(e, english: "Write her four-part name, without the family name.")
                }
                Text(L10n.t(T.motherNameHelp, "Her first name, her father's, grandfather's and great-grandfather's — without the family name."))
                    .dsFont(.footnote).foregroundColor(DS.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if fatherName == nil {
                    Text(L10n.t(T.fatherMissing, "Your father's name is incomplete — contact the admins."))
                        .dsFont(.footnote).foregroundColor(DS.Color.warning)
                        .fixedSize(horizontal: false, vertical: true)
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

    // MARK: ٢) «هل أحد أفراد أسرتك من العائلة؟»

    @ViewBuilder private var familyContent: some View {
        SignupBoxTitle(icon: "person.3.fill", title: L10n.t(T.familyQuestion, "Is a member of your family from the family?"),
                       tint: DS.Color.seaFill)
        Text(L10n.t(T.familyQuestionSub, "It helps the admins link you in the tree."))
            .dsFont(.footnote).foregroundColor(DS.Color.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        tilesLayout {
            SignupChoiceTile(title: L10n.t(T.spouseTile(relation), relation == .wife ? "Wife" : "Husband"),
                             subtitle: L10n.t(T.fromFamilyLine, "From the Al-Mohammad Ali family"),
                             glyph: .rings, tint: DS.Color.saduFill, selected: familyPick == true) {
                guard familyPick == nil else { return }
                familyPick = true
                DispatchQueue.main.asyncAfter(deadline: .now() + DSMotionRules.selectHold(reduceMotion: reduceMotion)) {
                    if R.afterFamily(hasSpouse: true) == .spouseName { go(to: .spouse) }
                }
            }
            SignupChoiceTile(title: L10n.t(T.noneTile, "None"), glyph: .symbol("xmark"), tint: DS.Color.slateFill,
                             selected: familyPick == false) {
                guard familyPick == nil, !busy else { return }
                familyPick = false
                confirmNone = true
            }
            .disabled(busy)
        }
        if let onLater {
            DSButton(L10n.t(T.later, "Later"), role: .cancel) { onLater() }
        }
    }

    // MARK: ٣) بيانات الزوجة/الزوج

    @ViewBuilder private var spouseContent: some View {
        SignupBoxTitle(glyph: .rings, title: L10n.t(T.spouseTitle(relation), relation == .wife ? "Wife's details" : "Husband's details"),
                       tint: DS.Color.saduFill)
        Text(L10n.t(T.spouseSub(relation), "The admins check the name and link you in the tree."))
            .dsFont(.footnote).foregroundColor(DS.Color.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        spouseField
        if spouseSettled, let e = R.spouseNameError(spouseName, relation: relation) {
            fieldError(e, english: "Write the four-part name, without the family name.")
        }
        Text(L10n.t(T.familyNameHint, "Without the family name; Al-Mohammad Ali is added automatically."))
            .dsFont(.footnote).foregroundColor(DS.Color.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
        HStack(spacing: DS.Spacing.sm) {
            DSButton(L10n.t(T.back, "Back"), role: .cancel) { goBack() }
                .disabled(busy)
            DSButton(L10n.t(T.send, "Send to the admins"), isLoading: busy) { sendSpouse() }
                .disabled(!R.canSendSpouse(spouseName) || busy)
        }
    }

    private var spouseField: some View {
        DSComposerField(icon: "person.fill",
                        label: L10n.t(T.spouseNameLabel(relation), relation == .wife ? "Wife's four-part name" : "Husband's four-part name"),
                        placeholder: L10n.t(T.spouseNameExample(relation), "e.g. Fatima Ahmad Zaid Hassan"),
                        text: $spouseName, tint: relation == .wife ? DS.Color.female : DS.Color.male, limit: 120, required: true,
                        suffix: R.familyName)
    }

    // MARK: «تم إرسال البيانات» — الصلة والاسم و«تعديل البيانات»

    @ViewBuilder private func spouseSentContent(_ p: SpouseLink.Pending) -> some View {
        SignupBoxTitle(icon: "checkmark", title: L10n.t(T.spouseSentTitle, "Details sent"), tint: DS.Color.palmFill)
        Text(L10n.t(T.spouseSentBody(p.relation), "The admins check the name and link you; you'll be notified."))
            .dsFont(.footnote).foregroundColor(DS.Color.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        VStack(spacing: 0) {
            sentRow(L10n.t(T.relationLabel, "Relation"), L10n.t(T.spouseTile(p.relation), p.relation == .wife ? "Wife" : "Husband"))
            DSDivider()
            sentRow(L10n.t(T.nameLabel, "Name"), p.spouseName)
        }
        .padding(.horizontal, DS.Spacing.md)
        .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).fill(DS.Color.cardBackgroundSoft))
        HStack(spacing: DS.Spacing.sm) {
            DSButton(L10n.t(T.editData, "Edit details"), icon: "pencil", role: .cancel) {
                spouseName = p.typedName
                familyPick = true
                step = .spouse
                forward = false
                withAnimation(reduceMotion ? DSMotion.fade : DSMotion.stepIn) { spouseSent = nil; sent = false }
            }
            DSButton(L10n.t(T.goToApp, "Go to the app")) { onSent() }
        }
    }

    private func sentRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.md) {
            Text(label).dsFont(.footnote).foregroundColor(DS.Color.textSecondary)
            Spacer(minLength: DS.Spacing.sm)
            Text(verbatim: value).dsFont(.rowTitle).foregroundColor(DS.Color.textPrimary)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, DS.Spacing.sm)
        .accessibilityElement(children: .combine)
    }

    // MARK: «طلب استكمال البيانات» (R2)

    @ViewBuilder private var askHeader: some View {
        SignupBoxTitle(icon: "exclamationmark.circle.fill",
                       title: L10n.t(AdminJoinBoxRules.Ar.memberAskTitle, "Please complete your details"),
                       tint: DS.Color.warningFill)
        Text(L10n.t(AdminJoinBoxRules.Ar.memberAskBody, "The admins asked you to complete:")
             + " " + AdminJoinBoxRules.askedList(ask?.fields ?? [], relation: relation,
                                                 isSpouse: ask?.isSpouse == true))
            .dsFont(.footnote).foregroundColor(DS.Color.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        if let note = ask?.note, !note.isEmpty {
            Text(verbatim: note).dsFont(.footnote).foregroundColor(DS.Color.warning)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var askContent: some View {
        askHeader
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

    /// الإدارة طلبت تصحيح اسم الزوج/الزوجة: الحقل نفسه مميّزاً ← `submit_spouse_link` (يعدّل الطلب ويغلق طلب المعلومات)
    @ViewBuilder private var askSpouseContent: some View {
        askHeader
        spouseField.completionAskHighlight(true)
        if spouseSettled, let e = R.spouseNameError(spouseName, relation: relation) {
            fieldError(e, english: "Write the four-part name, without the family name.")
        }
        DSButton(L10n.t(T.send, "Send to the admins"), icon: "paperplane.fill", isLoading: busy) { sendSpouse() }
            .disabled(!R.canSendSpouse(spouseName) || busy)
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

    // MARK: أُرسل (اسم الوالدة)

    @ViewBuilder private var sentContent: some View {
        SignupBoxTitle(icon: "clock.fill", title: L10n.t(T.pendingTitle, "Your registration is under review"))
        Text(L10n.t(T.sentBody, "You'll be notified once approved; then you're added to the tree."))
            .dsFont(.footnote).foregroundColor(DS.Color.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        DSButton(L10n.t(T.goToApp, "Go to the app")) { onSent() }
    }

    private func fieldError(_ arabic: String, english: String) -> some View {
        Label {
            Text(L10n.t(arabic, english)).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.circle.fill").dsGlyph(DS.Glyph.sm)
        }
        .dsFont(.footnote).foregroundColor(DS.Color.error)
        .transition(.dsReveal(reduceMotion: reduceMotion))
    }

    // MARK: الإرسال

    private func send() {
        guard canSend, !busy else { return }
        busy = true
        errorText = nil
        Task {
            do {
                try await OutsideLineage.submit(motherName: motherName)
                DSMomentToast.show(L10n.t(T.sentMoment, "Request sent"), moment: .success, section: nil)
                withAnimation(reduceMotion ? DSMotion.fade : DSMotion.stepIn) { sent = true }
            } catch {
                errorText = OutsideLineage.message(error)
            }
            busy = false
        }
    }

    private func sendSpouse() {
        guard R.canSendSpouse(spouseName), !busy else { return }
        busy = true
        errorText = nil
        let typed = R.spouseNameToSend(spouseName)
        let rel = relation
        Task {
            do {
                try await SpouseLink.submit(name: typed)
                DSMomentToast.show(L10n.t(T.sentMoment, "Request sent"), moment: .success, section: nil)
                let pending = await SpouseLink.mine() ?? SpouseLink.Pending(relation: rel, typedName: typed)
                forward = true
                withAnimation(reduceMotion ? DSMotion.fade : DSMotion.stepIn) { spouseSent = pending }
            } catch {
                errorText = OutsideLineage.message(error)
            }
            busy = false
        }
    }

    /// «لا يوجد»: صلاحيات محدودة مباشرة — بلا طلب ولا رسالة عنها
    private func markLimited() {
        guard !busy, R.afterFamily(hasSpouse: false) == .limited else { return }
        busy = true
        errorText = nil
        Task {
            do {
                try await OutsideLineage.markOutsideMother()
                onLimited()
            } catch {
                errorText = OutsideLineage.message(error)
                familyPick = nil
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
