import SwiftUI
import Supabase

// MARK: - «بنت بنت العائلة» في شاشة الانتظار (طلب المالك ٢٠٢٦-١١-٢٧، الوحدة B1)
//
// المسجّلة بالطريقة السابقة التي لم تجد والدها في الشجرة (أنثى «قيد المراجعة» بلا أب ولا عقدة في شجرة النساء، والسيرفر
// يقرّر) ترى بطاقة «هل الوالدة من بنات العائلة؟» ← صفحة: الوالدة (لا نتائج قبل الاسم الثلاثي) ← الوالد: زوج الوالدة
// المسجّل من خارج العائلة أو اسمه الكامل ← «إرسال الطلب إلى الإدارة» ← `submit_daughter_daughter_lineage`.
// المسار الجديد من التسجيل نفسه («من خارج العائلة»، R1 — SignupOriginViews.swift)؛ البطاقة احتياط لمن سجّل قبله.
// النصوص رسمية: «الوالد» و«الوالدة» فقط.
// الموافقة في «الوارد» (`AdminLineageRequestCard`) تفعّل حسابها وتضعها تحت أمّها وأبيها في شجرة النساء.
// قبل ترحيل `20261127150000_daughter_daughters` الدالة غائبة ← لا بطاقة (التطبيق كما كان).

enum DaughterDaughters {
    nonisolated struct Status: Decodable, Sendable, Equatable {
        let eligible: Bool
        let pending: Bool
        let wasRejected: Bool
        let rejectedReason: String?
        enum CodingKeys: String, CodingKey {
            case eligible, pending
            case wasRejected = "was_rejected"
            case rejectedReason = "rejected_reason"
        }
    }

    /// nil = الدالة غائبة (قبل الترحيل) أو تعذّر — لا بطاقة
    @MainActor static func fetchStatus() async -> Status? {
        do {
            return try await SupabaseConfig.client.rpc("my_daughter_lineage_status").execute().value
        } catch {
            if !ErrorHelper.isCancellation(error) {
                Log.warning("[DaughterDaughters] my_daughter_lineage_status: \(error.localizedDescription)")
            }
            return nil
        }
    }

    /// بنات العائلة — السيرفر يفرض الحد الأدنى من الأسماء و١٠ نتائج
    @MainActor static func searchMothers(_ query: String) async -> [DaughterSons.MotherCandidate] {
        guard NameSearch.words(query).count >= DaughterSons.motherMinParts else { return [] }
        do {
            return try await SupabaseConfig.client
                .rpc("search_daughters_for_lineage", params: ["p_query": query]).execute().value
        } catch {
            if !ErrorHelper.isCancellation(error) {
                Log.warning("[DaughterDaughters] search_daughters_for_lineage: \(error.localizedDescription)")
            }
            return []
        }
    }

    static func submit(motherId: UUID, fatherId: UUID?, fatherFullName: String, deceased: Bool) async throws {
        let line = fatherFullName.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let params: [String: AnyEncodable] = [
            "p_mother_id": AnyEncodable(motherId.uuidString),
            "p_father_id": AnyEncodable(fatherId?.uuidString),
            "p_father_full_name": AnyEncodable(fatherId == nil ? line : nil),
            "p_father_deceased": AnyEncodable(fatherId == nil && deceased)
        ]
        _ = try await SupabaseConfig.client.rpc("submit_daughter_daughter_lineage", params: params).execute()
    }

    /// رسائل الدالة بالـ hint — بصيغة المؤنّث
    static func message(_ error: Error) -> String {
        switch (error as? PostgrestError)?.hint ?? "" {
        case "not_allowed": return L10n.t("هذا الخيار لمن سجّل والوالدة من بنات العائلة والوالد من خارجها.", "This option is for those whose mother is a family daughter and father is from outside the family.")
        case "feature_off": return L10n.t("هذا الخيار غير متاح حالياً.", "This option is turned off.")
        case "already_pending": return L10n.t("الطلب لدى الإدارة، ويُرجى انتظار الرد.", "Your request is with the admins — please wait.")
        case "resubmit_limit": return L10n.t("تم بلوغ الحد الأقصى للمحاولات، ويُرجى التواصل مع الإدارة.", "You've reached the limit — contact the admins.")
        case "bad_mother": return L10n.t("يُرجى اختيار الوالدة من بنات العائلة.", "Choose your mother from the family's daughters.")
        case "bad_father": return L10n.t("تغيّر زوج الوالدة المسجّل، ويُرجى البحث عنها من جديد.", "Your mother's husband changed — search again.")
        case "father_in_family":
            return L10n.t("زوج الوالدة من أبناء العائلة، لذا يُرجى التسجيل «من العائلة» واختيار الوالد من الشجرة.",
                          "Your mother's husband is from the family — register «From the family» and pick your father from the tree.")
        case "name_required": return L10n.t("يُرجى كتابة اسم الوالد كاملاً.", "Type your father's full name.")
        case "name_too_long": return L10n.t("الاسم طويل.", "The name is too long.")
        default:
            return AuthViewModel.serverMessage(error, fallback: L10n.t("تعذّر الإرسال. يُرجى المحاولة مرة أخرى.", "Couldn't send. Try again."))
        }
    }
}

/// بطاقة شاشة الانتظار: «أمي من بنات العائلة» / «طلبك عند الإدارة» / «راجعي بياناتك»
struct DaughterLineageCard: View {
    @State private var status: DaughterDaughters.Status?
    @State private var showPage = false

    private var card: DaughterDaughterRules.WaitingCard {
        guard let status else { return .hidden }
        return DaughterDaughterRules.waitingCard(eligible: status.eligible, pending: status.pending,
                                                 wasRejected: status.wasRejected)
    }

    var body: some View {
        Group {
            switch card {
            case .hidden:
                EmptyView()
            case .pending:
                DSNoteCard(L10n.t(SignupOriginRules.Ar.cardPendingBody,
                                  "Your mother and father were sent to the admins — you'll be notified once approved."),
                           title: L10n.t(SignupOriginRules.Ar.cardPendingTitle, "Your lineage is under review"),
                           icon: "checkmark.shield.fill", tint: DS.Color.info)
                    .padding(.horizontal, DS.Spacing.xl)
                    // تصعد البطاقة مرة حين تصل حالتها — مثل أقسام مربّع التسجيل؛ «تقليل الحركة»: تلاشٍ
                    .dsEntrance(delay: DSMotion.sectionsAfterHeader, y: DSMotion.rise, scale: DSMotion.riseScale)
            case .offer, .rejected:
                Button { showPage = true } label: { offerContent }
                    .buttonStyle(DSPressStyle())
                    .padding(.horizontal, DS.Spacing.xl)
                    .dsEntrance(delay: DSMotion.sectionsAfterHeader, y: DSMotion.rise, scale: DSMotion.riseScale)
                    .accessibilityHint(L10n.t("يفتح اختيار الوالدة واسم الوالد", "Opens choosing your mother and father"))
            }
        }
        .task { status = await DaughterDaughters.fetchStatus() }
        .fullScreenCover(isPresented: $showPage) {
            DaughterLineagePage(rejectedReason: card == .rejected ? (status?.rejectedReason ?? "") : nil) {
                showPage = false
                Task { status = await DaughterDaughters.fetchStatus() }
            }
        }
    }

    private var offerContent: some View {
        HStack(spacing: DS.Spacing.sm) {
            DSFieldIcon(name: "heart.fill", tint: DS.Color.female)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(card == .rejected ? L10n.t(SignupOriginRules.Ar.cardRejected, "Review your mother and father")
                                       : L10n.t(SignupOriginRules.Ar.cardOffer, "Is your mother a daughter of the family?"))
                    .dsFont(.rowTitle).foregroundColor(DS.Color.textPrimary)
                Text(card == .rejected
                     ? (status?.rejectedReason.map { L10n.t("السبب: ", "Reason: ") + $0 }
                        ?? L10n.t(SignupOriginRules.Ar.cardRejectedBody, "Send them to the admins again"))
                     : L10n.t(SignupOriginRules.Ar.cardOfferBody,
                              "Pick your mother from the family's daughters and type your father's name"))
                    .dsFont(.caption).foregroundColor(DS.Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                .dsGlyph(DS.Glyph.md).foregroundColor(DS.Color.textTertiary)
                .accessibilityHidden(true)
        }
        .frame(minHeight: DS.Icon.tapTarget)
        .padding(DS.Spacing.md)
        .dsCard(padding: nil)
        .contentShape(Rectangle())
    }
}

/// «أمي من بنات العائلة»: الأم ثم الأب ثم الإرسال — صفحة واحدة
struct DaughterLineagePage: View {
    /// nil = أول مرة · نص (قد يكون فارغاً) = رُفض طلبها السابق
    let rejectedReason: String?
    let onClose: () -> Void

    @State private var search = ""
    @State private var results: [DaughterSons.MotherCandidate] = []
    @State private var searching = false
    @State private var mother: DaughterSons.MotherCandidate?
    @State private var useRegistered = true
    @State private var fatherFull = ""
    @State private var deceased = false
    @State private var busy = false
    @State private var sent = false
    @State private var errorText: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var option: DaughterDaughterRules.FatherOption? {
        mother.map { DaughterDaughterRules.fatherOption(husbandId: $0.husbandId, husbandName: $0.husbandName,
                                                        husbandInFamily: $0.husbandInFamily) }
    }
    private var minWords: Int { DaughterSons.fatherMinWords }
    private var canSend: Bool {
        DaughterDaughterRules.canSend(motherChosen: mother != nil, option: option, useRegistered: useRegistered,
                                      typedName: fatherFull, minWords: minWords)
    }
    private var queryLongEnough: Bool { NameSearch.words(search).count >= DaughterSons.motherMinParts }

    var body: some View {
        VStack(spacing: 0) {
            DSSubPageHeader(title: L10n.t("الوالدة والوالد", "Mother and father"),
                            subtitle: L10n.t("الوالدة من بنات العائلة", "Your mother is a family daughter"),
                            section: .tree, nav: .none)
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.md) {
                    // الاختيار ← «وصل طلبك» في الصفحة نفسها: انزلاق قصير للأمام مثل مربّعات التسجيل
                    ZStack(alignment: .top) {
                        if sent {
                            sentContent.transition(stepTransition)
                        } else {
                            VStack(alignment: .leading, spacing: DS.Spacing.md) { pickContent }
                                .transition(stepTransition)
                        }
                    }
                    if let errorText {
                        DSNoteCard(errorText, icon: "exclamationmark.triangle.fill", tint: DS.Color.error)
                    }
                }
                .padding(DS.Spacing.lg)
            }
            footer
        }
        .background(DS.Color.background.ignoresSafeArea())
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .task(id: search) { await runSearch() }
    }

    // MARK: الأم ثم الأب

    @ViewBuilder private var pickContent: some View {
        if let rejectedReason {
            DSNoteCard(rejectedReason.isEmpty ? L10n.t("يُرجى مراجعة الاختيار وإرساله من جديد.", "Review your choice and send it again.")
                                              : L10n.t("السبب: ", "Reason: ") + rejectedReason,
                       title: L10n.t("لم تعتمد الإدارة الطلب", "The admins didn't confirm your request"),
                       icon: "arrow.uturn.backward.circle.fill", tint: DS.Color.warning)
        }
        DSBoxSectionTitle(title: L10n.t("الوالدة", "Your mother"), icon: "person.fill", tint: DS.Color.female)
        if let m = mother {
            motherRow(m, selected: true) { withAnimation(revealAnimation) { mother = nil; useRegistered = true } }
                .dsRowBox()
            // اختيار الوالدة يكشف قسم الوالد في المكان نفسه
            VStack(alignment: .leading, spacing: DS.Spacing.md) { fatherSection(m) }
                .transition(.dsReveal(reduceMotion: reduceMotion))
        } else {
            DSSearchField(text: $search, placeholder: L10n.t(SignupOriginRules.Ar.motherPlaceholder, "Your mother's, her father's and grandfather's names"))
            if !queryLongEnough {
                Text(L10n.t(SignupOriginRules.Ar.motherHint, "Type her three-part name — no names show before that"))
                    .dsFont(.footnote).foregroundColor(DS.Color.textTertiary)
            } else if searching && results.isEmpty {
                DSPageLoader(L10n.t("جارٍ البحث", "Searching"), fillsSpace: false)
            } else if results.isEmpty {
                DSEmptyView(L10n.t("لم نجد الاسم", "No match"),
                            message: L10n.t(SignupOriginRules.Ar.motherNotFound,
                                            "Check her, her father's and grandfather's names, or contact the admins."),
                            style: .compact)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { i, d in
                        // النتائج تصعد تباعاً مرة — «تقليل الحركة»: تلاشٍ
                        VStack(spacing: 0) {
                            motherRow(d, selected: false) {
                                withAnimation(revealAnimation) {
                                    mother = d
                                    useRegistered = true
                                }
                                search = ""
                            }
                            if d.id != results.last?.id { Divider() }
                        }
                        .dsStaggerIn(i)
                    }
                }
                .dsCard(padding: DS.Spacing.sm)
            }
        }
    }

    @ViewBuilder private func fatherSection(_ m: DaughterSons.MotherCandidate) -> some View {
        DSBoxSectionTitle(title: L10n.t("الوالد", "Your father"), icon: "person.2.fill", tint: DS.Color.male)
        switch option {
        case .fatherInFamily(let name)?:
            DSNoteCard(L10n.t("زوج الوالدة «\(name)» من أبناء العائلة، لذا يُرجى الضغط على «تعديل الطلب» واختيار «من العائلة».",
                              "Your mother's husband «\(name)» is from the family. Tap «Edit Request» and choose «From the family»."),
                       icon: "info.circle.fill", tint: DS.Color.info)
        case .registered(_, let name)?:
            VStack(spacing: 0) {
                choiceRow(title: name, subtitle: L10n.t("زوج الوالدة المسجّل", "\(m.firstName)'s recorded husband"),
                          selected: useRegistered) { withAnimation(revealAnimation) { useRegistered = true } }
                Divider()
                choiceRow(title: L10n.t("الوالد شخص آخر", "My father is someone else"),
                          subtitle: L10n.t("يُرجى كتابة اسمه كاملاً", "Type his full name"),
                          selected: !useRegistered) { withAnimation(revealAnimation) { useRegistered = false } }
            }
            .dsCard(padding: DS.Spacing.sm)
            if !useRegistered {
                fatherFields
                    .transition(.dsReveal(reduceMotion: reduceMotion))
                if let other = DaughterDaughterRules.conflictName(option: option, useRegistered: false, typedName: fatherFull) {
                    DSNoteCard(L10n.t("الاسم يختلف عن زوج الوالدة المسجّل «\(other)»، وستراجعه الإدارة.",
                                      "This differs from your mother's recorded husband «\(other)» — the admins will check it with you."),
                               icon: "exclamationmark.triangle.fill", tint: DS.Color.warning)
                }
            }
        default:
            fatherFields
        }
        if !isFatherInFamily {
            DSNoteCard(L10n.t("يُرسل الطلب إلى الإدارة للتأكيد، ثم يُفعَّل الحساب ويظهر الاسم في شجرة النساء تحت \(shortName(m.fullName)).",
                              "It goes to the admins to confirm; then your account is activated and you appear in the women's tree under \(shortName(m.fullName))."),
                       icon: "checkmark.shield.fill", tint: DS.Color.info)
        }
    }

    private var isFatherInFamily: Bool {
        if case .fatherInFamily? = option { return true }
        return false
    }

    private var fatherFields: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            DSComposerField(icon: "person.fill", label: L10n.t("اسم الوالد كاملاً", "Your father's full name"),
                            placeholder: L10n.t(SignupOriginRules.Ar.fatherPlaceholder, "Type the three-part name"),
                            text: $fatherFull, limit: 120, required: true)
            if !fatherFull.trimmingCharacters(in: .whitespaces).isEmpty
                && DaughterDaughterRules.wordCount(fatherFull) < minWords {
                Text(L10n.t("يُرجى كتابة \(minWords) أسماء على الأقل", "Type at least \(minWords) names"))
                    .dsFont(.footnote).foregroundColor(DS.Color.textTertiary)
            }
            DSMenuTile(icon: "leaf.fill", label: L10n.t("الحالة", "Status"), options: [
                DSChoiceOption(id: false, title: L10n.t("على قيد الحياة", "Alive"), icon: "heart.fill"),
                DSChoiceOption(id: true, title: L10n.t("متوفى", "Deceased"), icon: "leaf.fill")
            ], selection: $deceased)
        }
    }

    private var sentContent: some View {
        VStack(spacing: DS.Spacing.sm) {
            DSStateIcon("paperplane.fill", tint: DS.Color.success, size: DS.Icon.state)
            Text(L10n.t(SignupOriginRules.Ar.waitingTitle, "Your request reached the admins"))
                .dsFont(.title).foregroundColor(DS.Color.textPrimary)
            Text(L10n.t("سيصلك إشعار عند اعتماد الطلب، ويُفعَّل الحساب.",
                        "You'll be notified once approved, and your account will be activated."))
                .dsFont(.footnote).foregroundColor(DS.Color.textSecondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .dsCard(padding: DS.Spacing.lg)
    }

    private var footer: some View {
        VStack(spacing: DS.Spacing.sm) {
            if sent {
                DSButton(L10n.t("تم", "Done"), icon: "checkmark", size: .large) { onClose() }
            } else {
                DSButton(L10n.t(SignupOriginRules.Ar.submit, "Send to the admins"), icon: "paperplane.fill",
                         size: .large, isLoading: busy) { send() }
                    .disabled(!canSend || busy)
                DSButton(L10n.t("إلغاء", "Cancel"), role: .cancel, size: .regular) { onClose() }
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.md)
        .background(DS.Color.background)
    }

    // MARK: الصفوف

    private func motherRow(_ m: DaughterSons.MotherCandidate, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.sm) {
                DSMemberAvatar(name: m.firstName, avatarUrl: nil, size: DS.Icon.row, roleColor: DS.Color.female)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(verbatim: m.fullName).dsFont(.rowTitle).foregroundColor(DS.Color.textPrimary)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    NamePartChips(parts: MotherPickRules.disambiguationParts(fatherName: m.fatherName,
                                                                             husbandName: m.husbandName))
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "xmark.circle.fill" : (L10n.isArabic ? "chevron.left" : "chevron.right"))
                    .dsGlyph(DS.Glyph.md).foregroundColor(DS.Color.textTertiary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: DS.Icon.tapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(selected ? L10n.t("إلغاء الاختيار", "Clear selection") : L10n.t("اختيار", "Choose"))
    }

    private func choiceRow(title: String, subtitle: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.sm) {
                DSFieldIcon(name: "person.2.fill", tint: DS.Color.male)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(title).dsFont(.rowTitle).foregroundColor(DS.Color.textPrimary).lineLimit(2)
                    Text(subtitle).dsFont(.caption).foregroundColor(DS.Color.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .dsGlyph(DS.Glyph.lg)
                    .foregroundColor(selected ? DS.Color.primary : DS.Color.textTertiary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: DS.Icon.tapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: البيانات

    private func runSearch() async {
        guard queryLongEnough, mother == nil else { results = []; searching = false; return }
        try? await Task.sleep(nanoseconds: 300_000_000)
        if Task.isCancelled { return }
        searching = true
        let found = await DaughterDaughters.searchMothers(search)
        if Task.isCancelled { return }
        results = found
        searching = false
    }

    private func send() {
        guard canSend, !busy, let m = mother else { return }
        busy = true
        errorText = nil
        let fid: UUID? = { if useRegistered, case .registered(let id, _)? = option { return id } else { return nil } }()
        Task {
            do {
                try await DaughterDaughters.submit(motherId: m.id, fatherId: fid, fatherFullName: fatherFull, deceased: deceased)
                // لحظة النجاح ثم «وصل طلبك» — نفس مربّعات التسجيل
                DSMomentToast.show(L10n.t(SignupOriginRules.Ar.sentMoment, "Request sent"), moment: .success, section: nil)
                withAnimation(reduceMotion ? DSMotion.fade : DSMotion.stepIn) { sent = true }
            } catch {
                errorText = DaughterDaughters.message(error)
            }
            busy = false
        }
    }

    private func shortName(_ name: String) -> String { MotherPickRules.shortName(name) }

    private var revealAnimation: Animation { reduceMotion ? DSMotion.fade : DSMotion.reveal }

    private var stepTransition: AnyTransition {
        .dsStep(forward: true, rtl: LanguageManager.shared.layoutDirection == .rightToLeft, reduceMotion: reduceMotion)
    }
}
