import SwiftUI

// MARK: - عُدّة الأخبار — إعادة التصميم (طلب المالك ٢٠٢٦-١٠-٢٤: «ملموم أكثر… وابدعلي بالتصميم»)
//
// الخبر يُقرأ كقصاصة جريدة: «ختم النوع» بلونه فوق (مولود أخضر، زواج وردي، وفاة رمادي، تصويت أزرق رصاصي،
// إعلان وخبر كحلي، تهنئة ذهبي — من `NewsTypeHelper`) ← النص ← الصور أو التصويت ← سطر التوقيع
// (الكاتب · الوقت) بجانب الإعجاب والتعليق. مقاسات الأخبار وأدوار خطوطها من هنا فقط.

enum NewsKit {
    // MARK: ختم النوع
    /// ختم النوع في رأس بطاقة الخبر
    static let sealCard: CGFloat = 28
    /// ختم النوع في صفّ مربّع الرئيسية
    static let sealRow: CGFloat = DS.Icon.discSmall
    /// ختم «آخر مناسبة» أعلى مربّع الرئيسية
    static let sealOccasion: CGFloat = DS.Icon.rowCompact

    // MARK: مربّع الرئيسية
    /// مجسّم «الأخبار» (الصحيفة ٦٠×٤٤) مصغّراً في رأس المربّع
    static let homeArtScale: CGFloat = 0.66
    static let homeArtWidth: CGFloat = 40
    static let homeArtHeight: CGFloat = 29
    /// صورة الخبر المصغّرة في طرف الصفّ
    static let homeThumb: CGFloat = DS.Icon.rowCompact
    /// نقطة «جديد» بجانب العنوان
    static let homeNewDot: CGFloat = 9
    /// عدد الأخبار في المعاينة (مع المناسبة إن وُجدت)
    static let homePreviewCount = 3
    /// تُبرز المناسبة (زواج/مولود/وفاة) أعلى المربّع إن نُشرت خلال هذه الأيام
    static let occasionDays = 30

    // MARK: البطاقة
    /// صورة الكاتب في سطر التوقيع
    static let bylineAvatar: CGFloat = 24
    /// «ختم» النوع يُطبع على البطاقة عند دخولها: يبدأ صغيراً مائلاً ثم يستقر
    static let stampFromScale: CGFloat = 0.45
    static let stampFromAngle: Double = -24
    static let stampDelay: Double = 0.14
    /// الفاصل بين أختام البطاقات المتتالية (= فاصل دخول البطاقات)
    static let stampStep: Double = 0.06
    /// نسبة صورة الخبر (العرض ÷ الارتفاع)
    static let mediaAspect: CGFloat = 1.6
    /// تباعد أسطر نص الخبر
    static let bodyLineSpacing: CGFloat = 2.5
    /// أدنى ارتفاع لخيار التصويت
    static let pollRowMinHeight: CGFloat = 42
    /// تأخير نموّ أشرطة التصويت بعد ظهور البطاقة
    static let pollGrowDelay: Double = 0.18
    /// ما مضى عليه أكثر من شهرين يُكتب بتاريخه بدل «قبل…» (طلب المالك)
    static let oldPostMonths = 2

    /// أنواع المناسبات — تُبرز في الرئيسية
    static let occasionTypes: Set<String> = ["زواج", "مولود", "وفاة"]

    /// منشور نُشر بهوية الإدارة — الاسم المحفوظ يختلف عن اسم العضو الحقيقي
    static func isAdminIdentity(_ authorName: String) -> Bool {
        authorName == L10n.t("إدارة العائلة", "Family Admin") || authorName == "إدارة العائلة"
    }

    static func isOld(_ date: Date) -> Bool {
        guard let limit = Calendar.current.date(byAdding: .month, value: -oldPostMonths, to: Date()) else { return false }
        return date < limit
    }

    /// وقت الخبر: «قبل ساعتين»، وما تجاوز الشهرين بتاريخه «٣ مايو ٢٠٢٦»
    static func timeText(_ date: Date) -> String {
        if isOld(date) {
            dateFormatter.locale = L10n.isArabic ? Locale(identifier: "ar") : Locale(identifier: "en_US")
            return dateFormatter.string(from: date)
        }
        relativeFormatter.locale = L10n.isArabic ? Locale(identifier: "ar") : Locale(identifier: "en_US")
        return relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMMM yyyy"
        return f
    }()
}

/// صور خبر تُفتح بملء الشاشة (`ProjectPhotoViewer`) من الصورة المضغوطة
struct NewsMediaViewerItem: Identifiable {
    let id = UUID()
    let urls: [String]
    let start: Int
}

extension DS.TextRole {
    /// اسم النوع فوق الخبر («مولود»، «زواج») — Footnote (١٣) عريض بلون النوع
    static let newsKicker = DS.TextRole(.footnote, weight: .semibold)
    /// اسم الكاتب في سطر التوقيع — Footnote (١٣) شبه عريض
    static let newsByline = DS.TextRole(.footnote, weight: .medium)
}

// MARK: - ختم النوع

/// قرص بلون النوع الخفيف يحمل شارة النوع المرسومة (مهد، خاتمان، هلال، مكبّر صوت…) —
/// والتصنيف المخصّص من الإدارة يبقى برمزه
struct NewsTypeSeal: View {
    let type: String
    var size: CGFloat = NewsKit.sealRow
    var seed: Int = 0
    /// هالة الاحتفال مرة واحدة (صفّ «آخر مناسبة»)
    var celebrate: Bool = false

    var body: some View {
        let color = NewsTypeHelper.color(for: type)
        let icon = NewsTypeHelper.icon(for: type)
        ZStack {
            Circle().fill(color.opacity(DS.Opacity.tintFillStrong))
            Circle().strokeBorder(color.opacity(DS.Opacity.tintStroke), lineWidth: DS.Border.width)
            if FTNewsBadges.hasArt(for: type, currentIcon: icon) {
                FTNewsBadge(type: type, tint: color, seed: seed, celebrate: celebrate)
            } else {
                Image(dsSymbol: icon)
                    .dsGlyph(size >= NewsKit.sealOccasion ? DS.Glyph.md : DS.Glyph.sm)
                    .foregroundColor(color)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// ختم «إدارة العائلة»: قرص كحلي بمكبّر صوت أبيض — نبضة ذهبية واحدة كل ٨ ث (طلب المالك «باعتدال»)
struct NewsAdminSeal: View {
    var size: CGFloat = NewsKit.bylineAvatar
    var seed: Int = 0

    var body: some View {
        ZStack {
            Circle().fill(DS.Color.gradientPrimary)
            FTNewsBadge(type: "إعلان", tint: DS.Color.textOnPrimary, seed: seed, style: .onColor)
        }
        .frame(width: size, height: size)
        .overlay(Circle().strokeBorder(DS.Color.headerBorder, lineWidth: DS.Border.width))
        .accessibilityHidden(true)
    }
}

// MARK: - مؤشّر صغير بعدد (إعجاب، تعليق، أصوات) في سطور المعاينة

struct NewsCountMark: View {
    let icon: String
    let value: Int

    var body: some View {
        HStack(spacing: DS.Spacing.xxs) {
            Image(dsSymbol: icon)
                .dsGlyph(DS.Glyph.xs)
            Text("\(value)")
                .dsFont(.micro)
                .monospacedDigit()
        }
        .foregroundColor(DS.Color.textTertiary)
    }
}
