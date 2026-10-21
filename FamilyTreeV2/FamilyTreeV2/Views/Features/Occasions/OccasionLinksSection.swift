import SwiftUI
import UIKit
import Combine
import Supabase

// MARK: - «🔗 رابط الموقع» (طلب المالك ٢٠٢٦-١٠-١٢ «نقدر نسوي قسم الروابط من التطبيق؟»)
//
// نفس قسم الموقع (OccasionLinksPanel): روابط عامة لمولّد البوستات على الموقع بدون تسجيل دخول —
// ما يظهر إلا لمن عنده الرابط. المالك أو المدير ينشئ الرابط ويوقفه ويحذفه (RLS جدول occasion_links)،
// والصفحة العامة almohali.com/o/<slug> تتحقق منه بدالة occasion_link_is_active.

struct OccasionLink: Identifiable, Decodable, Equatable {
    let id: UUID
    let slug: String
    let label: String?
    var is_active: Bool
    let created_at: String
}

@MainActor
final class OccasionLinksModel: ObservableObject {
    @Published private(set) var links: [OccasionLink]?
    @Published var errorText: String?
    @Published private(set) var isWorking = false

    /// عنوان الموقع العام — نفس PUBLIC_SITE في الموقع
    static var publicSite: String { FamilyLinks.website.absoluteString }

    private let supabase = SupabaseConfig.client

    static func url(for link: OccasionLink) -> URL {
        URL(string: "\(publicSite)/o/\(link.slug)")!
    }

    /// ١٠ أحرف بلا الحروف المتشابهة — نفس randomSlug في الموقع
    static func randomSlug() -> String {
        let alphabet = Array("abcdefghijkmnpqrstuvwxyz23456789")
        var rng = SystemRandomNumberGenerator()
        return String((0..<10).map { _ in alphabet[Int(rng.next(upperBound: UInt(alphabet.count)))] })
    }

    func load() async {
        do {
            let rows: [OccasionLink] = try await supabase
                .from("occasion_links")
                .select("id, slug, label, is_active, created_at")
                .order("created_at", ascending: false)
                .execute()
                .value
            links = rows
        } catch {
            links = links ?? []
            errorText = L10n.t("تعذّر جلب الروابط — تأكد من الاتصال.", "Couldn't load links — check your connection.")
        }
    }

    func create(label: String) async -> Bool {
        guard NetworkMonitor.shared.requireOnline() else { return false }
        isWorking = true
        defer { isWorking = false }
        let trimmed = String(label.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        struct Row: Encodable { let slug: String; let label: String? }
        do {
            try await supabase
                .from("occasion_links")
                .insert(Row(slug: Self.randomSlug(), label: trimmed.isEmpty ? nil : trimmed))
                .execute()
            await load()
            return true
        } catch {
            errorText = L10n.t("تعذّر إنشاء الرابط.", "Couldn't create the link.")
            return false
        }
    }

    func setActive(_ link: OccasionLink, _ active: Bool) async {
        guard NetworkMonitor.shared.requireOnline() else { return }
        do {
            try await supabase
                .from("occasion_links")
                .update(["is_active": active])
                .eq("id", value: link.id.uuidString)
                .execute()
            if let i = links?.firstIndex(where: { $0.id == link.id }) {
                withAnimation(DS.Anim.snappy) { links?[i].is_active = active }
            }
        } catch {
            errorText = L10n.t("تعذّر تغيير حالة الرابط.", "Couldn't change the link.")
        }
    }

    func delete(_ link: OccasionLink) async {
        guard NetworkMonitor.shared.requireOnline() else { return }
        do {
            try await supabase
                .from("occasion_links")
                .delete()
                .eq("id", value: link.id.uuidString)
                .execute()
            withAnimation(DS.Anim.snappy) { links?.removeAll { $0.id == link.id } }
        } catch {
            errorText = L10n.t("تعذّر حذف الرابط.", "Couldn't delete the link.")
        }
    }
}

/// القسم نفسه — يوضع أعلى قائمة أنواع البوستات للمالك والمدير
struct OccasionLinksSection: View {
    @StateObject private var model = OccasionLinksModel()
    @State private var label = ""
    @State private var copiedId: UUID?
    @State private var linkToDelete: OccasionLink?
    @State private var expanded = false

    private let tint = DS.Color.accent

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            header
            if expanded {
                createRow
                list
                if let error = model.errorText {
                    Text(error)
                        .dsFont(.footnote)
                        .foregroundColor(DS.Color.error)
                        .transition(.opacity)
                }
            }
        }
        .padding(DS.Spacing.md)
        .dsCard(padding: 0)
        .animation(DS.Anim.snappy, value: expanded)
        .task { await model.load() }
        .dsAlert(L10n.t("حذف الرابط؟", "Delete link?"),
                 isPresented: Binding(get: { linkToDelete != nil }, set: { if !$0 { linkToDelete = nil } }),
                 presenting: linkToDelete) { link in
            Button(L10n.t("حذف", "Delete"), role: .destructive) {
                Task { await model.delete(link) }
                linkToDelete = nil
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { linkToDelete = nil }
        } message: { _ in
            Text(L10n.t("الرابط يوقف عند كل اللي عندهم، ولا يمكن إرجاعه.",
                        "The link stops working for everyone who has it. This can't be undone."))
        }
    }

    // MARK: الرأس — يفتح ويطوي القسم

    private var header: some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            expanded.toggle()
        } label: {
            HStack(spacing: DS.Spacing.sm) {
                DSStateIcon("link", tint: tint, size: DS.Icon.sizeSm)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("رابط الموقع", "Website link"))
                        .dsFont(.headline)
                        .foregroundColor(DS.Color.fieldLabel)
                    Text(L10n.t("نفس المولّد على الموقع بدون تسجيل دخول — لمن عنده الرابط بس",
                                "The same generator on the website without signing in — only for whoever has the link"))
                        .dsFont(.footnote)
                        .foregroundColor(DS.Color.fieldValue)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: DS.Spacing.xs)
                if let count = model.links?.filter(\.is_active).count, count > 0 {
                    DSStatusChip(text: L10n.t("\(count) فعّال", "\(count) active"), tint: DS.Color.success, size: .mini)
                }
                Image(systemName: "chevron.down")
                    .dsGlyph(DS.Glyph.xs)
                    .foregroundColor(DS.Color.textTertiary)
                    .rotationEffect(.degrees(expanded ? 180 : 0))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(DSPressStyle())
        .accessibilityHint(expanded ? L10n.t("يطوي القسم", "Collapses") : L10n.t("يفتح القسم", "Expands"))
    }

    // MARK: إنشاء رابط

    private var createRow: some View {
        HStack(spacing: DS.Spacing.sm) {
            TextField(L10n.t("اسم الرابط (اختياري) — مثال: قروب العائلة", "Link name (optional)"), text: $label)
                .dsFont(.callout)
                .submitLabel(.done)
                .dsFieldChrome()
            DSButton(L10n.t("إنشاء", "Create"), icon: "plus", isLoading: model.isWorking, fullWidth: false) {
                Task {
                    if await model.create(label: label) {
                        label = ""
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
                }
            }
        }
        .transition(.opacity)
    }

    // MARK: الروابط

    @ViewBuilder
    private var list: some View {
        if let links = model.links {
            if links.isEmpty {
                Text(L10n.t("ما فيه روابط للحين — أنشئ رابط وشاركه مع من تبي.",
                            "No links yet — create one and share it."))
                    .dsFont(.footnote)
                    .foregroundColor(DS.Color.textTertiary)
            } else {
                VStack(spacing: DS.Spacing.xsm) {
                    ForEach(links) { link in row(link) }
                }
            }
        } else {
            ProgressView().frame(maxWidth: .infinity)
        }
    }

    private func row(_ link: OccasionLink) -> some View {
        let url = OccasionLinksModel.url(for: link)
        return VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack(spacing: DS.Spacing.xs) {
                Text(link.label ?? L10n.t("رابط بدون اسم", "Unnamed link"))
                    .dsFont(.rowTitle)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: DS.Spacing.xs)
                DSStatusChip(text: link.is_active ? L10n.t("فعّال", "Active") : L10n.t("موقوف", "Stopped"),
                             tint: link.is_active ? DS.Color.success : DS.Color.textTertiary, size: .mini)
            }
            Text(url.absoluteString)
                .dsFont(.footnote)
                .foregroundColor(link.is_active ? tint.dsReadableGlyph : DS.Color.textTertiary)
                .environment(\.layoutDirection, .leftToRight)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .trailing)
            HStack(spacing: DS.Spacing.xs) {
                DSChipButton(copiedId == link.id ? L10n.t("تم النسخ", "Copied") : L10n.t("نسخ", "Copy"),
                             icon: copiedId == link.id ? "checkmark" : "doc.on.doc", tint: tint, size: .small) {
                    UIPasteboard.general.string = url.absoluteString
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    withAnimation(DS.Anim.snappy) { copiedId = link.id }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                        withAnimation(DS.Anim.snappy) { if copiedId == link.id { copiedId = nil } }
                    }
                }
                ShareLink(item: url) {
                    Label(L10n.t("مشاركة", "Share"), systemImage: "square.and.arrow.up")
                        .dsFont(.footnote)
                        .padding(.horizontal, DS.Spacing.sm)
                        .frame(minHeight: DSBox.chipHeightSmall)
                        .foregroundColor(tint.dsReadableGlyph)
                        .background(Capsule().fill(tint.opacity(0.12)))
                }
                .disabled(!link.is_active)
                Spacer(minLength: 0)
                DSChipButton(link.is_active ? L10n.t("إيقاف", "Stop") : L10n.t("تشغيل", "Resume"),
                             icon: link.is_active ? "pause.fill" : "play.fill",
                             tint: link.is_active ? DS.Color.warning : DS.Color.success, size: .small) {
                    UISelectionFeedbackGenerator().selectionChanged()
                    Task { await model.setActive(link, !link.is_active) }
                }
                Button { linkToDelete = link } label: {
                    Image(systemName: "trash")
                        .dsGlyph(DS.Glyph.sm)
                        .foregroundColor(DS.Color.error)
                        .frame(width: 36, height: DSBox.chipHeightSmall)
                        .contentShape(Rectangle())
                }
                .buttonStyle(DSPressStyle())
                .accessibilityLabel(L10n.t("حذف الرابط", "Delete link"))
            }
        }
        .padding(DS.Spacing.sm)
        .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
            .fill(DS.Color.background))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
            .strokeBorder(DS.Color.textTertiary.opacity(0.15), lineWidth: 1))
        .opacity(link.is_active ? 1 : 0.75)
    }
}
