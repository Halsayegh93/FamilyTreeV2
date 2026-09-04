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

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Image(systemName: greetingSymbol)
                            .font(.system(size: 10, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(timeAccent)
                        Text(timeBasedGreeting)
                            .font(DS.Font.plex(11, weight: .medium))
                            .foregroundColor(DS.Color.textSecondary)
                    }
                    Text(greetingName)
                        .font(DS.Font.plex(17, weight: .bold))
                        .foregroundColor(DS.Color.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                Spacer(minLength: DS.Spacing.sm)

                Image(systemName: "chevron.forward")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DS.Color.textTertiary)
            }
            .padding(.horizontal, DS.Spacing.xs)
            .contentShape(Rectangle())
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
            .frame(width: 40, height: 40)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(timeAccent.opacity(0.5), lineWidth: 2))
        }
    }

    private func initial(_ user: FamilyMember) -> some View {
        ZStack {
            Circle().fill(timeAccent.opacity(0.12))
            Text(String(user.firstName.prefix(1)))
                .font(DS.Font.plex(16, weight: .bold))
                .foregroundColor(timeAccent)
        }
    }

    private var hour: Int { Calendar.current.component(.hour, from: Date()) }

    private var greetingSymbol: String {
        if hour < 12 { return "sun.and.horizon.fill" }
        else if hour < 17 { return "sun.max.fill" }
        else { return "moon.stars.fill" }
    }

    private var timeAccent: Color {
        if hour < 12 { return DS.Color.secondary }
        else if hour < 17 { return DS.Color.primary }
        else { return DS.Color.accent }
    }

    private var timeBasedGreeting: String {
        if hour < 12 { return L10n.t("صباح الخير", "Good morning") }
        else if hour < 17 { return L10n.t("مساء الخير", "Good afternoon") }
        else { return L10n.t("مساء الخير", "Good evening") }
    }

    /// الاسم الأول + اسم العائلة (الأخير) — بلا سلسلة النسب الكاملة
    private var greetingName: String {
        guard let user = authVM.currentUser else { return L10n.t("أهلاً بك", "Welcome") }
        let parts = user.fullName
            .trimmingCharacters(in: .whitespaces)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard let first = parts.first, let last = parts.last, first != last else {
            return user.firstName
        }
        return "\(first) \(last)"
    }
}
