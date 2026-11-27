import SwiftUI
import PhotosUI

// MARK: - مربّعات تعديل العضو (كانت مربّعات «محطة التفعيل»)
//
// تفتحها «ورقة العضو» (`AdminMemberSheet`) من أزرار «بيانات ناقصة» و«مشكلات الشجرة» وصفوف «البيانات» و«النسب»:
// ربط الأب، تاريخ الميلاد، الجنس، تاريخ الوفاة، الصورة، والاسم (كان في «صحة الشجرة»). صفحة المحطة نفسها حُذفت
// (٢٠٢٦-١٠-٢٠) — «التالي ›» في الورقة يمشي في القائمة عضواً عضواً. المربّعات ونداءاتها كما هي.
// إعادة تصميم الإدارة (٢٠٢٦-١١-٢٦، U13): كل حفظ يمرّ بـ`DebugAdminProbe.dryRun` (تجربة دور = نجاح مصطنع بلا كتابة)،
// وما يُبلغ فشله (الوفاة، الصورة، الجنس) يبقى المربّع مفتوحاً بسطر الخطأ داخله (spec C.10) بدل الإغلاق بصمت.

// MARK: - Link Father Sheet

/// ربط الأب — مربّع بمنتصف الشاشة بنفس تصميم مربّعات الإضافة (طلب المالك):
/// بطاقة العضو، ثم البحث وقائمة الأعضاء بعلامة اختيار، و«ربط الأب» / «إلغاء» أسفله.
struct LinkFatherSheet: View {
    let member: FamilyMember
    let memberVM: MemberViewModel
    @Environment(\.dismiss) var dismiss
    @State private var searchText = ""
    @State private var isSaving = false
    @State private var selectedFather: FamilyMember?
    @State private var cache = ResultsCache()
    /// نقد V3 م-ج٤: رفض السيرفر (حارس روابط العائلة…) سطر داخل المربّع، والمربّع يبقى مفتوحاً
    @State private var failure: String?

    /// نتائج البحث محفوظة لكل (نص بحث + نسخة الأعضاء): المربّع يعيد بناء محتواه كلما
    /// تغيّر ارتفاعه، وفرز آلاف الأعضاء مع كل مرة يثقّل الفتح والتمرير
    private final class ResultsCache {
        var key: String?
        var results: [FamilyMember] = []
    }

    private var results: [FamilyMember] {
        let key = "\(memberVM.membersVersion)|\(memberVM.allMembers.count)|\(searchText)"
        if cache.key != key {
            cache.results = Self.fathers(of: member, in: memberVM.allMembers, matching: searchText)
            cache.key = key
        }
        return cache.results
    }

    /// All potential fathers (non-pending, excluding self), filtered by the search text
    private static func fathers(of member: FamilyMember, in all: [FamilyMember],
                                matching search: String) -> [FamilyMember] {
        let potentialFathers = all
            .filter { $0.id != member.id && $0.role != .pending }
            .sorted {
                let a = $0.firstName.trimmingCharacters(in: .whitespaces)
                let b = $1.firstName.trimmingCharacters(in: .whitespaces)
                if a != b { return a.localizedStandardCompare(b) == .orderedAscending }
                return $0.fullName.localizedStandardCompare($1.fullName) == .orderedAscending
            }
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty { return potentialFathers }
        // البحث الدقيق الواحد (`NameSearch`): كل كلمة بداية كلمة بالترتيب

        return NameSearch.filter(potentialFathers, query: query) { $0.fullName }
    }

    var body: some View {
        DSComposer(
            title: L10n.t("ربط الأب", "Link Father"),
            subtitle: member.shortFullName,
            icon: "person.line.dotted.person",
            tint: DS.Color.actionNavy,
            actionTitle: L10n.t("ربط الأب", "Link Father"),
            actionIcon: "link",
            canSubmit: selectedFather != nil,
            isBusy: isSaving,
            // أب مختار ولم يُربط بعد → «إلغاء» يسأل قبل التجاهل (توصية أبل)
            hasUnsavedChanges: selectedFather != nil,
            onSubmit: save,
            onCancel: { dismiss() }
        ) {
            StationMemberCard(member: member).dsStaggerIn(0)
            if let failure {
                DSNoteCard(failure, icon: "exclamationmark.triangle.fill", tint: DS.Color.error)
            }
            fatherSection
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    /// البحث + قائمة الأعضاء — المختار بعلامة ✓ (الضغط عليه مرة ثانية يلغي الاختيار)
    private var fatherSection: some View {
        DSComposerSection(
            title: L10n.t("اختر الأب", "Choose Father"),
            icon: "person.2.fill",
            tint: DS.Color.info,
            trailing: L10n.t("\(results.count) عضو", "\(results.count) members"),
            index: 1
        ) {
            DSComposerField(icon: "magnifyingglass",
                            label: L10n.t("بحث", "Search"),
                            placeholder: L10n.t("ابحث عن الأب...", "Search for father..."),
                            text: $searchText,
                            tint: DS.Color.info)

            if results.isEmpty {
                DSEmptyView(L10n.t("لا توجد نتائج", "No results found"), style: .inline)
            } else {
                // كسولة — القائمة فيها آلاف الأعضاء: تُبنى الصفوف الظاهرة فقط
                LazyVStack(spacing: DS.Spacing.sm) {
                    ForEach(results) { father in
                        fatherRow(father)
                    }
                }
            }
        }
    }

    private func fatherRow(_ father: FamilyMember) -> some View {
        let isSelected = selectedFather?.id == father.id
        return Button {
            withAnimation(DS.Anim.snappy) {
                selectedFather = (selectedFather?.id == father.id) ? nil : father
            }
        } label: {
            HStack(spacing: DS.Spacing.sm) {
                // الحرف الأول بمربّع أيقونة الحقل (بلا تحميل صور لآلاف الصفوف)
                Text(String(father.firstName.prefix(1)))
                    .dsFont(.headlineCompact)
                    .foregroundColor(DS.Color.info)
                    .frame(width: DS.Icon.row, height: DS.Icon.row)
                    .background(RoundedRectangle(cornerRadius: DS.Icon.discRadius, style: .continuous)
                        .fill(DS.Color.info.opacity(DS.Opacity.tintFill)))
                    .accessibilityHidden(true)   // زخرفة — الاسم يُقرأ كاملاً بعدها

                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(father.displayFullName)
                        .dsFieldFont(DSBox.fieldValueSize, weight: isSelected ? .semibold : .medium)
                        .foregroundColor(isSelected ? DS.Color.textPrimary : DS.Color.fieldValue)
                        .dsNameLines()
                    if father.isDeceased == true {
                        Text(L10n.t("متوفى", "Deceased"))
                            .dsFont(.footnote)
                            .foregroundColor(DS.Color.textTertiary)
                    }
                }

                Spacer(minLength: 0)

                // علامة الاختيار للعين فقط — القارئ الصوتي يعلن «محدّد» من صفة isSelected
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .dsGlyph(DS.Glyph.xl, weight: .semibold)
                    .foregroundColor(isSelected ? DS.Color.info : DS.Color.textTertiary.opacity(DS.Opacity.disabled))
                    .accessibilityHidden(true)
            }
            .stationPickRow(selected: isSelected, tint: DS.Color.info)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// نقد V3 م-ج٤: يغلق بعد النجاح فقط — الفشل برسالة السيرفر (`errorMessage`) داخل المربّع، ثم تُمسح
    private func save() {
        guard let father = selectedFather, !isSaving else { return }
        if DebugAdminProbe.dryRun("updateMemberFather \(member.id) → \(father.id)") { dismiss(); return }
        isSaving = true
        failure = nil
        memberVM.errorMessage = nil
        Task { @MainActor in
            let ok = await memberVM.updateMemberFather(memberId: member.id, fatherId: father.id)
            isSaving = false
            if ok {
                dismiss()
            } else {
                failure = memberVM.errorMessage ?? L10n.t("تعذّر الحفظ. حاول مرة أخرى.", "Couldn't save. Try again.")
                memberVM.errorMessage = nil
            }
        }
    }
}

// MARK: - Edit Birth Date Sheet

/// تاريخ الميلاد — مربّع بمنتصف الشاشة بنفس تصميم مربّعات الإضافة (طلب المالك)
struct EditBirthDateSheet: View {
    let member: FamilyMember
    let memberVM: MemberViewModel
    @Environment(\.dismiss) var dismiss
    @State private var selectedDate: Date
    @State private var isSaving = false
    /// اليوم الذي فُتح عليه المربّع — «إلغاء» يسأل فقط إذا تغيّر (توصية أبل)
    private let startDay: String

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    init(member: FamilyMember, memberVM: MemberViewModel) {
        self.member = member
        self.memberVM = memberVM
        // Parse existing date or default to 1990-01-01
        let start: Date
        if let existing = member.birthDate,
           let parsed = Self.formatter.date(from: existing) {
            start = parsed
        } else {
            var comps = DateComponents()
            comps.year = 1990; comps.month = 1; comps.day = 1
            start = Calendar.current.date(from: comps) ?? Date()
        }
        _selectedDate = State(initialValue: start)
        startDay = Self.formatter.string(from: start)
    }

    var body: some View {
        DSComposer(
            title: L10n.t("تعديل تاريخ الميلاد", "Edit Birth Date"),
            subtitle: member.shortFullName,
            icon: "calendar.badge.plus",
            tint: DS.Color.actionNavy,
            actionTitle: L10n.t("حفظ", "Save"),
            canSubmit: true,
            isBusy: isSaving,
            // مقارنة باليوم فقط — العجلة لا تغيّر إلا التاريخ
            hasUnsavedChanges: Self.formatter.string(from: selectedDate) != startDay,
            onSubmit: save,
            onCancel: { dismiss() }
        ) {
            StationMemberCard(member: member).dsStaggerIn(0)

            DSComposerSection(title: L10n.t("تاريخ الميلاد", "Birth Date"),
                              icon: "calendar", tint: DS.Color.palm, index: 1) {
                // صفّ التاريخ الموحّد + منتقي التاريخ الموحّد (بدل العجلة داخل المربّع)
                DSDateFieldRow(icon: "calendar", title: L10n.t("تاريخ الميلاد", "Birth Date"),
                               hasDate: true, dateText: DSDateText.display(selectedDate)) {
                    dsPresentDatePicker(title: L10n.t("تاريخ الميلاد", "Birth Date"),
                                        initial: selectedDate, allowClear: false) { picked in
                        if let picked { selectedDate = picked }
                    }
                }
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    private func save() {
        if DebugAdminProbe.dryRun("updateMemberBirthDate \(member.id)") { dismiss(); return }
        isSaving = true
        Task {
            let dateString = Self.formatter.string(from: selectedDate)
            await memberVM.updateMemberBirthDate(
                memberId: member.id,
                birthDate: dateString
            )
            isSaving = false
            dismiss()
        }
    }
}

// MARK: - مربّعات المحطة: أجزاء مشتركة

/// بطاقة «العضو» أعلى مربّعات المحطة — صورته واسمه الكامل (من نكمل بياناته)
private struct StationMemberCard: View {
    let member: FamilyMember

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            DSMemberAvatar(name: member.fullName, avatarUrl: member.avatarUrl,
                           size: DS.Icon.avatar, roleColor: member.roleColor)
                // المتوفّى بالأبيض والأسود (نفس تفاصيل العضو)
                .grayscale(member.isDeceased == true ? 1 : 0)
                .accessibilityHidden(true)   // الصورة زخرفة — الاسم يُقرأ بعدها

            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(L10n.t("العضو", "Member"))
                    .dsFont(.caption)
                    .foregroundColor(DS.Color.textTertiary)
                Text(member.displayFullName)
                    .dsFont(.headlineCompact)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .dsCard(padding: DS.Spacing.md)
        // القارئ الصوتي: «العضو، الاسم» عنصراً واحداً
        .accessibilityElement(children: .combine)
    }
}

private extension View {
    /// صف اختيار: نفس صندوق صفوف المربّعات + إطار بلون الاختيار للصف المختار
    func stationPickRow(selected: Bool, tint: Color) -> some View {
        dsRowBox()
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .strokeBorder(tint.opacity(DS.Opacity.selectedStroke), lineWidth: DS.Border.widthBold)
                    .opacity(selected ? 1 : 0)
            )
    }
}

/// دائرة صورة العضو — مثل شعار مربّعات الإضافة: فارغة بحلقة متقطّعة تدور ببطء
/// وكاميرا، ومختارة بالصورة مع شارة تغيير. نفس اختيار الصورة السابق (بلا قصّ).
private struct StationPhotoCircle: View {
    @Binding var item: PhotosPickerItem?
    let image: UIImage?
    var tint: Color = AppSection.admin.ink
    var size: CGFloat = DS.Icon.photoPicker
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: DS.Spacing.xsm) {
            PhotosPicker(selection: $item, matching: .images) {
                circle
                    .overlay(alignment: .bottomTrailing) { badge }
            }
            .buttonStyle(DSScaleButtonStyle())
            // زر صورة بلا نص (بعد الاختيار) — اسمه للقارئ الصوتي هو نفس التسمية تحته
            .accessibilityLabel(caption)

            Text(caption)
                .dsFont(.footnote)
                .foregroundColor(DS.Color.textTertiary)
                .accessibilityHidden(true)   // مقروءة من اسم الزر أعلاه
        }
        .frame(maxWidth: .infinity)
    }

    private var caption: String {
        image == nil ? L10n.t("اختيار صورة", "Choose photo") : L10n.t("تغيير الصورة", "Change Photo")
    }

    @ViewBuilder
    private var circle: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(tint.opacity(DS.Opacity.selectedStroke), lineWidth: DS.Border.widthBold))
                // «تقليل الحركة»: تظهر الصورة بتلاشٍ فقط بلا تكبير
                .transition(reduceMotion ? .opacity : .scale(scale: 0.6).combined(with: .opacity))
        } else {
            ZStack {
                Circle().fill(tint.opacity(DS.Opacity.tintFillSoft))
                Circle()
                    .strokeBorder(tint.opacity(DS.Opacity.selectedStroke),
                                  style: StrokeStyle(lineWidth: DS.Border.widthBold, dash: [DS.Spacing.xsm, DS.Spacing.xs]))
                    .modifier(DSAmbientSpin())
                VStack(spacing: DS.Spacing.xxs) {
                    Image(systemName: "camera.fill").dsGlyph(DS.Glyph.xxl, weight: .semibold)
                    Text(L10n.t("صورة", "Photo")).dsFont(.badge)
                }
                .foregroundColor(tint)
            }
            .frame(width: size, height: size)
        }
    }

    private var badge: some View {
        Image(systemName: image == nil ? "plus" : "pencil")
            .dsGlyph(DS.Glyph.smCompact, weight: .heavy)
            .foregroundColor(DS.Color.textOnPrimary)
            .frame(width: DS.Icon.photoBadge, height: DS.Icon.photoBadge)
            .background(Circle().fill(tint))
            .overlay(Circle().strokeBorder(DS.Color.background, lineWidth: DS.Border.widthBold))
            .offset(x: DS.Spacing.xxs, y: DS.Spacing.xxs)
    }
}

// MARK: - مربّعات مخصّصة لكل تخصّص في المحطة

/// تحديد جنس العضو — بطاقة العضو ثم خياران بعلامة اختيار
struct EditGenderSheet: View {
    let member: FamilyMember
    let memberVM: MemberViewModel
    @Environment(\.dismiss) private var dismiss
    /// الخيار الذي يُفتح عليه المربّع — اختيار غيره تغيير لم يُحفظ
    private static let startGender = "male"
    @State private var gender: String = EditGenderSheet.startGender
    @State private var isSaving = false
    /// نقد V3 ح١: «أنثى» نقلٌ بين الشجرتين (`move_child_gender` يحذف ملفه) — لا يُنقل من له حساب
    @ObservedObject private var accounts = AdminAccountsStore.shared
    /// م-ج٢: جواب السيرفر `profile_has_login` — nil حتى يصل (أو إن فشل)
    @State private var serverLogin: Bool?
    @State private var checkingLogin = true

    /// له حساب في التطبيق؟ nil = لا يُعرف بعد (السؤال جارٍ أو فشل)
    private var account: Bool? {
        AdminMemberCardLogic.appAccount(serverLogin: serverLogin, role: member.role.rawValue,
                                        isViewer: member.id == memberVM.authVM?.currentUser?.id,
                                        frozen: member.status == .frozen, linkedLogin: false,
                                        inAccountsStore: accounts.info(member.id) != nil)
    }

    /// ما يمنع «أنثى» — nil = لا مانع (و«ذكر» يكتب العمود فقط)
    private var femaleBlock: String? {
        guard gender == "female" else { return nil }
        switch account {
        case true?:
            return L10n.t("له حساب في التطبيق — لا يُنقل إلى شجرة النساء: النقل يحذف ملفه ويبقى حسابه بلا ملف.",
                          "Has an app account — can't move to the women's tree: the move deletes the profile and orphans the account.")
        case nil:
            return checkingLogin
                ? L10n.t("يتحقق من حسابه في التطبيق…", "Checking the app account…")
                : L10n.t("تعذّر التحقق من حسابه في التطبيق — حاول بعد قليل.",
                         "Couldn't check the app account — try again shortly.")
        case false?:
            return nil
        }
    }

    var body: some View {
        DSComposer(
            title: L10n.t("تحديد الجنس", "Set Gender"),
            subtitle: member.shortFullName,
            icon: "person.fill.questionmark",
            tint: DS.Color.actionNavy,
            actionTitle: L10n.t("حفظ", "Save"),
            canSubmit: femaleBlock == nil,
            isBusy: isSaving,
            hasUnsavedChanges: gender != Self.startGender,
            onSubmit: save,
            onCancel: { dismiss() }
        ) {
            StationMemberCard(member: member).dsStaggerIn(0)

            // مختار الجنس الموحّد (`DSGenderPicker`) في البطاقة الواحدة
            DSGenderPicker(selection: $gender)
                .dsCard()
                .dsStaggerIn(1)

            // الأنثى مكانها شجرة النساء — كان الحفظ يكتب العمود فقط فتبقى في شجرة الرجال
            if let femaleBlock {
                // السؤال جارٍ: سطر محايد لا خطأ
                DSNoteCard(femaleBlock, icon: account == nil && checkingLogin ? "hourglass" : "person.crop.circle.badge.exclamationmark",
                           tint: account == nil && checkingLogin ? DS.Color.textTertiary : DS.Color.error)
                    .dsStaggerIn(2)
            } else if gender == "female" {
                DSNoteCard(L10n.t("ستُنقل إلى شجرة النساء تحت أبيها، بدون الرقم والصورة.",
                                  "She will move to the women's tree under her father, without phone and photo."),
                           tint: DS.Color.warning)
                    .dsStaggerIn(2)
            }
            if let failure {
                DSNoteCard(failure, icon: "exclamationmark.triangle.fill", tint: DS.Color.error)
            }
        }
        .task {
            checkingLogin = true
            serverLogin = await memberVM.profileHasLogin(member.id)
            checkingLogin = false
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    @State private var failure: String?

    private func save() {
        guard femaleBlock == nil else { return }
        if DebugAdminProbe.dryRun("gender \(gender) \(member.id)") { dismiss(); return }
        isSaving = true
        failure = nil
        Task {
            if gender == "female" {
                // النقل بين الشجرتين عبر السيرفر (يحفظ الروابط) — مثل «تعديل الابن»
                let moved = await memberVM.moveChildGender(childId: member.id, toGender: "female")
                isSaving = false
                guard moved != nil else {
                    failure = memberVM.errorMessage ?? L10n.t("تعذّر النقل. حاول مرة أخرى.", "Couldn't move. Try again.")
                    return
                }
                if let fatherId = member.fatherId { await memberVM.fetchChildren(for: fatherId) }
                dismiss()
            } else {
                // كان الفشل يُسجَّل فقط ويُغلق المربّع فيبقى الجنس كما هو بصمت — الآن يبقى مفتوحاً برسالة السيرفر (K1)
                memberVM.errorMessage = nil
                let saved = await memberVM.updateMemberGender(memberId: member.id, gender: gender)
                isSaving = false
                guard saved else {
                    failure = memberVM.errorMessage ?? FamilyTreeMenOnly.genderFailureMessage(serverMessage: nil)
                    return
                }
                dismiss()
            }
        }
    }
}

/// تاريخ الوفاة — رأس رمادي هادئ للمتوفّى (مثل «طلب إضافة تاريخ وفاة»)
struct EditDeathDateSheet: View {
    let member: FamilyMember
    let memberVM: MemberViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDate = Date()
    @State private var isSaving = false
    @State private var isUnknown = false
    /// فشل الحفظ — سطر داخل المربّع (يبقى مفتوحاً)
    @State private var failure: String?
    /// ما فُتح عليه المربّع (اليوم + «غير معروف») — «إلغاء» يسأل فقط إذا تغيّر (توصية أبل)
    private let startDay: String
    private let startUnknown: Bool

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    init(member: FamilyMember, memberVM: MemberViewModel) {
        self.member = member
        self.memberVM = memberVM
        _isUnknown = State(initialValue: member.deathDateUnknown == true)
        var start = Date()
        if let existing = member.deathDate, let parsed = Self.formatter.date(from: existing) {
            start = parsed
        }
        _selectedDate = State(initialValue: start)
        startDay = Self.formatter.string(from: start)
        startUnknown = member.deathDateUnknown == true
    }

    /// تغيير «غير معروف»، أو يوم مختلف والتاريخ معروف (العجلة معطّلة مع «غير معروف»)
    private var hasChanges: Bool {
        isUnknown != startUnknown
            || (!isUnknown && Self.formatter.string(from: selectedDate) != startDay)
    }

    var body: some View {
        DSComposer(
            title: L10n.t("تاريخ الوفاة", "Death Date"),
            subtitle: member.shortFullName,
            icon: "calendar.badge.minus",
            tint: DS.Color.textSecondary,
            actionTitle: L10n.t("حفظ", "Save"),
            canSubmit: true,
            isBusy: isSaving,
            hasUnsavedChanges: hasChanges,
            onSubmit: save,
            onCancel: { dismiss() }
        ) {
            StationMemberCard(member: member).dsStaggerIn(0)

            // صفّ التاريخ الموحّد: «بدون تاريخ» = «التاريخ غير معروف» (كان مفتاحاً)، والقلم يفتح المنتقي الموحّد
            DSComposerSection(title: L10n.t("تاريخ الوفاة", "Death Date"),
                              icon: "calendar.badge.minus", tint: DS.Color.textSecondary, index: 1) {
                DSDateFieldRow(icon: "calendar.badge.minus", title: L10n.t("تاريخ الوفاة", "Death Date"),
                               hasDate: !isUnknown, dateText: DSDateText.display(selectedDate)) {
                    // «بدون تاريخ» (= التاريخ غير معروف) داخل المنتقي
                    dsPresentDatePicker(title: L10n.t("تاريخ الوفاة", "Death Date"),
                                        initial: isUnknown ? nil : selectedDate, allowClear: !isUnknown) { picked in
                        if let picked {
                            selectedDate = picked
                            withAnimation(DS.Anim.snappy) { isUnknown = false }
                        } else {
                            withAnimation(DS.Anim.snappy) { isUnknown = true }
                        }
                    }
                }
            }
            if let failure {
                DSNoteCard(failure, icon: "exclamationmark.triangle.fill", tint: DS.Color.error)
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    private func save() {
        if DebugAdminProbe.dryRun("death date \(isUnknown ? "unknown" : "set") \(member.id)") { dismiss(); return }
        isSaving = true
        failure = nil
        memberVM.errorMessage = nil
        Task {
            if isUnknown {
                await memberVM.setDeathDateUnknown(memberId: member.id)
                isSaving = false
                if let err = memberVM.errorMessage {
                    withAnimation(DS.Anim.quick) { failure = err }
                    return
                }
                dismiss()
                return
            }
            let birth = member.birthDate.flatMap { Self.formatter.date(from: $0) }
            let saved = await memberVM.updateMemberData(
                memberId: member.id,
                fullName: member.fullName,
                phoneNumber: member.phoneNumber ?? "",
                birthDate: birth,
                isMarried: member.isMarried ?? false,
                isDeceased: true,
                deathDate: selectedDate,
                isPhoneHidden: member.isPhoneHidden ?? false
            )
            isSaving = false
            guard saved else {
                withAnimation(DS.Anim.quick) { failure = memberVM.errorMessage ?? Self.saveFailed }
                return
            }
            dismiss()
        }
    }

    static let saveFailed = L10n.t("تعذّر الحفظ. تأكد من الاتصال ثم حاول مرة أخرى.", "Couldn't save. Check your connection and try again.")
}

/// صورة العضو — دائرة الصورة (مثل شعار مربّعات الإضافة) و«لا توجد صورة لهذا العضو»
struct EditMemberPhotoSheet: View {
    let member: FamilyMember
    let memberVM: MemberViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var pickedItem: PhotosPickerItem?
    @State private var pickedImage: UIImage?
    @State private var isSaving = false
    /// فشل الحفظ — سطر داخل المربّع (يبقى مفتوحاً)
    @State private var failure: String?

    var body: some View {
        DSComposer(
            title: L10n.t("صورة العضو", "Member Photo"),
            subtitle: member.shortFullName,
            icon: "camera.fill",
            tint: DS.Color.actionNavy,
            actionTitle: L10n.t("حفظ", "Save"),
            canSubmit: pickedImage != nil,
            isBusy: isSaving,
            // صورة مختارة ولم تُرفع بعد → «إلغاء» يسأل قبل التجاهل
            hasUnsavedChanges: pickedImage != nil,
            onSubmit: save,
            onCancel: { dismiss() }
        ) {
            StationMemberCard(member: member).dsStaggerIn(0)

            DSComposerSection(title: L10n.t("الصورة", "Photo"),
                              icon: "photo.fill", tint: AppSection.admin.ink, index: 1) {
                StationPhotoCircle(item: $pickedItem, image: pickedImage)
                noPhotoButton
            }
            if let failure {
                DSNoteCard(failure, icon: "exclamationmark.triangle.fill", tint: DS.Color.error)
            }
        }
        .onChange(of: pickedItem) { item in
            Task {
                guard let data = try? await item?.loadTransferable(type: Data.self),
                      let img = UIImage(data: data) else { return }
                withAnimation(.spring(response: 0.45, dampingFraction: 0.68)) { pickedImage = img }
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    /// لا توجد صورة لهذا العضو — يخرجه من تقارير النقص بلا رفع صورة
    private var noPhotoButton: some View {
        Button {
            markNoPhoto()
        } label: {
            HStack(spacing: DS.Spacing.sm) {
                DSFieldIcon(name: "person.crop.circle.badge.xmark", tint: DS.Color.textSecondary)
                    .accessibilityHidden(true)
                Text(L10n.t("لا توجد صورة لهذا العضو", "No photo exists for this member"))
                    .dsFont(.rowTitle)
                    .foregroundColor(DS.Color.textSecondary)
                Spacer(minLength: 0)
            }
            .dsRowBox()
            .contentShape(Rectangle())
        }
        .buttonStyle(DSScaleButtonStyle())
    }

    private func markNoPhoto() {
        if DebugAdminProbe.dryRun("setAvatarUnavailable \(member.id)") { dismiss(); return }
        isSaving = true
        failure = nil
        memberVM.errorMessage = nil
        Task {
            await memberVM.setAvatarUnavailable(memberId: member.id)
            isSaving = false
            if let err = memberVM.errorMessage {
                withAnimation(DS.Anim.quick) { failure = err }
                return
            }
            dismiss()
        }
    }

    private func save() {
        guard let img = pickedImage else { return }
        if DebugAdminProbe.dryRun("uploadAvatar \(member.id)") { dismiss(); return }
        isSaving = true
        failure = nil
        memberVM.errorMessage = nil
        Task {
            let uploaded = await memberVM.uploadAvatar(image: img, for: member.id)
            isSaving = false
            guard uploaded else {
                withAnimation(DS.Anim.quick) { failure = memberVM.errorMessage ?? EditDeathDateSheet.saveFailed }
                return
            }
            dismiss()
        }
    }
}

// MARK: - Edit Name Sheet

/// تعديل الاسم — مربّع بمنتصف الشاشة بنفس تصميم مربّعات الإضافة (طلب المالك):
/// حقل الاسم الكامل + رقم العضو للتعرّف عليه، و«حفظ» / «إلغاء» أسفله.
struct EditNameSheet: View {
    let member: FamilyMember
    let memberVM: MemberViewModel
    @Environment(\.dismiss) var dismiss
    @State private var fullName: String = ""
    @State private var isSaving = false

    /// الاسم الذي يُفتح عليه المربّع (نفس تعبئة onAppear) — للمقارنة بما كُتب
    private var startName: String {
        let name = member.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        return (name == "بدون اسم") ? "" : name
    }

    var body: some View {
        DSComposer(
            title: L10n.t("تعديل الاسم", "Edit Name"),
            subtitle: L10n.t("عدّل بياناته في الشجرة", "Update the details in the tree"),
            icon: "pencil",
            tint: DS.Color.actionNavy,
            actionTitle: L10n.t("حفظ", "Save"),
            // الحفظ لا يعمل باسم فارغ (نفس شرط saveName)
            canSubmit: !fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            isBusy: isSaving,
            // اسم معدّل لم يُحفظ → «إلغاء» يسأل قبل التجاهل (توصية أبل)
            hasUnsavedChanges: fullName.trimmingCharacters(in: .whitespacesAndNewlines) != startName,
            onSubmit: { Task { await saveName() } },
            onCancel: { dismiss() }
        ) {
            DSComposerSection(title: L10n.t("البيانات الأساسية", "Basic Info"),
                              icon: "person.text.rectangle.fill", tint: AppSection.admin.ink, index: 0) {
                DSComposerField(icon: "person.fill",
                                label: L10n.t("الاسم الكامل", "Full Name"),
                                placeholder: L10n.t("أدخل الاسم الكامل...", "Enter full name..."),
                                text: $fullName)

                if let phone = member.phoneNumber, !phone.isEmpty {
                    phoneRow(phone)
                }
            }
        }
        .onAppear {
            fullName = startName
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    /// رقم العضو للقراءة فقط — يساعد على معرفة صاحب السجل بلا اسم
    private func phoneRow(_ phone: String) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            DSFieldIcon(name: "phone.fill", tint: DS.Color.sea)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(L10n.t("رقم الهاتف", "Phone Number"))
                    .dsFieldFont(.label)
                    .foregroundColor(DS.Color.fieldLabel)
                Text(phone)
                    .dsFieldFont(.fieldValue)
                    .foregroundColor(DS.Color.fieldValue)
                    .monospacedDigit()
                    .environment(\.layoutDirection, .leftToRight)
            }
            Spacer(minLength: 0)
        }
        .dsRowBox()
        .accessibilityElement(children: .combine)   // «رقم الهاتف، …» عنصراً واحداً
    }

    private func saveName() async {
        let trimmed = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if DebugAdminProbe.dryRun("updateMemberName \(member.id)") { dismiss(); return }
        isSaving = true
        await memberVM.updateMemberName(memberId: member.id, fullName: trimmed)
        isSaving = false
        dismiss()
    }
}
