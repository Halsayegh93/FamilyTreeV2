import SwiftUI

// MARK: - «المنجز اليوم» آخر «الوارد» (الدفعة ب من «نفّذ كل المقترح»، ٢٠٢٦-١٠-٢٠)
//
// صفحة «عرض الكل» (`AdminTodayListView`) حُذفت (D21): «عرض الكل» في «اليوم» يفتح «الوارد» على «بانتظار قرارك»، و«عرض
// المنجز» صار هذا السطر الأخير — ما أُنجز اليوم من مهامك (نفس سجلّ «اليوم» المحفوظ للمستخدم والدور، بلا جلب جديد).
// لا يُرسم بلا منجز.

struct AdminInboxDoneToday: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @State private var open = false

    var body: some View {
        // سجلّ صغير محفوظ على الجهاز (UserDefaults) — يُقرأ مع كل رسم فيتبع ما يُنجز والقائمة مفتوحة
        let records = AdminTodayTaskStore.doneToday(user: authVM.currentUser?.id,
                                                    role: authVM.currentUser?.role.rawValue ?? "")
        if !records.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(DS.Anim.snappy) { open.toggle() }
                } label: {
                    HStack(spacing: DS.Spacing.md) {
                        AdminIconSquare(symbol: "checkmark.circle.fill", tint: DS.Color.success)
                        Text(L10n.t("المنجز اليوم", "Done today"))
                            .dsFont(.hubRow)
                            .foregroundColor(DS.Color.textPrimary)
                        AdminCountChip(count: records.count)
                        Spacer(minLength: DS.Spacing.xs)
                        Image(systemName: "chevron.down")
                            .dsGlyph(DS.Glyph.sm, weight: .semibold)
                            .foregroundColor(DS.Color.textTertiary)
                            .rotationEffect(.degrees(open ? 180 : 0))
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: DS.Icon.tapTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(open ? L10n.t("يخفي المنجز", "Hides what's done") : L10n.t("يعرض المنجز", "Shows what's done"))
                if open {
                    ForEach(records) { record in
                        AdminRowDivider()
                        AdminTodayDoneRow(record: record)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
                .adminCard()
        }
    }
}
