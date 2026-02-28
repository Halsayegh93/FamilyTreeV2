import SwiftUI

struct AdminMembersListView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool

    // تصفية الأعضاء بناءً على البحث بالاسم أو رقم الهاتف
    var filteredMembers: [FamilyMember] {
        let members = authVM.allMembers.filter { $0.role != .pending }
        if searchText.isEmpty {
            return members.sorted { $0.fullName < $1.fullName }
        } else {
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            return members.filter {
                $0.fullName.localizedCaseInsensitiveContains(query)
                || ($0.phoneNumber ?? "").contains(query)
            }
        }
    }

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()
            DSDecorativeBackground()

            VStack(spacing: 0) {

                // 1. شريط البحث المودرن
                searchBar

                // 2. إحصائية سريعة
                HStack {
                    Spacer()
                    HStack(spacing: DS.Spacing.xs) {
                        Text("\(filteredMembers.count)")
                            .font(DS.Font.caption1)
                            .fontWeight(.bold)
                            .foregroundColor(DS.Color.primary)
                        Text("عضو في الشجرة")
                            .font(DS.Font.caption1)
                            .foregroundColor(DS.Color.textSecondary)
                    }
                    .padding(.horizontal, DS.Spacing.xl)
                }
                .padding(.bottom, DS.Spacing.sm)

                // 3. قائمة الأعضاء
                if filteredMembers.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(filteredMembers) { member in
                            MemberAdminRow(member: member)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        }
                    }
                    .listStyle(.plain)
                }
            }
        }
        .navigationTitle("إدارة أعضاء العائلة")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    // MARK: - المكونات الفرعية

    private var searchBar: some View {
        HStack(spacing: DS.Spacing.md) {
            // Gradient icon circle
            ZStack {
                Circle()
                    .fill(DS.Color.gradientPrimary)
                    .frame(width: 36, height: 36)
                Image(systemName: "magnifyingglass")
                    .font(DS.Font.scaled(14, weight: .semibold))
                    .foregroundColor(.white)
            }

            TextField(L10n.t("ابحث بالاسم أو رقم الهاتف...", "Search by name or phone..."), text: $searchText)
                .multilineTextAlignment(.leading)
                .font(DS.Font.body)
                .focused($isSearchFocused)

            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(DS.Color.textTertiary)
                }
            }
        }
        .padding(DS.Spacing.md)
        .background(DS.Color.surface)
        .cornerRadius(DS.Radius.lg)
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg)
                .stroke(isSearchFocused ? DS.Color.primary : Color.clear, lineWidth: 2)
        )
        .dsCardShadow()
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.md)
        .animation(.easeInOut(duration: 0.2), value: isSearchFocused)
    }

    private var emptyState: some View {
        VStack(spacing: DS.Spacing.lg) {
            Spacer()

            ZStack {
                // Layered gradient circles
                Circle()
                    .fill(DS.Color.gridTree.opacity(0.08))
                    .frame(width: 120, height: 120)
                Circle()
                    .fill(DS.Color.gridTree.opacity(0.12))
                    .frame(width: 88, height: 88)
                Circle()
                    .fill(DS.Color.gradientPrimary)
                    .frame(width: 60, height: 60)
                Image(systemName: "person.fill.questionmark")
                    .font(DS.Font.scaled(26, weight: .semibold))
                    .foregroundColor(.white)
            }

            Text(L10n.t("لا يوجد أعضاء بهذا البحث", "No members found"))
                .font(DS.Font.headline)
                .foregroundColor(DS.Color.textSecondary)

            Spacer()
        }
    }
}

// MARK: - بطاقة العضو الإدارية (Component)

struct MemberAdminRow: View {
    let member: FamilyMember

    var body: some View {
        ZStack(alignment: .leading) {
            // NavigationLink مخفي لتفعيل التنقل بدون سهم افتراضي
            NavigationLink(destination: AdminMemberDetailSheet(member: member)) {
                EmptyView()
            }
            .opacity(0)

            HStack(spacing: 0) {
                // Gradient left accent bar
                RoundedRectangle(cornerRadius: DS.Radius.full)
                    .fill(DS.Color.gradientPrimary)
                    .frame(width: 4, height: 50)
                    .padding(.trailing, DS.Spacing.md)

                // الصورة الرمزية أو الحرف الأول — gradient avatar circle
                ZStack {
                    Circle()
                        .fill(DS.Color.gradientPrimary)
                        .frame(width: 50, height: 50)

                    Text(member.fullName.prefix(1))
                        .font(DS.Font.headline)
                        .foregroundColor(.white)
                }
                .padding(.trailing, DS.Spacing.md)

                // معلومات العضو
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text(member.fullName)
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.textPrimary)

                    // وسم الرتبة (Badge)
                    DSRoleBadge(title: member.roleName, color: member.roleColor)
                }

                Spacer()

                // أيقونة توضح إمكانية الدخول للتعديل
                Image(systemName: "chevron.left")
                    .font(DS.Font.scaled(11, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 26, height: 26)
                    .background(DS.Color.primary.opacity(0.7))
                    .clipShape(Circle())
            }
            .padding(DS.Spacing.lg)
            .background(DS.Color.surface)
            .cornerRadius(DS.Radius.xl)
            .dsCardShadow()
        }
        .buttonStyle(.plain)
    }
}
