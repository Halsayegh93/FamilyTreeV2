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
                }
            }
            .background(DS.Color.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(DS.Font.scaled(24))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                ToolbarItem(placement: .principal) {
                    if kinshipResult == nil {
                        Text(L10n.t("الرمز التعريفي", "ID Code"))
                            .font(DS.Font.headline)
                            .foregroundColor(.white)
                    }
                }
            }
            .onAppear {
                checkCameraPermission()
            }
        }
    }

    // MARK: - Scan Overlay
    private var scanOverlay: some View {
        VStack {
            Spacer()

            Text(L10n.t("وجّه الكاميرا نحو الرمز التعريفي", "Point camera at ID code"))
                .font(DS.Font.calloutBold)
                .foregroundColor(.white)
                .padding(.horizontal, DS.Spacing.xl)
                .padding(.vertical, DS.Spacing.md)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .padding(.bottom, DS.Spacing.xxxxl)
        }
    }

    // MARK: - Result View
    private func resultView(member: FamilyMember, result: KinshipCalculator.KinshipResult) -> some View {
        VStack(spacing: DS.Spacing.xxl) {
            Spacer()

            // أيقونة النجاح
            ZStack {
                Circle()
                    .fill(DS.Color.primary.opacity(0.1))
                    .frame(width: 100, height: 100)
                Circle()
                    .fill(DS.Color.primary.opacity(0.2))
                    .frame(width: 80, height: 80)
                Image(systemName: "person.2.fill")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(DS.Color.primary)
            }

            // اسم العضو
            VStack(spacing: DS.Spacing.sm) {
                Text(member.firstName)
                    .font(DS.Font.title1)
                    .fontWeight(.bold)
                    .foregroundColor(DS.Color.textPrimary)

                Text(KinshipCalculator.lineageText(for: member, lookup: memberVM._memberById))
                    .font(DS.Font.callout)
                    .foregroundColor(DS.Color.textSecondary)
                    .multilineTextAlignment(.center)
            }

            // صلة القرابة
            DSCard(padding: DS.Spacing.lg) {
                VStack(spacing: DS.Spacing.md) {
                    Text(L10n.t("صلة القرابة", "Kinship"))
                        .font(DS.Font.caption1)
                        .fontWeight(.semibold)
                        .foregroundColor(DS.Color.textTertiary)

                    Text(result.relationship)
                        .font(DS.Font.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(DS.Color.gradientPrimary)
                        .multilineTextAlignment(.center)

                    if let ancestor = result.commonAncestor, ancestor.id != member.id {
                        HStack(spacing: DS.Spacing.sm) {
                            Image(systemName: "person.3.fill")
                                .font(DS.Font.caption1)
                            Text(L10n.t("الجد المشترك: \(ancestor.firstName)", "Common ancestor: \(ancestor.firstName)"))
                                .font(DS.Font.caption1)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(DS.Color.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, DS.Spacing.xl)

            Spacer()

            // زر مسح جديد
            Button {
                withAnimation(DS.Anim.snappy) {
                    scannedMemberId = nil
                    scannedMember = nil
                    kinshipResult = nil
                }
            } label: {
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: "qrcode.viewfinder")
                        .font(DS.Font.scaled(18, weight: .semibold))
                    Text(L10n.t("مسح باركود آخر", "Scan another"))
                        .font(DS.Font.calloutBold)
                }
                .foregroundColor(DS.Color.textOnPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(DS.Color.gradientPrimary)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.bottom, DS.Spacing.xl)
        }
    }

    // MARK: - Permission Denied
    private var permissionDeniedView: some View {
        VStack(spacing: DS.Spacing.xl) {
            Spacer()
            Image(systemName: "camera.fill")
                .font(.system(size: 50))
                .foregroundColor(DS.Color.textTertiary)
            Text(L10n.t("يرجى السماح بالوصول للكاميرا", "Please allow camera access"))
                .font(DS.Font.headline)
                .foregroundColor(DS.Color.textSecondary)
            Button(L10n.t("فتح الإعدادات", "Open Settings")) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(DS.Font.calloutBold)
            .foregroundColor(DS.Color.primary)
            Spacer()
        }
    }

    // MARK: - Handlers

    private func handleScannedCode(_ code: String) {
        // تحقق إن الكود deep link صحيح
        guard code.hasPrefix("familytree://member/"),
              let idString = code.split(separator: "/").last,
              let memberId = UUID(uuidString: String(idString)) else {
            return
        }

        // تجنب المسح المتكرر
        guard scannedMemberId == nil else { return }
        scannedMemberId = memberId

        // بحث عن العضو
        guard let member = memberVM.member(byId: memberId),
              let currentUser = authVM.currentUser else { return }

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
