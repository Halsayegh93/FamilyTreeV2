import SwiftUI

// MARK: - إضافة خبر
struct AddNewsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var newsVM: NewsViewModel
    @Environment(\.dismiss) var dismiss
    @State private var content = ""
    @State private var selectedType = "خبر"
    @State private var selectedImages: [UIImage] = []
    @State private var pollQuestion = ""
    @State private var pollOption1 = ""
    @State private var pollOption2 = ""
    @State private var pollOption3 = ""
    @State private var pollOption4 = ""
    @State private var showPostErrorAlert = false

    private var normalizedPollOptions: [String] {
        [pollOption1, pollOption2, pollOption3, pollOption4]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var isPollValid: Bool {
        selectedType != "تصويت" || normalizedPollOptions.count >= 2
    }

    private var canSubmit: Bool {
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && isPollValid && !authVM.isLoading
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: DS.Spacing.lg) {
                    addNewsTypeSelector
                    addNewsContentSection
                    addNewsPhotosSection

                    if selectedType == "تصويت" {
                        addNewsPollSection
                    }

                    addNewsSubmitSection
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.top, DS.Spacing.sm)
                .padding(.bottom, DS.Spacing.xxxl)
            }
            .background(.ultraThinMaterial)
            .navigationTitle(L10n.t("خبر جديد", "New Post"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.t("إلغاء", "Cancel")) { dismiss() }
                        .font(DS.Font.caption1)
                        .foregroundColor(DS.Color.textSecondary)
                }
            }
            .alert(L10n.t("تعذر النشر", "Post Failed"), isPresented: $showPostErrorAlert) {
                Button(L10n.t("حسناً", "OK"), role: .cancel) {}
            } message: { Text(newsVM.newsPostErrorMessage ?? L10n.t("حدث خطأ أثناء نشر الخبر.", "An error occurred.")) }
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        }
    }

    // MARK: - Type Selector
    private let gridColumns = Array(repeating: GridItem(.flexible(), spacing: DS.Spacing.sm), count: 3)

    private var addNewsTypeSelector: some View {
        DSCard(padding: 0) {
            DSSectionHeader(
                title: L10n.t("نوع الخبر", "Post Type"),
                icon: "tag.fill",
                iconColor: DS.Color.primary
            )

            LazyVGrid(columns: gridColumns, spacing: DS.Spacing.sm) {
                ForEach(NewsTypeHelper.allTypes, id: \.self) { type in
                    let isSelected = selectedType == type
                    let typeColor = NewsTypeHelper.color(for: type)

                    Button(action: {
                        withAnimation(DS.Anim.snappy) { selectedType = type }
                    }) {
                        VStack(spacing: DS.Spacing.xs) {
                            ZStack {
                                Circle()
                                    .fill(isSelected ? typeColor : typeColor.opacity(0.12))
                                    .frame(width: 42, height: 42)

                                Image(systemName: NewsTypeHelper.icon(for: type))
                                    .font(DS.Font.scaled(16, weight: .semibold))
                                    .foregroundColor(isSelected ? .white : typeColor)
                            }

                            Text(NewsTypeHelper.displayName(for: type))
                                .font(DS.Font.caption1)
                                .fontWeight(.bold)
                                .foregroundColor(isSelected ? typeColor : DS.Color.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DS.Spacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                                .fill(isSelected ? typeColor.opacity(0.1) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                                .stroke(isSelected ? typeColor.opacity(0.4) : Color.clear, lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(DSBoldButtonStyle())
                }
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.bottom, DS.Spacing.md)
        }
    }

    // MARK: - Content Section
    private var addNewsContentSection: some View {
        DSCard(padding: 0) {
            DSSectionHeader(
                title: L10n.t("محتوى الخبر", "Post Content"),
                icon: "text.alignright",
                iconColor: DS.Color.accent
            )

            ZStack(alignment: .topTrailing) {
                TextEditor(text: $content)
                    .frame(minHeight: 60, maxHeight: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
                    .scrollContentBackground(.hidden)
                    .font(DS.Font.callout)
                    .foregroundColor(DS.Color.textPrimary)
                    .padding(DS.Spacing.sm)

                if content.isEmpty {
                    Text(L10n.t("اكتب الخبر هنا...", "Write your post here..."))
                        .font(DS.Font.callout)
                        .foregroundColor(DS.Color.textTertiary)
                        .padding(.top, DS.Spacing.md)
                        .padding(.trailing, DS.Spacing.md)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    // MARK: - Photos Section
    private var addNewsPhotosSection: some View {
        DSMultiPhotoPicker(
            selectedImages: $selectedImages,
            maxCount: 5,
            enableCrop: false
        )
    }

    // MARK: - Poll Section
    private var addNewsPollSection: some View {
        DSCard(padding: 0) {
            DSSectionHeader(
                title: L10n.t("خيارات التصويت", "Poll Options"),
                icon: "chart.bar.fill",
                iconColor: DS.Color.newsVote
            )

            VStack(spacing: DS.Spacing.sm) {
                pollField(placeholder: L10n.t("سؤال التصويت (اختياري)", "Poll question (optional)"), text: $pollQuestion, icon: "questionmark.circle")
                pollField(placeholder: L10n.t("الخيار الأول", "Option 1"), text: $pollOption1, icon: "1.circle.fill")
                pollField(placeholder: L10n.t("الخيار الثاني", "Option 2"), text: $pollOption2, icon: "2.circle.fill")
                pollField(placeholder: L10n.t("الخيار الثالث (اختياري)", "Option 3 (optional)"), text: $pollOption3, icon: "3.circle.fill")
                pollField(placeholder: L10n.t("الخيار الرابع (اختياري)", "Option 4 (optional)"), text: $pollOption4, icon: "4.circle.fill")
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.bottom, DS.Spacing.md)
        }
    }

    // MARK: - Submit Section
    private var addNewsSubmitSection: some View {
        VStack(spacing: DS.Spacing.sm) {
            DSPrimaryButton(
                newsVM.canAutoPublishNews ? L10n.t("نشر الخبر", "Publish Post") : L10n.t("إرسال للمراجعة", "Submit for Review"),
                icon: "paperplane.fill",
                isLoading: authVM.isLoading,
                useGradient: canSubmit,
                color: canSubmit ? DS.Color.primary : .gray
            ) {
                Task { await submitNews() }
            }
            .disabled(!canSubmit)
            .opacity(canSubmit ? 1.0 : 0.6)

            if !newsVM.canAutoPublishNews {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "info.circle.fill")
                        .font(DS.Font.scaled(12))
                    Text(L10n.t("سيتم مراجعة الخبر من الإدارة قبل النشر.", "Your post will be reviewed by admin before publishing."))
                        .font(DS.Font.caption2)
                }
                .foregroundColor(DS.Color.textTertiary)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private func pollField(placeholder: String, text: Binding<String>, icon: String) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: icon)
                .font(DS.Font.scaled(14, weight: .medium))
                .foregroundColor(DS.Color.newsVote)
                .frame(width: 24)

            TextField(placeholder, text: text)
                .font(DS.Font.callout)
                .foregroundColor(DS.Color.textPrimary)
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.sm)
        .background(DS.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .stroke(DS.Color.textTertiary.opacity(0.15), lineWidth: 1)
        )
    }

    private func submitNews() async {
        guard canSubmit, let authorId = authVM.currentUser?.id else { return }
        var uploadedURLs: [String] = []
        for image in selectedImages {
            if let url = await newsVM.uploadNewsImage(image: image, for: authorId) { uploadedURLs.append(url) }
        }

        let question = pollQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        let isPosted = await newsVM.postNews(
            content: content.trimmingCharacters(in: .whitespacesAndNewlines),
            type: selectedType,
            imageURLs: uploadedURLs,
            pollQuestion: selectedType == "تصويت" && !question.isEmpty ? question : nil,
            pollOptions: selectedType == "تصويت" ? normalizedPollOptions : []
        )
        if isPosted { dismiss() } else { showPostErrorAlert = true }
    }
}
