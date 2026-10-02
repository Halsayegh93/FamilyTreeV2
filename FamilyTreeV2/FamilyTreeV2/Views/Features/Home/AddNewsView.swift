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

    /// الأنواع بلا «خبر» (طلب المالك) وبلا «تصويت» — التصويت من زره جنب الصور
    private var availableTypes: [String] {
        NewsTypeHelper.mainTypes.filter { $0 != "تصويت" && $0 != "خبر" }
    }

    private var pollsEnabled: Bool { appSettingsVM.settings.pollsEnabled ?? true }

    private var canSubmit: Bool {
        guard !isSubmitting else { return false }
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
    @Namespace private var identityNS

    private struct PollDraft: Identifiable, Equatable {
        let id = UUID()
        var text = ""
    }

    /// لون القسم يتبع نوع الخبر المختار (الإعلان كحلي رسمي)
    private var headerTint: Color {
        if isPoll { return DS.Color.newsVote }
        return selectedType == "إعلان" ? DS.Color.actionNavy : NewsTypeHelper.color(for: selectedType)
    }

    /// لون أيقونات الأقسام وإطار الكتابة — مثل الرأس، لكن «إعلان» بـ primary: نفس الكحلي
    /// في الفاتح، وأزرق فاتح في الداكن (كحلي الرأس الغامق كان يختفي على بطاقات الداكن)
    private var sectionTint: Color {
        if isPoll { return DS.Color.newsVote }
        return selectedType == "إعلان" ? DS.Color.primary : NewsTypeHelper.color(for: selectedType)
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
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Spacing.sm), count: 4),
                      spacing: DS.Spacing.sm) {
                ForEach(availableTypes, id: \.self) { type in
                    categoryTile(type)
                }
            }
            .opacity(isPoll ? 0.4 : 1)
            .allowsHitTesting(!isPoll)
        }
    }

    private func categoryTile(_ type: String) -> some View {
        let selected = !isPoll && selectedType == type
        // الإعلان: primary (كحلي في الفاتح، أزرق فاتح يُقرأ في الداكن)
        let c = type == "إعلان" ? DS.Color.primary : NewsTypeHelper.color(for: type)
        return Button {
            guard selectedType != type else { return }
            withAnimation(.spring(response: 0.38, dampingFraction: 0.68)) { selectedType = type }
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: NewsTypeHelper.icon(for: type))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(selected ? .white : c)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(selected ? AnyShapeStyle(LinearGradient(colors: [c, c.opacity(0.75)], startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(c.opacity(0.13))))
                    .shadow(color: selected ? c.opacity(0.45) : .clear, radius: 8, y: 3)
                    // «تقليل الحركة»: بلا تكبير — اللون وحده يدلّ على الاختيار
                    .scaleEffect(selected && !reduceMotion ? 1.08 : 1)
                    .accessibilityHidden(true)
                Text(NewsTypeHelper.displayName(for: type))
                    .font(DS.Font.plex(11.5, weight: selected ? .bold : .semibold))
                    .foregroundColor(selected ? c : DS.Color.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Spacing.sm + 1)
            .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .fill(selected ? c.opacity(0.10) : DS.Color.background))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .strokeBorder(selected ? c.opacity(0.55) : DS.Color.textTertiary.opacity(0.12),
                              lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(DSScaleButtonStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - النشر باسم (للإدارة)

    private var identitySection: some View {
        DSComposerSection(
            title: L10n.t("النشر باسم", "Post as"),
            icon: "person.crop.circle.badge.checkmark",
            tint: DS.Color.primary,
            index: 1
        ) {
            HStack(spacing: 4) {
                identityOption(isAdmin: false)
                identityOption(isAdmin: true)
            }
            .padding(4)
            .background(Capsule().fill(DS.Color.background))
            .overlay(Capsule().strokeBorder(DS.Color.textTertiary.opacity(0.15), lineWidth: 1))
        }
    }

    private func identityOption(isAdmin: Bool) -> some View {
        let selected = (postAsAdmin == isAdmin)
        let myName = authVM.currentUser?.firstName ?? L10n.t("باسمي", "Me")
        return Button {
            guard postAsAdmin != isAdmin else { return }
            withAnimation(.spring(response: 0.36, dampingFraction: 0.78)) { postAsAdmin = isAdmin }
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            HStack(spacing: 7) {
                Group {
                    if isAdmin {
                        ZStack {
                            Circle().fill(DS.Color.gradientPrimary)
                            Image(systemName: "megaphone.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .overlay(Circle().strokeBorder(Color.white.opacity(selected ? 0.6 : 0), lineWidth: 1))
                    } else {
                        // المختار على حبّة كحلية — الحرف الأبيض يُقرأ (الكحلي كان يختفي في الفاتح)
                        DSMemberAvatar(name: myName, avatarUrl: authVM.currentUser?.avatarUrl,
                                       size: 28, roleColor: selected ? .white : DS.Color.primary)
                    }
                }
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(isAdmin ? L10n.t("إدارة العائلة", "Family Admin") : myName)
                        .font(DS.Font.plex(12.5, weight: .bold))
                        .lineLimit(1)
                    Text(isAdmin ? L10n.t("منشور رسمي", "Official") : L10n.t("منشور شخصي", "Personal"))
                        .font(DS.Font.plex(10))
                        .opacity(0.8)
                }
                Spacer(minLength: 0)
            }
            .foregroundColor(selected ? .white : DS.Color.textSecondary)
            .padding(.horizontal, DS.Spacing.sm)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background {
                if selected {
                    Capsule()
                        .fill(DSActionFill.style())
                        .matchedGeometryEffect(id: "identity-pill", in: identityNS)
                        .shadow(color: DS.Color.actionNavy.opacity(0.35), radius: 6, y: 2)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
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
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $content)
                        .focused($contentFocused)
                        .frame(minHeight: 104, maxHeight: 190)
                        .scrollContentBackground(.hidden)
                        .dsFieldFont(15)
                        .foregroundColor(DS.Color.textPrimary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                    if content.isEmpty {
                        Text(L10n.t("اكتب الخبر هنا… مناسبة، إعلان، أو خبر يهم العائلة",
                                    "Write your post… an occasion, announcement or family news"))
                            .font(DS.Font.plex(15))
                            .foregroundColor(DS.Color.textTertiary)
                            .padding(.horizontal, 11)
                            .padding(.top, 12)
                            .allowsHitTesting(false)
                    }
                }
                .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).fill(DS.Color.background))
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .strokeBorder(contentFocused ? sectionTint.opacity(0.6) : DS.Color.textTertiary.opacity(0.15),
                                  lineWidth: contentFocused ? 1.5 : 1))
                .animation(.easeInOut(duration: 0.2), value: contentFocused)

                if !selectedImages.isEmpty {
                    DSComposerPhotoStrip(images: $selectedImages, limit: 5, tint: sectionTint, size: 68)
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                }
            }

            // أدوات المحتوى: الصور والتصويت داخل محتوى الخبر (طلب المالك)
            HStack(spacing: DS.Spacing.sm) {
                if !isPoll && selectedImages.isEmpty {
                    PhotosPicker(selection: $pickerItems, maxSelectionCount: 5, matching: .images) {
                        HStack(spacing: 6) {
                            if isLoadingPhotos {
                                ProgressView().scaleEffect(0.7).tint(sectionTint)
                            } else {
                                Image(systemName: "plus").font(.system(size: 11.5, weight: .bold))
                                Image(systemName: "photo.on.rectangle.angled").font(.system(size: 11.5, weight: .semibold))
                            }
                            Text(L10n.t("صور", "Photos")).font(DS.Font.plex(12, weight: .bold))
                        }
                        .foregroundColor(DS.Color.textSecondary)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .overlay(Capsule().strokeBorder(DS.Color.textTertiary.opacity(0.4),
                                                        style: StrokeStyle(lineWidth: 1.2, dash: [4, 3])))
                        // مساحة ضغط ٤٤ نقطة مثل شارة «تصويت» جنبها (DSExtraChip) — الشكل كما هو
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
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

    /// معاينة التصويت داخل المحتوى — الضغط يفتحه للتعديل
    private var pollPreview: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            let q = pollQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
            Text(q.isEmpty ? L10n.t("تصويت بدون سؤال", "Poll without a question") : q)
                .font(DS.Font.plex(14, weight: .bold))
                .foregroundColor(q.isEmpty ? DS.Color.textTertiary : DS.Color.textPrimary)
            ForEach(Array(normalizedPollOptions.enumerated()), id: \.offset) { idx, option in
                HStack(spacing: DS.Spacing.sm) {
                    Text("\(idx + 1)")
                        .font(DS.Font.plex(11, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(DS.Color.newsVote))
                    Text(option)
                        .font(DS.Font.plex(13))
                        .foregroundColor(DS.Color.textPrimary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, DS.Spacing.sm)
                .frame(height: 34)
                .background(
                    GeometryReader { g in
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(DS.Color.newsVote.opacity(0.10))
                            .frame(width: g.size.width * CGFloat(0.35 + 0.15 * Double((idx * 7) % 4)))
                    }
                )
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(DS.Color.background))
            }
            HStack {
                // النص ١٨ نقطة ← مساحة ضغط ٤٤ (١٣ فوق وتحت) بلا تغيير في التخطيط:
                // فوقه صف خيار غير قابل للضغط، وتحته ٢٠ نقطة قبل شارة «تصويت»
                Button { openPollBox() } label: {
                    Label(L10n.t("تعديل", "Edit"), systemImage: "pencil")
                        .font(DS.Font.plex(12, weight: .bold))
                        .foregroundColor(DS.Color.newsVote)
                        .tapArea(vertical: 13)
                }
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { removePoll() }
                } label: {
                    Label(L10n.t("إزالة التصويت", "Remove poll"), systemImage: "trash")
                        .font(DS.Font.plex(12, weight: .bold))
                        .foregroundColor(DS.Color.error)
                        .tapArea(vertical: 13)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(DS.Spacing.sm + 2)
        .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).fill(DS.Color.newsVote.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
            .strokeBorder(DS.Color.newsVote.opacity(0.3), lineWidth: 1))
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
                        Text("\(idx + 1)")
                            .font(DS.Font.plex(12, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(DS.Color.newsVote))
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
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                                    draftOptions.removeAll { $0.id == option.id }
                                }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(DS.Color.error.opacity(0.85))
                                    // الدائرة ٢٤ ← مساحة ضغط ٤٤×٤٤: نحو الحقل بقدر المسافة فقط (بلا
                                    // تغطيته)، والباقي في هامش المربّع؛ والصفوف متباعدة ٤٦ فلا تتداخل
                                    .tapArea(top: 10, leading: 8, bottom: 10, trailing: 12)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(L10n.t("حذف الخيار \(idx + 1)", "Remove option \(idx + 1)"))
                        }
                    }
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                }
                if draftOptions.count < 4 {
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                            draftOptions.append(PollDraft())
                        }
                    } label: {
                        Label(L10n.t("خيار آخر", "Another option"), systemImage: "plus")
                            .font(DS.Font.plex(12.5, weight: .bold))
                            .foregroundColor(DS.Color.newsVote)
                            .frame(maxWidth: .infinity).frame(height: 38)
                            .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                                .strokeBorder(DS.Color.newsVote.opacity(0.45),
                                              style: StrokeStyle(lineWidth: 1.2, dash: [5, 4])))
                            // ٣٨ ← مساحة ضغط ٤٤ (٣ فوق وتحت، ضمن المسافة للجيران) بلا تغيير في التخطيط
                            .tapArea(vertical: 3)
                    }
                    .buttonStyle(DSScaleButtonStyle())
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

// MARK: - مساحة ضغط أكبر (توصية أبل: ٤٤ نقطة)

private extension View {
    /// يكبّر منطقة اللمس حول عنصر صغير بلا تغيير في شكله ولا في التخطيط: الحشوة تُضاف
    /// لمنطقة اللمس ثم تُسترد من التخطيط. القيم محسوبة لكل عنصر حتى لا تتداخل مع جيرانه.
    func tapArea(top: CGFloat = 0, leading: CGFloat = 0, bottom: CGFloat = 0, trailing: CGFloat = 0) -> some View {
        self
            .padding(EdgeInsets(top: top, leading: leading, bottom: bottom, trailing: trailing))
            .contentShape(Rectangle())
            .padding(EdgeInsets(top: -top, leading: -leading, bottom: -bottom, trailing: -trailing))
    }

    func tapArea(horizontal: CGFloat = 0, vertical: CGFloat = 0) -> some View {
        tapArea(top: vertical, leading: horizontal, bottom: vertical, trailing: horizontal)
    }
}
