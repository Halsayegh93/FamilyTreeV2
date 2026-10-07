import SwiftUI
import UIKit

/// واجهة امتداد المشاركة — بشكل التطبيق اليوم (طلب المالك ٢٠٢٦-١٠-٠٧ «ما طوّرت مربّع المشاركة»):
/// رأس مربّع العمل الملوّن بالبحري، بطاقات `.dsCard()`، مربّعات الاختيار، حقول المربّع، وأزرار ٤٤ الموحّدة،
/// بخط IBM Plex Sans Arabic. القيم من `ShareDS` (مرآة صغيرة لـ DS التطبيق — الامتداد لا يستورده
/// حتى يبقى خفيفاً وسريع الفتح). السلوك (جسر الجلسة والرفع) كما هو.
struct ShareRootView: View {
    enum State {
        case ready(SharedFile)
        case failed(String)
    }

    let state: State
    let onClose: () -> Void

    @SwiftUI.State private var title = ""
    @SwiftUI.State private var note = ""
    @SwiftUI.State private var category: ShareUploader.LiveCategory = ShareUploader.builtInCategories[0]
    /// تصنيفات المكتبة بأسمائها الحالية من السيرفر («التصنيفات» في الإدارة) — المدمجة حتى تصل
    @SwiftUI.State private var categories: [ShareUploader.LiveCategory] = ShareUploader.builtInCategories
    /// وجهة الملف — الصور تقبل الوجهتين، وPDF للمكتبة فقط
    @SwiftUI.State private var destination: Destination = .library

    enum Destination { case library, avatar }
    @SwiftUI.State private var isUploading = false
    @SwiftUI.State private var didUpload = false
    @SwiftUI.State private var errorText: String?
    @SwiftUI.State private var keyboardHeight: CGFloat = 0
    @SwiftUI.State private var keyboardDuration: Double = 0.25
    /// طول المحتوى — منطقة التمرير بطوله (حتى المساحة المتاحة) فتلحقه الأزرار مباشرة
    @SwiftUI.State private var contentHeight: CGFloat = 0

    /// منطقة الأمان السفلى (شريط الهوم) — تُقرأ من GeometryReader لأن
    /// UIApplication.shared غير متاح داخل الامتدادات.
    @SwiftUI.State private var safeBottom: CGFloat = 0

    private var keyboardVisible: Bool { keyboardHeight > 0 }

    /// حشو أسفل الأزرار: مع الكيبورد هامش صغير يكفي، وبدونه نترك
    /// مساحة شريط الهوم حتى لا يلتصق الزر بحافة الشاشة.
    private var contentBottomInset: CGFloat {
        keyboardVisible ? ShareDS.Box.footerBottom : safeBottom + ShareDS.Box.homeBarClearance
    }

    private var canUpload: Bool {
        guard !isUploading, !didUpload else { return false }
        // الصورة الشخصية لا تحتاج عنواناً
        if destination == .avatar { return true }
        return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            ShareDS.Palette.background.ignoresSafeArea()
                // أسماء التصنيفات الحالية من السيرفر (مثل «مجلة العائلة») — يبقى الاختيار على نفس المفتاح
                .task {
                    guard let live = await ShareUploader.fetchCategories() else { return }
                    categories = live
                    category = live.first(where: { $0.key == category.key }) ?? live[0]
                }

            GeometryReader { proxy in
                Color.clear
                    .onAppear { safeBottom = proxy.safeAreaInsets.bottom }
                    .onChange(of: proxy.safeAreaInsets.bottom) { safeBottom = $0 }
            }
            .ignoresSafeArea(.keyboard)

            card
                .padding(.bottom, keyboardVisible ? max(0, keyboardHeight - safeBottom) : 0)
                .ignoresSafeArea(.keyboard)
                .animation(.easeOut(duration: keyboardDuration), value: keyboardHeight)
                .onReceive(NotificationCenter.default.publisher(
                    for: UIResponder.keyboardWillChangeFrameNotification)) { note in
                    guard let info = note.userInfo,
                          let frame = info[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
                    else { return }
                    keyboardDuration =
                        (info[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
                    let screen = UIScreen.main.bounds.height
                    keyboardHeight = max(0, screen - frame.origin.y)
                }
                .onReceive(NotificationCenter.default.publisher(
                    for: UIResponder.keyboardWillHideNotification)) { note in
                    keyboardDuration =
                        (note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey]
                            as? Double) ?? 0.25
                    keyboardHeight = 0
                }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .font(ShareDS.Typeface.role(.body))
    }

    private var card: some View {
        VStack(spacing: 0) {
            // رأس مربّع العمل الموحّد (`DSComposerHeader`)
            ShareBoxHeader(title: "مكتبة العائلة", subtitle: "رفع ملف من المشاركة", icon: "archivebox.fill")

            // المحتوى بطوله ثم يمرّر إن زاد — والأزرار تلحقه مباشرة (لا تُدفع لأسفل الشاشة)
            ScrollView(showsIndicators: false) {
                VStack(spacing: ShareDS.Box.sectionSpacing) {
                    switch state {
                    case .failed(let message):
                        failureView(message)
                    case .ready(let file):
                        if didUpload {
                            successView
                        } else {
                            formView(file)
                        }
                    }
                }
                .padding(.horizontal, ShareDS.Box.contentPadding)
                .padding(.top, ShareDS.Box.contentTop + ShareDS.Spacing.xs)
                .padding(.bottom, ShareDS.Box.contentBottom)
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: ShareContentHeightKey.self, value: proxy.size.height)
                })
            }
            .frame(maxHeight: contentHeight > 0 ? contentHeight : .infinity)
            .layoutPriority(1)
            .onPreferenceChange(ShareContentHeightKey.self) { contentHeight = $0 }

            if case .ready(let file) = state, !didUpload {
                footer(file)
                    .padding(.horizontal, ShareDS.Box.footerHorizontal)
                    .padding(.top, ShareDS.Box.footerTop)
                    .padding(.bottom, contentBottomInset)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - نموذج الرفع

    private func formView(_ file: SharedFile) -> some View {
        VStack(spacing: ShareDS.Box.sectionSpacing) {
            fileCard(file)

            // وجهة الرفع — تظهر للصور فقط
            if !file.isPDF {
                ShareSection(title: "أين تريدها؟", icon: "tray.and.arrow.down.fill") {
                    ShareOptionTiles(options: destinationOptions, selection: $destination, columns: 2)
                }
            }

            if destination == .library {
                VStack(spacing: ShareDS.Box.sectionInnerSpacing) {
                    ShareField(icon: "textformat", label: "العنوان", placeholder: "اسم يعرّف الملف", text: $title)
                    ShareField(icon: "text.alignright", label: "وصف (اختياري)", placeholder: "ملاحظات أو سياق", text: $note)
                }
                .shareCard()

                ShareSection(title: "القسم", icon: "folder.fill") {
                    ShareOptionTiles(options: categoryOptions, selection: $category, columns: 4)
                }
            } else {
                HStack(spacing: ShareDS.Spacing.xsm) {
                    Image(systemName: "crop")
                        .shareGlyph(ShareDS.Glyph.sm)
                        .foregroundColor(ShareDS.Palette.ink)
                        .accessibilityHidden(true)
                    Text("تُقصّ مربّعة من المنتصف تلقائياً")
                        .shareFont(.footnote)
                        .foregroundColor(ShareDS.Palette.fieldValue)
                    Spacer(minLength: 0)
                }
                .shareCard()
            }

            if let errorText {
                HStack(alignment: .top, spacing: ShareDS.Spacing.xsm) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .shareGlyph(ShareDS.Glyph.sm)
                        .accessibilityHidden(true)
                    Text(errorText)
                        .shareFont(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .foregroundColor(ShareDS.Palette.error)
                .shareCard(fill: ShareDS.Palette.error.opacity(ShareDS.Opacity.tintFillSoft))
            }
        }
    }

    /// الملف المشارَك — بطاقة واحدة: قرص مجسّم + الاسم والحجم
    private func fileCard(_ file: SharedFile) -> some View {
        HStack(spacing: ShareDS.Spacing.sm) {
            ShareClayDisc(icon: file.isPDF ? "doc.text.fill" : "photo.fill", size: ShareDS.Icon.row)
            VStack(alignment: .leading, spacing: ShareDS.Spacing.xxs) {
                Text(file.name)
                    .shareFont(.rowTitle)
                    .foregroundColor(ShareDS.Palette.fieldLabel)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(file.sizeText)
                    .shareFont(.footnote)
                    .foregroundColor(ShareDS.Palette.fieldValue)
            }
            Spacer(minLength: 0)
        }
        .shareCard()
    }

    private var destinationOptions: [ShareOption<Destination>] {
        [ShareOption(id: .library, title: "للمكتبة", icon: "archivebox.fill"),
         ShareOption(id: .avatar, title: "صورتي الشخصية", icon: "person.crop.circle.fill")]
    }

    private var categoryOptions: [ShareOption<ShareUploader.LiveCategory>] {
        categories.map { ShareOption(id: $0, title: $0.title, icon: $0.icon) }
    }

    /// صفّ الأزرار الموحّد (`DSBoxButtons`): الإجراء بلون القسم يميناً، والإلغاء الرمادي يساراً
    private func footer(_ file: SharedFile) -> some View {
        HStack(spacing: ShareDS.Box.buttonSpacing) {
            Button {
                Task { await upload(file) }
            } label: {
                HStack(spacing: ShareDS.Box.buttonSpacing) {
                    if isUploading {
                        ProgressView().tint(.white).scaleEffect(ShareDS.Box.spinnerScale)
                    } else {
                        Image(systemName: "icloud.and.arrow.up.fill")
                            .shareGlyph(ShareDS.Glyph.md)
                    }
                    Text(isUploading
                         ? "جارٍ الرفع…"
                         : (destination == .avatar ? "تعيين صورتي الشخصية" : "رفع للمكتبة"))
                }
            }
            .buttonStyle(ShareButtonStyle())
            // أثناء الرفع: نفس اللون بلا خفوت المعطّل، ولا يُضغط مرة ثانية (مثل `DSButton(isLoading:)`)
            .disabled(!canUpload && !isUploading)
            .allowsHitTesting(!isUploading)

            Button("إلغاء", role: .cancel) { onClose() }
                .buttonStyle(ShareButtonStyle(role: .cancel))
                .disabled(isUploading)
        }
    }

    // MARK: - النجاح والفشل

    private var successView: some View {
        VStack(spacing: ShareDS.Spacing.sm) {
            ShareClayDisc(icon: "checkmark", tint: ShareDS.Palette.success, size: ShareDS.Icon.state)
            Text(destination == .avatar ? "تم تحديث صورتك" : "تم الرفع للمكتبة")
                .shareFont(.headline)
                .foregroundColor(ShareDS.Palette.fieldLabel)
            Text(destination == .avatar
                 ? "تلقاها في: حسابي"
                 : "تلقاه في: الرئيسية ← مكتبة العائلة")
                .shareFont(.footnote)
                .foregroundColor(ShareDS.Palette.fieldValue)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, ShareDS.Spacing.lg)
        .shareCard()
        .onAppear {
            Task {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                onClose()
            }
        }
    }

    private func failureView(_ message: String) -> some View {
        VStack(spacing: ShareDS.Spacing.md) {
            ShareClayDisc(icon: "exclamationmark.triangle.fill", tint: ShareDS.Palette.warning, size: ShareDS.Icon.state)
            Text(message)
                .shareFont(.callout)
                .foregroundColor(ShareDS.Palette.fieldLabel)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("إغلاق", role: .cancel) { onClose() }
                .buttonStyle(ShareButtonStyle(role: .cancel))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, ShareDS.Spacing.md)
        .padding(.horizontal, ShareDS.Spacing.sm)
        .shareCard()
    }

    // MARK: - الرفع

    @MainActor
    private func upload(_ file: SharedFile) async {
        errorText = nil
        isUploading = true
        defer { isUploading = false }
        do {
            if destination == .avatar {
                try await ShareUploader.uploadAvatar(fileName: file.name, data: file.data)
            } else {
                try await ShareUploader.upload(
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    description: note,
                    category: category,
                    fileName: file.name,
                    mimeType: file.mimeType,
                    data: file.data
                )
            }
            didUpload = true
        } catch {
            errorText = error.localizedDescription
        }
    }
}

/// طول محتوى المربّع (لتحجيم منطقة التمرير على قدره)
private struct ShareContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
