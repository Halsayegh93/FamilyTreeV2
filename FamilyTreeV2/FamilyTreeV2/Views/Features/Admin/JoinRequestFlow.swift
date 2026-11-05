import SwiftUI

// MARK: - طلب الانضمام: سؤال واحد — هل هذا الشخص موجود في الشجرة؟ (طلب المالك ٢٠٢٦-١١-٠٥: «الشجرة أولاً» + «المقارنة»)
//
// موجود: اختيار السجل (الأقرب أولاً، الباقي تحت «عرض المزيد»، وبحث) ← مقارنة الطلب بالسجل ← «ربط بهذا» (`merge_member_into_tree`).
// غير موجود: اختيار الأب من شجرة صغيرة ← «ما فيه تكرار» ← «إضافة وربط» = نفس المسار اليدوي: إضافة ابن تحت الأب (`addChild`) ثم الربط به.
// غير واضح: الطلب يبقى معلّقاً، والتواصل بواتساب أو اتصال.
// حارس المكدس: كل لوحة نوع مستقل خلف `AnyView` (جسم `AdminAllRequestsView` فاض سابقاً).
// الأسماء من `displayFullName`/`nameUnits` دائماً، لا `firstName` (عند طالب الانضمام فيه كل ما كتبه)، وحتى ٣ أسطر.

/// مرشّح من مطابقات الشجرة (`AdminAllRequestsView.orderedMatchList`)
struct JoinSuggestion: Identifiable {
    let member: FamilyMember
    let depth: Int
    var id: UUID { member.id }
}

/// الإجراء الرئيسي للوحة الظاهرة: زرّ شريط المربّع (`JoinRequestComposer`)، أو داخل المحتوى في مربّع مسار الموافقات
/// (شريطه له). يُقارن بلا الإغلاق؛ الإغلاق يضبط `@State` فلا يتقادم
struct JoinPrimaryAction: Equatable {
    let id: String
    let title: String
    let icon: String
    let isEnabled: Bool
    let action: () -> Void

    static func == (a: JoinPrimaryAction, b: JoinPrimaryAction) -> Bool {
        a.id == b.id && a.title == b.title && a.icon == b.icon && a.isEnabled == b.isEnabled
    }
}

private struct JoinPrimaryKey: PreferenceKey {
    static let defaultValue: JoinPrimaryAction? = nil
    static func reduce(value: inout JoinPrimaryAction?, nextValue: () -> JoinPrimaryAction?) {
        value = value ?? nextValue()
    }
}

/// مربّع طلب الرجل: شريطه «رقم · رفض · حذف» كما كان، و«ربط بهذا»/«إضافة وربط» بجانب «إغلاق» حسب الجواب
struct JoinRequestComposer<Content: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    let isBusy: Bool
    let extraActions: [DSComposerAction]
    let onClose: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var primary: JoinPrimaryAction?

    var body: some View {
        DSComposer(
            title: title,
            subtitle: subtitle,
            icon: icon,
            tint: DS.Color.actionNavy,
            actionTitle: primary?.title ?? "",
            actionIcon: primary?.icon ?? "link",
            showsAction: primary != nil,
            cancelTitle: L10n.t("إغلاق", "Close"),
            canSubmit: primary?.isEnabled == true,
            isBusy: isBusy,
            extraActions: extraActions,
            onSubmit: { primary?.action() },
            onCancel: onClose
        ) {
            Group { content() }
                .onPreferenceChange(JoinPrimaryKey.self) { primary = $0 }
        }
    }
}

/// أسماء الأعضاء وأقاربهم من قائمة الشجرة
@MainActor
private enum JoinTree {
    /// أول وحدة من اسم عضو في الشجرة (الاسم المركّب وحدة واحدة)
    static func shortName(_ member: FamilyMember) -> String {
        member.nameUnits.first ?? member.displayFullName
    }

    static func children(of id: UUID, in memberVM: MemberViewModel) -> [FamilyMember] {
        memberVM.allMembers
            // المخفي من الشجرة يبقى هنا: فحص التكرار يراه، ولا يُضاف له شبيه
            .filter { $0.fatherId == id && $0.role != .pending && !$0.isFemale && $0.hasName }
            .sorted { $0.sortOrder < $1.sortOrder }
    }
}

/// مقارنة طلب بسجلّ، وكل ما يلزم قبل الربط
@MainActor
struct JoinLinkPlan {
    let nameLines: [JoinCompare.Line]
    let birth: JoinCompare.Birth
    let login: JoinCompare.Line
    let warnings: [String]
    /// سبب منع الربط (السيرفر يرفضه) — nil = مسموح
    let blocker: String?
    let sentence: String

    var lines: [JoinCompare.Line] { nameLines + [birth.line, login] }
    /// كم جزءاً من الأول والأب والجد تطابق
    var matchedNames: Int { nameLines.filter { $0.verdict == .match }.count }

    var strength: (title: String, tint: Color) {
        switch matchedNames {
        case 3: return (L10n.t("تطابق قوي", "Strong match"), DS.Color.success)
        case 2: return (L10n.t("تطابق متوسط", "Fair match"), DS.Color.warning)
        default: return (L10n.t("تطابق ضعيف", "Weak match"), DS.Color.error)
        }
    }

    init(applicant: FamilyMember, record: FamilyMember, memberVM: MemberViewModel, accounts: AdminAccountsStore) {
        let noise = NameMatcher.linkNoise(applicant.familyName).union(
            record.familyName.map { [NameMatcher.linkKey($0)] } ?? [])
        nameLines = JoinCompare.nameLines(requestUnits: applicant.nameUnits, treeUnits: record.nameUnits, noise: noise)
        birth = JoinCompare.birth(request: applicant.birthDate, tree: record.birthDate)

        let hasLogin: Bool? = accounts.info(record.id) != nil ? true : (accounts.loaded ? false : nil)
        let hasPhone = !JoinCompare.clean(record.phoneNumber).isEmpty
        login = JoinCompare.loginLine(hasLogin: hasLogin, hasPhone: hasPhone)

        // نفس حراس `merge_member_into_tree` — يظهر السبب قبل الضغط لا بعده
        let requestBirth = JoinCompare.clean(applicant.birthDate)
        let effectiveBirth = requestBirth.isEmpty ? JoinCompare.clean(record.birthDate) : requestBirth
        let age = JoinCompare.ageYears(effectiveBirth)
        if hasLogin == true {
            blocker = L10n.t("هذا السجل مربوط بحساب دخول — لا يُربط به حساب ثانٍ.",
                             "This record already has a login — it can't take another account.")
        } else if [.owner, .admin, .monitor, .supervisor].contains(record.role) {
            blocker = L10n.t("هذا سجل أحد أعضاء الإدارة — لا يُربط به.",
                             "This record belongs to a team member — it can't be linked.")
        } else if let age, age < JoinCompare.minimumAccountAge {
            blocker = birth.treeIsPlaceholder && requestBirth.isEmpty
                ? L10n.t("لا يوجد تاريخ في الطلب وتاريخ الشجرة غير مؤكد، فيُعدّ دون الثالثة عشرة ويرفض السيرفر الربط.",
                         "No date in the request and the tree date is unconfirmed, so the server treats him as under 13 and refuses.")
                : L10n.t("دون الثالثة عشرة: لا يُنشأ له حساب، ويُدرَج في الشجرة من خلال ولي أمره.",
                         "Under 13: no account is created; a guardian adds him to the tree.")
        } else {
            blocker = nil
        }

        var notes = JoinCompare.warnings(nameLines: nameLines, birth: birth)
        if hasPhone && hasLogin == false {
            notes.append(L10n.t("لهذا السجل رقم مسجّل، ولم يدخل صاحبه التطبيق بعد.",
                                "This record has a number on file, but its owner never signed in."))
        }
        if let age, age >= JoinCompare.minimumAccountAge, age < JoinCompare.adultAge {
            notes.append(L10n.t("قاصر: يلزم موافقة ولي أمره قبل تفعيل حسابه.",
                                "A minor: his guardian must consent before the account is activated."))
        }
        warnings = notes

        let father = record.fatherId.flatMap { memberVM.member(byId: $0) }
        let brothers = record.fatherId.map { fid in
            JoinTree.children(of: fid, in: memberVM).filter { $0.id != record.id }.map(JoinTree.shortName)
        } ?? []
        sentence = JoinCompare.linkSentence(applicant: applicant.displayFullName, record: record.displayFullName,
                                            father: father?.displayFullName, brothers: brothers)
    }

    var confirmText: String { JoinCompare.confirmText(sentence: sentence, warnings: warnings) }
}

// MARK: - الجواب على السؤال

struct JoinRequestFlowView: View {
    @ObservedObject var memberVM: MemberViewModel
    @ObservedObject var adminRequestVM: AdminRequestViewModel
    @ObservedObject private var accounts = AdminAccountsStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let member: FamilyMember
    let suggestions: [JoinSuggestion]
    /// nil = الربط مسموح؛ وإلا سبب المنع (للاطلاع فقط، مرحلة في مسار الموافقات)
    let lockedNote: String?
    /// الإجراء الرئيسي داخل المحتوى (مربّع مسار الموافقات) بدل شريط `JoinRequestComposer`
    let inlinePrimary: Bool
    /// انتهى الربط — `addedRecord`: أُضيف سجل جديد قبل محاولة الربط
    let onFinished: (_ addedRecord: Bool) -> Void

    private enum Answer: Hashable { case exists, newPerson, unclear }

    @State private var answer: Answer
    @State private var selectedRecordId: UUID?

    init(memberVM: MemberViewModel, adminRequestVM: AdminRequestViewModel, member: FamilyMember,
         suggestions: [JoinSuggestion], preselectedRecord: UUID?, lockedNote: String?, inlinePrimary: Bool,
         onFinished: @escaping (_ addedRecord: Bool) -> Void) {
        self.memberVM = memberVM
        self.adminRequestVM = adminRequestVM
        self.member = member
        self.suggestions = suggestions
        self.lockedNote = lockedNote
        self.inlinePrimary = inlinePrimary
        self.onFinished = onFinished
        _answer = State(initialValue: suggestions.isEmpty && preselectedRecord == nil ? .newPerson : .exists)
        _selectedRecordId = State(initialValue: preselectedRecord ?? suggestions.first?.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSBox.sectionSpacing) {
            AnyView(JoinPersonHeader(member: member))
            AnyView(questionSection)
            AnyView(answerPanel)
        }
        .animation(reduceMotion ? nil : DS.Anim.snappy, value: answer)
        .task { await accounts.refresh() }
    }

    private var questionSection: some View {
        DSComposerSection(title: L10n.t("هل هذا الشخص موجود في الشجرة؟", "Is this person already in the tree?"),
                          icon: "questionmark.circle.fill",
                          tint: AppSection.admin.ink,
                          index: 2) {
            DSSegmentedSwitch(options: [
                DSSegmentOption(id: Answer.exists, title: L10n.t("موجود", "In the tree"), icon: "checkmark.circle"),
                DSSegmentOption(id: Answer.newPerson, title: L10n.t("غير موجود", "Not in it"), icon: "person.badge.plus"),
                DSSegmentOption(id: Answer.unclear, title: L10n.t("غير واضح", "Unclear"), icon: "questionmark")
            ], selection: $answer, size: .regular)
        }
    }

    @ViewBuilder
    private var answerPanel: some View {
        switch answer {
        case .exists:
            JoinExistsPanel(memberVM: memberVM, adminRequestVM: adminRequestVM, accounts: accounts,
                            member: member, suggestions: suggestions, selectedRecordId: $selectedRecordId,
                            lockedNote: lockedNote, inlinePrimary: inlinePrimary, onFinished: onFinished)
        case .newPerson:
            JoinNewPersonPanel(memberVM: memberVM, adminRequestVM: adminRequestVM, member: member, lockedNote: lockedNote,
                               inlinePrimary: inlinePrimary,
                               onSameAsRecord: { id in
                                   selectedRecordId = id
                                   answer = .exists
                               },
                               onFinished: onFinished)
        case .unclear:
            JoinUnclearPanel(member: member)
        }
    }
}

// MARK: - صاحب الطلب: سطر مضغوط حتى يبقى السؤال قريباً من الأعلى

private struct JoinPersonHeader: View {
    let member: FamilyMember

    private var phone: String { JoinCompare.clean(member.phoneNumber) }

    private var factsLine: String {
        let birth = JoinCompare.clean(member.birthDate)
        let birthText = birth.isEmpty
            ? L10n.t("بلا تاريخ ميلاد", "No birth date")
            : L10n.t("مواليد \(JoinCompare.isolated(String(birth.prefix(10))))", "Born \(birth.prefix(10))")
        let source: String
        if member.registrationPlatform == "web" {
            let username = JoinCompare.clean(member.username)
            source = username.isEmpty ? L10n.t("من الموقع", "Website")
                : L10n.t("من الموقع · \(JoinCompare.isolated("@" + username))", "Website · @\(username)")
        } else {
            source = L10n.t("من التطبيق", "From the app")
        }
        return birthText + " · " + source
    }

    var body: some View {
        HStack(alignment: .top, spacing: DS.Spacing.sm) {
            DSMemberAvatar(name: member.fullName, avatarUrl: member.avatarUrl, size: DS.Icon.avatar, roleColor: AppSection.admin.ink)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(member.displayFullName)
                    .dsFieldFont(.headlineCompact)
                    .foregroundColor(DS.Color.fieldLabel)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                Text(factsLine)
                    .dsFont(.footnote)
                    .foregroundColor(DS.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !phone.isEmpty {
                    Text(JoinCompare.isolated(KuwaitPhone.display(phone)))
                        .dsFont(.footnote)
                        .foregroundColor(DS.Color.textSecondary)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - موجود: اختيار السجل والمقارنة

private struct JoinExistsPanel: View {
    @ObservedObject var memberVM: MemberViewModel
    @ObservedObject var adminRequestVM: AdminRequestViewModel
    @ObservedObject var accounts: AdminAccountsStore
    let member: FamilyMember
    let suggestions: [JoinSuggestion]
    @Binding var selectedRecordId: UUID?
    let lockedNote: String?
    let inlinePrimary: Bool
    let onFinished: (_ addedRecord: Bool) -> Void

    @State private var showAllSuggestions = false
    @State private var search = ""
    @State private var searchLimit = Self.searchPageSize
    @State private var showConfirm = false

    private static let searchPageSize = 20

    /// كل سجلات الشجرة القابلة للبحث — أصحاب الحسابات يظهرون وسبب المنع في المقارنة
    private var searchResults: [FamilyMember] {
        let all = memberVM.allMembers.filter {
            $0.role != .pending && $0.hasName && !$0.isFemale && $0.id != member.id && $0.isDeceased != true
        }
        return NameSearch.filter(all, query: search) { $0.fullName }
    }

    private var selectedRecord: FamilyMember? {
        selectedRecordId.flatMap { id in
            suggestions.first(where: { $0.id == id })?.member ?? memberVM.member(byId: id)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSBox.sectionSpacing) {
            AnyView(pickSection)
            if let record = selectedRecord {
                let plan = JoinLinkPlan(applicant: member, record: record, memberVM: memberVM, accounts: accounts)
                AnyView(JoinCompareCard(member: member, record: record, plan: plan))
                AnyView(linkArea(plan: plan))
                    .preference(key: JoinPrimaryKey.self, value: primaryAction(record: record, plan: plan))
                    .dsAlert(L10n.t("تأكيد الربط", "Confirm Link"), isPresented: $showConfirm) {
                        Button(L10n.t("ربط بهذا", "Link to this"), role: .none) { link(to: record) }
                        Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
                    } message: {
                        Text(plan.confirmText)
                    }
            }
        }
        .onChange(of: search) { _ in searchLimit = Self.searchPageSize }
    }

    // MARK: اختيار السجل

    private var pickSection: some View {
        DSComposerSection(title: L10n.t("أي سجل هو؟", "Which record is it?"),
                          icon: "person.2.fill",
                          tint: DS.Color.success,
                          trailing: suggestions.isEmpty ? nil : "\(suggestions.count)",
                          index: 3) {
            if suggestions.isEmpty {
                DSNoteCard(L10n.t("لا يوجد اسم قريب في الشجرة — ابحث بالاسم، أو اختر «غير موجود».",
                                  "No close name in the tree — search by name, or choose «Not in it»."),
                           icon: "magnifyingglass", tint: DS.Color.warning)
            }
            ForEach(Array(visibleSuggestions.enumerated()), id: \.element.id) { index, suggestion in
                JoinRecordRow(record: suggestion.member,
                              caption: NameMatcher.linkReason(depth: suggestion.depth),
                              badge: index == 0 ? L10n.t("الأقرب", "Closest") : nil,
                              isSelected: selectedRecordId == suggestion.id) {
                    selectedRecordId = suggestion.id
                }
            }
            if suggestions.count > 1 && !showAllSuggestions {
                DSChipButton(L10n.t("عرض المزيد (\(suggestions.count - 1))", "Show more (\(suggestions.count - 1))"),
                             icon: "chevron.down", tint: AppSection.admin.ink) {
                    showAllSuggestions = true
                }
                .frame(maxWidth: .infinity)
            }
            DSComposerField(icon: "magnifyingglass",
                            label: L10n.t("بحث في الشجرة", "Search the tree"),
                            placeholder: L10n.t("اسم السجل", "Record name"),
                            text: $search)
            if !search.isEmpty {
                searchRows
            }
        }
    }

    /// الأقرب وحده، والباقي تحت «عرض المزيد» — والمختار يبقى ظاهراً
    private var visibleSuggestions: [JoinSuggestion] {
        guard !showAllSuggestions else { return suggestions }
        return suggestions.enumerated().filter { $0.offset == 0 || $0.element.id == selectedRecordId }.map(\.element)
    }

    @ViewBuilder
    private var searchRows: some View {
        let results = searchResults
        if results.isEmpty {
            DSNoteCard(L10n.t("لا توجد نتائج.", "No results."), icon: "magnifyingglass", tint: DS.Color.textTertiary)
        }
        ForEach(Array(results.prefix(searchLimit))) { record in
            JoinRecordRow(record: record, caption: nil, badge: nil, isSelected: selectedRecordId == record.id) {
                selectedRecordId = record.id
            }
        }
        if results.count > searchLimit {
            DSChipButton(L10n.t("عرض المزيد (\(results.count - searchLimit))", "Show more (\(results.count - searchLimit))"),
                         icon: "chevron.down", tint: AppSection.admin.ink) {
                searchLimit += Self.searchPageSize
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: الربط

    @ViewBuilder
    private func linkArea(plan: JoinLinkPlan) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            if let blocker = plan.blocker {
                DSNoteCard(blocker, icon: "lock.fill", tint: DS.Color.error)
            }
            if !plan.warnings.isEmpty {
                DSNoteCard(plan.warnings.joined(separator: "\n"), title: L10n.t("انتبه", "Careful"),
                           icon: "exclamationmark.triangle.fill", tint: DS.Color.warning)
            }
            if let lockedNote {
                DSNoteCard(lockedNote, icon: "hourglass", tint: DS.Color.info)
            }
            if inlinePrimary {
                DSButton(L10n.t("ربط بهذا", "Link to this"), icon: "link", isLoading: adminRequestVM.isLoading) {
                    showConfirm = true
                }
                .disabled(!canLink(plan))
            }
        }
    }

    private func canLink(_ plan: JoinLinkPlan) -> Bool {
        plan.blocker == nil && lockedNote == nil && !adminRequestVM.isLoading
    }

    private func primaryAction(record: FamilyMember, plan: JoinLinkPlan) -> JoinPrimaryAction {
        JoinPrimaryAction(id: record.id.uuidString, title: L10n.t("ربط بهذا", "Link to this"), icon: "link",
                          isEnabled: canLink(plan)) { showConfirm = true }
    }

    private func link(to record: FamilyMember) {
        Task {
            await adminRequestVM.mergeMemberIntoTreeMember(newMemberId: member.id, existingTreeMemberId: record.id)
            onFinished(false)
        }
    }
}

/// صفّ سجلّ: الاسم كاملاً حتى ٣ أسطر، وسبب الاقتراح، وعلامة الأقرب
private struct JoinRecordRow: View {
    let record: FamilyMember
    let caption: String?
    let badge: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.sm) {
                DSFieldIcon(name: isSelected ? "checkmark" : "person.fill",
                            tint: isSelected ? DS.Color.success : AppSection.admin.ink)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(record.displayFullName)
                        .dsFieldFont(DSBox.fieldValueSize, weight: isSelected ? .medium : .regular)
                        .foregroundColor(isSelected ? DS.Color.textPrimary : DS.Color.fieldValue)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    if let caption {
                        Text(caption)
                            .dsFont(.caption)
                            .foregroundColor(DS.Color.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                if let badge {
                    DSStatusChip(text: badge, tint: DS.Color.success, size: .mini)
                }
            }
            .dsRowBox()
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .strokeBorder(DS.Color.success.opacity(isSelected ? DS.Opacity.selectedStroke : 0),
                                  lineWidth: DS.Border.widthBold)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(DSScaleButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - المقارنة: الطلب مقابل الشجرة

private struct JoinCompareCard: View {
    let member: FamilyMember
    let record: FamilyMember
    let plan: JoinLinkPlan

    var body: some View {
        DSComposerSection(title: L10n.t("الطلب مقابل الشجرة", "Request vs tree"),
                          icon: "rectangle.split.2x1.fill",
                          tint: AppSection.admin.ink,
                          index: 4) {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                HStack(alignment: .top, spacing: DS.Spacing.xsm) {
                    nameCell(title: L10n.t("الطلب", "Request"), name: member.displayFullName,
                             fill: DS.Color.cardBackgroundSoft)
                    nameCell(title: L10n.t("في الشجرة", "In the tree"), name: record.displayFullName,
                             fill: DS.Color.success.opacity(DS.Opacity.tintFill))
                }
                HStack(spacing: DS.Spacing.sm) {
                    DSRingGauge(progress: Double(plan.matchedNames) / 3, tint: plan.strength.tint,
                                size: DS.Ring.mini, ink: AppSection.admin.ink)
                    Text(plan.strength.title)
                        .dsFont(.chip)
                        .foregroundColor(plan.strength.tint.dsReadableGlyph)
                    Spacer(minLength: 0)
                }
                VStack(spacing: 0) {
                    ForEach(plan.lines) { line in
                        JoinCompareLine(line: line)
                        if line.field != .login {
                            Divider()
                        }
                    }
                }
                if let note = plan.birth.note {
                    Text(note)
                        .dsFont(.footnote)
                        .foregroundColor(DS.Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .dsCard(padding: DS.Spacing.sm, radius: DS.Radius.md, fill: DS.Color.background)
        }
    }

    private func nameCell(title: String, name: String, fill: Color) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            Text(title)
                .dsFont(.caption)
                .foregroundColor(DS.Color.textTertiary)
            Text(name)
                .dsFieldFont(.rowTitleCompact)
                .foregroundColor(DS.Color.fieldLabel)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DS.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(fill, in: RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// سطر بيان: العنوان، والنتيجة بعلامتها (✓ متطابق · ✗ مختلف · ≈ قريب · — ناقص)
private struct JoinCompareLine: View {
    let line: JoinCompare.Line

    private var tint: Color {
        switch line.verdict {
        case .match: return DS.Color.success.dsReadableGlyph
        case .close: return DS.Color.warning.dsReadableGlyph
        case .differ: return DS.Color.error.dsReadableGlyph
        case .unknown: return DS.Color.textTertiary
        }
    }

    private var symbol: String {
        switch line.verdict {
        case .match: return "checkmark.circle.fill"
        case .close: return "exclamationmark.circle.fill"
        case .differ: return "xmark.circle.fill"
        case .unknown: return "minus.circle"
        }
    }

    private var spokenVerdict: String {
        switch line.verdict {
        case .match: return L10n.t("مطابق", "Matches")
        case .close: return L10n.t("قريب", "Close")
        case .differ: return L10n.t("مختلف", "Differs")
        case .unknown: return L10n.t("غير معروف", "Unknown")
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.sm) {
            Text(line.field.title)
                .dsFont(.footnote)
                .foregroundColor(DS.Color.textSecondary)
            Spacer(minLength: DS.Spacing.xs)
            Text(line.detail)
                .dsFont(.chip)
                .foregroundColor(tint)
                .multilineTextAlignment(.trailing)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Image(systemName: symbol)
                .dsGlyph(DS.Glyph.sm)
                .foregroundColor(tint)
                .accessibilityHidden(true)
        }
        .padding(.vertical, DS.Spacing.xsm)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(line.field.title): \(spokenVerdict)، \(line.detail)")
    }
}

// MARK: - غير موجود: الأب من شجرة صغيرة

private struct JoinNewPersonPanel: View {
    @ObservedObject var memberVM: MemberViewModel
    @ObservedObject var adminRequestVM: AdminRequestViewModel
    let member: FamilyMember
    let lockedNote: String?
    let inlinePrimary: Bool
    let onSameAsRecord: (UUID) -> Void
    let onFinished: (_ addedRecord: Bool) -> Void

    @State private var loaded = false
    @State private var fatherId: UUID?
    @State private var fatherFromRequest = false
    @State private var suggestedFathers: [FamilyMember] = []
    @State private var search = ""
    @State private var newFirstName = ""
    @State private var working = false
    @State private var errorText: String?
    @State private var showConfirm = false

    private static let suggestedLimit = 5
    private static let searchLimit = 20

    private var father: FamilyMember? { fatherId.flatMap { memberVM.member(byId: $0) } }
    private var trimmedFirstName: String { newFirstName.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// سلسلة اسم المتقدّم بلا العائلة — [هو، أبوه، جدّه…]
    private var requestChain: [String] {
        NameMatcher.linkChain(member.nameUnits, noise: NameMatcher.linkNoise(member.familyName))
    }

    /// مرشّحو الأب: ذكور في الشجرة أحياء أو متوفون
    private var eligibleFathers: [FamilyMember] {
        memberVM.allMembers.filter { $0.isCountable && $0.id != member.id }
    }

    /// «الأقرب لاسمه»: من يطابق اسمه سلسلة اسم المتقدّم بعد اسمه الأول
    private func buildSuggestions() -> [(member: FamilyMember, depth: Int)] {
        let chain = Array(requestChain.dropFirst())
        guard !chain.isEmpty, let firstKey = chain.first else { return [] }
        let noise = NameMatcher.linkNoise(member.familyName)
        let needed = min(NameMatcher.minLinkDepth, chain.count)
        return eligibleFathers.compactMap { candidate -> (member: FamilyMember, depth: Int)? in
            // فحص سريع قبل بناء السلسلة (آلاف السجلّات) — أول حرفين يكفيان والاسم المركّب قد يختلف رسمه
            guard NameMatcher.linkKey(PersonName.firstUnit(candidate.fullName)).hasPrefix(String(firstKey.prefix(2))) else { return nil }
            let depth = NameMatcher.linkDepth(chain, NameMatcher.linkChain(candidate.nameUnits, noise: noise))
            return depth >= needed ? (member: candidate, depth: depth) : nil
        }
        .sorted { $0.depth > $1.depth }
    }

    /// الأب من الطلب (اختاره في التسجيل)، وإلا الأقرب لاسمه إن كان وحده بأعلى عمق
    private func load() async {
        guard !loaded else { return }
        loaded = true
        if newFirstName.isEmpty { newFirstName = PersonName.firstUnit(member.fullName) }
        let scored = buildSuggestions()
        suggestedFathers = scored.prefix(Self.suggestedLimit).map(\.member)
        if let requestFather = await adminRequestVM.fetchWomanJoinRequest(for: member.id)?.fatherId,
           memberVM.member(byId: requestFather)?.isCountable == true {
            fatherId = requestFather
            fatherFromRequest = true
        } else if let top = scored.first, scored.dropFirst().first?.depth != top.depth {
            fatherId = top.member.id
        }
    }

    // MARK: النتيجة

    private var brothers: [FamilyMember] {
        guard let fatherId else { return [] }
        return JoinTree.children(of: fatherId, in: memberVM).filter { $0.id != member.id }
    }

    /// أخ بالاسم نفسه (أو بفرق حرف) — ربما هو نفسه
    private var duplicate: FamilyMember? {
        let key = NameMatcher.linkKey(trimmedFirstName)
        guard !key.isEmpty else { return nil }
        return brothers.first {
            let other = NameMatcher.linkKey(JoinTree.shortName($0))
            return other == key || NameMatcher.isTypo(other, key)
        }
    }

    /// دون الثالثة عشرة لا يُربط (`merge_member_into_tree`) — لا يُضاف سجل ثم يُرفض ربطه
    private var underAgeNote: String? {
        guard let age = JoinCompare.ageYears(member.birthDate), age < JoinCompare.minimumAccountAge else { return nil }
        return L10n.t("دون الثالثة عشرة: لا يُنشأ له حساب، ويُدرَج في الشجرة من خلال ولي أمره.",
                      "Under 13: no account is created; a guardian adds him to the tree.")
    }

    private var warnings: [String] {
        guard let father else { return [] }
        let noise = NameMatcher.linkNoise(member.familyName)
        let lines = JoinCompare.nameLines(requestUnits: Array(member.nameUnits.dropFirst()),
                                          treeUnits: father.nameUnits, noise: noise)
        // سطرا «الاسم الأول» و«الأب» هنا = أب المتقدّم وجدّه
        var out: [String] = []
        if let line = lines.first, line.verdict == .differ || line.verdict == .close {
            out.append(L10n.t("الأب في الطلب «\(line.request ?? "")» والمختار «\(line.tree ?? "")».",
                              "The request says the father is «\(line.request ?? "")»; you chose «\(line.tree ?? "")»."))
        }
        if lines.count > 1, lines[1].verdict == .differ || lines[1].verdict == .close {
            out.append(L10n.t("الجد في الطلب «\(lines[1].request ?? "")» وعند الأب المختار «\(lines[1].tree ?? "")».",
                              "The request says the grandfather is «\(lines[1].request ?? "")»; the chosen father's is «\(lines[1].tree ?? "")»."))
        }
        if let age = JoinCompare.ageYears(member.birthDate), age >= JoinCompare.minimumAccountAge, age < JoinCompare.adultAge {
            out.append(L10n.t("قاصر: يُضاف السجل الآن، والربط بعد موافقة ولي أمره.",
                              "A minor: the record is added now, and linked after his guardian consents."))
        }
        return out
    }

    private var resultName: String {
        guard let father else { return trimmedFirstName }
        return "\(trimmedFirstName) \(father.displayFullName)"
    }

    private var confirmText: String {
        guard let father else { return "" }
        let sentence = JoinCompare.newRecordSentence(applicant: member.displayFullName, newName: resultName,
                                                     father: father.displayFullName,
                                                     brothers: brothers.map(JoinTree.shortName))
        return JoinCompare.confirmText(sentence: sentence, warnings: warnings)
    }

    private var isBusy: Bool { working || adminRequestVM.isLoading || memberVM.isLoading }

    private var canAdd: Bool {
        father != nil && !trimmedFirstName.isEmpty && duplicate == nil && underAgeNote == nil && lockedNote == nil && !isBusy
    }

    // MARK: الجسم

    var body: some View {
        VStack(alignment: .leading, spacing: DSBox.sectionSpacing) {
            AnyView(fatherSection)
            if father != nil { AnyView(resultSection) }
        }
        .task { await load() }
        .preference(key: JoinPrimaryKey.self, value: father == nil ? nil : JoinPrimaryAction(
            id: "new", title: L10n.t("إضافة وربط", "Add & Link"), icon: "link.badge.plus",
            isEnabled: canAdd) { showConfirm = true })
        .dsAlert(L10n.t("تأكيد الإضافة والربط", "Confirm add and link"), isPresented: $showConfirm) {
            Button(L10n.t("إضافة وربط", "Add & Link"), role: .none) { addAndLink() }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
        } message: {
            Text(confirmText)
        }
    }

    private var fatherSection: some View {
        DSComposerSection(title: L10n.t("من أبوه؟", "Who is his father?"),
                          icon: "figure.and.child.holdinghands",
                          tint: DS.Color.palm,
                          index: 3) {
            if let father {
                Text(L10n.t("اضغط على الأب الصحيح في الشجرة", "Tap the right father in the tree"))
                    .dsFont(.footnote)
                    .foregroundColor(DS.Color.textSecondary)
                    .frame(maxWidth: .infinity)
                JoinMiniTree(father: father, memberVM: memberVM, excludedId: member.id,
                             newName: trimmedFirstName.isEmpty ? L10n.t("الطلب", "Request") : trimmedFirstName) { id in
                    fatherId = id
                    fatherFromRequest = false
                }
                if fatherFromRequest {
                    Text(L10n.t("اختاره مقدّم الطلب في التسجيل", "Chosen by the applicant at sign-up"))
                        .dsFont(.caption)
                        .foregroundColor(DS.Color.textTertiary)
                        .frame(maxWidth: .infinity)
                }
            } else if search.isEmpty {
                ForEach(suggestedFathers) { candidate in
                    JoinRecordRow(record: candidate, caption: L10n.t("الأقرب لاسمه", "Closest to his name"),
                                  badge: nil, isSelected: false) {
                        fatherId = candidate.id
                    }
                }
            }
            DSComposerField(icon: "magnifyingglass",
                            label: father == nil ? L10n.t("ابحث عن الأب", "Search for the father")
                                                 : L10n.t("أب آخر؟ ابحث", "Another father? Search"),
                            placeholder: L10n.t("اسم الأب", "Father's name"),
                            text: $search)
            if !search.isEmpty {
                let results = NameSearch.filter(eligibleFathers, query: search) { $0.fullName }
                if results.isEmpty {
                    DSNoteCard(L10n.t("لا توجد نتائج.", "No results."), icon: "magnifyingglass", tint: DS.Color.textTertiary)
                }
                ForEach(Array(results.prefix(Self.searchLimit))) { candidate in
                    JoinRecordRow(record: candidate, caption: nil, badge: nil, isSelected: fatherId == candidate.id) {
                        fatherId = candidate.id
                        fatherFromRequest = false
                        search = ""
                    }
                }
            }
        }
    }

    private var resultSection: some View {
        DSComposerSection(title: L10n.t("النتيجة", "Result"),
                          icon: "checkmark.seal.fill",
                          tint: DS.Color.success,
                          index: 4) {
            DSComposerField(icon: "person.fill",
                            label: L10n.t("اسمه في الشجرة", "His name in the tree"),
                            placeholder: L10n.t("الاسم الأول", "First name"),
                            text: $newFirstName,
                            required: true)
            resultCard
            if let underAgeNote {
                DSNoteCard(underAgeNote, icon: "lock.fill", tint: DS.Color.error)
            }
            if !warnings.isEmpty {
                DSNoteCard(warnings.joined(separator: "\n"), title: L10n.t("انتبه", "Careful"),
                           icon: "exclamationmark.triangle.fill", tint: DS.Color.warning)
            }
            if let lockedNote {
                DSNoteCard(lockedNote, icon: "hourglass", tint: DS.Color.info)
            }
            if let errorText {
                DSNoteCard(errorText, icon: "exclamationmark.triangle.fill", tint: DS.Color.error)
            }
            if inlinePrimary {
                DSButton(L10n.t("إضافة وربط", "Add & Link"), icon: "link.badge.plus", isLoading: isBusy) {
                    showConfirm = true
                }
                .disabled(!canAdd)
            }
        }
    }

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack(alignment: .top, spacing: DS.Spacing.sm) {
                Text(resultName)
                    .dsFieldFont(.rowTitleCompact)
                    .foregroundColor(DS.Color.fieldLabel)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if duplicate == nil {
                    DSStatusChip(text: L10n.t("ما فيه تكرار", "No duplicate"), icon: "checkmark", tint: DS.Color.success, size: .mini)
                } else {
                    DSStatusChip(text: L10n.t("تكرار محتمل", "Possible duplicate"), icon: "exclamationmark", tint: DS.Color.warning, size: .mini)
                }
            }
            Text(brothersLine)
                .dsFont(.footnote)
                .foregroundColor(DS.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let duplicate {
                DSChipButton(L10n.t("هو نفسه: قارن", "Same person: compare"), icon: "rectangle.split.2x1",
                             tint: AppSection.admin.ink) {
                    onSameAsRecord(duplicate.id)
                }
            }
        }
        .dsCard(padding: DS.Spacing.sm, radius: DS.Radius.md, fill: DS.Color.background)
    }

    private var brothersLine: String {
        let name = trimmedFirstName
        let fatherShort = father.map(JoinTree.shortName) ?? ""
        let list = brothers.map(JoinTree.shortName)
        let siblings = list.isEmpty
            ? L10n.t("لا إخوة مسجّلون", "No brothers recorded")
            : L10n.t("الإخوة: \(JoinCompare.namesList(list))", "Brothers: \(JoinCompare.namesList(list))")
        if let duplicate {
            return siblings + " · " + L10n.t("يوجد «\(JoinTree.shortName(duplicate))» تحت \(fatherShort)",
                                             "«\(JoinTree.shortName(duplicate))» already exists under \(fatherShort)")
        }
        return siblings + " · " + L10n.t("ما فيه «\(name)» تحت \(fatherShort)", "No «\(name)» under \(fatherShort)")
    }

    // MARK: التنفيذ — نداءان موجودان: إضافة ابن تحت الأب، ثم «ربط بالشجرة» به

    private func addAndLink() {
        guard let father else { return }
        errorText = nil
        working = true
        let name = trimmedFirstName
        Task {
            // الميلاد لا يُكتب هنا: الربط يأخذ تاريخ الطلب، وسجلّ يفشل ربطه لا يحمل تاريخاً لم يُراجع
            memberVM.errorMessage = nil
            let newId = await memberVM.addChild(firstNameOnly: name, phoneNumber: "", birthDate: nil,
                                                fatherId: father.id, isDeceased: false, deathDate: nil,
                                                gender: "male", silent: true)
            guard let newId else {
                errorText = memberVM.errorMessage
                    ?? L10n.t("تعذّرت إضافة السجل. حاول مرة أخرى.", "Couldn't add the record. Try again.")
                working = false
                return
            }
            await adminRequestVM.mergeMemberIntoTreeMember(newMemberId: member.id, existingTreeMemberId: newId)
            working = false
            onFinished(true)
        }
    }
}

/// الشجرة الصغيرة: الفرع، ثم الجد، ثم الأب وإخوته، ثم الأبناء والشخص الجديد منقّطاً. الضغط على أي شخص يجعله الأب
private struct JoinMiniTree: View {
    let father: FamilyMember
    @ObservedObject var memberVM: MemberViewModel
    let excludedId: UUID
    let newName: String
    let onPick: (UUID) -> Void

    var body: some View {
        let grandfather = father.fatherId.flatMap { memberVM.member(byId: $0) }
        let branch = grandfather?.fatherId.flatMap { memberVM.member(byId: $0) }
        let fatherRow = grandfather.map { JoinTree.children(of: $0.id, in: memberVM) } ?? [father]
        let children = JoinTree.children(of: father.id, in: memberVM).filter { $0.id != excludedId }

        VStack(spacing: 0) {
            if let branch {
                node(branch, style: .muted)
                connector
            }
            if let grandfather {
                node(grandfather, style: .normal)
                connector
            }
            JoinCenteredFlow {
                ForEach(fatherRow) { person in
                    node(person, style: person.id == father.id ? .picked : .muted)
                }
            }
            connector
            JoinCenteredFlow {
                ForEach(children) { person in
                    node(person, style: .normal)
                }
                JoinTreeNode(title: newName, caption: L10n.t("الطلب", "Request"), style: .incoming, action: nil)
                    .accessibilityLabel(L10n.t("الشخص الجديد: \(newName)", "New person: \(newName)"))
            }
        }
        .frame(maxWidth: .infinity)
        .dsCard(padding: DS.Spacing.sm, radius: DS.Radius.md, fill: DS.Color.background)
    }

    private func node(_ person: FamilyMember, style: JoinTreeNode.Style) -> some View {
        JoinTreeNode(title: JoinTree.shortName(person),
                     caption: style == .picked ? L10n.t("الأب", "Father") : nil,
                     style: style,
                     action: style == .picked ? nil : { onPick(person.id) })
            .accessibilityLabel(person.displayFullName)
    }

    private var connector: some View {
        Rectangle()
            .fill(DS.Color.textTertiary.opacity(DS.Opacity.tintStroke))
            .frame(width: DS.Border.width, height: DS.Spacing.sm)
            .accessibilityHidden(true)
    }
}

private struct JoinTreeNode: View {
    enum Style { case muted, normal, picked, incoming }

    let title: String
    let caption: String?
    let style: Style
    let action: (() -> Void)?

    private var fill: Color {
        switch style {
        case .muted: return DS.Color.cardBackgroundSoft
        case .normal: return DS.Color.surface
        case .picked: return DS.Color.success.opacity(DS.Opacity.tintFill)
        case .incoming: return DS.Color.accentLight.opacity(DS.Opacity.tintFill)
        }
    }

    private var stroke: Color {
        switch style {
        case .muted, .normal: return DS.Color.textTertiary.opacity(DS.Opacity.tintStroke)
        case .picked: return DS.Color.success
        case .incoming: return DS.Color.accentLight
        }
    }

    private var textColor: Color {
        switch style {
        case .muted: return DS.Color.textSecondary
        case .normal: return DS.Color.textPrimary
        case .picked: return DS.Color.success.dsReadableGlyph
        case .incoming: return DS.Color.accent
        }
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous) }

    private var face: some View {
        HStack(spacing: DS.Spacing.xs) {
            if style == .picked {
                Image(systemName: "checkmark")
                    .dsGlyph(DS.Glyph.xs, weight: .bold)
                    .accessibilityHidden(true)
            }
            Text(title)
                .dsFont(style == .picked || style == .incoming ? .chip : .caption)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                // اسم عضو الشجرة وحدة قصيرة: بعرضها كاملة (بدونها قد ينكسر «يوسف» حرفاً على سطر)؛ وما كُتب للجديد قد يطول
                .fixedSize(horizontal: style != .incoming, vertical: true)
            if let caption {
                Text(caption)
                    .dsFont(.micro)
            }
        }
        .foregroundColor(textColor)
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, DS.Spacing.xs)
        .background(fill, in: shape)
        .overlay {
            if style == .incoming {
                shape.strokeBorder(stroke, style: StrokeStyle(lineWidth: DS.Border.widthBold,
                                                              dash: [DS.Spacing.xs, DS.Spacing.xs - 1]))
            } else {
                shape.strokeBorder(stroke, lineWidth: DS.Border.width)
            }
        }
        // لمس ٤٤ بلا تكبير الشكل
        .frame(minHeight: DS.Icon.tapTarget)
        .contentShape(Rectangle())
    }

    var body: some View {
        if let action {
            Button(action: action) { face }
                .buttonStyle(DSScaleButtonStyle())
        } else {
            face
                .accessibilityElement(children: .combine)
        }
    }
}

/// صفوف ملتفّة في الوسط — إخوة الأب أو الأبناء، بلا تمرير أفقي حتى تبقى الأسماء ظاهرة
private struct JoinCenteredFlow: Layout {
    var spacing: CGFloat = DS.Spacing.xsm

    private func lines(_ subviews: Subviews, maxWidth: CGFloat) -> [(items: [(index: Int, size: CGSize)], width: CGFloat, height: CGFloat)] {
        var out: [(items: [(index: Int, size: CGSize)], width: CGFloat, height: CGFloat)] = []
        var items: [(index: Int, size: CGSize)] = []
        var width: CGFloat = 0, height: CGFloat = 0
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            let next = items.isEmpty ? size.width : width + spacing + size.width
            if next > maxWidth, !items.isEmpty {
                out.append((items, width, height))
                items = []; width = 0; height = 0
            }
            width = items.isEmpty ? size.width : width + spacing + size.width
            height = max(height, size.height)
            items.append((index, size))
        }
        if !items.isEmpty { out.append((items, width, height)) }
        return out
    }

    private func finiteWidth(_ proposed: CGFloat?) -> CGFloat {
        guard let proposed, proposed.isFinite else { return DS.Landscape.columnMinWidth }
        return max(0, proposed)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = finiteWidth(proposal.width)
        let rows = lines(subviews, maxWidth: maxWidth)
        let height = rows.reduce(0) { $0 + $1.height } + CGFloat(max(0, rows.count - 1)) * spacing
        return CGSize(width: maxWidth, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in lines(subviews, maxWidth: bounds.width) {
            var x = bounds.minX + (bounds.width - row.width) / 2
            for item in row.items {
                // بالعرض المقيس مقرّباً لأعلى — العرض الكسري بالضبط قد يلفّ آخر حرف
                subviews[item.index].place(at: CGPoint(x: x, y: y + (row.height - item.size.height) / 2),
                                           anchor: .topLeading,
                                           proposal: ProposedViewSize(width: item.size.width.rounded(.up), height: item.size.height))
                x += item.size.width + spacing
            }
            y += row.height + spacing
        }
    }
}

// MARK: - غير واضح: يبقى معلّقاً والتواصل بما هو موجود

private struct JoinUnclearPanel: View {
    let member: FamilyMember

    private var phone: String { JoinCompare.clean(member.phoneNumber) }

    var body: some View {
        DSComposerSection(title: L10n.t("اسأل مقدّم الطلب", "Ask the applicant"),
                          icon: "bubble.left.and.bubble.right.fill",
                          tint: DS.Color.sea,
                          index: 3) {
            DSNoteCard(L10n.t("يبقى الطلب معلّقاً ولا يتغيّر شيء حتى تقرّر.",
                              "The request stays pending and nothing changes until you decide."),
                       icon: "hourglass", tint: DS.Color.info)
            if phone.isEmpty {
                DSNoteCard(L10n.t("لا يوجد رقم في الطلب — أضِفه من «تعديل / إضافة رقم فعلي».",
                                  "No number on the request — add one with «Edit / Add real number»."),
                           icon: "phone.badge.plus", tint: DS.Color.warning)
            } else {
                HStack(spacing: DSBox.buttonSpacing) {
                    if let whatsapp = KuwaitPhone.whatsappURL(phone) {
                        DSButton(L10n.t("واتساب", "WhatsApp"), icon: "message.fill", tint: DS.Color.sea) {
                            UIApplication.shared.open(whatsapp)
                        }
                    }
                    if let tel = KuwaitPhone.telURL(phone) {
                        DSButton(L10n.t("اتصال", "Call"), icon: "phone.fill") {
                            UIApplication.shared.open(tel)
                        }
                    }
                }
            }
        }
    }
}
