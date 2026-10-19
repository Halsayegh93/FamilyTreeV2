import SwiftUI

// MARK: - «ذكرى الراحلين» في لوحة الإدارة (طلب المالك ٢٠٢٦-١٠-١٩ «نبي نحط بلوحة الادارة ذكرى المتوفى»)
//
// نفس المواصفة في الأندرويد والموقع (memorial/SPEC.md). التقويم الميلادي فقط، وعرض فقط (بلا إشعارات):
//   ١. «الذكرى القريبة» — من تاريخ وفاته كامل (يوم وشهر) وذكراه خلال ٣٠ يوماً، الأقرب أولاً.
//   ٢. «ناقص تاريخه» — السنة فقط، أو مكتوب بالهجري — و«تكميل التاريخ» لمن يعدّل الأعضاء
//      (بدون تاريخ = «غير معروف» ما يطلع هنا (المالك ٢٠٢٦-١٠-١٩ «غير معروف او غير متوفر نفس المعنى»))
//      (نفس صلاحية «تعديل بيانات عضو») يحفظ بنفس مسار ذاك التعديل (DeceasedDateBox).
// البيانات من أعضاء الشجرة المحمّلين (memberVM.allMembers) — بلا طلبات جديدة للسيرفر غير حفظ التاريخ.
// التصنيف والحساب في `DeceasedMemorial` (Core/DeceasedMemorial.swift).

/// الأعضاء المتوفون مصنّفون للصفحة ولصفّ لوحة الإدارة
struct DeceasedMemorialBoard {
    struct Upcoming: Identifiable {
        let member: FamilyMember
        let anniversary: DeceasedMemorial.Anniversary
        var id: UUID { member.id }
    }

    struct Missing: Identifiable {
        let member: FamilyMember
        let kind: DeceasedMemorial.DateKind
        var id: UUID { member.id }
    }

    /// ذكراهم خلال ٣٠ يوماً — الأقرب أولاً
    let upcoming: [Upcoming]
    /// الهجري أولاً، ثم «السنة فقط» الأحدث أولاً، ثم بدون تاريخ
    let missing: [Missing]

    static let empty = DeceasedMemorialBoard([])

    init(_ all: [FamilyMember], today: Date = Date()) {
        let cal = DeceasedMemorial.gregorian
        var up: [Upcoming] = []
        var miss: [Missing] = []
        // «التاريخ غير معروف» (deathDateUnknown) ما يطلع هنا أبداً — طلب المالك ٢٠٢٦-١٠-١٩
        for m in all where m.isDeceased == true && m.isCountable && m.deathDateUnknown != true {
            let kind = DeceasedMemorial.classify(m.deathDate)
            switch kind {
            case .exact:
                if let a = DeceasedMemorial.anniversary(kind, today: today, calendar: cal),
                   a.daysUntil <= DeceasedMemorial.upcomingDays {
                    up.append(Upcoming(member: m, anniversary: a))
                }
            case .yearOnly, .hijriLike:
                miss.append(Missing(member: m, kind: kind))
            case .missing:
                continue   // بدون تاريخ = «غير معروف» — ما يطلع هنا
            }
        }
        upcoming = up.sorted {
            ($0.anniversary.daysUntil, $0.member.fullName) < ($1.anniversary.daysUntil, $1.member.fullName)
        }
        missing = miss.sorted {
            let a = DeceasedMemorial.missingRank($0.kind), b = DeceasedMemorial.missingRank($1.kind)
            return (a.group, a.year, $0.member.fullName) < (b.group, b.year, $1.member.fullName)
        }
    }

    var today: [Upcoming] { upcoming.filter { $0.anniversary.daysUntil == 0 } }
    /// شارة اللوحة و«هالأسبوع»: اليوم و٦ أيام بعده (٧ أيام — مثل الأندرويد والموقع)
    var withinWeek: Int { upcoming.filter { $0.anniversary.daysUntil < DeceasedMemorial.weekDays }.count }

    /// سطر صفّ لوحة الإدارة: «اليوم: ذكرى …» / «هالأسبوع: n» / «لا ذكرى قريبة · m ناقص تاريخهم»
    var dashboardCaption: String {
        if let first = today.first {
            return L10n.t("اليوم: ذكرى \(first.member.shortFullName)", "Today: \(first.member.shortFullName)'s anniversary")
        }
        if withinWeek > 0 {
            return L10n.t("هالأسبوع: \(withinWeek)", "This week: \(withinWeek)")
        }
        return L10n.t("لا ذكرى قريبة · \(missing.count) ناقص تاريخهم", "None upcoming · \(missing.count) missing a date")
    }
}

struct DeceasedMemorialView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel

    @State private var query = ""
    /// «ناقص تاريخه» طويلة (٢٢٩+) — تنعرض دفعات
    @State private var missingLimit = Self.pageSize
    /// العضو المفتوح في «تكميل التاريخ»
    @State private var editing: FamilyMember?

    private static let pageSize = 60
    private var tint: Color { DS.Color.actionNavy }
    private var arabic: Bool { L10n.isArabic }

    var body: some View {
        let board = DeceasedMemorialBoard(memberVM.allMembers)
        let upcoming = filter(board.upcoming) { $0.member }
        let missing = filter(board.missing) { $0.member }
        return ScrollView(showsIndicators: false) {
            VStack(spacing: DS.Spacing.md) {
                DSStatsRow([
                    DSHeroStat(value: "\(board.withinWeek)", label: L10n.t("هالأسبوع", "This week"), icon: "calendar"),
                    DSHeroStat(value: "\(board.upcoming.count)", label: L10n.t("خلال ٣٠ يوماً", "Next 30 days"),
                               icon: "moon.stars.fill"),
                    DSHeroStat(value: "\(board.missing.count)", label: L10n.t("ناقص تاريخهم", "Missing a date"),
                               icon: "calendar.badge.exclamationmark"),
                ], tint: tint)

                DSSearchField(text: $query, placeholder: L10n.t("ابحث بالاسم…", "Search by name…"), tint: tint)

                upcomingSection(upcoming)
                missingSection(missing, total: board.missing.count)
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.top, DS.Spacing.md)
            .padding(.bottom, DS.Spacing.xxxl)
        }
        .scrollDismissesKeyboard(.interactively)
        .dsSubPageHeader(L10n.t("ذكرى الراحلين", "Memorials"),
                         subtitle: L10n.t("الذكرى القريبة بالتاريخ الميلادي، ومن ينقصه تاريخ الوفاة",
                                          "Upcoming anniversaries (Gregorian), and who is missing a death date"),
                         icon: "moon.stars.fill")
        // نفس تحميل الأعضاء الموجود (لو فُتحت الصفحة قبل ما تتحمّل الشجرة)
        .task { if memberVM.allMembers.isEmpty { await memberVM.fetchAllMembers() } }
        .onChange(of: query) { _ in missingLimit = Self.pageSize }
        .dsCenterBox(item: $editing) { member in
            DeceasedDateBox(member: member)
                .environmentObject(authVM)
                .environmentObject(memberVM)
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    // MARK: البحث

    private func filter<T>(_ list: [T], member: (T) -> FamilyMember) -> [T] {
        let tokens = OccasionFamilyIndex.normalize(query).split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return list }
        return list.filter { item in
            let key = OccasionFamilyIndex.normalize(member(item).displayFullName)
            return tokens.allSatisfy { key.contains($0) }
        }
    }

    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    // MARK: «الذكرى القريبة»

    private func upcomingSection(_ list: [DeceasedMemorialBoard.Upcoming]) -> some View {
        DSComposerSection(title: L10n.t("الذكرى القريبة", "Upcoming anniversaries"), icon: "moon.stars.fill", tint: tint,
                          trailing: list.isEmpty ? nil : "\(list.count)", index: 1) {
            if list.isEmpty {
                DSEmptyView(isSearching ? L10n.t("لا يوجد متوفى بهذا الاسم", "No deceased member by that name")
                                        : L10n.t("لا توجد ذكرى خلال ٣٠ يوماً", "No anniversaries in the next 30 days"),
                            icon: "moon.stars", style: .compact)
            } else {
                LazyVStack(spacing: DS.Spacing.xsm) {
                    ForEach(list) { upcomingRow($0) }
                }
            }
        }
    }

    private func upcomingRow(_ item: DeceasedMemorialBoard.Upcoming) -> some View {
        let a = item.anniversary
        let when = DeceasedMemorial.whenLabel(a.daysUntil, arabic: arabic)
        let line = DeceasedMemorial.anniversaryLine(a, arabic: arabic)
        return HStack(spacing: DS.Spacing.sm) {
            avatar(item.member)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                // الاسم الكامل داخل المربع (طلب المالك ٢٠٢٦-١٠-١٩) — يلتف بدل ما ينقص
                Text(item.member.fullName)
                    .dsFieldFont(.rowTitle)
                    .foregroundColor(DS.Color.fieldLabel)
                    .fixedSize(horizontal: false, vertical: true)
                Text(line)
                    .dsFieldFont(.subtitle)
                    .foregroundColor(DS.Color.fieldValue)
            }
            Spacer(minLength: 0)
            DSStatusChip(text: when, tint: a.daysUntil <= 1 ? DS.Color.accent : tint, size: .mini)
        }
        .frame(minHeight: DSBox.fieldMinHeight)
        .dsRowBox()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.member.fullName)، \(line)، \(when)")
    }

    // MARK: «ناقص تاريخه»

    private func missingSection(_ list: [DeceasedMemorialBoard.Missing], total: Int) -> some View {
        let shown = list.prefix(missingLimit)
        return DSComposerSection(title: L10n.t("ناقص تاريخه", "Missing a date"), icon: "calendar.badge.exclamationmark",
                                 tint: DS.Color.warning, trailing: list.isEmpty ? nil : "\(list.count)", index: 2) {
            if list.isEmpty {
                DSEmptyView(isSearching ? L10n.t("لا يوجد متوفى بهذا الاسم", "No deceased member by that name")
                                        : L10n.t("كل المتوفين تواريخهم كاملة", "Every deceased member has a full date"),
                            icon: "checkmark.seal", style: .compact)
            } else {
                LazyVStack(spacing: DS.Spacing.xsm) {
                    ForEach(shown) { missingRow($0) }
                }
                if list.count > shown.count {
                    Button {
                        withAnimation(DS.Anim.quick) { missingLimit += Self.pageSize }
                    } label: {
                        Text(L10n.t("عرض المزيد (\(list.count - shown.count))", "Show more (\(list.count - shown.count))"))
                            .dsFont(.chip)
                            .foregroundColor(tint.dsReadableGlyph)
                            .frame(maxWidth: .infinity, minHeight: DS.Icon.tapTarget)
                    }
                    .buttonStyle(DSPressStyle())
                }
            }
        }
    }

    private func missingRow(_ item: DeceasedMemorialBoard.Missing) -> some View {
        let note = DeceasedMemorial.missingNote(item.kind, arabic: arabic)
        return HStack(spacing: DS.Spacing.sm) {
            avatar(item.member)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                // الاسم الكامل داخل المربع (طلب المالك ٢٠٢٦-١٠-١٩) — يلتف بدل ما ينقص
                Text(item.member.fullName)
                    .dsFieldFont(.rowTitle)
                    .foregroundColor(DS.Color.fieldLabel)
                    .fixedSize(horizontal: false, vertical: true)
                Text(note)
                    .dsFieldFont(.subtitle)
                    .foregroundColor(DS.Color.fieldValue)
            }
            Spacer(minLength: 0)
            // نفس صلاحية «تعديل بيانات عضو» (الإدارة والمراقب)
            if authVM.canEditMembers {
                Button { editing = item.member } label: {
                    Text(L10n.t("تكميل التاريخ", "Add date"))
                        .dsFont(.chip)
                        .foregroundColor(DS.Color.textOnPrimary)
                        .padding(.horizontal, DSBox.chipPadding)
                        .frame(minHeight: DSBox.chipHeightSmall)
                        .background(Capsule().fill(DSActionFill.style()))
                }
                .buttonStyle(DSPressStyle())
                .accessibilityLabel(L10n.t("تكميل تاريخ وفاة \(item.member.shortFullName)",
                                           "Add \(item.member.shortFullName)'s death date"))
            }
        }
        .frame(minHeight: DSBox.fieldMinHeight)
        .dsRowBox()
    }

    private func avatar(_ m: FamilyMember) -> some View {
        DSMemberAvatar(name: m.firstName, avatarUrl: m.avatarUrl, size: 40, roleColor: DS.Color.textSecondary)
            .accessibilityHidden(true)
    }
}

// MARK: - «تكميل التاريخ»

/// مربّع صغير بعجلة تاريخ ميلادية. الحفظ بنفس مسار «تعديل بيانات عضو» (AdminMemberDetailSheet.saveAction) لتاريخ الوفاة:
/// تحديث محلي فوري (upsertMemberLocally) ← memberVM.updateMemberHealthAndBirth (نفس الدالة، وتاريخ الميلاد كما هو).
/// بلا إشعار للإدارة (طلب المالك ٢٠٢٦-١٠-١٩: تكميل ٢٢٩ تاريخ ما يطلّع ٢٢٩ إشعار). بلا مسار كتابة جديد.
struct DeceasedDateBox: View {
    let member: FamilyMember
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var date: Date
    @State private var isSaving = false
    @State private var failure: String?
    private let kind: DeceasedMemorial.DateKind
    private let startDay: String

    /// نفس صيغة تواريخ «تعديل بيانات عضو» (yyyy-MM-dd)
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    init(member: FamilyMember) {
        self.member = member
        let kind = DeceasedMemorial.classify(member.deathDate)
        self.kind = kind
        let start = DeceasedMemorial.pickerStart(kind)
        self._date = State(initialValue: start)
        self.startDay = Self.dayFormatter.string(from: start)
    }

    private var tint: Color { DS.Color.actionNavy }

    var body: some View {
        DSComposer(
            title: L10n.t("تكميل التاريخ", "Add death date"),
            subtitle: member.shortFullName,
            icon: "calendar.badge.plus",
            tint: tint,
            actionTitle: L10n.t("حفظ", "Save"),
            canSubmit: !isSaving,
            isBusy: isSaving,
            note: failure ?? L10n.t("بالتقويم الميلادي — اليوم والشهر والسنة", "Gregorian calendar — day, month and year"),
            hasUnsavedChanges: Self.dayFormatter.string(from: date) != startDay,
            onSubmit: save,
            onCancel: { dismiss() }
        ) {
            DSComposerSection(title: L10n.t("المتوفى", "Deceased"), icon: "person.fill", tint: tint, index: 0) {
                Text(member.fullName)
                    .dsFieldFont(.rowTitle)
                    .foregroundColor(DS.Color.fieldLabel)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .dsRowBox()
            }
            DSComposerSection(title: L10n.t("تاريخ الوفاة", "Date of death"), icon: "calendar", tint: tint,
                              trailing: DeceasedMemorial.missingNote(kind, arabic: L10n.isArabic), index: 1) {
                StableWheelDatePicker(selection: $date, in: ...Date())
                    .environment(\.calendar, DeceasedMemorial.gregorian)
                    .dsRowBox()
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    private func save() {
        guard !isSaving else { return }
        guard NetworkMonitor.shared.isConnected else {
            failure = L10n.t("لا يوجد اتصال — حاول مرة ثانية.", "No connection — please try again.")
            return
        }
        let current = memberVM.member(byId: member.id) ?? member
        let newDeath = Self.dayFormatter.string(from: date)
        guard newDeath != String((current.deathDate ?? "").prefix(10)) else {
            dismiss()
            return
        }
        // الدالة نفسها ترسل تاريخ الميلاد مع الوفاة — يبقى كما هو (وما نحفظ لو ما قدرنا نقراه، حتى ما ينمسح)
        let birthRaw = (current.birthDate ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let birth = birthRaw.isEmpty ? nil : Self.dayFormatter.date(from: String(birthRaw.prefix(10)))
        guard birthRaw.isEmpty || birth != nil else {
            failure = L10n.t("تاريخ الميلاد المحفوظ غير واضح — عدّل من صفحة العضو.",
                             "The stored birth date is unclear — edit it from the member page.")
            return
        }
        isSaving = true
        failure = nil
        let picked = date

        // ١. تحديث محلي فوري (مثل التعديل)
        var updated = current
        updated.isDeceased = true
        updated.deathDate = newDeath
        memberVM.upsertMemberLocally(updated)

        Task {
            // ٢. نفس دالة حفظ التواريخ في «تعديل بيانات عضو»
            let saved = await memberVM.updateMemberHealthAndBirth(
                memberId: member.id,
                birthDate: birth,
                isDeceased: true,
                deathDate: picked
            )
            guard saved else {
                // يرجع للمحفوظ على السيرفر
                await memberVM.fetchSingleMember(id: member.id)
                isSaving = false
                failure = L10n.t("ما انحفظ التاريخ — حاول مرة ثانية.", "Couldn't save the date — please try again.")
                return
            }
            dismiss()
        }
    }
}
