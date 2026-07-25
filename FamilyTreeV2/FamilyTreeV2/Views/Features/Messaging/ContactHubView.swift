import SwiftUI

// MARK: - من نحن — تعريف بالتطبيق وأصحابه

struct AboutFamilySection: View {
    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        return b.map { "\(v) (\($0))" } ?? v
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            DSDivider()
                .padding(.vertical, DS.Spacing.xs)
            heroCard
            purposeCard
            featuresCard
            teamCard
            versionFooter
        }
    }

    // البطاقة التعريفية — بهوية الهيدر
    /// نفس بنية بانر «تواصل مع الإدارة» حرفياً — أيقونة يمين، سطران، بتدرّج الهيدر
    private var heroCard: some View {
        HStack(alignment: .center, spacing: DS.Spacing.md) {
            Image(systemName: "tree.fill")
                .font(DS.Font.scaled(15, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
                .background(SwiftUI.Color.white.opacity(0.20))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t("تطبيق عائلة المحمدعلي", "Al-Mohammad Ali Family App"))
                    .font(DS.Font.scaled(13, weight: .bold))
                    .foregroundColor(.white)
                Text(L10n.t("بيت العائلة الرقمي — يجمعنا مهما تباعدنا",
                            "The family's digital home — keeping us close"))
                    .font(DS.Font.scaled(10))
                    .foregroundColor(SwiftUI.Color.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.md - 2)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .fill(DS.Color.gradientPrimary)
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .fill(DS.Color.headerVeil)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .strokeBorder(DS.Color.headerBorder, lineWidth: 1)
        )
    }

    private var purposeCard: some View {
        aboutCard(title: L10n.t("لماذا هذا التطبيق", "Why this app"), icon: "heart.fill",
                  color: DS.Color.error) {
            Text(L10n.t(
                "أنشئ هذا التطبيق ليكون مرجع العائلة الواحد: شجرة تحفظ الأنساب جيلاً بعد جيل، وأخبار تجمع مناسباتنا أفراحاً وأتراحاً، وديوانيات تبقي أبواب بيوتنا مفتوحة لبعضنا.",
                "This app is the family's single home: a tree preserving our lineage generation after generation, news gathering our occasions, and diwaniyas keeping our doors open to one another."
            ))
            .font(DS.Font.scaled(11))
            .foregroundColor(DS.Color.textPrimary.opacity(0.9))
            .lineSpacing(3)
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

    /// نفس آلية أقسام التواصل: عنوان صغير خارج الصندوق ثم الصندوق نفسه
    private func aboutCard<C: View>(title: String, icon: String, color: Color,
                                    @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            sectionLabel(title, icon: icon)
            content()
                .padding(DS.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DS.Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md)
                        .strokeBorder(DS.Color.textTertiary.opacity(0.15), lineWidth: 1)
                )
        }
    }

    /// مطابق لـ sectionLabel في نموذج التواصل
    private func sectionLabel(_ title: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(DS.Font.scaled(10, weight: .bold))
                .foregroundColor(DS.Color.primary.opacity(0.75))
            Text(title)
                .font(DS.Font.caption1)
                .fontWeight(.bold)
                .foregroundColor(DS.Color.textSecondary)
        }
    }

    private func featureRow(_ icon: String, _ text: String, last: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: icon)
                    .font(DS.Font.scaled(9.5, weight: .semibold))
                    .foregroundColor(DS.Color.primary)
                    .frame(width: 21, height: 21)
                    .background(DS.Color.primary.opacity(0.08))
                    .clipShape(Circle())
                Text(text)
                    .font(DS.Font.scaled(11))
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
                    .font(DS.Font.scaled(11, weight: .bold))
                    .foregroundColor(gradient ? .white : DS.Color.accent)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(DS.Font.scaled(11, weight: .bold))
                    .foregroundColor(DS.Color.textPrimary)
                Text(subtitle)
                    .font(DS.Font.scaled(9))
                    .foregroundColor(DS.Color.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 7)
    }
}
