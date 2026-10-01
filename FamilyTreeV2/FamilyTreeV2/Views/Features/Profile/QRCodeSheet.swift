import SwiftUI

// MARK: - QRCodeSheet
// مربّع عرض الرمز التعريفي — بتصميم المربّعات الموحّد (طلب المالك):
// رأس ملوّن + بطاقة الرمز + الماسح، و«مشاركة الرمز» كحلي يمين و«إغلاق» يسار.

struct QRCodeSheet: View {
    @EnvironmentObject var memberVM: MemberViewModel
    @Environment(\.dismiss) private var dismiss

    let member: FamilyMember
    @Binding var selectedTab: Int

    @State private var qrImage: UIImage?
    @State private var showShareSheet = false
    @State private var showScanner = false

    private var lineage: String {
        let path = KinshipCalculator.ancestorPath(for: member, lookup: memberVM._memberById)
        return path.prefix(8).map(\.firstName).joined(separator: " ")
    }

    @Environment(\.verticalSizeClass) private var vSizeClass
    /// الوضع الأفقي — رمز أصغر (المربّع يتمرّر عند الحاجة)
    private var isLandscape: Bool { vSizeClass == .compact }

    var body: some View {
        DSComposer(
            title: L10n.t("رمز QR", "QR Code"),
            subtitle: L10n.t("رمزك التعريفي في شجرة العائلة", "Your ID code in the family tree"),
            icon: "qrcode",
            tint: DS.Color.actionNavy,
            actionTitle: L10n.t("مشاركة الرمز", "Share Code"),
            actionIcon: "square.and.arrow.up",
            cancelTitle: L10n.t("إغلاق", "Close"),
            canSubmit: qrImage != nil,
            onSubmit: { showShareSheet = true },
            onCancel: { dismiss() }
        ) {
            codeSection

            // زر فتح الماسح
            scanButton
                .dsStaggerIn(1)
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        // المشاركة (وفيها حفظ الصورة) — ورقة النظام كما كانت
        .sheet(isPresented: $showShareSheet) {
            if let qrImage {
                ShareSheet(items: [qrImage, lineage])
            }
        }
        .fullScreenCover(isPresented: $showScanner) {
            QRScannerView(selectedTab: $selectedTab)
        }
        .task {
            let id = member.id
            let image = await Task.detached {
                await MainActor.run {
                    let deepLink = QRCodeGenerator.memberDeepLink(memberId: id)
                    return QRCodeGenerator.generate(from: deepLink, size: 200)
                }
            }.value
            qrImage = image
        }
    }

    /// الرمز على بطاقة بيضاء (يُقرأ في الوضع الداكن أيضاً) + الاسم تحته
    private var codeSection: some View {
        let side: CGFloat = isLandscape ? 130 : 200
        return DSComposerSection(title: L10n.t("الرمز التعريفي", "ID Code"),
                                 icon: "qrcode",
                                 tint: DS.Color.primary,
                                 index: 0) {
            VStack(spacing: DS.Spacing.md) {
                ZStack {
                    if let qrImage {
                        // الباركود — أصغر في الوضع الأفقي حتى يظهر كل المحتوى
                        Image(uiImage: qrImage)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            // القارئ الصوتي: صورة الرمز بلا اسم كانت تُقرأ «صورة» فقط
                            .accessibilityLabel(L10n.t("رمز QR الخاص بك", "Your QR code"))
                    } else {
                        ProgressView()
                            .tint(DS.Color.primary)
                    }
                }
                .frame(width: side, height: side)
                .padding(DS.Spacing.md)
                .background(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous).fill(Color.white))
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .strokeBorder(DS.Color.textTertiary.opacity(0.15), lineWidth: 1))

                // الاسم
                Text(lineage)
                    .font(DS.Font.plex(15, weight: .bold))
                    .foregroundColor(DS.Color.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Spacing.xs)
        }
    }

    /// فتح الماسح — لمعرفة صلة القرابة من رمز فرد آخر
    private var scanButton: some View {
        Button {
            showScanner = true
        } label: {
            HStack(spacing: DS.Spacing.sm) {
                DSFieldIcon(name: "camera.viewfinder", tint: DS.Color.primary)
                    .accessibilityHidden(true)   // زخرفة
                Text(L10n.t("امسح رمز QR لمعرفة صلة القرابة", "Scan QR to discover kinship"))
                    .font(DS.Font.plex(13.5, weight: .bold))
                    .foregroundColor(DS.Color.fieldLabel)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(DS.Color.textTertiary)
                    .accessibilityHidden(true)   // زخرفة
            }
            .dsRowBox()
            .contentShape(Rectangle())
        }
        .buttonStyle(DSScaleButtonStyle())
    }
}

// MARK: - ShareSheet
private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uvc: UIActivityViewController, context: Context) {}
}
