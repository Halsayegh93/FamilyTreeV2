import SwiftUI
import Combine
import Supabase

/// نصوص بطاقة حساب مراجعة Apple — من السيرفر (`my_review_card()` ← `app_config.review_card`)،
/// ولا ترجع إلا لحسابات `review_account_ids` (غيرهم null فتبقى «حسابي» كما هي).
struct ReviewCardInfo: Decodable, Equatable {
    var badgeAr: String?, badgeEn: String?, tag: String?
    var titleAr: String?, titleEn: String?
    var subtitleAr: String?, subtitleEn: String?
    var accessAr: String?, accessEn: String?
    var aboutAr: String?, aboutEn: String?
    var verifiedAr: String?, verifiedEn: String?

    enum CodingKeys: String, CodingKey {
        case badgeAr = "badge_ar", badgeEn = "badge_en", tag
        case titleAr = "title_ar", titleEn = "title_en"
        case subtitleAr = "subtitle_ar", subtitleEn = "subtitle_en"
        case accessAr = "access_ar", accessEn = "access_en"
        case aboutAr = "about_ar", aboutEn = "about_en"
        case verifiedAr = "verified_ar", verifiedEn = "verified_en"
    }

    var badge: String { L10n.t(badgeAr ?? "بطاقة زائر رسمي", badgeEn ?? "Official visitor pass") }
    var title: String { L10n.t(titleAr ?? "فريق مراجعة Apple", titleEn ?? "Apple Review Team") }
    var subtitle: String { L10n.t(subtitleAr ?? "ضيف — غير مرتبط بالشجرة", subtitleEn ?? "Guest — not linked to the tree") }
    /// شارة «معتمد» بجانب الاسم (طلب المالك ٢٠٢٦-١٠-٣٠)
    var verified: String { L10n.t(verifiedAr ?? "معتمد", verifiedEn ?? "Verified") }
    var access: String { L10n.t(accessAr ?? "تصفح وتجربة", accessEn ?? "Browse and try") }
    var about: String? {
        let text = L10n.t(aboutAr ?? "", aboutEn ?? "")
        return text.isEmpty ? nil : text
    }
}

/// يُجلب مرة لكل جلسة (`reset()` عند الخروج)
@MainActor
final class ReviewCardStore: ObservableObject {
    static let shared = ReviewCardStore()
    @Published private(set) var card: ReviewCardInfo?
    /// معرّفات حسابات المراجعة — لشارة «معتمد» (`ReviewVerifiedMark`)
    @Published private(set) var ids: Set<UUID> = []
    private var loadedFor: UUID?
    private var idsLoaded = false

    func isReview(_ id: UUID?) -> Bool { id.map { ids.contains($0) } ?? false }

    func loadIds() async {
        guard !idsLoaded else { return }
        do {
            let list: [UUID] = try await SupabaseConfig.client.rpc("review_account_list").execute().value
            ids = Set(list)
            idsLoaded = true
        } catch {
            if !ErrorHelper.isCancellation(error) { Log.warning("[REVIEW] تعذّر جلب حسابات المراجعة: \(error.localizedDescription)") }
        }
    }

    func load(for userId: UUID) async {
        guard loadedFor != userId else { return }
        do {
            let value: ReviewCardInfo? = try await SupabaseConfig.client.rpc("my_review_card").execute().value
            card = value
            loadedFor = userId
        } catch {
            if !ErrorHelper.isCancellation(error) { Log.warning("[REVIEW] تعذّر جلب بطاقة المراجعة: \(error.localizedDescription)") }
        }
    }

    func reset() {
        card = nil
        loadedFor = nil
        ids = []
        idsLoaded = false
    }
}

/// بطاقة الزائر — مكان رأس الملف و«معلوماتي» في «حسابي» لحساب المراجعة
struct ReviewAccountPassCard: View {
    let info: ReviewCardInfo
    let phone: String?

    // بطاقة كحلية بنصوص كريمية وذهبية، بلا شارة «معتمد» (طلب المالك ٢٠٢٦-١٠-٣١)
    var body: some View {
        VStack(spacing: DS.Spacing.md) {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                HStack {
                    Text(info.badge)
                        .dsFont(.badge)
                        .foregroundColor(DS.Color.accent)
                    Spacer(minLength: DS.Spacing.sm)
                    Text(verbatim: info.tag ?? "APP REVIEW")
                        .dsFont(.badge)
                        .tracking(1.5)
                        .foregroundColor(DS.Color.textOnPrimary.opacity(0.6))
                        .environment(\.layoutDirection, .leftToRight)
                }

                HStack(spacing: DS.Spacing.md) {
                    Image(systemName: "checkmark.rectangle.portrait")
                        .dsGlyph(DS.Glyph.lg)
                        .foregroundColor(DS.Color.navyDeep)
                        .frame(width: DS.Icon.rowLarge + DS.Spacing.sm, height: DS.Icon.rowLarge + DS.Spacing.sm)
                        .background(RoundedRectangle(cornerRadius: DS.Radius.md).fill(DS.Color.accent))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                        passTitle
                        Text(info.subtitle)
                            .dsFont(.subtitle)
                            .foregroundColor(DS.Color.textOnPrimary.opacity(0.75))
                    }
                    Spacer(minLength: 0)
                }

                Rectangle().fill(DS.Color.textOnPrimary.opacity(0.15)).frame(height: DS.Border.width)

                HStack(alignment: .top, spacing: DS.Spacing.md) {
                    // الرقم معزول باتجاه يسار←يمين حتى لا تنقلب «+965» في العربية
                    passField(L10n.t("الجوال", "Phone"),
                              phone.flatMap { $0.isEmpty ? nil : "\u{2066}" + KuwaitPhone.display($0) + "\u{2069}" } ?? "—")
                    passField(L10n.t("الصلاحية", "Access"), info.access)
                }
            }
            .padding(DS.Spacing.lg)
            // كحلي الهوية متدرّج بإطار ذهبي رفيع — نفس الشكل في الفاتح والداكن
            .background(RoundedRectangle(cornerRadius: DS.Radius.lg)
                .fill(LinearGradient(colors: [DS.Color.navyFill, DS.Color.navyDeep],
                                     startPoint: .topLeading, endPoint: .bottomTrailing)))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.lg)
                .stroke(DS.Color.accent.opacity(0.55), lineWidth: DS.Border.width))
            .environment(\.colorScheme, .dark)
            .dsSubtleShadow()
            .accessibilityElement(children: .combine)

            if let about = info.about {
                DSFormCard(L10n.t("عن هذا الحساب", "About this account"), icon: "info.circle.fill",
                           color: DS.Color.primary) {
                    Text(about)
                        .dsFont(.callout)
                        .foregroundColor(DS.Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.top, DS.Spacing.lg)
    }

    private var passTitle: some View {
        Text(info.title)
            .dsFont(.headline)
            .foregroundColor(DS.Color.textOnPrimary)
            .fixedSize(horizontal: true, vertical: false)
    }

    private func passField(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            Text(label)
                .dsFont(.micro)
                .foregroundColor(DS.Color.accent)
            Text(verbatim: value)
                .dsFont(.rowTitle)
                .foregroundColor(DS.Color.textOnPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// شارة «معتمد» بجانب اسم حساب المراجعة أينما ظهر ما فعله (خبر، تعليق، طلب، مشروع…) — للمالك وحده (طلب المالك ٢٠٢٦-١٠-٣٠):
/// المعرّفات من `review_account_list()` مرة لكل جلسة؛ لغير حسابات المراجعة لا يُرسم شيء.
struct ReviewVerifiedMark: View {
    let id: UUID?
    @ObservedObject private var store = ReviewCardStore.shared

    init(_ id: UUID?) { self.id = id }

    var body: some View {
        if store.isReview(id) {
            HStack(spacing: DS.Spacing.xxs) {
                Image(systemName: "checkmark.seal.fill")
                    .dsGlyph(DS.Glyph.xs)
                    .accessibilityHidden(true)
                Text(L10n.t("معتمد", "Verified"))
                    .dsFont(.micro)
            }
            .foregroundColor(DS.Color.accent)
            .padding(.horizontal, DS.Spacing.xsm)
            .padding(.vertical, DS.Spacing.xxs)
            .background(Capsule().fill(DS.Color.accentLight.opacity(DS.Opacity.tintFill)))
            .overlay(Capsule().stroke(DS.Color.accentLight.opacity(DS.Opacity.tintStroke), lineWidth: DS.Border.width))
            .fixedSize()
            .accessibilityLabel(L10n.t("حساب معتمد", "Verified account"))
        }
    }
}
