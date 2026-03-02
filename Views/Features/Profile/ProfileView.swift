import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Binding var selectedTab: Int
    @State private var showingNotifications = false
    @ObservedObject private var langManager = LanguageManager.shared

    @State private var showEditProfile = false
    @State private var showSettings = false
    @State private var showAddChild = false
    @State private var editingChild: FamilyMember? = nil

    var user: FamilyMember? { authVM.currentUser }

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()

                DSDecorativeBackground()

                if let currentUser = user {
                    VStack(spacing: 0) {
                        MainHeaderView(
                            selectedTab: $selectedTab,
                            showingNotifications: $showingNotifications,
                            title: L10n.t("حسابي", "My Profile"),
                            icon: "person.fill"
                        ) {
                            Button(action: { showEditProfile = true }) {
                                Image(systemName: "pencil")
                                    .font(DS.Font.scaled(18, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 44, height: 44)
                                    .background(Color.white.opacity(0.15))
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1.5))
                            }
                            .buttonStyle(BounceButtonStyle())
                        }

                        ScrollView(showsIndicators: false) {
                            VStack(spacing: DS.Spacing.md) {
                                // Profile Header
                                profileHeader(user: currentUser)
                                    .padding(.top, DS.Spacing.md)

                                // Personal Info section
                                personalInfoSection(user: currentUser)

                                // Children section
                                serverSonsSection

                                // General: Gallery, Privacy, Settings, Sign Out
                                generalSection(user: currentUser)
                            }
                            .padding(.bottom, DS.Spacing.xxl)
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
            .sheet(item: $editingChild) { child in EditChildSheet(member: child) }
            .onChange(of: showAddChild) { _, isPresented in
                guard !isPresented, let currentUser = user else { return }
                Task { await authVM.fetchChildren(for: currentUser.id) }
            }
            .onChange(of: editingChild) { _, newValue in
                guard newValue == nil, let currentUser = user else { return }
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
                    .frame(width: 130, height: 130)
                    .shadow(color: .black.opacity(0.1), radius: 8, y: 4)

                if let urlStr = user.avatarUrl, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { img in img.resizable().scaledToFill() }
                    placeholder: { ProgressView() }
                    .frame(width: 120, height: 120).clipShape(Circle())
                } else {
                    Circle()
                        .fill(DS.Color.background)
                        .frame(width: 120, height: 120)
                        .overlay(
                            Text(String(user.firstName.first ?? "P"))
                                .font(DS.Font.scaled(48, weight: .bold))
                                .foregroundColor(DS.Color.primary)
                        )
                }
            }
            
            // User Info
            VStack(spacing: DS.Spacing.xs) {
                Text(user.fullName.isEmpty ? L10n.t("غير معروف", "Unknown") : user.fullName)
                    .font(DS.Font.title3)
                    .foregroundColor(DS.Color.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DS.Spacing.lg)

                Text(user.roleName)
                    .font(DS.Font.scaled(11, weight: .semibold))
                    .foregroundColor(user.roleColor)
                    .padding(.horizontal, DS.Spacing.sm)
                    .padding(.vertical, 3)
                    .background(user.roleColor.opacity(0.10))
                    .clipShape(Capsule())
            }
            .padding(.bottom, DS.Spacing.xs)
        }
    }

    // MARK: - Personal Info Section
    private func personalInfoSection(user: FamilyMember) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            let infoItems = buildInfoItems(user: user)
            let columns = [GridItem(.flexible()), GridItem(.flexible())]

            DSCard(padding: 0) {
                DSSectionHeader(
                    title: L10n.t("المعلومات الشخصية", "Personal Info"),
                    icon: "info.circle.fill",
                    iconColor: DS.Color.primary
                )

                LazyVGrid(columns: columns, spacing: DS.Spacing.md) {
                    ForEach(infoItems, id: \.title) { item in
                        infoGridCell(icon: item.icon, color: item.color, title: item.title, value: item.value)
                    }
                }
                .padding(DS.Spacing.md)

                DSDivider()

                Button(action: { showEditProfile = true }) {
                    HStack(spacing: DS.Spacing.md) {
                        DSIcon("pencil", color: DS.Color.primary)

                        Text(L10n.t("تعديل البيانات", "Edit Info"))
                            .font(DS.Font.calloutBold)
                            .foregroundColor(DS.Color.primary)

                        Spacer()

                        Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                            .font(DS.Font.scaled(11, weight: .bold))
                            .foregroundColor(DS.Color.textTertiary)
                            .frame(width: 26, height: 26)
                            .background(DS.Color.textTertiary.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.vertical, DS.Spacing.md)
                }
                .buttonStyle(DSBoldButtonStyle())
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
    }

    private struct InfoItem {
        let icon: String
        let color: Color
        let title: String
        let value: String
    }

    private func buildInfoItems(user: FamilyMember) -> [InfoItem] {
        var items: [InfoItem] = []

        items.append(InfoItem(
            icon: "phone.fill",
            color: DS.Color.success,
            title: L10n.t("الهاتف", "Phone"),
            value: user.phoneNumber?.isEmpty == false ? KuwaitPhone.display(user.phoneNumber!) : L10n.t("غير محدد", "N/A")
        ))

        if let birth = user.birthDate, !birth.isEmpty {
            items.append(InfoItem(
                icon: "calendar",
                color: DS.Color.primary,
                title: L10n.t("تاريخ الميلاد", "Birthday"),
                value: birth
            ))
        }

        if let married = user.isMarried {
            items.append(InfoItem(
                icon: "heart.fill",
                color: DS.Color.neonPink,
                title: L10n.t("الحالة الاجتماعية", "Status"),
                value: married ? L10n.t("متزوج", "Married") : L10n.t("أعزب", "Single")
            ))
        }

        if let created = user.createdAt, !created.isEmpty {
            items.append(InfoItem(
                icon: "clock.fill",
                color: DS.Color.info,
                title: L10n.t("تاريخ الانضمام", "Joined"),
                value: formatDateOnly(created)
            ))
        }

        return items
    }

    private func infoGridCell(icon: String, color: Color, title: String, value: String) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: icon)
                .font(DS.Font.scaled(16, weight: .bold))
                .foregroundColor(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DS.Font.caption2)
                    .foregroundColor(DS.Color.textTertiary)
                    .lineLimit(1)

                Text(value)
                    .font(DS.Font.caption1)
                    .fontWeight(.bold)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Spacing.sm)
        .background(DS.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .stroke(color.opacity(0.15), lineWidth: 1)
        )
    }

    private static let isoDateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let displayDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private func formatDateOnly(_ dateString: String) -> String {
        guard let date = Self.isoDateFormatter.date(from: dateString) ?? ISO8601DateFormatter().date(from: dateString) else {
            return dateString
        }
        Self.displayDateFormatter.locale = LanguageManager.shared.locale
        return Self.displayDateFormatter.string(from: date)
    }

    // MARK: - Children Section
    private var serverSonsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            DSCard(padding: 0) {
                DSSectionHeader(
                    title: L10n.t("الأبناء", "Children"),
                    icon: "person.2.fill",
                    trailing: authVM.currentMemberChildren.isEmpty ? nil : "\(authVM.currentMemberChildren.count)",
                    iconColor: DS.Color.success
                )

                let columns = [GridItem(.flexible()), GridItem(.flexible())]
                LazyVGrid(columns: columns, spacing: DS.Spacing.md) {
                    ForEach(authVM.currentMemberChildren) { son in
                        Button {
                            editingChild = son
                        } label: {
                            childGridCell(son: son)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }

                    // Add child as last grid cell
                    Button {
                        showAddChild = true
                    } label: {
                        HStack(spacing: DS.Spacing.sm) {
                            Image(systemName: "plus")
                                .font(DS.Font.scaled(16, weight: .bold))
                                .foregroundColor(DS.Color.success)
                                .frame(width: 36, height: 36)
                                .background(DS.Color.success.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))

                            Text(L10n.t("إضافة ابن", "Add Child"))
                                .font(DS.Font.caption1)
                                .fontWeight(.bold)
                                .foregroundColor(DS.Color.success)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(DS.Spacing.sm)
                        .background(DS.Color.surface)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                                .stroke(DS.Color.success.opacity(0.3), lineWidth: 1)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5]))
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(DS.Spacing.md)
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
    }

    private func childGridCell(son: FamilyMember) -> some View {
        let isDeceased = son.isDeceased ?? false
        let isFemale = son.gender?.lowercased() == "female"
        let iconName: String = {
            if isDeceased { return "person.fill.xmark" }
            return isFemale ? "figure.stand.dress" : "person.fill"
        }()
        let iconColor = isDeceased ? DS.Color.error : (isFemale ? DS.Color.neonPink : DS.Color.primary)

        return HStack(spacing: DS.Spacing.sm) {
            Image(systemName: iconName)
                .font(DS.Font.scaled(16, weight: .bold))
                .foregroundColor(iconColor)
                .frame(width: 36, height: 36)
                .background(iconColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(son.firstName.isEmpty ? L10n.t("الاسم", "Name") : son.firstName)
                    .font(DS.Font.caption1)
                    .fontWeight(.bold)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)

                if let birth = son.birthDate, !birth.isEmpty {
                    Text(birth)
                        .font(DS.Font.caption2)
                        .foregroundColor(DS.Color.textSecondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Spacing.sm)
        .background(DS.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .stroke(iconColor.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - General Section (Gallery, Privacy, Settings, Sign Out)
    private func generalSection(user: FamilyMember) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            DSCard(padding: 0) {
                DSSectionHeader(
                    title: L10n.t("اعدادات التطبيق", "App Settings"),
                    icon: "gearshape.2.fill",
                    iconColor: DS.Color.warning
                )
                VStack(spacing: 0) {
                    // Gallery Row
                    NavigationLink(destination: PersonalGalleryView(member: user, isEditable: true)) {
                        HStack(spacing: DS.Spacing.md) {
                            DSIcon("photo.on.rectangle.angled", color: DS.Color.neonBlue)

                            Text(L10n.t("معرض الصور الشخصي", "Personal Gallery"))
                                .font(DS.Font.calloutBold)
                                .foregroundColor(DS.Color.textPrimary)

                            Spacer()

                            Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                                .font(DS.Font.scaled(11, weight: .bold))
                                .foregroundColor(DS.Color.textTertiary)
                                .frame(width: 26, height: 26)
                                .background(DS.Color.textTertiary.opacity(0.1))
                                .clipShape(Circle())
                        }
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.vertical, DS.Spacing.md)
                    }
                    .buttonStyle(DSBoldButtonStyle())

                    DSDivider()

                    // Privacy Row
                    NavigationLink(destination: PrivacySettingsView()) {
                        HStack(spacing: DS.Spacing.md) {
                            DSIcon("lock.shield.fill", color: DS.Color.neonPurple)

                            Text(L10n.t("الخصوصية", "Privacy"))
                                .font(DS.Font.calloutBold)
                                .foregroundColor(DS.Color.textPrimary)

                            Spacer()

                            Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                                .font(DS.Font.scaled(11, weight: .bold))
                                .foregroundColor(DS.Color.textTertiary)
                                .frame(width: 26, height: 26)
                                .background(DS.Color.textTertiary.opacity(0.1))
                                .clipShape(Circle())
                        }
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.vertical, DS.Spacing.md)
                    }
                    .buttonStyle(DSBoldButtonStyle())

                    DSDivider()

                    // Settings Row
                    Button(action: { showSettings = true }) {
                        HStack(spacing: DS.Spacing.md) {
                            DSIcon("gearshape.fill", color: DS.Color.warning)

                            Text(L10n.t("الإعدادات", "Settings"))
                                .font(DS.Font.calloutBold)
                                .foregroundColor(DS.Color.textPrimary)

                            Spacer()

                            Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                                .font(DS.Font.scaled(11, weight: .bold))
                                .foregroundColor(DS.Color.textTertiary)
                                .frame(width: 26, height: 26)
                                .background(DS.Color.textTertiary.opacity(0.1))
                                .clipShape(Circle())
                        }
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.vertical, DS.Spacing.md)
                    }
                    .buttonStyle(DSBoldButtonStyle())

                    DSDivider()

                    // Sign Out Row
                    Button(action: { Task { await authVM.signOut() } }) {
                        HStack(spacing: DS.Spacing.md) {
                            DSIcon("rectangle.portrait.and.arrow.right", color: DS.Color.error)

                            Text(L10n.t("تسجيل الخروج", "Sign Out"))
                                .font(DS.Font.calloutBold)
                                .foregroundColor(DS.Color.error)

                            Spacer()
                        }
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.vertical, DS.Spacing.md)
                    }
                    .buttonStyle(DSBoldButtonStyle())
                }
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.bottom, DS.Spacing.lg)
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
