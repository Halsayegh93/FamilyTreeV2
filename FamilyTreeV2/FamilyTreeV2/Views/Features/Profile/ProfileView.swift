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
    @State private var editingFamilyMember: WomenFamilyEntry? = nil
    @State private var isReorderingChildren = false
    // إضافة/اختيار الزوجة والأم
    @State private var showAddWife = false
    @State private var newWifeName = ""
    // مصدر إضافة الزوجة: بالاسم أو اختيار من العائلة
    @State private var showWifeSource = false
    @State private var showWifePicker = false
    @State private var wifeCandidates: [FamilyMember] = []
    @State private var wifeSearch = ""
    @State private var isLoadingWifeCandidates = false
    @State private var showMotherOptions = false
    @State private var showAddMotherName = false
    @State private var newMotherName = ""
    @State private var fatherWives: [WomanMember] = []
    @State private var appeared = false
    @State private var isLoadingChildren = true

    var user: FamilyMember? { authVM.currentUser }

    /// عائلة شجرة النساء (الأم/الزوجة/الأبناء) تظهر فقط عند «متزوج».
    private var isCurrentUserMarried: Bool { authVM.currentUser?.isMarried ?? false }
    private var hasWife: Bool { memberVM.currentMemberWomenFamily.contains { $0.role == .wife } }
    private var hasMother: Bool { memberVM.currentMemberWomenFamily.contains { $0.role == .mother } }

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

                                // قسم «عائلتي» — يظهر فقط عند «متزوج»، ويختفي كاملاً عند «أعزب»
                                if isCurrentUserMarried {
                                    serverSonsSection
                                        .opacity(appeared ? 1 : 0)
                                        .offset(y: appeared ? 0 : 30)
                                }

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
                        }
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
            .sheet(isPresented: $showAddChild) { if let c = user { AddChildSheet(member: c).presentationDragIndicator(.visible) } }
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
            .sheet(item: $editingChild) { child in EditChildSheet(member: child).presentationDragIndicator(.visible) }
            .sheet(item: $editingFamilyMember) { entry in
                WomanMemberEditSheet(memberVM: memberVM, entry: entry)
                    .presentationDragIndicator(.visible)
            }
            .alert(L10n.t("إضافة زوجة", "Add Wife"), isPresented: $showAddWife) {
                TextField(L10n.t("اسم الزوجة", "Wife's name"), text: $newWifeName)
                Button(L10n.t("إضافة", "Add")) {
                    let n = newWifeName
                    Task { await memberVM.addSelfWife(name: n) }
                }
                Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
            }
            // مصدر إضافة الزوجة: بالاسم أو اختيار من العائلة (مثل شجرة النساء)
            .confirmationDialog(L10n.t("إضافة زوجة", "Add Wife"),
                                isPresented: $showWifeSource, titleVisibility: .visible) {
                Button(L10n.t("اختيار من العائلة", "Choose from family")) {
                    Task {
                        isLoadingWifeCandidates = true
                        wifeCandidates = await loadWifeCandidates()
                        isLoadingWifeCandidates = false
                        showWifePicker = true
                    }
                }
                Button(L10n.t("إضافة بالاسم", "Add by name")) {
                    // تأخير بسيط لتفادي تعارض عرض التنبيه بعد إغلاق الحوار
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        newWifeName = ""; showAddWife = true
                    }
                }
                Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
            }
            .sheet(isPresented: $showWifePicker) { wifePickerSheet }
            .confirmationDialog(L10n.t("الأم", "Mother"), isPresented: $showMotherOptions, titleVisibility: .visible) {
                ForEach(fatherWives) { w in
                    Button(w.firstName.isEmpty ? L10n.t("زوجة الأب", "Father's wife") : w.firstName) {
                        Task { await memberVM.setSelfMother(motherId: w.id) }
                    }
                }
                Button(L10n.t("إضافة أم جديدة", "Add new mother")) {
                    newMotherName = ""; showAddMotherName = true
                }
                Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
            } message: {
                Text(fatherWives.isEmpty
                     ? L10n.t("لا زوجات مسجّلة للأب — أضف أمّاً جديدة", "No registered father's wives — add a new mother")
                     : L10n.t("اختر الأم من زوجات الأب، أو أضف جديدة", "Pick the mother from father's wives, or add new"))
            }
            .alert(L10n.t("إضافة أم", "Add Mother"), isPresented: $showAddMotherName) {
                TextField(L10n.t("اسم الأم", "Mother's name"), text: $newMotherName)
                Button(L10n.t("إضافة", "Add")) {
                    let n = newMotherName
                    Task { await memberVM.addSelfMother(name: n) }
                }
                Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
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

                    // عدد الأبناء (شجرة الرجال + شجرة النساء)
                    let totalChildren = memberVM.currentMemberChildren.count + (isCurrentUserMarried ? memberVM.currentMemberWomenFamily.count : 0)
                    if totalChildren > 0 {
                        HStack(spacing: DS.Spacing.xs) {
                            Image(systemName: "person.2.fill")
                                .font(DS.Font.scaled(10, weight: .semibold))
                            Text("\(totalChildren) " + L10n.t("من العائلة", "family"))
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
                        title: L10n.t("عائلتي", "My Family"),
                        icon: "person.2.fill",
                        iconColor: DS.Color.textSecondary
                    )

                    Spacer()

                    if memberVM.currentMemberChildren.count > 1 || womenChildrenList.count > 1 {
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
                    VStack(spacing: DS.Spacing.sm) {
                        ForEach(0..<3, id: \.self) { _ in
                            DSSkeletonRow(avatarSize: 44)
                        }
                    }
                    .padding(DS.Spacing.md)
                    .transition(.opacity)
                } else if isReorderingChildren && !memberVM.currentMemberChildren.isEmpty {
                    // وضع ترتيب أبناء الشجرة العامة (قائمة عمودية بأسهم)
                    childrenReorderView
                } else {
                    // الوضع العادي / ترتيب أبناء شجرة النساء (شبكة مع أسهم على الخلايا)
                    childrenGridView
                        .transition(.opacity)
                }
            }
            .animation(DS.Anim.medium, value: isLoadingChildren)
        }
        .padding(.horizontal, DS.Spacing.lg)
    }

    // MARK: - Grid View (الوضع العادي)
    /// خلية إجراء إضافة (زوجة/أم) بنفس شكل خلية «إضافة ابن».
    private func addFamilyActionCell(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: icon)
                    .font(DS.Font.scaled(16, weight: .bold))
                    .foregroundColor(color)
                    .frame(width: 36, height: 36)
                    .background(color.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                Text(title).font(DS.Font.caption1).fontWeight(.bold).foregroundColor(color).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DS.Spacing.sm)
            .background(DS.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .stroke(color.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [5]))
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    /// خلية فرد عائلة (أم/زوجة) — زر تعديل للمخوّل، وإلا عرض فقط.
    @ViewBuilder
    private func familyMemberButton(_ entry: WomenFamilyEntry) -> some View {
        if authVM.canModerate {
            Button { editingFamilyMember = entry } label: { womanFamilyGridCell(entry: entry) }
                .buttonStyle(PlainButtonStyle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(entry.member.firstName.isEmpty ? L10n.t("فرد", "Member") : entry.member.firstName)
                .accessibilityHint(L10n.t("تعديل", "Edit"))
        } else {
            womanFamilyGridCell(entry: entry)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(entry.member.firstName.isEmpty ? L10n.t("فرد", "Member") : entry.member.firstName)
        }
    }

    private var childrenGridView: some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible())]
        let parents = memberVM.currentMemberWomenFamily.filter { $0.role == .mother || $0.role == .wife }
        let womenKids = memberVM.currentMemberWomenFamily.filter { $0.role == .child }
        let motherEntry = parents.first { $0.role == .mother }
        let wifeEntries = parents.filter { $0.role == .wife }
        let showParents = isCurrentUserMarried && (!parents.isEmpty || authVM.canModerate)
        return VStack(spacing: DS.Spacing.sm) {
            // ═══ الأم / الزوجة — أماكن ثابتة (البطاقة أو زر الإضافة/الاختيار) ═══
            if showParents {
                LazyVGrid(columns: columns, spacing: DS.Spacing.md) {
                    // خانة الأم (ثابتة أولاً)
                    if let motherEntry {
                        familyMemberButton(motherEntry)
                    } else if authVM.canModerate {
                        addFamilyActionCell(title: L10n.t("إضافة/اختيار الأم", "Add/Pick Mother"),
                                            icon: "person.fill", color: DS.Color.accent) {
                            Task { fatherWives = await memberVM.fetchFatherWives(); showMotherOptions = true }
                        }
                    }
                    // خانة الزوجة (ثابتة بعد الأم)
                    ForEach(wifeEntries) { entry in familyMemberButton(entry) }
                    // إضافة الزوجة متاحة لأي عضو متزوّج (مو المدير فقط) — اختياري لا إجبار
                    if !hasWife {
                        addFamilyActionCell(title: L10n.t("إضافة زوجة", "Add Wife"),
                                            icon: "heart.fill", color: DS.Color.neonPink) {
                            showWifeSource = true
                        }
                    }
                }
                DSDivider().padding(.vertical, 0)
            }

            // ═══ الأبناء ═══
            LazyVGrid(columns: columns, spacing: DS.Spacing.md) {
                ForEach(memberVM.currentMemberChildren, id: \.id) { son in
                    Button { editingChild = son } label: { childGridCell(son: son) }
                        .buttonStyle(PlainButtonStyle())
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(son.firstName.isEmpty ? L10n.t("ابن بدون اسم", "Unnamed child") : son.firstName)
                        .accessibilityHint(L10n.t("تعديل", "Edit"))
                }
                if isCurrentUserMarried {
                    ForEach(womenKids) { entry in
                        if authVM.canModerate {
                            Button { editingFamilyMember = entry } label: { womanFamilyGridCell(entry: entry) }
                                .buttonStyle(PlainButtonStyle())
                                .overlay(alignment: .topLeading) {
                                    if isReorderingChildren, entry.role == .child, womenChildrenList.count > 1 {
                                        womanChildReorderControls(for: entry.member)
                                    }
                                }
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(entry.member.firstName.isEmpty ? L10n.t("فرد", "Member") : entry.member.firstName)
                                .accessibilityHint(L10n.t("تعديل", "Edit"))
                        } else {
                            womanFamilyGridCell(entry: entry)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(entry.member.firstName.isEmpty ? L10n.t("فرد", "Member") : entry.member.firstName)
                        }
                    }
                }
                // إضافة ابن
                Button { showAddChild = true } label: {
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
        }
        .padding(DS.Spacing.md)
    }

    private func childGridCell(son: FamilyMember) -> some View {
        let info = childIconInfo(for: son)

        return HStack(spacing: DS.Spacing.sm) {
            childAvatarView(for: son, iconFont: 16, size: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(son.firstName.isEmpty ? L10n.t("الاسم", "Name") : son.firstName)
                    .font(DS.Font.caption1)
                    .fontWeight(.bold)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)

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
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Spacing.sm)
        .background(DS.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .stroke(info.color.opacity(0.15), lineWidth: 1)
        )
    }

    /// أبناء شجرة النساء بالترتيب الحالي (للترتيب).
    // MARK: - اختيار الزوجة من العائلة

    /// إناث شجرة النساء المتاحات (بلا زوج) — مرشّحات «زوجة من العائلة».
    private func loadWifeCandidates() async -> [FamilyMember] {
        guard let me = authVM.currentUser?.id else { return [] }
        let all = (try? await WomenStore.fetch()) ?? []
        return all
            .filter {
                $0.isFemale
                && $0.husbandId == nil                                              // غير مرتبطة بزوج
                && $0.id != me
                && WomenStore.linkedUserByWoman[$0.id] == nil                        // ليست عضواً بحساب
                && !$0.fullName.trimmingCharacters(in: .whitespaces).isEmpty         // لها اسم
            }
            .sorted { $0.fullName.localizedCompare($1.fullName) == .orderedAscending }
    }

    /// ربط أنثى موجودة كزوجة للمستخدم الحالي (RPC مقيّد على النفس — يعمل لأي دور).
    private func linkWife(_ womanId: UUID) {
        showWifePicker = false; wifeSearch = ""
        Task { await memberVM.setSelfWife(wifeId: womanId) }
    }

    /// شيت اختيار زوجة من العائلة (مع بحث).
    private var wifePickerSheet: some View {
        let list = wifeSearch.trimmingCharacters(in: .whitespaces).isEmpty
            ? wifeCandidates
            : wifeCandidates.filter { $0.fullName.contains(wifeSearch) || $0.firstName.contains(wifeSearch) }
        return NavigationStack {
            Group {
                if wifeCandidates.isEmpty {
                    VStack(spacing: DS.Spacing.md) {
                        Image(systemName: "person.2.slash")
                            .font(DS.Font.scaled(36, weight: .regular))
                            .foregroundColor(DS.Color.textTertiary)
                        Text(L10n.t("لا توجد إناث متاحات في العائلة", "No available family women"))
                            .font(DS.Font.callout)
                            .foregroundColor(DS.Color.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(list) { m in
                        Button { linkWife(m.id) } label: {
                            HStack(spacing: DS.Spacing.md) {
                                wifePickerAvatar(m)
                                Text(m.fullName.isEmpty ? m.firstName : m.fullName)
                                    .font(DS.Font.callout)
                                    .foregroundColor(DS.Color.textPrimary)
                                Spacer()
                            }
                        }
                    }
                    .searchable(text: $wifeSearch, prompt: L10n.t("بحث بالاسم", "Search by name"))
                }
            }
            .navigationTitle(L10n.t("اختيار زوجة من العائلة", "Choose wife"))
            .navigationBarTitleDisplayMode(.inline)
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("إلغاء", "Cancel")) { showWifePicker = false; wifeSearch = "" }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func wifePickerAvatar(_ m: FamilyMember) -> some View {
        Group {
            if let url = m.avatarUrl ?? m.photoURL, let u = URL(string: url) {
                CachedAsyncImage(url: u) { img in img.resizable().scaledToFill() }
                    placeholder: { DS.Color.primary.opacity(0.1) }
            } else {
                DS.Color.primary.opacity(0.1)
                    .overlay(Image(systemName: "person.fill").foregroundColor(DS.Color.primary.opacity(0.5)))
            }
        }
        .frame(width: 36, height: 36)
        .clipShape(Circle())
        .overlay(Circle().stroke(DS.Color.primary.opacity(0.18), lineWidth: 1))
    }

    private var womenChildrenList: [WomanMember] {
        memberVM.currentMemberWomenFamily.filter { $0.role == .child }.map { $0.member }
    }

    /// نقل ابن/ابنة أعلى/أسفل في الترتيب.
    private func moveWomanChild(_ child: WomanMember, up: Bool) {
        var list = womenChildrenList
        guard let idx = list.firstIndex(where: { $0.id == child.id }) else { return }
        let target = up ? idx - 1 : idx + 1
        guard target >= 0, target < list.count else { return }
        list.swapAt(idx, target)
        Task { await memberVM.reorderWomenChildren(list) }
    }

    /// أسهم أعلى/أسفل صغيرة لترتيب ابن/ابنة.
    private func womanChildReorderControls(for child: WomanMember) -> some View {
        let list = womenChildrenList
        let idx = list.firstIndex(where: { $0.id == child.id }) ?? 0
        return HStack(spacing: 3) {
            Button { moveWomanChild(child, up: true) } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .black))
                    .foregroundColor(idx > 0 ? DS.Color.primary : DS.Color.textTertiary.opacity(0.4))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(DS.Color.surface))
                    .overlay(Circle().strokeBorder(DS.Color.primary.opacity(0.15), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(idx == 0)
            .accessibilityLabel(L10n.t("نقل لأعلى", "Move up"))

            Button { moveWomanChild(child, up: false) } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .black))
                    .foregroundColor(idx < list.count - 1 ? DS.Color.primary : DS.Color.textTertiary.opacity(0.4))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(DS.Color.surface))
                    .overlay(Circle().strokeBorder(DS.Color.primary.opacity(0.15), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(idx >= list.count - 1)
            .accessibilityLabel(L10n.t("نقل لأسفل", "Move down"))
        }
        .padding(6)
    }

    // خلية فرد «عائلتي» — بنفس شكل خلايا الأبناء القديمة (صورة + اسم)، دور رمادي خفيف.
    private func womanFamilyGridCell(entry: WomenFamilyEntry) -> some View {
        let woman = entry.member
        return HStack(spacing: DS.Spacing.sm) {
            Group {
                if let urlStr = woman.displayImageUrl, let url = URL(string: urlStr) {
                    CachedAsyncImage(url: url) { img in
                        img.resizable().scaledToFill()
                    } placeholder: { womanAvatarFallback }
                } else {
                    womanAvatarFallback
                }
            }
            .frame(width: 36, height: 36)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(DS.Color.primary.opacity(0.12), lineWidth: 1))

            VStack(alignment: .leading, spacing: 2) {
                Text(woman.firstName.isEmpty ? L10n.t("الاسم", "Name") : woman.firstName)
                    .font(DS.Font.caption1)
                    .fontWeight(.bold)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)

                HStack(spacing: DS.Spacing.xs) {
                    // الدور (زوجة/أم) — يُخفى للأبناء
                    if entry.role != .child {
                        Text(L10n.t(entry.role.label, entry.role.labelEn))
                            .font(DS.Font.caption2)
                            .foregroundColor(DS.Color.textSecondary)
                            .lineLimit(1)
                    }
                    if woman.isDeceased {
                        Text(L10n.t("متوفى", "Deceased"))
                            .font(DS.Font.scaled(8, weight: .bold))
                            .foregroundColor(DS.Color.textOnPrimary)
                            .padding(.horizontal, DS.Spacing.xs).padding(.vertical, 1)
                            .background(DS.Color.error.opacity(0.8)).clipShape(Capsule())
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Spacing.sm)
        .background(DS.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .stroke(DS.Color.primary.opacity(0.12), lineWidth: 1)
        )
    }

    private var womanAvatarFallback: some View {
        ZStack {
            DS.Color.primary.opacity(0.08)
            Image(systemName: "person.fill")
                .font(DS.Font.scaled(16, weight: .bold))
                .foregroundColor(DS.Color.primary.opacity(0.6))
        }
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

// MARK: - Woman-tree family member edit sheet

/// تعديل فرد من «عائلتي» (شجرة النساء): الاسم/تاريخ الميلاد/متوفى + حذف.
struct WomanMemberEditSheet: View {
    @ObservedObject var memberVM: MemberViewModel
    let entry: WomenFamilyEntry
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var hasBirthDate: Bool
    @State private var birthDate: Date
    @State private var isDeceased: Bool
    @State private var selectedGender: String
    @State private var deathDate: Date
    @State private var hasDeathDate: Bool
    @State private var selectedUIImage: UIImage? = nil
    @State private var isSaving = false
    @State private var showDeleteConfirm = false
    @State private var errorBanner: String? = nil
    @State private var sheetHeight: CGFloat = 480

    init(memberVM: MemberViewModel, entry: WomenFamilyEntry) {
        self.memberVM = memberVM
        self.entry = entry
        _name = State(initialValue: entry.member.firstName)
        _isDeceased = State(initialValue: entry.member.isDeceased)
        _selectedGender = State(initialValue: entry.member.gender)
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        if let b = entry.member.birthDate, let d = f.date(from: b) {
            _hasBirthDate = State(initialValue: true)
            _birthDate = State(initialValue: d)
        } else {
            _hasBirthDate = State(initialValue: false)
            _birthDate = State(initialValue: Date())
        }
        if let dd = entry.member.deathDate, let d = f.date(from: dd) {
            _hasDeathDate = State(initialValue: true)
            _deathDate = State(initialValue: d)
        } else {
            _hasDeathDate = State(initialValue: false)
            _deathDate = State(initialValue: Date())
        }
    }

    private var roleTitle: String { L10n.t(entry.role.label, entry.role.labelEn) }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && !isSaving }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: DS.Spacing.md) {
                    // الصورة للذكر فقط — الأنثى بلا خيار صورة
                    if selectedGender != "female" {
                        DSProfilePhotoPicker(
                            selectedImage: $selectedUIImage,
                            existingURL: entry.member.displayImageUrl,
                            enableCrop: true,
                            cropShape: .circle,
                            trailing: L10n.t("اختياري", "Optional"),
                            compactEmptyState: true
                        )
                        .padding(.horizontal, DS.Spacing.lg)
                    }

                    DSCard(padding: 0) {
                        DSSectionHeader(
                            title: L10n.t("المعلومات الشخصية", "Personal Info"),
                            icon: "person.text.rectangle",
                            iconColor: DS.Color.primary
                        )
                        VStack(spacing: 0) {
                            DSLabeledFieldRow(icon: "person.fill", iconColor: DS.Color.primary,
                                              label: L10n.t("الاسم", "Name")) {
                                TextField(L10n.t("الاسم", "Name"), text: $name)
                                    .font(DS.Font.callout)
                                    .foregroundColor(DS.Color.textPrimary)
                            }
                            // اختيار الجنس — للأبناء فقط (الأم/الزوجة أنثى دائمًا)
                            if entry.role == .child {
                                DSDivider()
                                DSFormRow(icon: "person.2.fill", iconColor: DS.Color.accent,
                                          label: L10n.t("الجنس", "Gender")) {
                                    HStack(spacing: DS.Spacing.xs) {
                                        genderButton(title: L10n.t("ذكر", "Male"), value: "male", color: DS.Color.primary)
                                        genderButton(title: L10n.t("أنثى", "Female"), value: "female", color: DS.Color.neonPink)
                                    }
                                }
                            }
                            DSDivider()
                            DSDateField(
                                label: L10n.t("تاريخ الميلاد", "Birth Date"),
                                date: $birthDate,
                                range: ...Date(),
                                labelAbove: true
                            )
                            .onChange(of: birthDate) { _ in hasBirthDate = true }
                            DSDivider()
                            DSFormRow(icon: "leaf.fill", iconColor: DS.Color.error,
                                      label: L10n.t("متوفى", "Deceased")) {
                                Toggle("", isOn: $isDeceased).labelsHidden().tint(DS.Color.error)
                            }
                            .animation(.default, value: isDeceased)
                            if isDeceased {
                                DSDivider()
                                DSDateField(
                                    label: L10n.t("تاريخ الوفاة", "Death Date"),
                                    date: $deathDate,
                                    icon: "calendar",
                                    iconColor: DS.Color.error,
                                    range: ...Date()
                                )
                                .onChange(of: deathDate) { _ in hasDeathDate = true }
                            }
                        }
                    }
                    .padding(.horizontal, DS.Spacing.lg)

                    if let errorBanner {
                        Text(errorBanner).font(DS.Font.caption1).foregroundColor(DS.Color.error)
                            .padding(.horizontal, DS.Spacing.lg)
                    }

                    DSPrimaryButton(L10n.t("حفظ", "Save"), icon: "checkmark.circle.fill", isLoading: isSaving) { save() }
                        .disabled(!canSave)
                        .opacity(canSave ? 1 : 0.5)
                        .padding(.horizontal, DS.Spacing.lg)

                    Button(role: .destructive) { showDeleteConfirm = true } label: {
                        Label(L10n.t("حذف من العائلة", "Remove from family"), systemImage: "trash")
                            .font(DS.Font.calloutBold)
                            .foregroundColor(DS.Color.error)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, DS.Spacing.sm)
                    }
                    .padding(.horizontal, DS.Spacing.lg)

                }
                .padding(.vertical, DS.Spacing.md)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: SheetContentHeightKey.self, value: proxy.size.height)
                    }
                )
            }
            .background(DS.Color.background.ignoresSafeArea())
            .navigationTitle(L10n.t("تعديل \(roleTitle)", "Edit \(roleTitle)"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.t("إلغاء", "Cancel")) { dismiss() }
                        .foregroundColor(DS.Color.error)
                        .disabled(isSaving)
                }
            }
            .alert(L10n.t("حذف من العائلة", "Remove from family"), isPresented: $showDeleteConfirm) {
                Button(L10n.t("حذف", "Delete"), role: .destructive) {
                    Task {
                        // الأم: فكّ الارتباط (RPC مقيّد على النفس).
                        // الزوجة: حذف/فكّ مقيّد على النفس (يعمل لأي دور).
                        // الابن: حذف السجل (للإدارة).
                        let ok: Bool
                        switch entry.role {
                        case .mother: ok = await memberVM.setSelfMother(motherId: nil)
                        case .wife:   ok = await memberVM.removeSelfWife(wifeId: entry.member.id)
                        default:      ok = await memberVM.deleteWomanMember(id: entry.member.id)
                        }
                        if ok { await MainActor.run { dismiss() } }
                    }
                }
                Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
            } message: {
                Text(entry.role == .mother
                     ? L10n.t("إزالة الأم «\(name)» من عائلتك؟ (لن تُحذف من الشجرة)", "Unlink mother “\(name)”?")
                     : L10n.t("حذف «\(name)» من عائلتك؟", "Remove “\(name)” from your family?"))
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .onPreferenceChange(SheetContentHeightKey.self) { h in
            if h > 0 { sheetHeight = min(h + 40, 760) }
        }
        .presentationDetents([.height(sheetHeight)])
        .presentationDragIndicator(.visible)
    }

    private func genderButton(title: String, value: String, color: Color) -> some View {
        let selected = selectedGender == value
        return Button { selectedGender = value } label: {
            Text(title)
                .font(DS.Font.caption1).fontWeight(.bold)
                .foregroundColor(selected ? .white : DS.Color.textSecondary)
                .padding(.horizontal, DS.Spacing.md)
                .frame(height: 34)
                .background(Capsule().fill(selected ? color : DS.Color.surface))
                .overlay(Capsule().strokeBorder(selected ? Color.clear : DS.Color.textTertiary.opacity(0.3), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func save() {
        Task {
            isSaving = true
            let ok = await memberVM.updateWomanMember(
                id: entry.member.id,
                firstName: name,
                birthDate: hasBirthDate ? birthDate : nil,
                isDeceased: isDeceased,
                deathDate: hasDeathDate ? deathDate : nil,
                gender: selectedGender
            )
            if ok, let img = selectedUIImage {
                await memberVM.updateWomanAvatar(id: entry.member.id, image: img)
            }
            isSaving = false
            if ok { dismiss() } else { errorBanner = memberVM.errorMessage }
        }
    }
}
