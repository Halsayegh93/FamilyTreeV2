import SwiftUI
import AVFoundation

// MARK: - QRScannerView
// ماسح الباركود — يفتح الكاميرا ويمسح QR Code ويعرض صلة القرابة

struct QRScannerView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @Environment(\.dismiss) private var dismiss

    @Binding var selectedTab: Int

    @State private var scannedMemberId: UUID?
    @State private var kinshipResult: KinshipCalculator.KinshipResult?
    /// جلب العضو من السيرفر جارٍ (رمز لعضو غير محمّل)
    @State private var isResolving = false
    /// سبب فشل المسح — يُعرض بدل الخروج الصامت
    @State private var scanErrorMessage: String?
    @State private var scannedMember: FamilyMember?
    @State private var cameraPermissionDenied = false

    var body: some View {
        NavigationStack {
            ZStack {
                if let result = kinshipResult, let member = scannedMember {
                    // نتيجة المسح
                    resultView(member: member, result: result)
                } else if cameraPermissionDenied {
                    permissionDeniedView
                } else {
                    // الكاميرا
                    QRCameraPreview(onCodeScanned: handleScannedCode)
                        .ignoresSafeArea()

                    // إطار المسح
                    scanOverlay

                    if isResolving {
                        // التحميل الواحد: المجسّم يتنفّس + النص، على البطاقة الواحدة
                        DSPageLoader(L10n.t("جارٍ إيجاد العضو…", "Finding member…"), fillsSpace: false)
                            .padding(DS.Spacing.lg)
                            .dsCard(padding: nil)
                            .padding(.horizontal, DS.Spacing.xxxxl)
                    }
                }
            }
            .dsAlert(L10n.t("تعذّر المسح", "Scan Failed"),
                   isPresented: Binding(
                     get: { scanErrorMessage != nil },
                     set: { if !$0 { scanErrorMessage = nil } }
                   )) {
                Button(L10n.t("حسناً", "OK")) { scanErrorMessage = nil }
            } message: {
                Text(scanErrorMessage ?? "")
            }
            // الرأس الملوّن الموحّد للصفحات الفرعية (بدل شريط النظام فوق الكاميرا) — × في الطرف لأنها غطاء
            .dsSubPageHeader(L10n.t("رمز QR", "QR Code"), section: .profile, nav: .close)
            .onAppear {
                checkCameraPermission()
            }
        }
    }

    // MARK: - Scan Overlay
    private var scanOverlay: some View {
        VStack {
            Spacer()

            Text(L10n.t("وجّه الكاميرا نحو رمز QR", "Point camera at QR code"))
                .dsFont(.rowTitle)
                .foregroundColor(DS.Color.textOnPrimary)
                .padding(.horizontal, DS.Spacing.xl)
                .padding(.vertical, DS.Spacing.md)
                .background(DS.Color.shadowOverlay)
                .clipShape(Capsule())
                .padding(.bottom, DS.Spacing.xxxxl)
        }
    }

    // MARK: - Result View
    private func resultView(member: FamilyMember, result: KinshipCalculator.KinshipResult) -> some View {
        VStack(spacing: DS.Spacing.xxl) {
            Spacer()

            // أيقونة النجاح — قرص مجسّم بدل الدوائر والرمز المسطّح
            DSStateIcon("person.2.fill", tint: AppSection.profile.ink, size: DS.Icon.loaderArt, mapsChrome: false)
                .accessibilityHidden(true)

            // اسم العضو
            VStack(spacing: DS.Spacing.sm) {
                Text(member.firstName)
                    .dsFont(.emptyTitle)
                    .foregroundColor(DS.Color.textPrimary)

                Text(KinshipCalculator.lineageText(for: member, lookup: memberVM._memberById))
                    .dsFont(.callout)
                    .foregroundColor(DS.Color.textSecondary)
                    .multilineTextAlignment(.center)
            }

            // صلة القرابة — البطاقة الواحدة
            VStack(spacing: DS.Spacing.md) {
                Text(L10n.t("صلة القرابة", "Kinship"))
                    .dsFont(.caption)
                    .foregroundColor(DS.Color.textTertiary)

                Text(result.relationship)
                    .dsFont(.pageTitle)
                    .foregroundStyle(AppSection.profile.gradient)
                    .multilineTextAlignment(.center)

                if let ancestor = result.commonAncestor, ancestor.id != member.id {
                    HStack(spacing: DS.Spacing.sm) {
                        Image(systemName: "person.3.fill")
                            .dsGlyph(DS.Glyph.sm)
                        Text(L10n.t("الجد المشترك: \(ancestor.firstName)", "Common ancestor: \(ancestor.firstName)"))
                            .dsFont(.subtitle)
                    }
                    .foregroundColor(DS.Color.textSecondary)
                }
            }
            .frame(maxWidth: .infinity)
            .dsCard(padding: DS.Spacing.lg)
            .padding(.horizontal, DS.Spacing.xl)

            Spacer()

            // زر مسح جديد — الزرّ الواحد بمقاس الإجراء الرئيسي (٤٨)
            DSButton(L10n.t("مسح باركود آخر", "Scan another"), icon: "qrcode.viewfinder", size: .large) {
                withAnimation(DS.Anim.snappy) {
                    scannedMemberId = nil
                    scannedMember = nil
                    kinshipResult = nil
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.bottom, DS.Spacing.xl)
        }
    }

    // MARK: - Permission Denied
    private var permissionDeniedView: some View {
        // الحالة الفاضية الواحدة: مجسّم + عنوان + زرّ بالمواصفة الواحدة
        DSEmptyView(L10n.t("يرجى السماح بالوصول للكاميرا", "Please allow camera access"),
                    section: .profile, icon: "camera.fill",
                    actionTitle: L10n.t("فتح الإعدادات", "Open Settings"), actionIcon: "gearshape.fill") {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        }
    }

    // MARK: - Handlers

    private func handleScannedCode(_ code: String) {
        // تحقق إن الكود deep link صحيح
        guard code.hasPrefix("familytree://member/"),
              let idString = code.split(separator: "/").last,
              let memberId = UUID(uuidString: String(idString)) else {
            scanErrorMessage = L10n.t("هذا ليس رمز عضو في العائلة.",
                                      "This isn't a family member code.")
            return
        }

        // تجنب المسح المتكرر
        guard scannedMemberId == nil else { return }
        scannedMemberId = memberId
        Task { await resolveAndShow(memberId) }
    }

    /// يجلب العضو من السيرفر إن لم يكن محمّلاً — كان الماسح يخرج صامتاً
    /// فيظنّ المستخدم أن الرمز لا يعمل.
    @MainActor
    private func resolveAndShow(_ memberId: UUID) async {
        var found = memberVM.member(byId: memberId)
        if found == nil {
            isResolving = true
            await memberVM.fetchSingleMember(id: memberId)
            found = memberVM.member(byId: memberId)
            isResolving = false
        }

        guard let member = found, let currentUser = authVM.currentUser else {
            scannedMemberId = nil        // اسمح بمحاولة أخرى
            scanErrorMessage = L10n.t("هذا الرمز لا يخصّ عضواً في العائلة.",
                                      "This code doesn't belong to a family member.")
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }

        // حساب صلة القرابة
        let result = KinshipCalculator.calculate(
            from: currentUser,
            to: member,
            lookup: memberVM._memberById
        )

        // اهتزاز
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        // بناء كل الـ IDs بالمسار (pathA + pathB) للهايلايت بالشجرة
        var allPathIds = result.pathA.map(\.id) + result.pathB.map(\.id)
        allPathIds.append(currentUser.id)
        allPathIds.append(member.id)

        // إقفال السكانر → الانتقال لتاب الشجرة → إرسال notification
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            selectedTab = 1 // تاب الشجرة
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NotificationCenter.default.post(
                    name: .showKinshipPath,
                    object: nil,
                    userInfo: [
                        "memberId": member.id,
                        "relationship": result.relationship,
                        "pathIds": allPathIds
                    ]
                )
            }
        }
    }

    private func checkCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: break
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if !granted {
                    Task { @MainActor in cameraPermissionDenied = true }
                }
            }
        default:
            cameraPermissionDenied = true
        }
    }
}

// MARK: - Camera Preview (UIKit)

struct QRCameraPreview: UIViewRepresentable {
    let onCodeScanned: (String) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        let session = AVCaptureSession()

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else { return view }

        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        session.addOutput(output)
        output.setMetadataObjectsDelegate(context.coordinator, queue: .main)
        output.metadataObjectTypes = [.qr]

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = UIScreen.main.bounds
        view.layer.addSublayer(previewLayer)

        context.coordinator.session = session
        Task.detached { session.startRunning() }

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCodeScanned: onCodeScanned)
    }

    class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        let onCodeScanned: (String) -> Void
        var session: AVCaptureSession?
        private var hasScanned = false

        init(onCodeScanned: @escaping (String) -> Void) {
            self.onCodeScanned = onCodeScanned
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard !hasScanned,
                  let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  let code = object.stringValue else { return }
            hasScanned = true
            session?.stopRunning()
            onCodeScanned(code)
        }
    }
}
