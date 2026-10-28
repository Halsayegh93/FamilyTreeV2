import SwiftUI

// MARK: - «ذكرى الراحلين» (طلب المالك ٢٠٢٦-١٠-١٩ «نبي نحط بلوحة الادارة ذكرى المتوفى»)
//
// نفس المواصفة في الأندرويد والموقع (memorial/SPEC.md). التقويم الميلادي فقط، وعرض فقط (بلا إشعارات).
// منذ الدفعة ب («نفّذ كل المقترح» ٢٠٢٦-١٠-٢٠) لا صفحة مستقلّة: الذكرى القريبة (خلال ٣٠ يوماً) صفوف في «المناسبات
// والإعلانات» ← «القادم» (`AdminOccasionsPage`)، و«تاريخ الوفاة غير مكتمل» (السنة فقط أو هجري) في «العائلة» ← متوفون ←
// «تاريخ الوفاة غير مكتمل» — والاستكمال بمربّع `DeceasedDateBox` نفسه من ورقة العضو. بحث الذكرى حُذف (S8).
// التصنيف والحساب في `DeceasedMemorial` (Core/DeceasedMemorial.swift).

/// الذكرى القريبة — لـ«القادم» ولتلميح مربّع القسم في «اليوم»
struct DeceasedMemorialBoard {
    struct Upcoming: Identifiable {
        let member: FamilyMember
        let anniversary: DeceasedMemorial.Anniversary
        var id: UUID { member.id }
    }

    /// ذكراهم خلال ٣٠ يوماً — الأقرب أولاً
    let upcoming: [Upcoming]

    static let empty = DeceasedMemorialBoard([])

    init(_ all: [FamilyMember], today: Date = Date()) {
        let cal = DeceasedMemorial.gregorian
        var up: [Upcoming] = []
        // «التاريخ غير معروف» (deathDateUnknown) ما يطلع هنا أبداً — طلب المالك ٢٠٢٦-١٠-١٩
        for m in all where m.isDeceased == true && m.isCountable && m.deathDateUnknown != true {
            let kind = DeceasedMemorial.classify(m.deathDate)
            // السنة فقط/الهجري/بلا تاريخ: لا ذكرى (استكمالها في «العائلة» ← متوفون ← «تاريخ الوفاة غير مكتمل»)
            if let a = DeceasedMemorial.anniversary(kind, today: today, calendar: cal),
               a.daysUntil <= DeceasedMemorial.upcomingDays {
                up.append(Upcoming(member: m, anniversary: a))
            }
        }
        upcoming = up.sorted {
            ($0.anniversary.daysUntil, $0.member.fullName) < ($1.anniversary.daysUntil, $1.member.fullName)
        }
    }

    var today: [Upcoming] { upcoming.filter { $0.anniversary.daysUntil == 0 } }
    /// شارة اللوحة و«هذا الأسبوع»: اليوم و٦ أيام بعده (٧ أيام — مثل الأندرويد والموقع)
    var withinWeek: Int { upcoming.filter { $0.anniversary.daysUntil < DeceasedMemorial.weekDays }.count }

    /// تلميح مربّع القسم في «اليوم»: «اليوم: ذكرى …» / «ذكرى هذا الأسبوع: n» / «لا ذكرى قريبة»
    var dashboardCaption: String {
        if let first = today.first {
            return L10n.t("اليوم: ذكرى \(first.member.shortFullName)", "Today: \(first.member.shortFullName)'s anniversary")
        }
        if withinWeek > 0 {
            return L10n.t("ذكرى هذا الأسبوع: \(withinWeek)", "Memorials this week: \(withinWeek)")
        }
        return L10n.t("لا ذكرى قريبة", "No upcoming memorials")
    }
}

// MARK: - «تكميل التاريخ»

/// مربّع صغير بعجلة تاريخ ميلادية (يفتحه زرّ «استكمال تاريخ الوفاة» في ورقة العضو). الحفظ بنفس مسار «تعديل بيانات عضو» (AdminMemberDetailSheet.saveAction) لتاريخ الوفاة:
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
            title: L10n.t("استكمال تاريخ الوفاة", "Complete the death date"),
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
