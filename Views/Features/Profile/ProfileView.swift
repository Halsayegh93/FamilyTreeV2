import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Binding var selectedTab: Int
    @State private var showingNotifications = false
    @ObservedObject private var langManager = LanguageManager.shared

    @State private var showEditProfile = false
    @State private var showSettings = false
    @State private var showAddChild = false

    var user: FamilyMember? { authVM.currentUser }

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()

                if let currentUser = user {
                    VStack(spacing: 0) {
                        MainHeaderView(
                            selectedTab: $selectedTab,
                            showingNotifications: $showingNotifications,
                            title: L10n.t("حسابي", "My Profile"),
                            icon: "person.fill",
                            hasDropShadow: false
                        ) {
                            Button(action: { showEditProfile = true }) {
                                Image(systemName: "pencil")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 44, height: 44)
                                    .background(Color.white.opacity(0.15))
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1.5))
                            }
                            .buttonStyle(BounceButtonStyle())
                        }
                        .zIndex(2)

                        ScrollView(showsIndicators: false) {
                            VStack(spacing: DS.Spacing.lg) {
                                // Profile Header
                                profileHeader(user: currentUser)
                                    .padding(.top, DS.Spacing.xl) // Move the picture down slightly

                            // Personal Info section (previously hidden elements)
                            personalInfoSection(user: currentUser)

                            // Children section
                            serverSonsSection

                            // Settings
                            settingsAccessCard

                            // Sign out
                            signOutButton
                        }
                        .padding(.bottom, DS.Spacing.xxxl)
                        } // closes ScrollView
                        .onAppear {
                            Task {
                                await authVM.fetchChildren(for: currentUser.id)
                            }
                        }
                    } // closes VStack
                } else {
                    ProgressView(L10n.t("جاري تحميل الملف...", "Loading profile..."))
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showEditProfile) { if let c = user { EditProfileView(member: c) } }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showAddChild) { if let c = user { AddChildSheet(member: c) } }
            .onChange(of: showAddChild) { _, isPresented in
                guard !isPresented, let currentUser = user else { return }
                Task { await authVM.fetchChildren(for: currentUser.id) }
            }
        }
        .environment(\.layoutDirection, langManager.layoutDirection)
    }

    // MARK: - Profile Header — Avatar & Info
    private func profileHeader(user: FamilyMember) -> some View {
        VStack(spacing: DS.Spacing.sm) {
            // Overlapping Avatar
            ZStack {
                Circle()
                    .fill(DS.Color.surface)
                    .frame(width: 110, height: 110)
                    .shadow(color: .black.opacity(0.1), radius: 8, y: 4)

                if let urlStr = user.avatarUrl, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { img in img.resizable().scaledToFill() }
                    placeholder: { ProgressView() }
                    .frame(width: 100, height: 100).clipShape(Circle())
                } else {
                    Circle()
                        .fill(DS.Color.background)
                        .frame(width: 100, height: 100)
                        .overlay(
                            Text(String(user.firstName.first ?? "P"))
                                .font(.system(size: 40, weight: .bold))
                                .foregroundColor(DS.Color.primary)
                        )
                }
            }
            
            // User Info
            VStack(spacing: DS.Spacing.xs) {
                Text(user.fullName.isEmpty ? L10n.t("غير معروف", "Unknown") : user.fullName)
                    .font(DS.Font.title2)
                    .foregroundColor(DS.Color.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DS.Spacing.lg)

                DSRoleBadge(title: user.roleName, color: user.roleColor)
            }
            .padding(.bottom, DS.Spacing.md)
        }
    }

    // MARK: - Personal Info Section (Hidden Elements Revealed)
    private func personalInfoSection(user: FamilyMember) -> some View {
        DSCard {
            VStack(spacing: 0) {
                HStack {
                    DSIcon("info.circle.fill", color: DS.Color.primary, iconSize: 13)
                    Text(L10n.t("المعلومات الشخصية", "Personal Info"))
                        .font(DS.Font.headline)
                    Spacer()
                    Button(action: { showEditProfile = true }) {
                        Image(systemName: "pencil")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .padding(DS.Spacing.xs + 2)
                            .background(DS.Color.gradientPrimary)
                            .clipShape(Circle())
                            .dsGlowShadow()
                    }
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.md)

                DSDivider()

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DS.Spacing.sm) {
                    gridItem(
                        title: L10n.t("رقم الهاتف", "Phone Number"),
                        value: user.phoneNumber?.isEmpty == false ? user.phoneNumber! : L10n.t("غير محدد", "Not specified"),
                        icon: "phone.fill"
                    )
                    
                    if let birth = user.birthDate, !birth.isEmpty {
                        gridItem(
                            title: L10n.t("تاريخ الميلاد", "Birth Date"),
                            value: birth,
                            icon: "calendar"
                        )
                    }

                    if let married = user.isMarried {
                        gridItem(
                            title: L10n.t("الحالة الاجتماعية", "Marital Status"),
                            value: married ? L10n.t("متزوج", "Married") : L10n.t("أعزب", "Single"),
                            icon: "heart.fill"
                        )
                    }

                    if let created = user.createdAt, !created.isEmpty {
                        gridItem(
                            title: L10n.t("تاريخ الانضمام", "Join Date"),
                            value: formatDateOnly(created),
                            icon: "clock.fill"
                        )
                    }
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.md)
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
    }

    private func gridItem(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(DS.Color.primary)
                Text(title)
                    .font(DS.Font.caption1)
                    .foregroundColor(DS.Color.textSecondary)
            }
            Text(value)
                .font(DS.Font.subheadline)
                .fontWeight(.bold)
                .foregroundColor(DS.Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Spacing.md)
        .background(DS.Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
    }

    private func formatDateOnly(_ dateString: String) -> String {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = isoFormatter.date(from: dateString) ?? ISO8601DateFormatter().date(from: dateString) else {
            return dateString
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = LanguageManager.shared.locale
        return formatter.string(from: date)
    }

    // MARK: - Children Section
    private var serverSonsSection: some View {
        DSCard {
            VStack(spacing: 0) {
                HStack {
                    DSIcon("person.2.fill", color: DS.Color.primary, iconSize: 13)
                    Text(L10n.t("الأبناء", "Children"))
                        .font(DS.Font.headline)
                    Spacer()
                    Button(action: { showAddChild = true }) {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(DS.Color.gradientPrimary)
                            .clipShape(Circle())
                    }
                    .buttonStyle(BounceButtonStyle())
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.md)

                DSDivider()

                if authVM.currentMemberChildren.isEmpty {
                    VStack(spacing: DS.Spacing.sm) {
                        Image(systemName: "person.2.slash")
                            .font(.system(size: 22))
                            .foregroundColor(DS.Color.textTertiary)
                        Text(L10n.t("لا يوجد أبناء مضافين حالياً", "No children added yet"))
                            .font(DS.Font.callout)
                            .foregroundColor(DS.Color.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(DS.Spacing.xl)
                } else {
                    ForEach(authVM.currentMemberChildren) { son in
                        NavigationLink(destination: EditChildSheet(member: son)) {
                            HStack(spacing: DS.Spacing.md) {
                                ZStack {
                                    Circle()
                                        .fill(DS.Color.primary.opacity(0.10))
                                        .frame(width: 30, height: 30)
                                    Text(String(son.firstName.first ?? "A"))
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(DS.Color.primary)
                                }
                                Text(son.firstName.isEmpty ? L10n.t("الاسم", "Name") : son.firstName)
                                    .font(DS.Font.subheadline)
                                    .foregroundColor(DS.Color.textPrimary)
                                Spacer()
                                Image(systemName: "pencil")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 24, height: 24)
                                    .background(DS.Color.gradientPrimary)
                                    .clipShape(Circle())
                            }
                            .padding(.horizontal, DS.Spacing.lg)
                            .padding(.vertical, DS.Spacing.sm)
                        }
                        .buttonStyle(PlainButtonStyle())

                        if son.id != authVM.currentMemberChildren.last?.id { DSDivider() }
                    }
                }
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
    }

    // MARK: - Settings
    private var settingsAccessCard: some View {
        Button(action: { showSettings = true }) {
            DSCard {
                DSActionRow(
                    title: L10n.t("الإعدادات", "Settings"),
                    subtitle: L10n.t("التنبيهات، المظهر، اللغة", "Notifications, appearance, language"),
                    icon: "gearshape.fill",
                    color: DS.Color.warning
                )
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, DS.Spacing.lg)
    }

    // MARK: - Sign Out
    private var signOutButton: some View {
        Button(action: { Task { await authVM.signOut() } }) {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: "power")
                    .font(.system(size: 16, weight: .bold))
                Text(L10n.t("تسجيل الخروج", "Sign Out"))
                    .font(DS.Font.headline)
            }
            .foregroundColor(DS.Color.error)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Spacing.md)
            .background(DS.Color.error.opacity(0.10))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg)
                    .stroke(DS.Color.error.opacity(0.25), lineWidth: 1.5)
            )
            .cornerRadius(DS.Radius.lg)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.bottom, DS.Spacing.xxl)
    }
}

// MARK: - RoundedShape
private struct RoundedShape: Shape {
    var corners: UIRectCorner
    var radius: CGFloat
    
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}
