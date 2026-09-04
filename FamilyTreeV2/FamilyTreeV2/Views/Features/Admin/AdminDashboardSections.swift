import SwiftUI

// MARK: - صندوق العمل — «وش ينتظرني؟»
//
// بطاقة واحدة في أعلى لوحة الإدارة: صف لكل نوع بانتظار المراجعة مع رقمه
// وزر فتح. مصدر واحد للأرقام، فلا تكرار بين «طلبات» و«بانتظار» كما كان.
// لا يظهر صف رقمه صفر، وإن خلت كلها ظهر سطر أخضر واحد.

struct AdminWorkInbox: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var memberVM: MemberViewModel
    @EnvironmentObject private var newsVM: NewsViewModel
    @EnvironmentObject private var adminRequestVM: AdminRequestViewModel
    @EnvironmentObject private var projectsVM: ProjectsViewModel

    /// الديوانيات المعلّقة تأتي من ViewModel اللوحة (ليس كائن بيئة)
    let pendingDiwaniyas: Int

    private struct Row: Identifiable {
        let id: String
        let icon: String
        let color: Color
        let title: String
        let count: Int
        let destination: AnyView
    }

    private var joinRequests: Int { memberVM.allMembers.filter { $0.role == .pending }.count }
    private var memberRequests: Int {
        adminRequestVM.deceasedRequests.count
            + adminRequestVM.childAddRequests.count
            + adminRequestVM.phoneChangeRequests.count
            + adminRequestVM.nameChangeRequests.count
            + adminRequestVM.photoSuggestionRequests.count
    }

    private var rows: [Row] {
        var out: [Row] = []
        func add(_ id: String, _ icon: String, _ color: Color, _ title: String, _ count: Int, _ dest: AnyView) {
            if count > 0 { out.append(.init(id: id, icon: icon, color: color, title: title, count: count, destination: dest)) }
        }
        add("join", "person.badge.plus", DS.Color.success,
            L10n.t("طلبات انضمام", "Join requests"), joinRequests, AnyView(AdminAllRequestsView()))
        add("news", "newspaper.fill", DS.Color.primary,
            L10n.t("أخبار بانتظار الموافقة", "News awaiting approval"), newsVM.pendingNewsRequests.count, AnyView(AdminAllRequestsView()))
        add("messages", "bubble.left.fill", DS.Color.info,
            L10n.t("رسائل غير مقروءة", "Unread messages"), adminRequestVM.unreadContactMessagesCount, AnyView(AdminInboxView()))
        add("reports", "exclamationmark.bubble.fill", DS.Color.error,
            L10n.t("بلاغات", "Reports"), adminRequestVM.newsReportRequests.count, AnyView(AdminAllRequestsView()))
        add("tree", "arrow.triangle.branch", DS.Color.accent,
            L10n.t("تعديلات الشجرة", "Tree edits"), adminRequestVM.treeEditRequests.count, AnyView(AdminTreeEditRequestsView()))
        add("members", "person.text.rectangle", DS.Color.warning,
            L10n.t("طلبات الأعضاء", "Member requests"), memberRequests, AnyView(AdminAllRequestsView()))
        add("diwaniyas", "map.fill", DS.Color.tileContact,
            L10n.t("ديوانيات معلّقة", "Pending diwaniyas"), pendingDiwaniyas, AnyView(AdminAllRequestsView()))
        add("projects", "briefcase.fill", DS.Color.tileProjects,
            L10n.t("مشاريع معلّقة", "Pending projects"), projectsVM.pendingProjects.count, AnyView(AdminAllRequestsView()))
        return out
    }

    private var total: Int { rows.reduce(0) { $0 + $1.count } }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .fill(total > 0 ? AnyShapeStyle(DS.Color.gradientPrimary) : AnyShapeStyle(DS.Color.success))
                        .frame(width: 36, height: 36)
                    Image(systemName: total > 0 ? "tray.full.fill" : "checkmark.seal.fill")
                        .font(DS.Font.scaled(15, weight: .bold))
                        .foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(L10n.t("بانتظارك", "Awaiting you"))
                        .font(DS.Font.scaled(15, weight: .bold))
                        .foregroundColor(DS.Color.textPrimary)
                    Text(total > 0
                         ? L10n.t("\(total) عنصر يحتاج مراجعتك", "\(total) items need your review")
                         : L10n.t("ما فيه شي ينتظر مراجعتك", "Nothing awaiting your review"))
                        .font(DS.Font.scaled(11, weight: .medium))
                        .foregroundColor(DS.Color.textSecondary)
                }
                Spacer()
                if total > 0 {
                    Text("\(total)")
                        .font(DS.Font.scaled(13, weight: .heavy))
                        .foregroundColor(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(DS.Color.error))
                        .contentTransition(.numericText())
                }
            }

            if !rows.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        NavigationLink(destination: row.destination) {
                            HStack(spacing: DS.Spacing.sm) {
                                ZStack {
                                    Circle().fill(row.color.opacity(0.14))
                                    Image(systemName: row.icon)
                                        .font(DS.Font.scaled(12, weight: .bold))
                                        .foregroundColor(row.color)
                                }
                                .frame(width: 30, height: 30)
                                Text(row.title)
                                    .font(DS.Font.scaled(13, weight: .semibold))
                                    .foregroundColor(DS.Color.textPrimary)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(row.count)")
                                    .font(DS.Font.scaled(14, weight: .heavy))
                                    .foregroundColor(row.color)
                                    .contentTransition(.numericText())
                                Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                                    .font(DS.Font.scaled(11, weight: .bold))
                                    .foregroundColor(DS.Color.textTertiary)
                            }
                            .padding(.vertical, DS.Spacing.sm)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(DSScaleButtonStyle())
                        if index < rows.count - 1 {
                            Rectangle().fill(DS.Color.textTertiary.opacity(0.10)).frame(height: 0.5)
                        }
                    }
                }
            }
        }
        .padding(DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .strokeBorder((total > 0 ? DS.Color.primary : DS.Color.success).opacity(0.16), lineWidth: 1)
        )
        .shadow(color: DS.Color.primaryDark.opacity(0.10), radius: 14, x: 0, y: 6)
    }
}

// MARK: - مجموعة بلاطات بعنوان

/// قسم في اللوحة: عنوان + شبكة بلاطات بثلاثة أعمدة.
struct AdminTileSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            DSSectionHeader(title: title, icon: icon)
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: DS.Spacing.sm), count: 3),
                spacing: DS.Spacing.sm
            ) {
                content()
            }
        }
    }
}
