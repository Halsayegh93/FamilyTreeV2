import SwiftUI

// MARK: - Social Platform Brand Icons
enum SocialPlatform {
    case website, instagram, twitter, tiktok, snapchat, whatsapp, phone

    var label: String {
        switch self {
        case .website: return L10n.t("الموقع الإلكتروني", "Website")
        case .instagram: return "Instagram"
        case .twitter: return "X"
        case .tiktok: return "TikTok"
        case .snapchat: return "Snapchat"
        case .whatsapp: return "WhatsApp"
        case .phone: return L10n.t("الهاتف", "Phone")
        }
    }

    var brandColor: Color {
        switch self {
        case .website: return DS.Color.primary
        case .instagram: return Color(hex: "#E1306C")
        case .twitter: return Color(hex: "#000000")
        case .tiktok: return Color(hex: "#010101")
        case .snapchat: return Color(hex: "#FFFC00")
        case .whatsapp: return Color(hex: "#25D366")
        case .phone: return DS.Color.success
        }
    }

    var bgColor: Color {
        switch self {
        case .snapchat: return Color(hex: "#FFFC00")
        case .twitter, .tiktok: return Color(hex: "#000000")
        case .instagram: return Color(hex: "#E1306C")
        case .whatsapp: return Color(hex: "#25D366")
        case .website: return DS.Color.primary
        case .phone: return DS.Color.success
        }
    }

    @ViewBuilder
    func iconView(size: CGFloat = 40) -> some View {
        let iconSize = size * 0.45
        ZStack {
            Circle()
                .fill(DS.Color.primary.opacity(0.10))
                .frame(width: size, height: size)
            
            switch self {
            case .website:
                Image(systemName: "globe")
                    .font(DS.Font.scaled(iconSize, weight: .bold))
                    .foregroundColor(DS.Color.primary)
            case .instagram:
                // Instagram camera icon
                Image(systemName: "camera.fill")
                    .font(DS.Font.scaled(iconSize, weight: .bold))
                    .foregroundColor(DS.Color.primary)
            case .twitter:
                Text("𝕏")
                    .font(DS.Font.scaled(iconSize + 2, weight: .black))
                    .foregroundColor(DS.Color.primary)
            case .tiktok:
                Image(systemName: "music.note")
                    .font(DS.Font.scaled(iconSize, weight: .bold))
                    .foregroundColor(DS.Color.primary)
            case .snapchat:
                Image(systemName: "ghost.fill")
                    .font(DS.Font.scaled(iconSize, weight: .bold))
                    .foregroundColor(DS.Color.primary)
            case .whatsapp:
                Image(systemName: "phone.bubble.fill")
                    .font(DS.Font.scaled(iconSize, weight: .bold))
                    .foregroundColor(DS.Color.primary)
            case .phone:
                Image(systemName: "phone.fill")
                    .font(DS.Font.scaled(iconSize, weight: .bold))
                    .foregroundColor(DS.Color.primary)
            }
        }
    }

    /// SF Symbol name for use in DSTextField
    var sfSymbol: String {
        switch self {
        case .website: return "globe"
        case .instagram: return "camera.fill"
        case .twitter: return "xmark"
        case .tiktok: return "music.note"
        case .snapchat: return "ghost.fill"
        case .whatsapp: return "phone.bubble.fill"
        case .phone: return "phone.fill"
        }
    }
}

struct ProjectDetailView: View {
    let project: Project
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var projectsVM: ProjectsViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    
    @State private var showDeleteAlert = false
    @State private var showEditSheet = false
    @State private var didEdit = false
    
    private var isOwnerOrAdmin: Bool {
        guard let user = authVM.currentUser else { return false }
        return user.id == project.ownerId || authVM.isAdmin
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: DS.Spacing.md) {
                        // Logo + Title
                        projectHeader
                        
                        // Description
                        if let desc = project.description, !desc.isEmpty {
                            descriptionSection(desc)
                        }
                        
                        // Owner
                        ownerSection
                        
                        // Social Media Links
                        if project.hasSocialLinks {
                            socialLinksSection
                        }
                        
                        // Delete button for owner/admin
                        if isOwnerOrAdmin {
                            deleteSection
                        }
                    }
                    .padding(DS.Spacing.lg)
                    .padding(.bottom, DS.Spacing.xxxl)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("إغلاق", "Close")) { dismiss() }
                }
                if isOwnerOrAdmin {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showEditSheet = true
                        } label: {
                            HStack(spacing: DS.Spacing.xs) {
                                Image(systemName: "pencil")
                                    .font(DS.Font.scaled(14, weight: .bold))
                                Text(L10n.t("تعديل", "Edit"))
                                    .font(DS.Font.callout)
                                    .fontWeight(.bold)
                            }
                            .foregroundColor(DS.Color.primary)
                        }
                    }
                }
            }
            .sheet(isPresented: $showEditSheet, onDismiss: {
                if didEdit { dismiss() }
            }) {
                EditProjectView(project: project, didEdit: $didEdit)
                    .environmentObject(projectsVM)
                    .environmentObject(authVM)
            }
            .alert(
                L10n.t("حذف المشروع", "Delete Project"),
                isPresented: $showDeleteAlert
            ) {
                Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
                Button(L10n.t("حذف", "Delete"), role: .destructive) {
                    Task {
                        await projectsVM.deleteProject(id: project.id)
                        dismiss()
                    }
                }
            } message: {
                Text(L10n.t(
                    "هل أنت متأكد من حذف \"\(project.title)\"؟",
                    "Are you sure you want to delete \"\(project.title)\"?"
                ))
            }
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        }
    }
    
    // MARK: - Header
    private var projectHeader: some View {
        VStack(spacing: DS.Spacing.lg) {
            if let logoUrl = project.logoUrl, let url = URL(string: logoUrl) {
                CachedAsyncImage(url: url) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                        .frame(width: 100, height: 100)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(DS.Color.primary.opacity(0.2), lineWidth: 2)
                        )
                } placeholder: {
                    ProgressView().frame(width: 100, height: 100)
                }
            } else {
                largePlaceholder
            }
            
            Text(project.title)
                .font(DS.Font.title1)
                .fontWeight(.black)
                .foregroundColor(DS.Color.textPrimary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, DS.Spacing.lg)
    }
    
    private var largePlaceholder: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [DS.Color.neonBlue.opacity(0.2), DS.Color.primary.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 100, height: 100)
            Image(systemName: "briefcase.fill")
                .font(DS.Font.scaled(40, weight: .bold))
                .foregroundColor(DS.Color.neonBlue)
        }
    }
    
    // MARK: - Description
    private func descriptionSection(_ text: String) -> some View {
        DSCard {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: "text.alignright")
                        .font(DS.Font.scaled(14, weight: .semibold))
                        .foregroundColor(DS.Color.primary)
                    Text(L10n.t("الوصف", "Description"))
                        .font(DS.Font.caption1)
                        .fontWeight(.bold)
                        .foregroundColor(DS.Color.textSecondary)
                }
                Text(text)
                    .font(DS.Font.body)
                    .foregroundColor(DS.Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    // MARK: - Owner
    private var ownerSection: some View {
        DSCard {
            HStack(spacing: DS.Spacing.md) {
                ZStack {
                    Circle()
                        .fill(DS.Color.primary.opacity(0.1))
                        .frame(width: 44, height: 44)
                    Image(systemName: "person.fill")
                        .font(DS.Font.scaled(18, weight: .bold))
                        .foregroundColor(DS.Color.primary)
                }
                
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text(L10n.t("صاحب المشروع", "Project Owner"))
                        .font(DS.Font.caption1)
                        .foregroundColor(DS.Color.textSecondary)
                    Text(project.ownerName)
                        .font(DS.Font.callout)
                        .fontWeight(.bold)
                        .foregroundColor(DS.Color.textPrimary)
                }
                
                Spacer()
            }
        }
    }
    
    // MARK: - Social Links
    private var socialLinksSection: some View {
        VStack(spacing: DS.Spacing.md) {
            DSSectionHeader(
                title: L10n.t("حسابات التواصل", "Social Accounts"),
                icon: "link"
            )
            
            VStack(spacing: DS.Spacing.sm) {
                if let url = project.websiteUrl, !url.isEmpty {
                    socialLinkRow(platform: .website, value: url)
                }
                if let url = project.instagramUrl, !url.isEmpty {
                    socialLinkRow(platform: .instagram, value: url)
                }
                if let url = project.twitterUrl, !url.isEmpty {
                    socialLinkRow(platform: .twitter, value: url)
                }
                if let url = project.tiktokUrl, !url.isEmpty {
                    socialLinkRow(platform: .tiktok, value: url)
                }
                if let number = project.whatsappNumber, !number.isEmpty {
                    socialLinkRow(platform: .whatsapp, value: number)
                }
                if let number = project.phoneNumber, !number.isEmpty {
                    socialLinkRow(platform: .phone, value: number)
                }
            }
        }
    }
    
    private func socialLinkRow(platform: SocialPlatform, value: String) -> some View {
        Button {
            openSocialLink(platform: platform, value: value)
        } label: {
            DSCard {
                HStack(spacing: DS.Spacing.md) {
                    platform.iconView(size: 40)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(platform.label)
                            .font(DS.Font.caption1)
                            .foregroundColor(DS.Color.textSecondary)
                        Text(value)
                            .font(DS.Font.callout)
                            .fontWeight(.medium)
                            .foregroundColor(DS.Color.primary)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "arrow.up.right")
                        .font(DS.Font.scaled(12, weight: .bold))
                        .foregroundColor(DS.Color.textTertiary)
                }
            }
        }
        .buttonStyle(DSScaleButtonStyle())
    }
    
    // MARK: - Delete
    private var deleteSection: some View {
        Button {
            showDeleteAlert = true
        } label: {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: "trash.fill")
                    .font(DS.Font.scaled(14, weight: .bold))
                Text(L10n.t("حذف المشروع", "Delete Project"))
                    .font(DS.Font.callout)
                    .fontWeight(.bold)
            }
            .foregroundColor(DS.Color.error)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Spacing.lg)
        }
    }
    
    // MARK: - Helpers
    private func openSocialLink(platform: SocialPlatform, value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        switch platform {
        case .phone:
            let cleaned = trimmed.filter { $0.isNumber || $0 == "+" }
            if let url = URL(string: "tel:\(cleaned)") { openURL(url) }
            
        case .whatsapp:
            let cleaned = trimmed.filter { $0.isNumber || $0 == "+" }
            let number = cleaned.hasPrefix("+") ? String(cleaned.dropFirst()) : cleaned
            if let url = URL(string: "https://wa.me/\(number)") { openURL(url) }
            
        case .instagram:
            let username = trimmed.replacingOccurrences(of: "@", with: "")
            if trimmed.contains("instagram.com") || trimmed.hasPrefix("http") {
                openWebURL(trimmed)
            } else if let url = URL(string: "https://instagram.com/\(username)") {
                openURL(url)
            }
            
        case .twitter:
            let username = trimmed.replacingOccurrences(of: "@", with: "")
            if trimmed.contains("x.com") || trimmed.contains("twitter.com") || trimmed.hasPrefix("http") {
                openWebURL(trimmed)
            } else if let url = URL(string: "https://x.com/\(username)") {
                openURL(url)
            }
            
        case .tiktok:
            let username = trimmed.hasPrefix("@") ? trimmed : "@\(trimmed)"
            if trimmed.contains("tiktok.com") || trimmed.hasPrefix("http") {
                openWebURL(trimmed)
            } else if let url = URL(string: "https://tiktok.com/\(username)") {
                openURL(url)
            }
            
        case .snapchat:
            let username = trimmed.replacingOccurrences(of: "@", with: "")
            if trimmed.contains("snapchat.com") || trimmed.hasPrefix("http") {
                openWebURL(trimmed)
            } else if let url = URL(string: "https://snapchat.com/add/\(username)") {
                openURL(url)
            }
            
        case .website:
            openWebURL(trimmed)
        }
    }
    
    private func openWebURL(_ value: String) {
        var urlString = value
        if !urlString.hasPrefix("http://") && !urlString.hasPrefix("https://") {
            urlString = "https://\(urlString)"
        }
        if let url = URL(string: urlString) {
            openURL(url)
        }
    }
}

// MARK: - Edit Project View
struct EditProjectView: View {
    let project: Project
    @Binding var didEdit: Bool
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var projectsVM: ProjectsViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var title: String
    @State private var description: String
    @State private var websiteUrl: String
    @State private var instagramUrl: String
    @State private var twitterUrl: String
    @State private var tiktokUrl: String
    @State private var whatsappNumber: String
    @State private var phoneNumber: String
    @State private var logoImage: UIImage? = nil
    @State private var isSaving = false
    
    init(project: Project, didEdit: Binding<Bool>) {
        self.project = project
        _didEdit = didEdit
        _title = State(initialValue: project.title)
        _description = State(initialValue: project.description ?? "")
        _websiteUrl = State(initialValue: project.websiteUrl ?? "")
        _instagramUrl = State(initialValue: project.instagramUrl ?? "")
        _twitterUrl = State(initialValue: project.twitterUrl ?? "")
        _tiktokUrl = State(initialValue: project.tiktokUrl ?? "")
        _whatsappNumber = State(initialValue: project.whatsappNumber ?? "")
        _phoneNumber = State(initialValue: project.phoneNumber ?? "")
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: DS.Spacing.md) {
                        // Logo picker
                        DSProfilePhotoPicker(
                            selectedImage: $logoImage,
                            existingURL: project.logoUrl,
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
                            L10n.t("حفظ التعديلات", "Save Changes"),
                            isLoading: isSaving
                        ) {
                            Task { await saveChanges() }
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
            .navigationTitle(L10n.t("تعديل المشروع", "Edit Project"))
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
    
    private func saveChanges() async {
        isSaving = true
        
        // Upload new logo if selected
        var finalLogoUrl = project.logoUrl
        if let logoImage {
            if let data = ImageProcessor.process(logoImage, for: .projectLogo) {
                if let uploaded = await projectsVM.uploadLogo(imageData: data, projectId: project.id) {
                    finalLogoUrl = uploaded
                }
            }
        }
        
        let success = await projectsVM.updateProject(
            id: project.id,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            description: description.isEmpty ? nil : description,
            logoUrl: finalLogoUrl,
            websiteUrl: websiteUrl.isEmpty ? nil : websiteUrl,
            instagramUrl: instagramUrl.isEmpty ? nil : instagramUrl,
            twitterUrl: twitterUrl.isEmpty ? nil : twitterUrl,
            tiktokUrl: tiktokUrl.isEmpty ? nil : tiktokUrl,
            snapchatUrl: nil,
            whatsappNumber: whatsappNumber.isEmpty ? nil : whatsappNumber,
            phoneNumber: phoneNumber.isEmpty ? nil : phoneNumber
        )
        
        if success {
            await projectsVM.fetchProjects()
            if let userId = authVM.currentUser?.id {
                await projectsVM.fetchMyPendingProjects(ownerId: userId)
            }
            isSaving = false
            didEdit = true
            dismiss()
        } else {
            isSaving = false
        }
    }
}
