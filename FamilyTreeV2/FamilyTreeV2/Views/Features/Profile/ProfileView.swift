import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @Binding var selectedTab: Int
    @State private var showingNotifications = false
    @ObservedObject private var langManager = LanguageManager.shared

    @State private var showEditProfile = false
    @State private var showQRCode = false
    @State private var showQRScanner = false
    @State private var showSignOutConfirm = false

    @State private var showAddChild = false
    @State private var editingChild: FamilyMember? = nil
    @State private var isReorderingChildren = false
    @State private var appeared = false
    @State private var isLoadingChildren = true

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
                            subtitle: L10n.t("الملف الشخصي والإعدادات", "Profile and settings"),
                            icon: "person.fill",
                            backgroundGradient: DS.Color.gradientPrimary
                        ) {
                            HStack(spacing: DS.Spacing.sm) {
                                // زر تغيير اللغة
                                DSIconButton(icon: "globe", iconColor: DS.Color.textOnPrimary) {
                                    langManager.selectedLanguage = langManager.selectedLanguage == "ar" ? "en" : "ar"
                                }
                                .accessibilityLabel(L10n.t("تغيير اللغة", "Change Language"))

                                // زر تسجيل الخروج
                                DSIconButton(icon: "rectangle.portrait.and.arrow.right", iconColor: DS.Color.textOnPrimary) {
                                    showSignOutConfirm = true
                                }
                                .accessibilityLabel(L10n.t("تسجيل الخروج", "Sign Out"))
                            }
                        }

                        ScrollView(showsIndicators: false) {
                            VStack(spacing: DS.Spacing.md) {
                                // Profile Header
                                profileHeader(user: currentUser)
                                    .padding(.top, DS.Spacing.md)
                                    .opacity(appeared ? 1 : 0)
                                    .offset(y: appeared ? 0 : 20)

                                // Personal Info section
                                personalInfoSection(user: currentUser)
                                    .opacity(appeared ? 1 : 0)
                                    .offset(y: appeared ? 0 : 25)

                                // المفضلة
                                favoritesSection
                                    .opacity(appeared ? 1 : 0)
                                    .offset(y: appeared ? 0 : 28)

                                // Children section
                                serverSonsSection
                                    .opacity(appeared ? 1 : 0)
                                    .offset(y: appeared ? 0 : 30)

                                // General: Gallery, Privacy, Settings, Sign Out
                                generalSection(user: currentUser)
                                    .opacity(appeared ? 1 : 0)
                                    .offset(y: appeared ? 0 : 35)
                            }
                            .padding(.bottom, DS.Spacing.xxl)
                        } // closes ScrollView
                        .task {
                            isLoadingChildren = true
                            await memberVM.fetchChildren(for: currentUser.id)
                            isLoadingChildren = false
                        }
                        .onAppear {
                            guard !appeared else { return }
                            withAnimation(DS.Anim.smooth.delay(0.1)) { appeared = true }
                        }
                    } // closes VStack
                } else {
                    ProgressView(L10n.t("جاري تحميل الملف...", "Loading profile..."))
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showEditProfile) { if let c = user { EditProfileView(member: c) } }
            .sheet(isPresented: $showQRCode) {
                if let c = user {
                    QRCodeSheet(member: c)
                        .fixedSize(horizontal: false, vertical: true)
                        .presentationDetents([.height(420)])
                }
            }
            .fullScreenCover(isPresented: $showQRScanner) { QRScannerView(selectedTab: $selectedTab) }
            .sheet(isPresented: $showAddChild) { if let c = user { AddChildSheet(member: c) } }
            .confirmationDialog(
                L10n.t("تسجيل الخروج", "Sign Out"),
                isPresented: $showSignOutConfirm,
                titleVisibility: .visible
            ) {
                Button(L10n.t("تسجيل الخروج", "Sign Out"), role: .destructive) {
                    Task { await authVM.signOut() }
                }
                Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
            } message: {
                Text(L10n.t("هل تريد الخروج من حسابك على هذا الجهاز؟", "Do you want to sign out of your account on this device?"))
            }
            .sheet(item: $editingChild) { child in EditChildSheet(member: child) }
            .onChange(of: showAddChild) { isPresented in
                guard !isPresented, let currentUser = user else { return }
                Task { await memberVM.fetchChildren(for: currentUser.id) }
            }
            .onChange(of: editingChild) { newValue in
                guard newValue == nil, let currentUser = user else { return }
                Task { await memberVM.fetchChildren(for: currentUser.id) }
            }

        }
        .environment(\.layoutDirection, langManager.layoutDirection)
    }

    // MARK: - Profile Header — Avatar & Info
    private func profileHeader(user: FamilyMember) -> some View {
        VStack(spacing: 0) {
            // الصورة الشخصية
            ZStack {
                // حلقة خارجية متوهجة
                Circle()
                    .fill(DS.Color.surface)
                    .frame(width: 110, height: 110)
                    .dsGlowShadow()
                
                // حلقة gradient
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [DS.Color.primary, DS.Color.secondary, DS.Color.primary],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        lineWidth: 3
                    )
                    .frame(width: 106, height: 106)

                if let urlStr = user.avatarUrl, let url = URL(string: urlStr) {
                    CachedAsyncImage(url: url) { img in img.resizable().scaledToFill() }
                    placeholder: { ProgressView() }
                    .frame(width: 98, height: 98).clipShape(Circle())
                } else {
                    Circle()
                        .fill(DS.Color.background)
                        .frame(width: 98, height: 98)
                        .overlay(
                            Text(String(user.firstName.first ?? "P"))
                                .font(DS.Font.scaled(40, weight: .bold))
                                .foregroundColor(DS.Color.primary)
                        )
                }
            }
            .padding(.top, DS.Spacing.xl)
            
            // User Info
            VStack(spacing: DS.Spacing.sm) {
                Text(user.fullName.isEmpty ? L10n.t("غير معروف", "Unknown") : user.fullName)
                    .font(DS.Font.title2)
                    .fontWeight(.bold)
                    .foregroundColor(DS.Color.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DS.Spacing.lg)

                // مستوى الحساب + عدد الأبناء
                HStack(spacing: DS.Spacing.sm) {
                    // الرتبة
                    HStack(spacing: DS.Spacing.xs) {
                        Circle()
                            .fill(user.roleColor)
                            .frame(width: 8, height: 8)
                        Text(user.roleName)
                            .font(DS.Font.scaled(11, weight: .bold))
                            .foregroundColor(user.roleColor)
                    }
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.vertical, DS.Spacing.xs)
                    .background(user.roleColor.opacity(0.10))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(user.roleColor.opacity(0.2), lineWidth: 1))

                    // عدد الأبناء
                    if !memberVM.currentMemberChildren.isEmpty {
                        HStack(spacing: DS.Spacing.xs) {
                            Image(systemName: "person.2.fill")
                                .font(DS.Font.scaled(10, weight: .semibold))
                            Text("\(memberVM.currentMemberChildren.count) " + L10n.t("أبناء", "children"))
                                .font(DS.Font.scaled(11, weight: .bold))
                        }
                        .foregroundColor(DS.Color.textSecondary)
                        .padding(.horizontal, DS.Spacing.sm)
                        .padding(.vertical, DS.Spacing.xs)
                        .background(DS.Color.textSecondary.opacity(0.10))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(DS.Color.textSecondary.opacity(0.2), lineWidth: 1))
                    }
                }
            }
            .padding(.top, DS.Spacing.md)
            .padding(.bottom, DS.Spacing.sm)
        }
    }

    // MARK: - Personal Info Section
    private func personalInfoSection(user: FamilyMember) -> some View {
        let infoItems = buildInfoItems(user: user)
        let columns = [GridItem(.flexible()), GridItem(.flexible())]

        return DSCard(padding: 0) {
            // هيدر مخصص مع أزرار QR
            VStack(spacing: 0) {
                HStack(spacing: DS.Spacing.sm) {
                    // عنوان القسم
                    HStack(spacing: DS.Spacing.xs) {
                        Image(systemName: "info.circle.fill")
                            .font(DS.Font.scaled(12, weight: .bold))
                            .foregroundColor(DS.Color.textSecondary)
                        Text(L10n.t("المعلومات الشخصية", "Personal Info"))
                            .font(DS.Font.scaled(13, weight: .semibold))
                            .foregroundColor(DS.Color.textSecondary)
                    }
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.vertical, DS.Spacing.xs + 2)
                    .background(DS.Color.textSecondary.opacity(0.08))
                    .clipShape(Capsule())

                    Spacer()

                    // زر مسح QR
                    Button(action: { showQRScanner = true }) {
                        HStack(spacing: DS.Spacing.xs) {
                            Image(systemName: "camera.viewfinder")
                                .font(DS.Font.scaled(11, weight: .bold))
                            Text(L10n.t("مسح", "Scan"))
                                .font(DS.Font.scaled(11, weight: .bold))
                        }
                        .foregroundColor(DS.Color.accent)
                        .padding(.horizontal, DS.Spacing.sm)
                        .padding(.vertical, DS.Spacing.xs)
                        .background(DS.Color.accent.opacity(0.1))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(DSScaleButtonStyle())
                    .accessibilityLabel(L10n.t("مسح رمز QR", "Scan QR Code"))

                    // زر عرض QR
                    Button(action: { showQRCode = true }) {
                        HStack(spacing: DS.Spacing.xs) {
                            Image(systemName: "qrcode")
                                .font(DS.Font.scaled(11, weight: .bold))
                            Text(L10n.t("كودي", "My QR"))
                                .font(DS.Font.scaled(11, weight: .bold))
                        }
                        .foregroundColor(DS.Color.secondary)
                        .padding(.horizontal, DS.Spacing.sm)
                        .padding(.vertical, DS.Spacing.xs)
                        .background(DS.Color.secondary.opacity(0.1))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(DSScaleButtonStyle())
                    .accessibilityLabel(L10n.t("عرض كودي", "Show My QR"))
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.top, DS.Spacing.md)
                .padding(.bottom, DS.Spacing.sm)

                DSDivider()
            }

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
                    chevronCircle
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.md)
            }
            .buttonStyle(DSBoldButtonStyle())
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
            color: DS.Color.textSecondary,
            title: L10n.t("الهاتف", "Phone"),
            value: user.phoneNumber.flatMap { $0.isEmpty ? nil : KuwaitPhone.display($0) } ?? L10n.t("غير محدد", "N/A")
        ))

        if let birth = user.birthDate, !birth.isEmpty {
            items.append(InfoItem(
                icon: "calendar",
                color: DS.Color.textSecondary,
                title: L10n.t("تاريخ الميلاد", "Birthday"),
                value: birth
            ))
        }

        if let married = user.isMarried {
            items.append(InfoItem(
                icon: "heart.fill",
                color: DS.Color.textSecondary,
                title: L10n.t("الحالة الاجتماعية", "Status"),
                value: married ? L10n.t("متزوج", "Married") : L10n.t("أعزب", "Single")
            ))
        }

        if let created = user.createdAt, !created.isEmpty {
            items.append(InfoItem(
                icon: "clock.fill",
                color: DS.Color.textSecondary,
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
    // MARK: - المفضلة
    @ViewBuilder
    private var favoritesSection: some View {
        let favIds = FavoritesManager.shared.favoriteIds
        let favMembers = favIds.compactMap { id in memberVM.member(byId: id) }

        if !favMembers.isEmpty {
            DSCard(padding: 0) {
                DSSectionHeader(
                    title: L10n.t("المفضلة", "Favorites"),
                    icon: "heart.fill",
                    iconColor: DS.Color.error
                )

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DS.Spacing.md) {
                        ForEach(favMembers, id: \.id) { member in
                            NavigationLink(destination: MemberDetailsView(member: member)) {
                                VStack(spacing: DS.Spacing.xs) {
                                    DSMemberAvatar(name: member.firstName, avatarUrl: member.avatarUrl, size: 50, roleColor: member.roleColor)

                                    Text(member.firstName)
                                        .font(DS.Font.caption2)
                                        .fontWeight(.semibold)
                                        .foregroundColor(DS.Color.textPrimary)
                                        .lineLimit(1)
                                }
                                .frame(width: 60)
                            }
                        }
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.vertical, DS.Spacing.sm)
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
        }
    }

    private var serverSonsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            DSCard(padding: 0) {
                // Header مع زر الترتيب
                HStack {
                    DSSectionHeader(
                        title: L10n.t("الأبناء", "Children"),
                        icon: "person.2.fill",
                        iconColor: DS.Color.textSecondary
                    )

                    Spacer()

                    if memberVM.currentMemberChildren.count > 1 {
                        Button {
                            withAnimation(DS.Anim.snappy) {
                                isReorderingChildren.toggle()
                            }
                        } label: {
                            HStack(spacing: DS.Spacing.xs) {
                                Image(systemName: isReorderingChildren ? "checkmark" : "arrow.up.arrow.down")
                                    .font(DS.Font.scaled(11, weight: .bold))
                                Text(isReorderingChildren ? L10n.t("تم", "Done") : L10n.t("ترتيب", "Sort"))
                                    .font(DS.Font.scaled(11, weight: .bold))
                            }
                            .foregroundColor(isReorderingChildren ? DS.Color.success : DS.Color.primary)
                            .padding(.horizontal, DS.Spacing.md)
                            .padding(.vertical, DS.Spacing.xs + 2)
                            .background(
                                (isReorderingChildren ? DS.Color.success : DS.Color.primary).opacity(0.1)
                            )
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, DS.Spacing.lg)
                    }
                }

                if isLoadingChildren && memberVM.currentMemberChildren.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView()
                            .tint(DS.Color.primary)
                            .padding(DS.Spacing.lg)
                        Spacer()
                    }
                } else if isReorderingChildren {
                    // وضع الترتيب — قائمة عمودية مع أسهم
                    childrenReorderView
                } else {
                    // الوضع العادي — شبكة
                    childrenGridView
                }
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
    }

    // MARK: - Grid View (الوضع العادي)
    private var childrenGridView: some View {
        VStack(spacing: 0) {
            let columns = [GridItem(.flexible()), GridItem(.flexible())]
            LazyVGrid(columns: columns, spacing: DS.Spacing.md) {
                ForEach(memberVM.currentMemberChildren, id: \.id) { son in
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
                            .foregroundColor(DS.Color.primary)
                            .frame(width: 36, height: 36)
                            .background(DS.Color.primary.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))

                        Text(L10n.t("إضافة ابن", "Add Child"))
                            .font(DS.Font.caption1)
                            .fontWeight(.bold)
                            .foregroundColor(DS.Color.primary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DS.Spacing.sm)
                    .background(DS.Color.surface)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                            .stroke(DS.Color.primary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [5]))
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(DS.Spacing.md)
        }
    }

    private func childGridCell(son: FamilyMember) -> some View {
        let info = childIconInfo(for: son)

        return HStack(spacing: DS.Spacing.sm) {
            childAvatarView(for: son, iconFont: 16, size: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(son.firstName.isEmpty ? L10n.t("الاسم", "Name") : son.firstName)
                    .font(DS.Font.caption1)
                    .fontWeight(.bold)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)

                HStack(spacing: DS.Spacing.xs) {
                    if let birth = son.birthDate, !birth.isEmpty {
                        Text(birth)
                            .font(DS.Font.caption2)
                            .foregroundColor(DS.Color.textSecondary)
                            .lineLimit(1)
                    }
                    if son.isDeceased ?? false {
                        Text(L10n.t("متوفى", "Deceased"))
                            .font(DS.Font.scaled(8, weight: .bold))
                            .foregroundColor(DS.Color.textOnPrimary)
                            .padding(.horizontal, DS.Spacing.xs)
                            .padding(.vertical, 1)
                            .background(DS.Color.error.opacity(0.8))
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Spacing.sm)
        .background(DS.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .stroke(info.color.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - Reorder View (وضع الترتيب)
    private var childrenReorderView: some View {
        VStack(spacing: 0) {
            let children = memberVM.currentMemberChildren
            ForEach(Array(children.enumerated()), id: \.element.id) { index, son in
                if index > 0 { DSDivider() }

                let info = childIconInfo(for: son)

                HStack(spacing: DS.Spacing.md) {
                    // رقم الترتيب
                    Text("\(index + 1)")
                        .font(DS.Font.scaled(13, weight: .bold))
                        .foregroundColor(DS.Color.textOnPrimary)
                        .frame(width: 28, height: 28)
                        .background(info.color.opacity(0.8))
                        .clipShape(Circle())

                    // صورة
                    childAvatarView(for: son, iconFont: 14, size: 44)

                    // الاسم
                    Text(son.firstName.isEmpty ? L10n.t("الاسم", "Name") : son.firstName)
                        .font(DS.Font.callout)
                        .fontWeight(.bold)
                        .foregroundColor(DS.Color.textPrimary)
                        .lineLimit(1)

                    Spacer()

                    // أزرار أعلى/أسفل
                    VStack(spacing: 4) {
                        Button {
                            guard index > 0 else { return }
                            var reordered = children
                            reordered.swapAt(index, index - 1)
                            Task {
                                await memberVM.reorderChildren(reordered)
                            }
                        } label: {
                            Image(systemName: "chevron.up")
                                .font(DS.Font.scaled(14, weight: .bold))
                                .foregroundColor(index > 0 ? DS.Color.primary : DS.Color.textTertiary.opacity(0.3))
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .disabled(index == 0)

                        Button {
                            guard index < children.count - 1 else { return }
                            var reordered = children
                            reordered.swapAt(index, index + 1)
                            Task {
                                await memberVM.reorderChildren(reordered)
                            }
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(DS.Font.scaled(14, weight: .bold))
                                .foregroundColor(index < children.count - 1 ? DS.Color.primary : DS.Color.textTertiary.opacity(0.3))
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .disabled(index >= children.count - 1)
                    }
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.xs)
            }
        }
        .padding(.vertical, DS.Spacing.xs)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Helpers

    /// Directional chevron inside a tinted circle — used for navigation rows.
    private var chevronCircle: some View {
        Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
            .font(DS.Font.scaled(11, weight: .bold))
            .foregroundColor(DS.Color.textTertiary)
            .frame(width: 26, height: 26)
            .background(DS.Color.textTertiary.opacity(0.1))
            .clipShape(Circle())
    }

    /// Derives the SF Symbol name and accent color for a child member.
    private func childIconInfo(for member: FamilyMember) -> (name: String, color: Color) {
        let isDeceased = member.isDeceased ?? false
        let isFemale = member.gender?.lowercased() == "female"
        let iconName: String = {
            if isDeceased { return "person.fill.xmark" }
            return isFemale ? "figure.stand.dress" : "person.fill"
        }()
        let iconColor = isDeceased ? DS.Color.error : (isFemale ? DS.Color.neonPink : DS.Color.primary)
        return (iconName, iconColor)
    }

    /// Avatar circle for a child — shows the photo if available, otherwise an icon.
    private func childAvatarView(for member: FamilyMember, iconFont: CGFloat, size: CGFloat) -> some View {
        let info = childIconInfo(for: member)
        return ZStack {
            if let urlStr = member.avatarUrl, let url = URL(string: urlStr) {
                CachedAsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Image(systemName: info.name)
                        .font(DS.Font.scaled(iconFont, weight: .bold))
                        .foregroundColor(info.color)
                }
                .frame(width: size, height: size)
                .clipShape(Circle())
            } else {
                Image(systemName: info.name)
                    .font(DS.Font.scaled(iconFont, weight: .bold))
                    .foregroundColor(info.color)
                    .frame(width: size, height: size)
                    .background(info.color.opacity(0.12))
                    .clipShape(Circle())
            }
        }
    }

    // MARK: - General Section (Privacy, Settings)
    private func generalSection(user: FamilyMember) -> some View {
        DSCard(padding: 0) {
            DSSectionHeader(
                title: L10n.t("اعدادات التطبيق", "App Settings"),
                icon: "gearshape.2.fill",
                iconColor: DS.Color.textSecondary
            )

            // Privacy Row
            NavigationLink(destination: PrivacySettingsView()) {
                DSActionRow(
                    title: L10n.t("الإشعارات والخصوصية", "Notifications & Privacy"),
                    subtitle: L10n.t("إدارة الإشعارات وخصوصية بياناتك", "Manage notifications and data privacy"),
                    icon: "lock.shield.fill",
                    color: DS.Color.info
                )
            }
            .buttonStyle(DSBoldButtonStyle())

            DSDivider()

            // Settings Row
            NavigationLink(destination: SettingsView()) {
                DSActionRow(
                    title: L10n.t("الإعدادات", "Settings"),
                    subtitle: L10n.t("المظهر واللغة والأجهزة وإدارة الحساب", "Display, language, devices & account"),
                    icon: "gearshape.fill",
                    color: DS.Color.accent
                )
            }
            .buttonStyle(DSBoldButtonStyle())
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.bottom, DS.Spacing.lg)
    }
}
