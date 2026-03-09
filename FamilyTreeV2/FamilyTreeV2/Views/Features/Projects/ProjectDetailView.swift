import SwiftUI

struct ProjectDetailView: View {
    let project: Project
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var projectsVM: ProjectsViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    
    @State private var showDeleteAlert = false
    
    private var isOwnerOrAdmin: Bool {
        guard let user = authVM.currentUser else { return false }
        return user.id == project.ownerId || authVM.canModerate
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()
                DSDecorativeBackground()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: DS.Spacing.xxl) {
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
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 100, height: 100)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(DS.Color.primary.opacity(0.2), lineWidth: 2)
                            )
                    case .failure:
                        largePlaceholder
                    default:
                        ProgressView()
                            .frame(width: 100, height: 100)
                    }
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
                    socialLinkRow(icon: "globe", label: L10n.t("الموقع الإلكتروني", "Website"),
                                  value: url, color: DS.Color.primary)
                }
                if let url = project.instagramUrl, !url.isEmpty {
                    socialLinkRow(icon: "camera.fill", label: "Instagram",
                                  value: url, color: Color(hex: "#E1306C"))
                }
                if let url = project.twitterUrl, !url.isEmpty {
                    socialLinkRow(icon: "at", label: "X / Twitter",
                                  value: url, color: DS.Color.textPrimary)
                }
                if let url = project.tiktokUrl, !url.isEmpty {
                    socialLinkRow(icon: "play.rectangle.fill", label: "TikTok",
                                  value: url, color: DS.Color.textPrimary)
                }
                if let url = project.snapchatUrl, !url.isEmpty {
                    socialLinkRow(icon: "camera.metering.spot", label: "Snapchat",
                                  value: url, color: Color(hex: "#FFFC00"))
                }
                if let number = project.whatsappNumber, !number.isEmpty {
                    socialLinkRow(icon: "message.fill", label: "WhatsApp",
                                  value: number, color: Color(hex: "#25D366"))
                }
                if let number = project.phoneNumber, !number.isEmpty {
                    socialLinkRow(icon: "phone.fill", label: L10n.t("الهاتف", "Phone"),
                                  value: number, color: DS.Color.success)
                }
            }
        }
    }
    
    private func socialLinkRow(icon: String, label: String, value: String, color: Color) -> some View {
        Button {
            openSocialLink(value)
        } label: {
            DSCard {
                HStack(spacing: DS.Spacing.md) {
                    ZStack {
                        Circle()
                            .fill(color.opacity(0.12))
                            .frame(width: 40, height: 40)
                        Image(systemName: icon)
                            .font(DS.Font.scaled(16, weight: .bold))
                            .foregroundColor(color)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(label)
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
    private func openSocialLink(_ value: String) {
        var urlString = value.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // If it looks like a phone number, use tel:
        if urlString.hasPrefix("+") || urlString.allSatisfy({ $0.isNumber || $0 == "+" || $0 == " " || $0 == "-" }) {
            let cleaned = urlString.filter { $0.isNumber || $0 == "+" }
            if let url = URL(string: "tel:\(cleaned)") {
                openURL(url)
            }
            return
        }
        
        // Add https:// if missing
        if !urlString.hasPrefix("http://") && !urlString.hasPrefix("https://") {
            urlString = "https://\(urlString)"
        }
        
        if let url = URL(string: urlString) {
            openURL(url)
        }
    }
}
