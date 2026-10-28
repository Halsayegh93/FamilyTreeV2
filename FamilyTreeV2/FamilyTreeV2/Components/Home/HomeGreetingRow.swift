import SwiftUI

/// سطر ترحيب مدمج أعلى الرئيسية — صورة العضو + تحية الوقت + الاسم.
/// الضغط على الصورة أو الاسم يفتح تبويب «حسابي».
///
/// بنية مستقلة حتى لا تُثقل نوع واجهة الرئيسية (سبب انهيار سابق).
struct HomeGreetingRow: View {
    @EnvironmentObject private var authVM: AuthViewModel

    let onOpenProfile: () -> Void
    /// ضغطة مطوّلة للمطوّر (DEBUG) — تُمرَّر من الرئيسية إن وُجدت
    var onLongPress: (() -> Void)? = nil

    var body: some View {
        Button(action: onOpenProfile) {
            HStack(alignment: .center, spacing: DS.Spacing.md) {
                avatar

                VStack(alignment: .leading, spacing: DSBox.headerLineGap) {
                    // التحية بلون الوقت — كبسولة صغيرة واضحة فوق الاسم
                    HStack(spacing: DS.Spacing.xs) {
                        // رمز الوقت المرسوم (شمس طالعة · شمس الظهر · شمس على البحر · هلال) يتحرّك بهدوء
                        TrialGreetingGlyph(hour: hour, tint: timeAccent)
                        Text(timeBasedGreeting)
                            .dsFont(.rowTitleCompact)
                    }
                    .foregroundStyle(timeAccent)

                    Text(greetingName)
                        .dsFont(.emptyTitle)
                        .foregroundColor(DS.Color.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .layoutPriority(1)

                // بطاقة بسيطة بلا منظر (طلب المالك ٢٠٢٦-١٠-٠٥ «شيل خله ابسط بكثير»):
                // الصورة · رمز الوقت والتحية · الاسم · السهم
                Spacer(minLength: DS.Spacing.sm)

                Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                    .dsGlyph(DS.Glyph.sm)
                    .foregroundColor(DS.Color.textSecondary)
                    .frame(width: DSBox.compactHeaderIcon, height: DSBox.compactHeaderIcon)
                    .background(Circle().fill(DS.Color.mutedBackground))
            }
            .padding(.horizontal, DS.Spacing.xs)
            // البطاقة الواحدة (`.dsCard`) — نفس بطاقة الأخبار تحتها
            .dsCard()
            .contentShape(RoundedRectangle(cornerRadius: DS.Card.radius, style: .continuous))
        }
        .buttonStyle(DSScaleButtonStyle())
        .accessibilityLabel(L10n.t("حسابي", "My profile"))
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 1.5).onEnded { _ in onLongPress?() }
        )
    }

    @ViewBuilder
    private var avatar: some View {
        if let user = authVM.currentUser {
            Group {
                if let urlStr = user.avatarUrl, let url = URL(string: urlStr) {
                    CachedAsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        initial(user)
                    }
                } else {
                    initial(user)
                }
            }
            .frame(width: DS.Icon.sizeLg - DS.Spacing.sm, height: DS.Icon.sizeLg - DS.Spacing.sm)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(timeAccent.opacity(DS.Opacity.selectedStroke), lineWidth: DS.Border.widthBold))
            .padding(DS.Spacing.xxs)
        }
    }

    private func initial(_ user: FamilyMember) -> some View {
        ZStack {
            Circle().fill(timeAccent.opacity(DS.Opacity.tintFill))
            Text(String(user.firstName.prefix(1)))
                .dsFont(.emptyTitle)
                .foregroundColor(timeAccent)
        }
    }

    private var hour: Int { Calendar.current.component(.hour, from: Date()) }

    /// الصباح من ٤ الفجر — بعد منتصف الليل يبقى «مساء الخير» بالهلال (كان «صباح الخير» بشمس طالعة)
    private var isMorning: Bool { (4..<12).contains(hour) }
    private var isAfternoon: Bool { (12..<17).contains(hour) }

    private var timeAccent: Color {
        if isMorning { return DS.Color.secondary }
        else if isAfternoon { return DS.Color.primary }
        else { return DS.Color.accent }
    }

    private var timeBasedGreeting: String {
        if isMorning { return L10n.t("صباح الخير", "Good morning") }
        else if isAfternoon { return L10n.t("مساء الخير", "Good afternoon") }
        else { return L10n.t("مساء الخير", "Good evening") }
    }

    /// الاسم الأول + العائلة المختارة (الاسم الأخير) — بلا سلسلة النسب الكاملة
    private var greetingName: String {
        guard let user = authVM.currentUser else { return L10n.t("أهلاً بك", "Welcome") }
        return user.displayName
    }
}
