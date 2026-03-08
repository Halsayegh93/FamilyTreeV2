import SwiftUI

struct FamilyProjectsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var projectsVM: ProjectsViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var showingAddProject = false
    @State private var selectedProject: Project?
    
    private let columns = [
        GridItem(.flexible(), spacing: DS.Spacing.md),
        GridItem(.flexible(), spacing: DS.Spacing.md)
    ]
    
    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()
                DSDecorativeBackground()
                
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Button(action: { dismiss() }) {
                            Image(systemName: L10n.isArabic ? "chevron.right" : "chevron.left")
                                .font(DS.Font.scaled(18, weight: .bold))
                                .foregroundColor(DS.Color.textPrimary)
                                .frame(width: 44, height: 44)
                        }
                        
                        Spacer()
                        
                        Text(L10n.t("مشاريع العائلة", "Family Projects"))
                            .font(DS.Font.title2)
                            .fontWeight(.black)
                            .foregroundColor(DS.Color.textPrimary)
                        
                        Spacer()
                        
                        Button(action: { showingAddProject = true }) {
                            Image(systemName: "plus")
                                .font(DS.Font.scaled(18, weight: .bold))
                                .foregroundColor(DS.Color.textPrimary)
                                .frame(width: 44, height: 44)
                        }
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.top, DS.Spacing.sm)
                    .padding(.bottom, DS.Spacing.md)
                    
                    if projectsVM.isLoading && projectsVM.projects.isEmpty {
                        Spacer()
                        ProgressView(L10n.t("جاري التحميل...", "Loading..."))
                        Spacer()
                    } else if projectsVM.projects.isEmpty {
                        emptyStateView
                    } else {
                        ScrollView(showsIndicators: false) {
                            LazyVGrid(columns: columns, spacing: DS.Spacing.md) {
                                ForEach(projectsVM.projects) { project in
                                    projectCard(project)
                                        .onTapGesture {
                                            selectedProject = project
                                        }
                                }
                            }
                            .padding(.horizontal, DS.Spacing.lg)
                            .padding(.bottom, DS.Spacing.xxxl)
                        }
                        .refreshable {
                            await projectsVM.fetchProjects()
                        }
                    }
                }
            }
            .navigationBarHidden(true)
            .task { await projectsVM.fetchProjects() }
            .sheet(isPresented: $showingAddProject) {
                AddProjectView()
                    .environmentObject(projectsVM)
                    .environmentObject(authVM)
            }
            .sheet(item: $selectedProject) { project in
                ProjectDetailView(project: project)
                    .environmentObject(projectsVM)
                    .environmentObject(authVM)
            }
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        }
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
                Text(L10n.t("اضغط + لإضافة مشروع جديد", "Tap + to add a new project"))
                    .font(DS.Font.callout)
                    .foregroundColor(DS.Color.textSecondary)
            }
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
    @Environment(\.dismiss) private var dismiss
    
    @State private var title = ""
    @State private var description = ""
    @State private var websiteUrl = ""
    @State private var instagramUrl = ""
    @State private var twitterUrl = ""
    @State private var tiktokUrl = ""
    @State private var snapchatUrl = ""
    @State private var whatsappNumber = ""
    @State private var phoneNumber = ""
    @State private var logoImage: UIImage? = nil
    @State private var isSaving = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: DS.Spacing.xl) {
                        // Logo picker
                        DSProfilePhotoPicker(
                            selectedImage: $logoImage,
                            enableCrop: true,
                            cropShape: .circle,
                            title: L10n.t("لوقو المشروع", "Project Logo"),
                            trailing: L10n.t("اختياري", "Optional")
                        )
                        
                        DSSectionHeader(title: L10n.t("معلومات المشروع", "Project Info"), icon: "briefcase.fill")
                        
                        DSTextField(
                            label: L10n.t("اسم المشروع", "Project Name"),
                            placeholder: L10n.t("اسم المشروع", "Project Name"),
                            text: $title,
                            icon: "textformat"
                        )
                        
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
                        
                        DSTextField(label: L10n.t("الموقع الإلكتروني", "Website"), placeholder: "https://...", text: $websiteUrl, icon: "globe")
                        DSTextField(label: "Instagram", placeholder: "@username", text: $instagramUrl, icon: "camera.fill")
                        DSTextField(label: "Twitter / X", placeholder: "@username", text: $twitterUrl, icon: "at")
                        DSTextField(label: "TikTok", placeholder: "@username", text: $tiktokUrl, icon: "play.rectangle.fill")
                        DSTextField(label: "Snapchat", placeholder: "@username", text: $snapchatUrl, icon: "camera.metering.spot")
                        DSTextField(label: "WhatsApp", placeholder: "+965...", text: $whatsappNumber, icon: "message.fill")
                        DSTextField(label: L10n.t("رقم الهاتف", "Phone"), placeholder: "+965...", text: $phoneNumber, icon: "phone.fill")
                        
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
    
    private func saveProject() async {
        guard let currentUser = authVM.currentUser else { return }
        isSaving = true
        
        let ownerName = currentUser.firstName.isEmpty ? currentUser.fullName : currentUser.firstName
        
        // Upload logo if selected
        var uploadedLogoUrl: String? = nil
        if let logoImage {
            let projectId = UUID()
            if let data = logoImage.jpegData(compressionQuality: 0.8) {
                uploadedLogoUrl = await projectsVM.uploadLogo(imageData: data, projectId: projectId)
            }
        }
        
        let success = await projectsVM.addProject(
            ownerId: currentUser.id,
            ownerName: ownerName,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            description: description.isEmpty ? nil : description,
            logoUrl: uploadedLogoUrl,
            websiteUrl: websiteUrl.isEmpty ? nil : websiteUrl,
            instagramUrl: instagramUrl.isEmpty ? nil : instagramUrl,
            twitterUrl: twitterUrl.isEmpty ? nil : twitterUrl,
            tiktokUrl: tiktokUrl.isEmpty ? nil : tiktokUrl,
            snapchatUrl: snapchatUrl.isEmpty ? nil : snapchatUrl,
            whatsappNumber: whatsappNumber.isEmpty ? nil : whatsappNumber,
            phoneNumber: phoneNumber.isEmpty ? nil : phoneNumber
        )
        
        isSaving = false
        if success { dismiss() }
    }
}
