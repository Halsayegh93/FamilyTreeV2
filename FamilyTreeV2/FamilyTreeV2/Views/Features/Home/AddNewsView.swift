import SwiftUI
import PhotosUI

// MARK: - إضافة خبر
struct AddNewsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var newsVM: NewsViewModel
    @EnvironmentObject var appSettingsVM: AppSettingsViewModel
    @Environment(\.dismiss) var dismiss
    @State private var content = ""
    @State private var selectedType = "خبر"
    /// النشر باسم «إدارة العائلة» بدل الاسم الشخصي (للإدارة فقط)
    @State private var postAsAdmin = false
    @State private var selectedImages: [UIImage] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var pollQuestion = ""
    @State private var pollOption1 = ""
    @State private var pollOption2 = ""
    @State private var pollOption3 = ""
    @State private var pollOption4 = ""
    @State private var showPostErrorAlert = false
    @State private var isSubmitting = false
    @State private var isLoadingPhotos = false

    private var normalizedPollOptions: [String] {
        [pollOption1, pollOption2, pollOption3, pollOption4]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var isPollValid: Bool {
        selectedType != "تصويت" || normalizedPollOptions.count >= 2
    }

    private var isPoll: Bool { selectedType == "تصويت" }

    private var availableTypes: [String] {
        let pollsOn = appSettingsVM.settings.pollsEnabled ?? true
        return pollsOn ? NewsTypeHelper.mainTypes : NewsTypeHelper.mainTypes.filter { $0 != "تصويت" }
    }

    private var canSubmit: Bool {
        if isPoll {
            return isPollValid && !isSubmitting
        } else {
            return !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSubmitting
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: DS.Spacing.md) {
                    addNewsTypeSelector

                    // النشر باسم الإدارة — بطاقة بهوية الهيدر، مميّزة عن بقية البطاقات
                    if authVM.canModerate { adminIdentityCard }

                    if isPoll {
                        addNewsPollSection
                    } else {
                        addNewsContentSection
                    }

                    addNewsSubmitSection
                }
                .animation(DS.Anim.snappy, value: isPoll)
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.top, DS.Spacing.sm)
                .padding(.bottom, DS.Spacing.xxxl)
            }
            .background(DS.Color.surfaceElevated)
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
            .onChange(of: pickerItems) { items in
                guard !items.isEmpty else { return }
                loadImages(from: items)
            }
        }
    }

    // MARK: - هوية الناشر

    /// بدل مفتاح تشغيل/إطفاء غامض: اختيار هويّة صريح بين بطاقتين —
    /// صورتك واسمك مقابل شعار الإدارة. تشوف بمن ستُنشر قبل ما تنشر.
    private var adminIdentityCard: some View {
        compactCard {
            compactHeader(L10n.t("النشر باسم", "Post as"),
                          icon: "person.crop.circle.badge.checkmark",
                          color: DS.Color.primary)

            HStack(spacing: DS.Spacing.sm) {
                identityOption(isAdmin: false)
                identityOption(isAdmin: true)
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.bottom, DS.Spacing.sm + 2)
        }
    }

    private func identityOption(isAdmin: Bool) -> some View {
        let selected = (postAsAdmin == isAdmin)
        let myName = authVM.currentUser?.firstName ?? L10n.t("باسمي", "Me")

        return Button {
            guard postAsAdmin != isAdmin else { return }
            withAnimation(DS.Anim.snappy) { postAsAdmin = isAdmin }
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    if isAdmin {
                        Circle()
                            .fill(DS.Color.gradientPrimary)
                            .frame(width: 40, height: 40)
                            .overlay(Circle().strokeBorder(DS.Color.headerBorder, lineWidth: 1))
                        Image(systemName: "shield.lefthalf.filled")
                            .font(DS.Font.scaled(17, weight: .bold))
                            .foregroundColor(.white)
                    } else {
                        DSMemberAvatar(
                            name: myName,
                            avatarUrl: authVM.currentUser?.avatarUrl,
                            size: 40,
                            roleColor: DS.Color.primary
                        )
                    }

                    // علامة الاختيار — تحلّ محلّ المفتاح
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(DS.Font.scaled(13, weight: .bold))
                            .foregroundStyle(.white, DS.Color.primary)
                            .background(Circle().fill(DS.Color.cardBackground).frame(width: 15, height: 15))
                            .offset(x: 15, y: 15)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(height: 44)

                Text(isAdmin ? L10n.t("إدارة العائلة", "Family Admin") : myName)
                    .font(DS.Font.scaled(11.5, weight: .bold))
                    .foregroundColor(selected ? DS.Color.primary : DS.Color.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(isAdmin ? L10n.t("منشور رسمي", "Official post")
                             : L10n.t("منشور شخصي", "Personal post"))
                    .font(DS.Font.scaled(9))
                    .foregroundColor(DS.Color.textTertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Spacing.sm + 2)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .fill(selected ? DS.Color.primary.opacity(0.07) : DS.Color.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .strokeBorder(selected ? DS.Color.primary.opacity(0.45)
                                           : DS.Color.textTertiary.opacity(0.12),
                                  lineWidth: selected ? 1.6 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - بطاقة وهيدر مصغّران (نفس التوزيعة، أصغر)

    private func compactCard<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(spacing: 0) { content() }
            .background(DS.Color.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .strokeBorder(DS.Color.textTertiary.opacity(0.10), lineWidth: 1)
            )
            .dsSubtleShadow()
    }

    private func compactHeader(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(DS.Font.scaled(10, weight: .bold))
                .foregroundColor(color)
            Text(title)
                .font(DS.Font.scaled(11, weight: .bold))
                .foregroundColor(color)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.top, DS.Spacing.sm + 2)
        .padding(.bottom, DS.Spacing.xs)
    }

    // MARK: - Type Selector

    private var addNewsTypeSelector: some View {
        compactCard {
            compactHeader(L10n.t("نوع الخبر", "Post Type"), icon: "tag.fill", color: DS.Color.primary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Spacing.sm) {
                    ForEach(availableTypes, id: \.self) { type in
                        let isSelected = selectedType == type
                        let typeColor = NewsTypeHelper.color(for: type)

                        Button(action: {
                            withAnimation(DS.Anim.snappy) { selectedType = type }
                        }) {
                            HStack(spacing: DS.Spacing.sm) {
                                Image(systemName: NewsTypeHelper.icon(for: type))
                                    .font(DS.Font.scaled(11, weight: .bold))
                                    .foregroundColor(isSelected ? DS.Color.textOnPrimary : typeColor)
                                    .frame(width: 22, height: 22)
                                    .background(isSelected ? typeColor : typeColor.opacity(0.12))
                                    .clipShape(Circle())

                                Text(NewsTypeHelper.displayName(for: type))
                                    .font(DS.Font.scaled(11, weight: .bold))
                                    .foregroundColor(isSelected ? typeColor : DS.Color.textSecondary)
                            }
                            .padding(.horizontal, DS.Spacing.sm + 2)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(isSelected ? typeColor.opacity(0.1) : DS.Color.surface.opacity(0.5))
                            )
                            .overlay(
                                Capsule()
                                    .stroke(isSelected ? typeColor.opacity(0.4) : DS.Color.primary.opacity(0.08), lineWidth: 1.5)
                            )
                        }
                        .buttonStyle(DSBoldButtonStyle())
                    }
                }
                .padding(.horizontal, DS.Spacing.md)
            }
            .padding(.bottom, DS.Spacing.sm + 2)
        }
    }

    // MARK: - Content Section (مع شريط الأدوات والصور)
    private var addNewsContentSection: some View {
        compactCard {
            compactHeader(L10n.t("محتوى الخبر", "Post Content"), icon: "text.alignright", color: DS.Color.accent)

            // حقل النص
            ZStack(alignment: .topTrailing) {
                TextEditor(text: $content)
                    .frame(minHeight: 52, maxHeight: .infinity)
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

            // الصور المختارة
            if !selectedImages.isEmpty {
                photosPreview
            }

            // شريط الأدوات (أيقونة الصور)
            contentToolbar
        }
    }

    // MARK: - Content Toolbar
    private var contentToolbar: some View {
        HStack(spacing: DS.Spacing.md) {
            // زر إضافة صور
            PhotosPicker(
                selection: $pickerItems,
                maxSelectionCount: 5,
                matching: .images
            ) {
                HStack(spacing: DS.Spacing.xs) {
                    if isLoadingPhotos {
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(DS.Color.primary)
                    } else {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(DS.Font.scaled(16, weight: .medium))
                    }

                    if !selectedImages.isEmpty {
                        Text("\(selectedImages.count)/5")
                            .font(DS.Font.caption2)
                            .fontWeight(.bold)
                    }
                }
                .foregroundColor(DS.Color.primary)
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.sm)
                .background(DS.Color.primary.opacity(0.06))
                .clipShape(Capsule())
            }
            .disabled(isLoadingPhotos)

            Spacer()
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.bottom, DS.Spacing.md)
    }

    // MARK: - Photos Preview
    private var photosPreview: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Spacing.sm) {
                ForEach(Array(selectedImages.enumerated()), id: \.offset) { idx, image in
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))

                        // زر حذف الصورة
                        Button {
                            let generator = UIImpactFeedbackGenerator(style: .light)
                            generator.impactOccurred()
                            _ = withAnimation(DS.Anim.snappy) {
                                selectedImages.remove(at: idx)
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(DS.Font.scaled(18, weight: .bold))
                                .foregroundStyle(DS.Color.textOnPrimary, DS.Color.error)
                                .dsCardShadow()
                        }
                        .offset(x: 6, y: -6)
                    }
                }
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)
        }
    }

    // MARK: - Poll Section
    private var addNewsPollSection: some View {
        compactCard {
            compactHeader(L10n.t("خيارات التصويت", "Poll Options"), icon: "chart.bar.fill", color: DS.Color.newsVote)

            VStack(spacing: 6) {
                pollField(placeholder: L10n.t("سؤال التصويت (اختياري)", "Poll question (optional)"), text: $pollQuestion, icon: "questionmark.circle")
                pollField(placeholder: L10n.t("الخيار الأول", "Option 1"), text: $pollOption1, icon: "1.circle.fill")
                pollField(placeholder: L10n.t("الخيار الثاني", "Option 2"), text: $pollOption2, icon: "2.circle.fill")
                pollField(placeholder: L10n.t("الخيار الثالث (اختياري)", "Option 3 (optional)"), text: $pollOption3, icon: "3.circle.fill")
                pollField(placeholder: L10n.t("الخيار الرابع (اختياري)", "Option 4 (optional)"), text: $pollOption4, icon: "4.circle.fill")
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.bottom, DS.Spacing.sm + 2)
        }
    }

    // MARK: - Submit Section
    private var addNewsSubmitSection: some View {
        VStack(spacing: DS.Spacing.sm) {
            DSPrimaryButton(
                newsVM.canAutoPublishNews ? L10n.t("نشر الخبر", "Publish Post") : L10n.t("إرسال للمراجعة", "Submit for Review"),
                icon: "paperplane.fill",
                isLoading: isSubmitting,
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
                    Text(L10n.t("يحتاج موافقة الإدارة", "Pending admin review"))
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
                .font(DS.Font.scaled(12, weight: .semibold))
                .foregroundColor(DS.Color.newsVote)
                .frame(width: 20)

            TextField(placeholder, text: text)
                .font(DS.Font.scaled(13))
                .foregroundColor(DS.Color.textPrimary)
        }
        .padding(.horizontal, DS.Spacing.sm + 2)
        .padding(.vertical, 5)
        .background(DS.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .stroke(DS.Color.textTertiary.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - Load Images
    private func loadImages(from items: [PhotosPickerItem]) {
        Task {
            isLoadingPhotos = true
            var loaded: [UIImage] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    loaded.append(image)
                }
            }
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            withAnimation(DS.Anim.snappy) {
                selectedImages = loaded
                isLoadingPhotos = false
            }
        }
    }

    // MARK: - Submit
    private func submitNews() async {
        guard canSubmit, !isSubmitting, let authorId = authVM.currentUser?.id else { return }
        isSubmitting = true
        defer { isSubmitting = false }

        let question = pollQuestion.trimmingCharacters(in: .whitespacesAndNewlines)

        // التصويت: لا صور ولا محتوى — سؤال التصويت يصير المحتوى
        var uploadedURLs: [String] = []
        let finalContent: String
        if isPoll {
            finalContent = L10n.t("تصويت", "Poll")
        } else {
            finalContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
            for image in selectedImages {
                if let url = await newsVM.uploadNewsImage(image: image, for: authorId) { uploadedURLs.append(url) }
            }
        }

        let isPosted = await newsVM.postNews(
            content: finalContent,
            type: selectedType,
            imageURLs: uploadedURLs,
            pollQuestion: isPoll && !question.isEmpty ? question : nil,
            pollOptions: isPoll ? normalizedPollOptions : [],
            asAdminIdentity: postAsAdmin
        )
        if isPosted { dismiss() } else { showPostErrorAlert = true }
    }
}
