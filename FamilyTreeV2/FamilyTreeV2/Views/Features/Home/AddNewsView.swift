import SwiftUI
import PhotosUI

// MARK: - إضافة خبر
struct AddNewsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var newsVM: NewsViewModel
    @EnvironmentObject var appSettingsVM: AppSettingsViewModel
    @Environment(\.dismiss) var dismiss
    /// «تقليل الحركة» (توصية أبل): تلاشٍ بدل التكبير والانزلاق
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var content = ""
    @State private var selectedType = "إعلان"
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

    /// الأنواع كما فعّلتها الإدارة في «التصنيفات» (المصدر الواحد — كان «خبر» مُستثنى هنا يدوياً فلا يظهر
    /// وهو مفعّل في اللوحة، ٢٠٢٦-١٠-٠٩)، بلا «تصويت» — التصويت من زره جنب الصور
    private var availableTypes: [String] {
        NewsTypeHelper.mainTypes.filter { $0 != "تصويت" }
    }

    private var pollsEnabled: Bool { appSettingsVM.settings.pollsEnabled ?? true }

    private var canSubmit: Bool {
        guard !isSubmitting, selectedImages.count <= RemoteSettings.int("news_max_photos", 5, range: 1...10) else { return false }
        // التصويت يخفي نص الخبر، فالشرط خياراته لا النص
        if isPoll { return isPollValid }
        return !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// ما أدخله المستخدم ولم يُنشر (نص، صور، تصويت) — «إلغاء» يسأل قبل التجاهل (توصية أبل).
    /// التصنيف و«النشر باسم» اختيار فقط فلا يُحتسبان.
    private var hasUnsavedChanges: Bool {
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !selectedImages.isEmpty || isLoadingPhotos
            || isPoll
    }

    // MARK: - المربّع الإضافي (التصويت)

    private enum NewsExtra: String, Identifiable { case poll; var id: String { rawValue } }
    @State private var activeExtra: NewsExtra?
    @State private var draftQuestion = ""
    @State private var draftOptions: [PollDraft] = [PollDraft(), PollDraft()]
    @FocusState private var contentFocused: Bool

    private struct PollDraft: Identifiable, Equatable {
        let id = UUID()
        var text = ""
    }

    /// «خبر» العادي (أو نوع بلا لون خاص) — إطار المربّع بلون قسم الأخبار لا بكحلي العلامة
    /// (طلب المالك ٢٠٢٦-١٠-٠٥ «وحتى الاخبار»). الأنواع ذات المعنى (إعلان، زواج، وفاة…) بلونها.
    private var isPlainNewsType: Bool {
        selectedType != "إعلان" && NewsTypeHelper.color(for: selectedType) == DS.Color.brand
    }

    /// لون القسم يتبع نوع الخبر المختار (الإعلان كحلي رسمي ثابت — معنى لا يتبع لون التبويب)
    private var headerTint: Color {
        if isPoll { return DS.Color.newsVote }
        if isPlainNewsType { return AppSection.news.fill }
        return selectedType == "إعلان" ? DS.Color.brandFill : NewsTypeHelper.color(for: selectedType)
    }

    /// لون أيقونات الأقسام وإطار الكتابة — مثل الرأس، لكن «إعلان» بـ brand: نفس الكحلي
    /// في الفاتح، وأزرق فاتح في الداكن (كحلي الرأس الغامق كان يختفي على بطاقات الداكن)
    private var sectionTint: Color {
        if isPoll { return DS.Color.newsVote }
        if isPlainNewsType { return AppSection.news.ink }
        return selectedType == "إعلان" ? DS.Color.brand : NewsTypeHelper.color(for: selectedType)
    }

    private var headerIcon: String {
        isPoll ? "chart.bar.fill" : NewsTypeHelper.icon(for: selectedType)
    }

    var body: some View {
        DSComposer(
            title: L10n.t("خبر جديد", "New Post"),
            subtitle: isPoll ? L10n.t("تصويت لأفراد العائلة", "A poll for the family")
                             : L10n.t("شارك العائلة · \(NewsTypeHelper.displayName(for: selectedType))",
                                      "Share with the family · \(NewsTypeHelper.displayName(for: selectedType))"),
            icon: headerIcon,
            tint: headerTint,
            actionTitle: newsVM.canAutoPublishNews ? L10n.t("نشر", "Publish") : L10n.t("إرسال للمراجعة", "Submit"),
            actionIcon: "paperplane.fill",
            canSubmit: canSubmit,
            isBusy: isSubmitting,
            note: newsVM.canAutoPublishNews ? nil : L10n.t("يحتاج موافقة الإدارة قبل الظهور", "Needs admin approval before it appears"),
            isBehindExtra: activeExtra != nil,
            hasUnsavedChanges: hasUnsavedChanges,
            onSubmit: { Task { await submitNews() } },
            onCancel: { dismiss() }
        ) {
            categorySection
            if authVM.canModerate { identitySection }
            contentSection
        }
        .dsExtraBox(item: $activeExtra) { _ in pollBox }
        .dsAlert(L10n.t("تعذر النشر", "Post Failed"), isPresented: $showPostErrorAlert) {
            Button(L10n.t("حسناً", "OK")) {}
        } message: { Text(newsVM.newsPostErrorMessage ?? L10n.t("حدث خطأ أثناء نشر الخبر.", "An error occurred.")) }
        .onChange(of: pickerItems) { items in
            guard !items.isEmpty else { return }
            loadImages(from: items)
        }
        // مربّع الأخبار بلون قسم الأخبار (زر النشر، النشر باسم، التصويت، الرسائل)
        .dsSectionPage(.news)
    }

    // MARK: - التصنيف

    private var categorySection: some View {
        DSComposerSection(
            title: L10n.t("التصنيف", "Category"),
            icon: "square.grid.2x2.fill",
            tint: sectionTint,
            trailing: isPoll ? L10n.t("غير مطلوب للتصويت", "Not needed for polls") : nil,
            index: 0
        ) {
            // مربّعات الاختيار الموحّدة (`DSOptionTiles`) بشارة كل نوع — مشتركة مع «تعديل الخبر»
            NewsTypeTiles(types: availableTypes, selection: $selectedType, disabled: isPoll)
        }
    }

    // MARK: - النشر باسم (للإدارة)

    private var identitySection: some View {
        DSComposerSection(
            title: L10n.t("النشر باسم", "Post as"),
            icon: "person.crop.circle.badge.checkmark",
            tint: DS.Color.primary,
            trailing: postAsAdmin ? L10n.t("منشور رسمي", "Official") : L10n.t("منشور شخصي", "Personal"),
            index: 1
        ) {
            // المبدّل الموحّد (`DSSegmentedSwitch`) بدل الكبسولة المرسومة باليد
            DSSegmentedSwitch(options: [
                DSSegmentOption(id: false, title: authVM.currentUser?.firstName ?? L10n.t("باسمي", "Me"),
                                icon: "person.fill"),
                DSSegmentOption(id: true, title: L10n.t("إدارة العائلة", "Family Admin"), icon: "megaphone.fill")
            ], selection: $postAsAdmin)
        }
    }

    // MARK: - المحتوى (مع الصور والتصويت)

    private var contentSection: some View {
        DSComposerSection(
            title: isPoll ? L10n.t("التصويت", "Poll") : L10n.t("محتوى الخبر", "Post Content"),
            icon: isPoll ? "chart.bar.fill" : "text.alignright",
            tint: sectionTint,
            trailing: (!isPoll && !content.isEmpty) ? "\(content.count)" : nil,
            index: 2
        ) {
            if isPoll {
                pollPreview
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.92).combined(with: .opacity))
            } else {
                NewsContentEditor(text: $content,
                                  placeholder: L10n.t("اكتب الخبر هنا… مناسبة، إعلان، أو خبر يهم العائلة",
                                                      "Write your post… an occasion, announcement or family news"),
                                  tint: sectionTint, focused: $contentFocused)

                if !selectedImages.isEmpty {
                    DSComposerPhotoStrip(images: $selectedImages, limit: RemoteSettings.int("news_max_photos", 5, range: 1...10), tint: sectionTint)
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                }
            }

            // أدوات المحتوى: الصور والتصويت داخل محتوى الخبر (طلب المالك)
            HStack(spacing: DS.Spacing.sm) {
                if !isPoll && selectedImages.isEmpty {
                    PhotosPicker(selection: $pickerItems, maxSelectionCount: RemoteSettings.int("news_max_photos", 5, range: 1...10), matching: .images) {
                        // نفس وجه شريحة «تصويت» جنبها (DSExtraChip)
                        DSAddChipLabel(icon: "photo.on.rectangle.angled", title: L10n.t("صور", "Photos"),
                                       isLoading: isLoadingPhotos)
                    }
                    .disabled(isLoadingPhotos)
                    .accessibilityLabel(L10n.t("إضافة صور", "Add photos"))
                }
                if pollsEnabled {
                    DSExtraChip(
                        icon: "chart.bar.fill",
                        title: L10n.t("تصويت", "Poll"),
                        tint: DS.Color.newsVote,
                        summary: isPoll ? L10n.t("تصويت · \(normalizedPollOptions.count) خيارات",
                                                 "Poll · \(normalizedPollOptions.count) options") : nil
                    ) { openPollBox() }
                }
                Spacer(minLength: 0)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isPoll)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: selectedImages.count)
    }

    /// معاينة التصويت داخل المحتوى — الضغط يفتحه للتعديل (القطعة المشتركة مع «تعديل الخبر»)
    private var pollPreview: some View {
        NewsPollPreview(question: pollQuestion, options: normalizedPollOptions,
                        onEdit: { openPollBox() },
                        onRemove: { withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { removePoll() } })
    }

    // MARK: - مربّع التصويت

    private var draftValidCount: Int {
        draftOptions.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }

    private var pollBox: some View {
        DSExtraBox(
            title: L10n.t("تصويت", "Poll"),
            subtitle: L10n.t("خياران على الأقل، وحتى أربعة", "At least two options, up to four"),
            icon: "chart.bar.fill",
            tint: DS.Color.newsVote,
            doneTitle: isPoll ? L10n.t("حفظ", "Save") : L10n.t("إضافة التصويت", "Add poll"),
            doneEnabled: draftValidCount >= 2,
            onDone: commitPoll,
            onCancel: { dsCloseExtra { activeExtra = nil } }
        ) {
            VStack(spacing: DS.Spacing.sm) {
                TextField(L10n.t("سؤال التصويت (اختياري)", "Poll question (optional)"), text: $draftQuestion)
                    .dsAlertField()
                ForEach(Array(draftOptions.enumerated()), id: \.element.id) { idx, option in
                    HStack(spacing: DS.Spacing.sm) {
                        NewsPollNumber(number: idx + 1, size: DS.Spacing.xxl)
                        TextField(idx < 2 ? L10n.t("الخيار \(idx + 1)", "Option \(idx + 1)")
                                          : L10n.t("الخيار \(idx + 1) (اختياري)", "Option \(idx + 1) (optional)"),
                                  text: Binding(
                                    get: { draftOptions.first(where: { $0.id == option.id })?.text ?? "" },
                                    set: { v in
                                        if let i = draftOptions.firstIndex(where: { $0.id == option.id }) {
                                            draftOptions[i].text = v
                                        }
                                    }))
                            .dsAlertField()
                        if draftOptions.count > 2 {
                            NewsPollRemoveOptionButton(label: L10n.t("حذف الخيار \(idx + 1)", "Remove option \(idx + 1)")) {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                                    draftOptions.removeAll { $0.id == option.id }
                                }
                            }
                        }
                    }
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                }
                if draftOptions.count < 4 {
                    NewsPollAddOptionButton {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                            draftOptions.append(PollDraft())
                        }
                    }
                }
            }
        }
    }

    private func openPollBox() {
        draftQuestion = pollQuestion
        let existing = [pollOption1, pollOption2, pollOption3, pollOption4]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        var drafts = existing.map { PollDraft(text: $0) }
        while drafts.count < 2 { drafts.append(PollDraft()) }
        draftOptions = drafts
        contentFocused = false
        activeExtra = .poll
    }

    private func commitPoll() {
        let opts = draftOptions.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        pollQuestion = draftQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        pollOption1 = opts.count > 0 ? opts[0] : ""
        pollOption2 = opts.count > 1 ? opts[1] : ""
        pollOption3 = opts.count > 2 ? opts[2] : ""
        pollOption4 = opts.count > 3 ? opts[3] : ""
        dsCloseExtra { activeExtra = nil }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) { selectedType = "تصويت" }
    }

    private func removePoll() {
        pollQuestion = ""; pollOption1 = ""; pollOption2 = ""; pollOption3 = ""; pollOption4 = ""
        selectedType = availableTypes.first ?? "إعلان"
    }

    // MARK: - Load Images
    private func loadImages(from items: [PhotosPickerItem]) {
        Task {
            isLoadingPhotos = true
            var loaded: [UIImage] = []
            for item in items {
                // فكّ مصغّر خارج الخيط الرئيسي (كان يعلّق عند إضافة الصور — ٢٠٢٦-١٠-٠٥)
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = await Task.detached(priority: .userInitiated, operation: {
                       ImageProcessor.downsampled(data)
                   }).value {
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
