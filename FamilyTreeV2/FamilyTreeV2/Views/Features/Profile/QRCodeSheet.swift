import SwiftUI

// MARK: - QRCodeSheet
// شيت عرض الرمز التعريفي

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

    var body: some View {
        VStack(spacing: DS.Spacing.lg) {
            // هيدر
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(DS.Font.scaled(28))
                        .foregroundStyle(DS.Color.textTertiary)
                }
                Spacer()
                Text(L10n.t("رمز QR", "QR Code"))
                    .font(DS.Font.headline)
                    .foregroundColor(DS.Color.textPrimary)
                Spacer()
                Image(systemName: "xmark.circle.fill")
                    .font(DS.Font.scaled(28))
                    .foregroundStyle(.clear)
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.top, DS.Spacing.sm)

            if let qrImage {
                // الباركود
                Image(uiImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)

                // الاسم
                Text(lineage)
                    .font(DS.Font.headline)
                    .fontWeight(.bold)
                    .foregroundColor(DS.Color.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DS.Spacing.lg)

                // زر فتح الماسح
                Button {
                    showScanner = true
                } label: {
                    HStack(spacing: DS.Spacing.sm) {
                        Image(systemName: "camera.viewfinder")
                            .font(DS.Font.scaled(14, weight: .semibold))
                        Text(L10n.t("امسح رمز QR لمعرفة صلة القرابة", "Scan QR to discover kinship"))
                            .font(DS.Font.caption1)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(DS.Color.primary)
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.vertical, DS.Spacing.sm)
                    .background(DS.Color.primary.opacity(0.08))
                    .clipShape(Capsule())
                }
                .buttonStyle(DSScaleButtonStyle())

                // زر المشاركة
                Button {
                    showShareSheet = true
                } label: {
                    HStack(spacing: DS.Spacing.sm) {
                        Image(systemName: "square.and.arrow.up")
                            .font(DS.Font.scaled(15, weight: .bold))
                        Text(L10n.t("مشاركة الرمز", "Share Code"))
                            .font(DS.Font.calloutBold)
                    }
                    .foregroundColor(DS.Color.textOnPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.Spacing.md)
                    .background(DS.Color.gradientPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
                }
                .buttonStyle(DSScaleButtonStyle())
                .padding(.horizontal, DS.Spacing.xl)
                .sheet(isPresented: $showShareSheet) {
                    ShareSheet(items: [qrImage, lineage])
                }
            } else {
                ProgressView()
                    .tint(DS.Color.primary)
            }
        }
        .padding(.bottom, DS.Spacing.xl)
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
}

// MARK: - ShareSheet
private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uvc: UIActivityViewController, context: Context) {}
}
