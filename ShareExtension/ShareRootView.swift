import SwiftUI
import UIKit

/// واجهة امتداد المشاركة — بسيطة ومكتفية بذاتها (لا تستورد DS التطبيق
/// حتى يبقى الامتداد خفيفاً وسريع الفتح).
struct ShareRootView: View {
    enum State {
        case ready(SharedFile)
        case failed(String)
    }

    let state: State
    let onClose: () -> Void

    @SwiftUI.State private var title = ""
    @SwiftUI.State private var note = ""
    @SwiftUI.State private var category: ShareUploader.Category = .documents
    /// وجهة الملف — الصور تقبل الوجهتين، وPDF للمكتبة فقط
    @SwiftUI.State private var destination: Destination = .library

    enum Destination { case library, avatar }
    @SwiftUI.State private var isUploading = false
    @SwiftUI.State private var didUpload = false
    @SwiftUI.State private var errorText: String?
    @SwiftUI.State private var keyboardHeight: CGFloat = 0
    @SwiftUI.State private var keyboardDuration: Double = 0.25

    /// منطقة الأمان السفلى (شريط الهوم) — تُقرأ من GeometryReader لأن
    /// UIApplication.shared غير متاح داخل الامتدادات.
    @SwiftUI.State private var safeBottom: CGFloat = 0

    private var keyboardVisible: Bool { keyboardHeight > 0 }

    /// حشو أسفل المحتوى: مع الكيبورد هامش صغير يكفي، وبدونه نترك
    /// مساحة شريط الهوم حتى لا يلتصق الزر بحافة الشاشة.
    private var contentBottomInset: CGFloat {
        keyboardVisible ? 0 : safeBottom + 20
    }

    private let brand = Color(red: 0.21, green: 0.49, blue: 0.93)      // #357DED
    private let brandDeep = Color(red: 0.14, green: 0.38, blue: 0.75)  // #2460C0
    private let indigo = Color(red: 0.33, green: 0.22, blue: 0.86)     // #5438DC

    private var gradient: LinearGradient {
        LinearGradient(colors: [brandDeep, brand, indigo],
                       startPoint: .bottomTrailing, endPoint: .topLeading)
    }

    private var canUpload: Bool {
        guard !isUploading, !didUpload else { return false }
        // الصورة الشخصية لا تحتاج عنواناً
        if destination == .avatar { return true }
        return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

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
    }

    private var card: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
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
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 2)
            }

            // الزر يلحق المحتوى مباشرة — لا يُدفع لأسفل الشاشة
            if case .ready(let file) = state, !didUpload {
                uploadButton(file)
                    .padding(.horizontal, 16)
                    .padding(.bottom, contentBottomInset)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - نموذج الرفع

    private func formView(_ file: SharedFile) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            // الملف المشارَك
            HStack(spacing: 10) {
                Image(systemName: file.isPDF ? "doc.text.fill" : "photo.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(brand)
                    .frame(width: 34, height: 34)
                    .background(brand.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.name)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(file.sizeText)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            // وجهة الرفع — تظهر للصور فقط
            if !file.isPDF {
                VStack(alignment: .leading, spacing: 6) {
                    label("أين تريدها؟")
                    HStack(spacing: 8) {
                        destinationChip(.library, icon: "archivebox.fill", title: "للمكتبة")
                        destinationChip(.avatar, icon: "person.crop.circle.fill", title: "صورتي الشخصية")
                    }
                }
            }

            if destination == .library {
                field("العنوان", text: $title, placeholder: "اسم يعرّف الملف")
                field("وصف (اختياري)", text: $note, placeholder: "ملاحظات أو سياق")

                // القسم
                VStack(alignment: .leading, spacing: 6) {
                    label("القسم")
                    HStack(spacing: 6) {
                        ForEach(ShareUploader.Category.allCases) { c in
                            categoryChip(c)
                        }
                    }
                }
            } else {
                HStack(spacing: 7) {
                    Image(systemName: "crop")
                        .font(.system(size: 11, weight: .bold))
                    Text("تُقصّ مربّعة من المنتصف تلقائياً")
                        .font(.system(size: 11))
                }
                .foregroundColor(.secondary)
            }

            if let errorText {
                Text(errorText)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

        }
    }

    /// زر الرفع — مثبّت أسفل الشاشة فلا يبقى فراغ أبيض تحته
    private func uploadButton(_ file: SharedFile) -> some View {
        Button {
            Task { await upload(file) }
        } label: {
            HStack(spacing: 7) {
                if isUploading {
                    ProgressView().tint(.white).scaleEffect(0.85)
                } else {
                    Image(systemName: "icloud.and.arrow.up.fill")
                        .font(.system(size: 13, weight: .bold))
                }
                Text(isUploading
                     ? "جارٍ الرفع…"
                     : (destination == .avatar ? "تعيين صورتي الشخصية" : "رفع للمكتبة"))
                    .font(.system(size: 15, weight: .bold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(canUpload ? AnyShapeStyle(gradient)
                                  : AnyShapeStyle(Color.secondary.opacity(0.35)))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .disabled(!canUpload)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "archivebox.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(gradient))
            VStack(alignment: .leading, spacing: 1) {
                Text("مكتبة العائلة")
                    .font(.system(size: 14, weight: .bold))
                Text("رفع ملف من المشاركة")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
            Button("إلغاء") { onClose() }
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .disabled(isUploading)
        }
    }

    private func destinationChip(_ d: Destination, icon: String, title: String) -> some View {
        let selected = destination == d
        return Button {
            destination = d
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                Text(title)
                    .font(.system(size: 11.5, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundColor(selected ? .white : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                Group {
                    if selected {
                        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(gradient)
                    } else {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    }
                }
            )
        }
        .buttonStyle(.plain)
    }

    private func categoryChip(_ c: ShareUploader.Category) -> some View {
        let selected = category == c
        return Button {
            category = c
        } label: {
            VStack(spacing: 3) {
                Image(systemName: c.icon)
                    .font(.system(size: 12, weight: .bold))
                Text(c.title)
                    .font(.system(size: 9.5, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundColor(selected ? .white : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                Group {
                    if selected {
                        RoundedRectangle(cornerRadius: 11, style: .continuous).fill(gradient)
                    } else {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    }
                }
            )
        }
        .buttonStyle(.plain)
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            self.label(label)
            TextField(placeholder, text: text)
                .font(.system(size: 13))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(.secondary)
    }

    // MARK: - النجاح والفشل

    private var successView: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 46))
                .foregroundColor(.green)
            Text(destination == .avatar ? "تم تحديث صورتك" : "تم الرفع للمكتبة")
                .font(.system(size: 16, weight: .bold))
            Text(destination == .avatar
                 ? "تلقاها في: حسابي"
                 : "تلقاه في: الرئيسية ← مكتبة العائلة")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 22)
        .onAppear {
            Task {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                onClose()
            }
        }
    }

    private func failureView(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 34))
                .foregroundColor(.orange)
            Text(message)
                .font(.system(size: 13))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("إغلاق") { onClose() }
                .font(.system(size: 14, weight: .bold))
                .padding(.top, 4)
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 8)
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
