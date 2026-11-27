import SwiftUI
import Supabase

// MARK: - «بنت بنت العائلة» في شاشة الانتظار (طلب المالك ٢٠٢٦-١١-٢٧، الوحدة B1)
//
// المسجّلة التي لم تجد أباها في الشجرة (أنثى «قيد المراجعة» بلا أب ولا عقدة في شجرة النساء، والسيرفر يقرّر) ترى بطاقة
// «أمي من بنات العائلة» ← صفحة: تبحث عن أمّها (لا نتائج قبل الاسم الثلاثي — نفس قاعدة الخصوصية) ← أبوها: زوج أمّها
// المسجّل من خارج العائلة أو اسمه الكامل ← «إرسال للإدارة» ← `submit_daughter_daughter_lineage`.
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
        case "not_allowed": return L10n.t("هذا الخيار لمن تسجّلت ولم تجد أباها في الشجرة.", "This option is for those who couldn't find their father in the tree.")
        case "feature_off": return L10n.t("هذا الخيار مطفأ حالياً.", "This option is turned off.")
        case "already_pending": return L10n.t("طلبك عند الإدارة — انتظري ردّها.", "Your request is with the admins — please wait.")
        case "resubmit_limit": return L10n.t("وصلتِ حد المحاولات — تواصلي مع الإدارة.", "You've reached the limit — contact the admins.")
        case "bad_mother": return L10n.t("اختاري أمّك من بنات العائلة.", "Choose your mother from the family's daughters.")
        case "bad_father": return L10n.t("زوج أمّك تغيّر — ابحثي عنها من جديد.", "Your mother's husband changed — search again.")
        case "father_in_family":
            return L10n.t("زوج أمّك من العائلة، فأبوك في الشجرة — اضغطي «تعديل البيانات» واختاريه.",
                          "Your mother's husband is from the family, so your father is in the tree — tap «Edit Info» and pick him.")
        case "name_required": return L10n.t("اكتبي اسم أبيك الكامل.", "Type your father's full name.")
        case "name_too_long": return L10n.t("الاسم طويل.", "The name is too long.")
        default:
            return AuthViewModel.serverMessage(error, fallback: L10n.t("تعذّر الإرسال. حاولي مرة أخرى.", "Couldn't send. Try again."))
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
                DSNoteCard(L10n.t("اختيارك لأمّك وأبيك عند الإدارة — يصلك إشعار فور الموافقة.",
                                  "Your mother and father are with the admins — you'll be notified once approved."),
                           title: L10n.t("نسبك قيد المراجعة", "Your lineage is under review"),
                           icon: "checkmark.shield.fill", tint: DS.Color.info)
                    .padding(.horizontal, DS.Spacing.xl)
            case .offer, .rejected:
                Button { showPage = true } label: { offerContent }
                    .buttonStyle(DSPressStyle())
                    .padding(.horizontal, DS.Spacing.xl)
                    .accessibilityHint(L10n.t("يفتح اختيار الأم واسم الأب", "Opens choosing your mother and father"))
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
                Text(card == .rejected ? L10n.t("راجعي أمّك وأبيك", "Review your mother and father")
                                       : L10n.t("ما لقيتِ أباك؟", "Couldn't find your father?"))
                    .dsFont(.rowTitle).foregroundColor(DS.Color.textPrimary)
                Text(card == .rejected
                     ? (status?.rejectedReason.map { L10n.t("السبب: ", "Reason: ") + $0 }
                        ?? L10n.t("أرسليها من جديد للإدارة", "Send them to the admins again"))
                     : L10n.t("إذا أمك من بنات العائلة، اختاريها واكتبي اسم أبيك",
                              "If your mother is a daughter of the family, pick her and type your father's name"))
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
            DSSubPageHeader(title: L10n.t("أمي من بنات العائلة", "My mother is a family daughter"),
                            subtitle: L10n.t("أمك وأبوك", "Your mother and father"),
                            section: .tree, nav: .none)
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.md) {
                    if sent { sentContent } else { pickContent }
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
            DSNoteCard(rejectedReason.isEmpty ? L10n.t("راجعي اختيارك وأرسليه من جديد.", "Review your choice and send it again.")
                                              : L10n.t("السبب: ", "Reason: ") + rejectedReason,
                       title: L10n.t("لم تؤكّد الإدارة طلبك", "The admins didn't confirm your request"),
                       icon: "arrow.uturn.backward.circle.fill", tint: DS.Color.warning)
        }
        DSBoxSectionTitle(title: L10n.t("أمك", "Your mother"), icon: "person.fill", tint: DS.Color.female)
        if let m = mother {
            motherRow(m, selected: true) { mother = nil; useRegistered = true }
                .dsRowBox()
            fatherSection(m)
        } else {
            DSSearchField(text: $search, placeholder: L10n.t("اسم أمك واسم أبيها وجدها", "Your mother's, her father's and grandfather's names"))
            if !queryLongEnough {
                Text(L10n.t("اكتبي اسمها الثلاثي — لا تظهر الأسماء قبله", "Type her three-part name — no names show before that"))
                    .dsFont(.footnote).foregroundColor(DS.Color.textTertiary)
            } else if searching && results.isEmpty {
                DSPageLoader(L10n.t("جارٍ البحث", "Searching"), fillsSpace: false)
            } else if results.isEmpty {
                DSEmptyView(L10n.t("لم نجد الاسم", "No match"),
                            message: L10n.t("تأكدي من اسمها واسم أبيها وجدها، أو تواصلي مع الإدارة.",
                                            "Check her, her father's and grandfather's names, or contact the admins."),
                            style: .compact)
            } else {
                VStack(spacing: 0) {
                    ForEach(results) { d in
                        motherRow(d, selected: false) {
                            mother = d
                            useRegistered = true
                            search = ""
                        }
                        if d.id != results.last?.id { Divider() }
                    }
                }
                .dsCard(padding: DS.Spacing.sm)
            }
        }
    }

    @ViewBuilder private func fatherSection(_ m: DaughterSons.MotherCandidate) -> some View {
        DSBoxSectionTitle(title: L10n.t("أبوك", "Your father"), icon: "person.2.fill", tint: DS.Color.male)
        switch option {
        case .fatherInFamily(let name)?:
            DSNoteCard(L10n.t("زوج أمّك «\(name)» من العائلة، فأبوك في الشجرة. اضغطي «تعديل البيانات» واختاريه أباً.",
                              "Your mother's husband «\(name)» is from the family, so your father is in the tree. Tap «Edit Info» and pick him."),
                       icon: "info.circle.fill", tint: DS.Color.info)
        case .registered(_, let name)?:
            VStack(spacing: 0) {
                choiceRow(title: name, subtitle: L10n.t("زوج \(m.firstName) المسجّل", "\(m.firstName)'s recorded husband"),
                          selected: useRegistered) { useRegistered = true }
                Divider()
                choiceRow(title: L10n.t("أبوي غيره", "My father is someone else"),
                          subtitle: L10n.t("اكتبي اسمه الكامل", "Type his full name"),
                          selected: !useRegistered) { useRegistered = false }
            }
            .dsCard(padding: DS.Spacing.sm)
            if !useRegistered {
                fatherFields
                if let other = DaughterDaughterRules.conflictName(option: option, useRegistered: false, typedName: fatherFull) {
                    DSNoteCard(L10n.t("الاسم يختلف عن زوج أمك المسجّل «\(other)» — الإدارة تراجعه معك.",
                                      "This differs from your mother's recorded husband «\(other)» — the admins will check it with you."),
                               icon: "exclamationmark.triangle.fill", tint: DS.Color.warning)
                }
            }
        default:
            fatherFields
        }
        if !isFatherInFamily {
            DSNoteCard(L10n.t("يُرسل للإدارة للتأكيد، ثم يُفعَّل حسابك وتظهرين في شجرة النساء تحت \(shortName(m.fullName)).",
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
            DSComposerField(icon: "person.fill", label: L10n.t("اسم أبيك الكامل", "Your father's full name"),
                            placeholder: L10n.t("اكتبي الاسم الثلاثي", "Type the three-part name"),
                            text: $fatherFull, limit: 120, required: true)
            if !fatherFull.trimmingCharacters(in: .whitespaces).isEmpty
                && DaughterDaughterRules.wordCount(fatherFull) < minWords {
                Text(L10n.t("اكتبي \(minWords) أسماء على الأقل", "Type at least \(minWords) names"))
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
            Text(L10n.t("وصل طلبك للإدارة", "Your request reached the admins"))
                .dsFont(.title).foregroundColor(DS.Color.textPrimary)
            Text(L10n.t("يصلك إشعار فور الموافقة، ويُفعَّل حسابك.",
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
                DSButton(L10n.t("إرسال للإدارة", "Send to the admins"), icon: "paperplane.fill",
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
                    Text(MotherPickRules.disambiguationLine(fatherName: m.fatherName, husbandName: m.husbandName,
                                                            isMarried: m.husbandId != nil))
                        .dsFont(.caption).foregroundColor(DS.Color.textTertiary)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
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
                sent = true
            } catch {
                errorText = DaughterDaughters.message(error)
            }
            busy = false
        }
    }

    private func shortName(_ name: String) -> String { MotherPickRules.shortName(name) }
}
