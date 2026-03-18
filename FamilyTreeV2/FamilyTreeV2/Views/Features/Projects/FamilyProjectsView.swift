import SwiftUI

struct FamilyProjectsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var projectsVM: ProjectsViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    
    @State private var showingAddProject = false
    @State private var selectedProject: Project?
    @State private var showAddedAlert = false
    
    private let columns = [
        GridItem(.flexible(), spacing: DS.Spacing.md),
        GridItem(.flexible(), spacing: DS.Spacing.md)
    ]
    
    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()
            DSDecorativeBackground()
            
            if projectsVM.isLoading && projectsVM.projects.isEmpty && projectsVM.myPendingProjects.isEmpty {
                VStack(spacing: DS.Spacing.lg) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text(L10n.t("جاري التحميل...", "Loading..."))
                        .font(DS.Font.callout)
                        .foregroundColor(DS.Color.textSecondary)
                }
            } else if projectsVM.projects.isEmpty && projectsVM.myPendingProjects.isEmpty {
                emptyStateView
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: DS.Spacing.lg) {
                        // مشاريع المستخدم المعلقة
                        if !projectsVM.myPendingProjects.isEmpty {
                            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                                DSSectionHeader(
                                    title: L10n.t("بانتظار الموافقة", "Pending Approval"),
                                    icon: "clock.badge.checkmark"
                                )
                                
                                LazyVGrid(columns: columns, spacing: DS.Spacing.md) {
                                    ForEach(projectsVM.myPendingProjects) { project in
                                        pendingProjectCard(project)
                                            .onTapGesture {
                                                selectedProject = project
                                            }
                                    }
                                }
                            }
                        }
                        
                        // المشاريع المعتمدة
                        if !projectsVM.projects.isEmpty {
                            DSSectionHeader(
                                title: L10n.t("المشاريع", "Projects"),
                                icon: "briefcase.fill"
                            )
                        }
                        
                        LazyVGrid(columns: columns, spacing: DS.Spacing.md) {
                            ForEach(projectsVM.projects) { project in
                                projectCard(project)
                                    .onTapGesture {
                                        selectedProject = project
                                    }
                            }
                        }
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.top, DS.Spacing.md)
                    .padding(.bottom, 100)
                }
                .refreshable {
                    await projectsVM.fetchProjects()
                    if let userId = authVM.currentUser?.id {
                        await projectsVM.fetchMyPendingProjects(ownerId: userId)
                    }
                }
            }
            
            // FAB - Add Project
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    DSFloatingButton(
                        icon: "plus"
                    ) {
                        showingAddProject = true
                    }
                    .padding(.trailing, DS.Spacing.xl)
                    .padding(.bottom, DS.Spacing.xxl)
                }
            }
        }
        .task {
            await projectsVM.fetchProjects()
            if let userId = authVM.currentUser?.id {
                await projectsVM.fetchMyPendingProjects(ownerId: userId)
            }
        }
        .sheet(isPresented: $showingAddProject) {
            AddProjectView(showAddedAlert: $showAddedAlert)
                .environmentObject(projectsVM)
                .environmentObject(authVM)
                .environmentObject(memberVM)
        }
        .alert(
            L10n.t("تم إرسال المشروع", "Project Submitted"),
            isPresented: $showAddedAlert
        ) {
            Button(L10n.t("حسناً", "OK"), role: .cancel) {}
        } message: {
            Text(L10n.t(
                "تم إرسال مشروعك للمراجعة. سيظهر بعد موافقة الإدارة.",
                "Your project has been submitted for review. It will appear after admin approval."
            ))
        }
        .sheet(item: $selectedProject) { project in
            ProjectDetailView(project: project)
                .environmentObject(projectsVM)
                .environmentObject(authVM)
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }
    
    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: DS.Spacing.xl) {
            Spacer()
            ZStack {
                Circle()
                    .fill(DS.Color.neonBlue.opacity(0.10))
                    .frame(width: 120, height: 120)
                
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                DS.Color.neonBlue.opacity(0.20),
                                DS.Color.primary.opacity(0.10)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 96, height: 96)
                
                Image(systemName: "briefcase")
                    .font(DS.Font.scaled(40, weight: .bold))
                    .foregroundColor(DS.Color.neonBlue)
            }
            
            VStack(spacing: DS.Spacing.sm) {
                Text(L10n.t("لا توجد مشاريع", "No projects yet"))
                    .font(DS.Font.title3)
                    .fontWeight(.black)
                    .foregroundColor(DS.Color.textPrimary)
                Text(L10n.t("أضف مشروعك ليراه أفراد العائلة", "Add your project for family members to see"))
                    .font(DS.Font.callout)
                    .foregroundColor(DS.Color.textSecondary)
                    .multilineTextAlignment(.center)
            }
            
            Button {
                showingAddProject = true
            } label: {
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: "plus.circle.fill")
                        .font(DS.Font.scaled(20, weight: .bold))
                    Text(L10n.t("إضافة مشروع", "Add Project"))
                        .font(DS.Font.callout)
                        .fontWeight(.bold)
                }
                .foregroundColor(DS.Color.textOnPrimary)
                .padding(.horizontal, DS.Spacing.xxl)
                .padding(.vertical, DS.Spacing.md)
                .background(DS.Color.gradientPrimary)
                .clipShape(Capsule())
            }
            .buttonStyle(DSBoldButtonStyle())
            .padding(.top, DS.Spacing.sm)
            
            Spacer()
        }
    }
    
    // MARK: - Project Card
    private func projectCard(_ project: Project) -> some View {
        DSCard(padding: 0) {
            VStack(spacing: DS.Spacing.sm) {
                // Logo
                if let logoUrl = project.logoUrl, let url = URL(string: logoUrl) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 64, height: 64)
                                .clipShape(Circle())
                        case .failure:
                            projectPlaceholderIcon
                        default:
                            ProgressView()
                                .frame(width: 64, height: 64)
                        }
                    }
                } else {
                    projectPlaceholderIcon
                }
                
                // Title
                Text(project.title)
                    .font(DS.Font.callout)
                    .fontWeight(.bold)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                
                // Owner
                Text(project.ownerName)
                    .font(DS.Font.caption1)
                    .foregroundColor(DS.Color.textSecondary)
                    .lineLimit(1)
            }
            .padding(DS.Spacing.lg)
            .frame(maxWidth: .infinity)
        }
    }
    
    // MARK: - Pending Project Card
    private func pendingProjectCard(_ project: Project) -> some View {
        DSCard(padding: 0) {
            VStack(spacing: DS.Spacing.sm) {
                // Logo
                if let logoUrl = project.logoUrl, let url = URL(string: logoUrl) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 64, height: 64)
                                .clipShape(Circle())
                        case .failure:
                            projectPlaceholderIcon
                        default:
                            ProgressView()
                                .frame(width: 64, height: 64)
                        }
                    }
                } else {
                    projectPlaceholderIcon
                }
                
                // Title
                Text(project.title)
                    .font(DS.Font.callout)
                    .fontWeight(.bold)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                
                // Pending badge
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "clock.fill")
                        .font(DS.Font.scaled(10, weight: .bold))
                    Text(L10n.t("بانتظار الموافقة", "Pending"))
                        .font(DS.Font.caption2)
                        .fontWeight(.bold)
                }
                .foregroundColor(DS.Color.warning)
                .padding(.horizontal, DS.Spacing.sm)
                .padding(.vertical, DS.Spacing.xs)
                .background(DS.Color.warning.opacity(0.12))
                .clipShape(Capsule())
            }
            .padding(DS.Spacing.lg)
            .frame(maxWidth: .infinity)
        }
        .opacity(0.75)
    }
    
    private var projectPlaceholderIcon: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [DS.Color.neonBlue.opacity(0.2), DS.Color.primary.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 64, height: 64)
            Image(systemName: "briefcase.fill")
                .font(DS.Font.scaled(26, weight: .bold))
                .foregroundColor(DS.Color.neonBlue)
        }
    }
}

// MARK: - Add Project View
struct AddProjectView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var projectsVM: ProjectsViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @Environment(\.dismiss) private var dismiss
    @Binding var showAddedAlert: Bool
    
    @State private var title = ""
    @State private var description = ""
    @State private var websiteUrl = ""
    @State private var instagramUrl = ""
    @State private var twitterUrl = ""
    @State private var tiktokUrl = ""
    @State private var whatsappNumber = ""
    @State private var phoneNumber = ""
    @State private var logoImage: UIImage? = nil
    @State private var isSaving = false
    @State private var selectedOwnerId: UUID?
    @State private var showMemberPicker = false
    @State private var memberSearchText = ""
    
    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: DS.Spacing.md) {
                        // Logo picker
                        DSProfilePhotoPicker(
                            selectedImage: $logoImage,
                            enableCrop: true,
                            cropShape: .circle,
                            title: L10n.t("شعار المشروع", "Project Logo"),
                            trailing: L10n.t("اختياري", "Optional"),
                            compactEmptyState: true
                        )
                        
                        DSSectionHeader(title: L10n.t("معلومات المشروع", "Project Info"), icon: "briefcase.fill")
                        
                        DSTextField(
                            label: L10n.t("اسم المشروع", "Project Name"),
                            placeholder: L10n.t("اسم المشروع", "Project Name"),
                            text: $title,
                            icon: "briefcase.fill"
                        )
                        
                        // Owner picker — admin/supervisor only
                        if authVM.canModerate {
                            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                                Text(L10n.t("صاحب المشروع", "Project Owner"))
                                    .font(DS.Font.caption1)
                                    .foregroundColor(DS.Color.textSecondary)
                                
                                Button {
                                    showMemberPicker = true
                                } label: {
                                    HStack(spacing: DS.Spacing.md) {
                                        Image(systemName: "person.fill")
                                            .font(DS.Font.body)
                                            .foregroundColor(DS.Color.primary)
                                            .frame(width: 24)
                                        
                                        if let ownerId = selectedOwnerId,
                                           let member = memberVM.member(byId: ownerId) {
                                            Text(member.fullName)
                                                .font(DS.Font.body)
                                                .foregroundColor(DS.Color.textPrimary)
                                        } else {
                                            Text(authVM.currentUser?.fullName ?? "")
                                                .font(DS.Font.body)
                                                .foregroundColor(DS.Color.textPrimary)
                                            
                                            Text(L10n.t("(أنت)", "(You)"))
                                                .font(DS.Font.caption1)
                                                .foregroundColor(DS.Color.textTertiary)
                                        }
                                        
                                        Spacer()
                                        
                                        Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                                            .font(DS.Font.caption1)
                                            .foregroundColor(DS.Color.textTertiary)
                                    }
                                    .padding(DS.Spacing.md)
                                    .background(DS.Color.surface)
                                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                                            .stroke(DS.Color.textTertiary.opacity(0.15), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                            .sheet(isPresented: $showMemberPicker) {
                                memberPickerSheet
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                            Text(L10n.t("وصف المشروع", "Description"))
                                .font(DS.Font.caption1)
                                .foregroundColor(DS.Color.textSecondary)
                            TextEditor(text: $description)
                                .font(DS.Font.body)
                                .frame(minHeight: 80)
                                .padding(DS.Spacing.sm)
                                .background(DS.Color.surface)
                                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                                        .stroke(DS.Color.textTertiary.opacity(0.3), lineWidth: 1)
                                )
                        }
                        
                        DSSectionHeader(title: L10n.t("حسابات التواصل", "Social Accounts"), icon: "link")
                        
                        socialTextField(platform: .website, placeholder: "https://...", text: $websiteUrl)
                        socialTextField(platform: .instagram, placeholder: "@username", text: $instagramUrl)
                        socialTextField(platform: .twitter, placeholder: "@username", text: $twitterUrl)
                        socialTextField(platform: .tiktok, placeholder: "@username", text: $tiktokUrl)
                        socialTextField(platform: .whatsapp, placeholder: "+965...", text: $whatsappNumber)
                        socialTextField(platform: .phone, placeholder: "+965...", text: $phoneNumber)
                        
                        DSPrimaryButton(
                            L10n.t("إضافة المشروع", "Add Project"),
                            isLoading: isSaving
                        ) {
                            Task { await saveProject() }
                        }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .opacity(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
                        .padding(.top, DS.Spacing.md)
                    }
                    .padding(DS.Spacing.lg)
                    .padding(.bottom, DS.Spacing.xxxl)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("إلغاء", "Cancel")) { dismiss() }
                }
            }
            .navigationTitle(L10n.t("مشروع جديد", "New Project"))
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        }
    }
    
    private func socialTextField(platform: SocialPlatform, placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: DS.Spacing.md) {
            platform.iconView(size: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text(platform.label)
                    .font(DS.Font.caption1)
                    .foregroundColor(DS.Color.textSecondary)
                TextField(placeholder, text: text)
                    .font(DS.Font.body)
            }
        }
        .padding(DS.Spacing.md)
        .background(DS.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .stroke(DS.Color.textTertiary.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - Member Picker Sheet
    
    private var memberPickerSheet: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Search bar
                    HStack(spacing: DS.Spacing.sm) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(DS.Color.textTertiary)
                        TextField(L10n.t("بحث عن عضو...", "Search member..."), text: $memberSearchText)
                            .font(DS.Font.body)
                    }
                    .padding(DS.Spacing.md)
                    .background(DS.Color.surface)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.top, DS.Spacing.sm)
                    
                    List {
                        ForEach(filteredMembers) { member in
                            Button {
                                selectedOwnerId = member.id
                                showMemberPicker = false
                                memberSearchText = ""
                            } label: {
                                HStack(spacing: DS.Spacing.md) {
                                    // Avatar
                                    if let avatarUrl = member.avatarUrl, let url = URL(string: avatarUrl) {
                                        AsyncImage(url: url) { phase in
                                            switch phase {
                                            case .success(let image):
                                                image
                                                    .resizable()
                                                    .aspectRatio(contentMode: .fill)
                                                    .frame(width: 40, height: 40)
                                                    .clipShape(Circle())
                                            default:
                                                memberPlaceholderAvatar
                                            }
                                        }
                                    } else {
                                        memberPlaceholderAvatar
                                    }
                                    
                                    Text(member.fullName)
                                        .font(DS.Font.body)
                                        .foregroundColor(DS.Color.textPrimary)
                                    
                                    Spacer()
                                    
                                    if selectedOwnerId == member.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(DS.Color.primary)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(L10n.t("اختيار صاحب المشروع", "Select Project Owner"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("إلغاء", "Cancel")) {
                        showMemberPicker = false
                        memberSearchText = ""
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t("إعادة تعيين", "Reset")) {
                        selectedOwnerId = nil
                        showMemberPicker = false
                        memberSearchText = ""
                    }
                    .foregroundColor(DS.Color.textSecondary)
                }
            }
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        }
    }
    
    private var memberPlaceholderAvatar: some View {
        ZStack {
            Circle()
                .fill(DS.Color.primary.opacity(0.10))
                .frame(width: 40, height: 40)
            Image(systemName: "person.fill")
                .font(DS.Font.caption1)
                .foregroundColor(DS.Color.primary)
        }
    }
    
    private var filteredMembers: [FamilyMember] {
        let active = memberVM.allMembers.filter { $0.status == .active }
        let query = memberSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty {
            return Array(active.prefix(20))
        }
        return active.filter {
            $0.fullName.lowercased().contains(query)
        }
    }
    
    private func saveProject() async {
        guard let currentUser = authVM.currentUser else { return }
        isSaving = true

        // owner_id لازم يكون المستخدم الحالي (RLS: owner_id = auth.uid())
        // لو اختار عضو ثاني نحفظ اسمه بس الـ owner_id يبقى المستخدم الحالي
        let ownerId = currentUser.id
        let ownerName: String

        if let selectedId = selectedOwnerId,
           let selectedMember = memberVM.member(byId: selectedId) {
            ownerName = selectedMember.fullName
        } else {
            ownerName = currentUser.fullName
        }
        
        // Upload logo if selected
        var uploadedLogoUrl: String? = nil
        if let logoImage {
            let projectId = UUID()
            if let data = logoImage.jpegData(compressionQuality: 0.8) {
                uploadedLogoUrl = await projectsVM.uploadLogo(imageData: data, projectId: projectId)
            }
        }
        
        let success = await projectsVM.addProject(
            ownerId: ownerId,
            ownerName: ownerName,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            description: description.isEmpty ? nil : description,
            logoUrl: uploadedLogoUrl,
            websiteUrl: websiteUrl.isEmpty ? nil : websiteUrl,
            instagramUrl: instagramUrl.isEmpty ? nil : instagramUrl,
            twitterUrl: twitterUrl.isEmpty ? nil : twitterUrl,
            tiktokUrl: tiktokUrl.isEmpty ? nil : tiktokUrl,
            snapchatUrl: nil,
            whatsappNumber: whatsappNumber.isEmpty ? nil : whatsappNumber,
            phoneNumber: phoneNumber.isEmpty ? nil : phoneNumber
        )
        
        if success {
            if let userId = authVM.currentUser?.id {
                await projectsVM.fetchMyPendingProjects(ownerId: userId)
            }
            isSaving = false
            showAddedAlert = true
            dismiss()
        } else {
            isSaving = false
        }
    }
}
