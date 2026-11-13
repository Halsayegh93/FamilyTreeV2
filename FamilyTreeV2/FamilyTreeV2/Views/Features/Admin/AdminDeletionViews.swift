import SwiftUI

// MARK: - «المنجزة»: حذف الإدارة المباشر (§9، طلب المالك ٢٠٢٦-١١-١٣ «والإدارة ما يصل طلب بس إشعار ومنجز»)
//
// صفّ بين الطلبات المعالجة في يومه: «حذف من الشجرة — {الأسماء الثلاثة}» · «بواسطة … · الوقت» · شريحة «حُذف» حمراء،
// ومربّع للعرض فقط: الاسم · كان ابن/بنت · حذفه · الوقت ← «مكانه في الشجرة» (من سجلّ الأماكن) ← «إغلاق».

/// عنصر في «المنجزة»: طلب معالَج أو حذف مباشر
enum AdminHandledEntry: Identifiable {
    case request(AdminRequest)
    case deletion(MemberDeletePlace)

    var id: String {
        switch self {
        case .request(let r): return "r-" + r.id.uuidString
        case .deletion(let d): return "d-" + d.id
        }
    }
}

enum AdminDeletionText {
    static let title = L10n.t("حذف من الشجرة", "Removed from the tree")
    static let chip = L10n.t("حُذف", "Removed")

    static func rowTitle(_ d: MemberDeletePlace) -> String {
        title + " — " + PersonName.firstThree(d.displayFullName)
    }

    static func by(_ d: MemberDeletePlace) -> String {
        let who = d.deletedByName.flatMap { $0.isEmpty ? nil : $0 } ?? AdminTrailText.notRecorded
        return L10n.t("بواسطة ", "By ") + who
    }

    static func time(_ d: MemberDeletePlace) -> String {
        DateHelper.displayDateTime(d.deletedAt) ?? AdminTrailText.notRecorded
    }
}

struct AdminDeletionRow: View {
    let deletion: MemberDeletePlace
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: DS.Spacing.sm) {
                DSFieldIcon(name: "person.badge.minus", tint: DS.Color.error)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(AdminDeletionText.rowTitle(deletion))
                        .dsFont(.adminRowTitle)
                        .foregroundColor(DS.Color.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(AdminDeletionText.by(deletion) + " · " + AdminDeletionText.time(deletion))
                        .dsFont(.adminRowSubtitle)
                        .foregroundColor(DS.Color.textSecondary)
                        .monospacedDigit()
                        .lineLimit(2)
                }
                Spacer(minLength: DS.Spacing.xs)
                // نفس شكل شريحة «قُبل»
                HStack(spacing: DS.Spacing.xxs) {
                    Image(systemName: "trash.fill").dsGlyph(DS.Glyph.xs, weight: .bold)
                    Text(AdminDeletionText.chip).dsFont(.badge)
                }
                .foregroundColor(DS.Color.error.dsReadableGlyph)
                .padding(.horizontal, DS.Spacing.sm)
                .padding(.vertical, DS.Spacing.xxs)
                .background(Capsule().fill(DS.Color.error.opacity(DS.Opacity.tintFill)))
            }
            .padding(DS.Card.padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: DS.Card.radius, style: .continuous).fill(DS.Color.fieldFill))
            .contentShape(Rectangle())
        }
        .buttonStyle(DSPressStyle())
        .accessibilityElement(children: .combine)
    }
}

/// المربّع للعرض فقط — «إغلاق» وحده، والمعاينة بـ«العودة إلى الطلب» وحدها
struct AdminDeletionBox: View {
    let deletion: MemberDeletePlace
    let men: [FamilyMember]
    let onClose: () -> Void

    var body: some View {
        let d = deletion
        let place = TreePlace(tree: d.isWomenTree ? .women : .men, change: .delete(d.memberId),
                              kindLabel: AdminDeletionText.title, tense: .past)
        let son = d.isFemale ? L10n.t("كانت بنت", "Daughter of") : L10n.t("كان ابن", "Son of")
        return DSComposer(
            title: AdminDeletionText.title,
            subtitle: AdminDeletionText.time(d),
            icon: "person.badge.minus",
            tint: DS.Color.actionNavy,
            actionTitle: "",
            showsAction: false,
            cancelTitle: L10n.t("إغلاق", "Close"),
            canSubmit: false,
            onSubmit: {},
            onCancel: onClose
        ) {
            DSComposerSection(title: L10n.t("بيانات الحذف", "Removal info"), icon: "doc.text.fill",
                              tint: AppSection.admin.ink, index: 1) {
                DSTileGrid([
                    .wide(DSFieldTileFace(label: L10n.t("الاسم", "Name"), value: PersonName.firstThree(d.displayFullName),
                                          glyph: .none)),
                    .wide(DSFieldTileFace(label: son, value: d.parentName.flatMap { $0.isEmpty ? nil : $0 } ?? "—",
                                          glyph: .none)),
                    .half(DSFieldTileFace(label: L10n.t("حذفه", "Removed by"),
                                          value: d.deletedByName.flatMap { $0.isEmpty ? nil : $0 } ?? AdminTrailText.notRecorded,
                                          glyph: .none)),
                    .half(DSFieldTileFace(label: L10n.t("الوقت", "Time"), value: AdminDeletionText.time(d), glyph: .none)),
                ])
            }
            AnyView(TreePlaceSection(place: place, index: 2, men: men))
        }
        .onAppear { TreePlaceDeletedLookup.remember(d) }
    }
}
