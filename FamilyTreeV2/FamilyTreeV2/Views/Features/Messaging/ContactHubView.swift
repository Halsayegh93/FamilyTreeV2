import SwiftUI

// MARK: - مركز التواصل
// تبويبان: «مراسلة الإدارة» (النموذج الحالي) و«من نحن» (تعريف بالتطبيق وأصحابه).
struct ContactHubView: View {
    @State private var section: ContactSection = .message

    enum ContactSection: CaseIterable {
        case message, about

        var title: String {
            switch self {
            case .message: return L10n.t("مراسلة الإدارة", "Message Admin")
            case .about:   return L10n.t("من نحن", "About Us")
            }
        }
        var icon: String {
            switch self {
            case .message: return "envelope.fill"
            case .about:   return "info.circle.fill"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            sectionSwitcher
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.top, DS.Spacing.xs)
                .padding(.bottom, DS.Spacing.sm)

            ZStack {
                switch section {
                case .message:
                    MemberContactFormView()
                        .transition(.opacity)
                case .about:
                    AboutFamilyAppView()
                        .transition(.opacity)
                }
            }
            .animation(DS.Anim.quick, value: section)
        }
        .background(DS.Color.background)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    /// مبدّل تبويب منزلق — كبسولة بيضاء تنزلق تحت الخيار المختار
    private var sectionSwitcher: some View {
        HStack(spacing: 0) {
            ForEach(ContactSection.allCases, id: \.self) { s in
                let selected = section == s
                Button {
                    withAnimation(DS.Anim.snappy) { section = s }
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: s.icon)
                            .font(DS.Font.scaled(11, weight: .bold))
                        Text(s.title)
                            .font(DS.Font.scaled(12, weight: .bold))
                    }
                    .foregroundColor(selected ? DS.Color.primary : DS.Color.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: DS.Radius.md - 2, style: .continuous)
                                .fill(DS.Color.surface)
                                .shadow(color: .black.opacity(0.07), radius: 4, y: 1)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(DS.Color.textTertiary.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
    }
}

// MARK: - من نحن — تعريف بالتطبيق وأصحابه

struct AboutFamilyAppView: View {
    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        return b.map { "\(v) (\($0))" } ?? v
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: DS.Spacing.md) {
                heroCard
                purposeCard
                featuresCard
                teamCard
                versionFooter
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.top, DS.Spacing.xs)
            .padding(.bottom, DS.Spacing.xxxxl)
        }
    }

    // البطاقة التعريفية — بهوية الهيدر
    private var heroCard: some View {
        VStack(spacing: DS.Spacing.sm) {
            Image(systemName: "tree.fill")
                .font(DS.Font.scaled(30, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 64, height: 64)
                .background(SwiftUI.Color.white.opacity(0.18))
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(SwiftUI.Color.white.opacity(0.30), lineWidth: 1))

            Text(L10n.t("تطبيق عائلة المحمدعلي", "Al-Mohammad Ali Family App"))
                .font(DS.Font.scaled(17, weight: .black))
                .foregroundColor(.white)

            Text(L10n.t("بيت العائلة الرقمي — يجمعنا مهما تباعدنا",
                        "The family's digital home — keeping us close"))
                .font(DS.Font.scaled(11.5))
                .foregroundColor(SwiftUI.Color.white.opacity(0.85))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.xl)
        .padding(.horizontal, DS.Spacing.lg)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                    .fill(DS.Color.gradientPrimary)
                RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                    .fill(DS.Color.headerVeil)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                .strokeBorder(DS.Color.headerBorder, lineWidth: 1)
        )
        .dsCardShadow()
    }

    private var purposeCard: some View {
        aboutCard(title: L10n.t("لماذا هذا التطبيق", "Why this app"), icon: "heart.fill",
                  color: DS.Color.error) {
            Text(L10n.t(
                "أنشئ هذا التطبيق ليكون مرجع العائلة الواحد: شجرة تحفظ الأنساب جيلاً بعد جيل، وأخبار تجمع مناسباتنا أفراحاً وأتراحاً، وديوانيات تبقي أبواب بيوتنا مفتوحة لبعضنا.",
                "This app is the family's single home: a tree preserving our lineage generation after generation, news gathering our occasions, and diwaniyas keeping our doors open to one another."
            ))
            .font(DS.Font.scaled(12.5))
            .foregroundColor(DS.Color.textPrimary.opacity(0.9))
            .lineSpacing(4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var featuresCard: some View {
        aboutCard(title: L10n.t("ماذا يقدّم", "What it offers"), icon: "square.grid.2x2.fill",
                  color: DS.Color.primary) {
            VStack(spacing: 0) {
                featureRow("tree.fill",       L10n.t("شجرة العائلة كاملة بفروعها ونسائها", "The full family tree"))
                featureRow("newspaper.fill",  L10n.t("أخبار ومناسبات العائلة أولاً بأول", "Family news & events"))
                featureRow("map.fill",        L10n.t("دليل ديوانيات العائلة ومواعيدها", "Diwaniyas guide & schedule"))
                featureRow("books.vertical.fill", L10n.t("مكتبة وأرشيف يحفظ تاريخنا", "A library preserving our history"))
                featureRow("bell.fill",       L10n.t("إشعارات بكل جديد يخص العائلة", "Notifications for all family updates"), last: true)
            }
        }
    }

    private var teamCard: some View {
        aboutCard(title: L10n.t("خلف التطبيق", "Behind the app"), icon: "person.2.fill",
                  color: DS.Color.accent) {
            VStack(spacing: 0) {
                teamRow(icon: "shield.lefthalf.filled",
                        title: L10n.t("إدارة العائلة", "Family Administration"),
                        subtitle: L10n.t("الإشراف على المحتوى والعضويات", "Content & membership oversight"),
                        gradient: true)

                DSDivider()

                teamRow(icon: "hammer.fill",
                        title: L10n.t("تطوير: حسن المحمدعلي", "Developed by Hasan Al-Mohammad Ali"),
                        subtitle: L10n.t("فكرة وتصميم وبرمجة — صدقةً جارية لأهله", "Idea, design & code — a gift to his family"),
                        gradient: false)
            }
        }
    }

    private var versionFooter: some View {
        VStack(spacing: 3) {
            Text(L10n.t("الإصدار \(appVersion)", "Version \(appVersion)"))
                .font(DS.Font.scaled(10, weight: .semibold))
                .foregroundColor(DS.Color.textTertiary)
            Text(L10n.t("صُنع بمحبة للعائلة · \(String(Calendar.current.component(.year, from: Date())))",
                        "Made with love for the family · \(String(Calendar.current.component(.year, from: Date())))"))
                .font(DS.Font.scaled(9.5))
                .foregroundColor(DS.Color.textTertiary.opacity(0.8))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, DS.Spacing.sm)
    }

    // MARK: - لبنات

    private func aboutCard<C: View>(title: String, icon: String, color: Color,
                                    @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(DS.Font.scaled(10, weight: .bold))
                    .foregroundColor(color)
                Text(title)
                    .font(DS.Font.scaled(11, weight: .bold))
                    .foregroundColor(color)
                Spacer(minLength: 0)
            }
            content()
        }
        .padding(DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .strokeBorder(DS.Color.textTertiary.opacity(0.10), lineWidth: 1)
        )
        .dsSubtleShadow()
    }

    private func featureRow(_ icon: String, _ text: String, last: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: icon)
                    .font(DS.Font.scaled(11, weight: .semibold))
                    .foregroundColor(DS.Color.primary)
                    .frame(width: 24, height: 24)
                    .background(DS.Color.primary.opacity(0.08))
                    .clipShape(Circle())
                Text(text)
                    .font(DS.Font.scaled(12))
                    .foregroundColor(DS.Color.textPrimary.opacity(0.9))
                Spacer(minLength: 0)
            }
            .padding(.vertical, 7)
            if !last { DSDivider() }
        }
    }

    private func teamRow(icon: String, title: String, subtitle: String, gradient: Bool) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            ZStack {
                if gradient {
                    Circle().fill(DS.Color.gradientPrimary)
                } else {
                    Circle().fill(DS.Color.accent.opacity(0.12))
                }
                Image(systemName: icon)
                    .font(DS.Font.scaled(13, weight: .bold))
                    .foregroundColor(gradient ? .white : DS.Color.accent)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(DS.Font.scaled(12, weight: .bold))
                    .foregroundColor(DS.Color.textPrimary)
                Text(subtitle)
                    .font(DS.Font.scaled(9.5))
                    .foregroundColor(DS.Color.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 7)
    }
}
