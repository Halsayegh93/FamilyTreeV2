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
    @State private var showSettings = false

    @State private var showAddChild = false
    @State private var editingChild: FamilyMember? = nil
    @State private var editingRelative: FamilyMember? = nil
    @State private var editingRelativeLabel: String = ""
    @State private var isReorderingChildren = false
    @State private var appeared = false
    @State private var isLoadingChildren = true
    // عائلة شجرة النساء للمستخدم الحالي (زوجاته/أمّه/أبناؤه من women_members).
    @State private var womenCache: [FamilyMember] = WomenStore.cache
    @State private var showAddWifeAlert = false
    @State private var newWifeName = ""
    @State private var pendingNodeId: UUID? = nil
    @State private var motherPickerNode: FamilyMember? = nil

    private func reloadWomen() {
        Task { womenCache = (try? await WomenStore.fetch()) ?? womenCache }
    }

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
                            // زر الإعدادات — يفتح كل تفضيلات التطبيق
                            DSIconButton(icon: "gearshape.fill", iconColor: DS.Color.textOnPrimary) {
                                showSettings = true
                            }
                            .accessibilityLabel(L10n.t("الإعدادات", "Settings"))
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

                                // زر تسجيل الخروج بأسفل الصفحة
                                signOutButton
                                    .opacity(appeared ? 1 : 0)
                                    .offset(y: appeared ? 0 : 35)
                            }
                            .padding(.bottom, DS.Spacing.xxl)
                        } // closes ScrollView
                        .refreshable {
                            await memberVM.fetchAllMembers(force: true)
                            await memberVM.fetchChildren(for: currentUser.id)
                            womenCache = (try? await WomenStore.fetch()) ?? WomenStore.cache
                        }
                        .task {
                            isLoadingChildren = true
                            await memberVM.fetchChildren(for: currentUser.id)
                            isLoadingChildren = false
                            if WomenStore.cache.isEmpty {
                                womenCache = (try? await WomenStore.fetch()) ?? []
                            } else {
                                womenCache = WomenStore.cache
                            }
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
            .sheet(isPresented: $showSettings) {
                NavigationStack { SettingsView() }
                    .environment(\.layoutDirection, langManager.layoutDirection)
            }
            .sheet(isPresented: $showEditProfile) { if let c = user { EditProfileView(member: c).presentationDragIndicator(.visible) } }
            .sheet(isPresented: $showQRCode) {
                if let c = user {
                    QRCodeSheet(member: c, selectedTab: $selectedTab)
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                }
            }
            .fullScreenCover(isPresented: $showQRScanner) { QRScannerView(selectedTab: $selectedTab) }
            .sheet(isPresented: $showAddChild, onDismiss: reloadWomen) { if let c = user { AddChildSheet(member: c).presentationDragIndicator(.visible) } }
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
            .sheet(item: $editingChild, onDismiss: reloadWomen) { child in EditChildSheet(member: child).presentationDragIndicator(.visible) }
            .sheet(item: $editingRelative) { rel in
                EditRelativeSheet(member: rel, roleLabel: editingRelativeLabel)
                    .presentationDragIndicator(.visible)
            }
            .onChange(of: editingRelative) { newValue in
                guard newValue == nil, let currentUser = user else { return }
                Task { await memberVM.fetchChildren(for: currentUser.id) }
            }
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
                Button { showEditProfile = true } label: {
                    (
                        Text(user.fullName.isEmpty ? L10n.t("غير معروف", "Unknown") : user.fullName)
                            .font(DS.Font.title2.bold())
                            .foregroundColor(DS.Color.textPrimary)
                        + Text("  ")
                        + Text(Image(systemName: "pencil.circle.fill"))
                            .font(DS.Font.scaled(20, weight: .bold))
                            .foregroundColor(DS.Color.primary)
                    )
                    .multilineTextAlignment(.center)
                }
                .buttonStyle(DSScaleButtonStyle())
                .accessibilityLabel(L10n.t("تعديل البيانات", "Edit Profile"))
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
                            Text(L10n.t("رمز QR", "QR Code"))
                                .font(DS.Font.scaled(11, weight: .bold))
                        }
                        .foregroundColor(DS.Color.secondary)
                        .padding(.horizontal, DS.Spacing.sm)
                        .padding(.vertical, DS.Spacing.xs)
                        .background(DS.Color.secondary.opacity(0.1))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(DSScaleButtonStyle())
                    .accessibilityLabel(L10n.t("عرض رمز QR", "Show QR Code"))
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
                                    DSMemberAvatar(name: member.firstName, avatarUrl: member.displayAvatarUrl, size: 50, roleColor: member.roleColor, isFemale: member.isFemale)

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

    @ViewBuilder
    private var serverSonsSection: some View {
        // العائلة من شجرة النساء: الأم دائماً؛ الزوجات/الأبناء حسب الحالة الاجتماعية.
        if let u = user {
            let nodeId = WomenStore.womanByLinkedUser[u.id] ?? u.id
            let node = womenCache.first { $0.id == nodeId }
            let isMarried = u.isMarried ?? false
            let wives = womenCache.filter { $0.husbandId == nodeId }
                .sorted { $0.sortOrder < $1.sortOrder }
            let mom = node?.motherId.flatMap { mid in womenCache.first { $0.id == mid } }
            let kids = womenCache.filter { $0.fatherId == nodeId }
                .sorted { $0.sortOrder < $1.sortOrder }
            let canEdit = authVM.canEditMembers
            let sons = memberVM.currentMemberChildren
            let daughters = kids.filter { $0.isFemale }
            let hasAny = mom != nil || canEdit || isMarried
            if hasAny {
                VStack(alignment: .leading, spacing: 0) {
                    DSCard(padding: 0) {
                        DSSectionHeader(
                            title: L10n.t("العائلة", "Family"),
                            icon: "person.2.fill",
                            iconColor: DS.Color.textSecondary
                        )
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: DS.Spacing.md)],
                                  spacing: DS.Spacing.md) {
                            if let mom { womenFamilyBox(mom, label: L10n.t("الأم", "Mother")) }
                            if isMarried {
                                ForEach(wives, id: \.id) { womenFamilyBox($0, label: L10n.t("الزوجة", "Wife")) }
                                // الأبناء (الشجرة العامة) — نقر للتعديل.
                                ForEach(sons, id: \.id) { son in
                                    Button { editingChild = son } label: {
                                        womenFamilyBox(son, label: L10n.t("ابن", "Son"))
                                    }.buttonStyle(.plain)
                                }
                                // البنات (شجرة النساء) — نقر للتعديل/تغيير الجنس.
                                ForEach(daughters, id: \.id) { dgh in
                                    Button { editingChild = dgh } label: {
                                        womenFamilyBox(dgh, label: L10n.t("بنت", "Daughter"))
                                    }.buttonStyle(.plain)
                                }
                                // إضافة ابن (الشجرة العامة) — للمتزوج.
                                womenActionBox(icon: "person.badge.plus",
                                               color: DS.Color.primary,
                                               title: L10n.t("إضافة ابن", "Add son")) {
                                    showAddChild = true
                                }
                                if canEdit {
                                    womenActionBox(icon: "heart.circle.fill",
                                                   color: FemaleAvatarView.wifeIcon,
                                                   title: L10n.t("إضافة زوجة", "Add wife")) {
                                        pendingNodeId = nodeId; newWifeName = ""; showAddWifeAlert = true
                                    }
                                }
                            }
                            if canEdit {
                                womenActionBox(icon: "figure.2.and.child.holdinghands",
                                               color: FemaleAvatarView.motherIcon,
                                               title: mom == nil ? L10n.t("إضافة الأم", "Add mother")
                                                                 : L10n.t("تغيير الأم", "Change mother")) {
                                    motherPickerNode = node ?? u
                                }
                            }
                        }
                        .padding(DS.Spacing.md)
                    }
                }
                .padding(.horizontal, DS.Spacing.lg)
                .alert(L10n.t("إضافة زوجة", "Add wife"), isPresented: $showAddWifeAlert) {
                    TextField(L10n.t("اسم الزوجة", "Wife name"), text: $newWifeName)
                    Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
                    Button(L10n.t("إضافة", "Add")) { addWifeFromProfile() }
                }
                .sheet(item: $motherPickerNode) { n in motherPickerSheet(for: n) }
            }
        }
    }

    // مربع عائلة — أم/زوجة بالاسم الكامل، الأبناء بالاسم الأول.
    private func womenFamilyBox(_ member: FamilyMember, label: String) -> some View {
        let isWife = label == L10n.t("الزوجة", "Wife")
        let isMother = label == L10n.t("الأم", "Mother")
        let isChild = !isWife && !isMother
        let fbg = isWife ? FemaleAvatarView.wifeBg : (isMother ? FemaleAvatarView.motherBg : FemaleAvatarView.pink)
        let ficon = isWife ? FemaleAvatarView.wifeIcon : (isMother ? FemaleAvatarView.motherIcon : FemaleAvatarView.pinkIcon)
        let name = isChild ? member.firstName : (member.fullName.isEmpty ? member.firstName : member.fullName)
        return VStack(spacing: 4) {
            DSMemberAvatar(
                name: member.firstName,
                avatarUrl: member.isFemale ? nil : member.displayAvatarUrl,
                size: 46,
                isFemale: member.isFemale,
                femaleBg: fbg,
                femaleIcon: ficon,
                isDeceased: member.isDeceased == true,
                square: true
            )
            Text(name)
                .font(DS.Font.caption1).fontWeight(.semibold)
                .foregroundColor(DS.Color.textPrimary)
                .lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.7)
            Text(label).font(DS.Font.caption2).foregroundColor(DS.Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // مربع إجراء (إضافة زوجة / الأم).
    private func womenActionBox(icon: String, color: Color, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(DS.Font.scaled(18, weight: .semibold))
                    .foregroundColor(color)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(color.opacity(0.12)))
                    .overlay(Circle().strokeBorder(color.opacity(0.35), lineWidth: 1))
                Text(title).font(DS.Font.caption2).fontWeight(.semibold)
                    .foregroundColor(color).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private func addWifeFromProfile() {
        guard let nid = pendingNodeId else { return }
        let nm = newWifeName.trimmingCharacters(in: .whitespaces)
        guard !nm.isEmpty else { return }
        Task {
            try? await WomenStore.addWife(husbandId: nid, name: nm)
            womenCache = (try? await WomenStore.fetch()) ?? womenCache
        }
    }

    // اختيار الأم من زوجات الأب، أو إضافة زوجة للأب.
    @ViewBuilder
    private func motherPickerSheet(for node: FamilyMember) -> some View {
        let father = node.fatherId.flatMap { fid in womenCache.first { $0.id == fid } }
        let candidates = womenCache
            .filter { $0.isFemale && father != nil && $0.husbandId == father!.id }
            .sorted { $0.fullName < $1.fullName }
        NavigationStack {
            List {
                Button(L10n.t("بدون أم", "No mother")) {
                    motherPickerNode = nil
                    Task { try? await WomenStore.setMotherId(childId: node.id, motherId: nil)
                           womenCache = (try? await WomenStore.fetch()) ?? womenCache }
                }.foregroundColor(DS.Color.textSecondary)
                if candidates.isEmpty {
                    Text(L10n.t("لا توجد زوجات للأب — أضِف زوجة للأب من شجرة النساء.",
                                "No wives for the father — add one from the women tree."))
                        .foregroundColor(DS.Color.textSecondary)
                } else {
                    Text(L10n.t("اختر الأم من زوجات الأب:", "Choose mother from father's wives:"))
                        .font(DS.Font.caption1).foregroundColor(DS.Color.textSecondary)
                    ForEach(candidates) { c in
                        Button(c.fullName.isEmpty ? c.firstName : c.fullName) {
                            motherPickerNode = nil
                            Task { try? await WomenStore.setMotherId(childId: node.id, motherId: c.id)
                                   womenCache = (try? await WomenStore.fetch()) ?? womenCache }
                        }.foregroundColor(DS.Color.textPrimary)
                    }
                }
            }
            .navigationTitle(L10n.t("الأم", "Mother"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) {
                Button(L10n.t("إلغاء", "Cancel")) { motherPickerNode = nil }
            } }
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - صف الأم/الزوجة داخل «العائلة» — نقر → نفس تعديلات الأبناء
    private func familyRelRow(member: FamilyMember, label: String) -> some View {
        let isWife = label == L10n.t("الزوجة", "Wife")
        let isMother = label == L10n.t("الأم", "Mother")
        let fbg = isWife ? FemaleAvatarView.wifeBg : (isMother ? FemaleAvatarView.motherBg : FemaleAvatarView.pink)
        let ficon = isWife ? FemaleAvatarView.wifeIcon : (isMother ? FemaleAvatarView.motherIcon : FemaleAvatarView.pinkIcon)
        return Button {
            editingRelativeLabel = label
            editingRelative = member
        } label: {
            HStack(spacing: DS.Spacing.md) {
                DSMemberAvatar(
                    name: member.firstName,
                    avatarUrl: member.displayAvatarUrl,
                    size: 40,
                    isFemale: member.isFemale,
                    femaleBg: fbg,
                    femaleIcon: ficon,
                    isDeceased: member.isDeceased == true
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(member.fullName.isEmpty ? member.firstName : member.fullName)
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.textPrimary)
                        .lineLimit(1)
                    Text(label)
                        .font(DS.Font.caption1)
                        .foregroundColor(DS.Color.textSecondary)
                }
                Spacer()
                Image(systemName: "pencil")
                    .font(DS.Font.scaled(13, weight: .semibold))
                    .foregroundColor(DS.Color.textTertiary)
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(son.firstName.isEmpty ? L10n.t("ابن بدون اسم", "Unnamed child") : son.firstName)
                    .accessibilityHint(L10n.t("تعديل", "Edit"))
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
    private var signOutButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            showSignOutConfirm = true
        } label: {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(DS.Font.scaled(15, weight: .semibold))
                Text(L10n.t("تسجيل الخروج", "Sign Out"))
                    .font(DS.Font.calloutBold)
            }
            .foregroundColor(DS.Color.error)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Spacing.md)
            .background(DS.Color.error.opacity(0.10))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .stroke(DS.Color.error.opacity(0.20), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        }
        .buttonStyle(DSScaleButtonStyle())
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.top, DS.Spacing.md)
    }
}

// MARK: - تعديل الزوجة/الأم (محرّر مختلف عن الابن — الاسم الكامل + متوفّاة + إخفاء)
struct EditRelativeSheet: View {
    @EnvironmentObject var memberVM: MemberViewModel
    @Environment(\.dismiss) private var dismiss

    let member: FamilyMember
    let roleLabel: String

    @State private var fullName: String = ""
    @State private var isDeceased: Bool = false
    @State private var hasDeathDate: Bool = false
    @State private var deathDate: Date = Date()
    @State private var isHidden: Bool = false
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L10n.t("الاسم الكامل", "Full name"), text: $fullName)
                } header: {
                    Text(L10n.t("الاسم الكامل", "Full name"))
                }

                Section {
                    Toggle(isOn: $isDeceased.animation(DS.Anim.snappy)) {
                        Label(L10n.t("متوفّاة", "Deceased"), systemImage: "leaf.fill")
                    }
                    .tint(DS.Color.error)
                    if isDeceased {
                        Toggle(isOn: $hasDeathDate.animation(DS.Anim.snappy)) {
                            Label(L10n.t("أعرف تاريخ الوفاة", "Death date known"), systemImage: "calendar")
                        }
                        .tint(DS.Color.primary)
                        if hasDeathDate {
                            DatePicker(L10n.t("تاريخ الوفاة", "Death date"),
                                       selection: $deathDate, in: ...Date(),
                                       displayedComponents: .date)
                        }
                    }
                }

                Section {
                    Toggle(isOn: Binding(get: { !isHidden }, set: { isHidden = !$0 })) {
                        Label(L10n.t("إظهار في الشجرة", "Show in tree"),
                              systemImage: isHidden ? "eye.slash" : "eye")
                    }
                    .tint(DS.Color.primary)
                }
            }
            .navigationTitle(L10n.t("تعديل \(roleLabel)", "Edit \(roleLabel)"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.t("إلغاء", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.t("حفظ", "Save")) { save() }
                        .disabled(fullName.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        }
        .onAppear {
            fullName = member.fullName.isEmpty ? member.firstName : member.fullName
            isDeceased = member.isDeceased ?? false
            isHidden = member.isHiddenFromTree
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
            if let d = member.deathDate, let parsed = f.date(from: String(d.prefix(10))) {
                deathDate = parsed
                hasDeathDate = true
            }
        }
    }

    private func save() {
        let name = fullName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        isSaving = true
        Task {
            // الاسم الكامل كما هو (بدون إلحاق/تكرار).
            await memberVM.updateMemberName(memberId: member.id, fullName: name, silent: true)
            if isDeceased != (member.isDeceased ?? false) || isDeceased {
                await memberVM.setDeceased(memberId: member.id, isDeceased: isDeceased,
                                           deathDate: (isDeceased && hasDeathDate) ? deathDate : nil)
            }
            if isHidden != member.isHiddenFromTree {
                await memberVM.setHiddenFromTree(memberId: member.id, hidden: isHidden)
            }
            isSaving = false
            dismiss()
        }
    }
}
