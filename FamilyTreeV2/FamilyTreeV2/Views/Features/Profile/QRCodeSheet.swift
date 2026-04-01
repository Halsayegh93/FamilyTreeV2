import SwiftUI

// MARK: - QRCodeSheet
// شيت عرض الرمز التعريفي

struct QRCodeSheet: View {
    @EnvironmentObject var memberVM: MemberViewModel
    @Environment(\.dismiss) private var dismiss

    let member: FamilyMember

    @State private var qrImage: UIImage?

    private var lineage: String {
        let path = KinshipCalculator.ancestorPath(for: member, lookup: memberVM._memberById)
        return path.prefix(8).map(\.firstName).joined(separator: " ")
    }

    var body: some View {
        VStack(spacing: DS.Spacing.xl) {
            // هيدر
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(DS.Font.scaled(22))
                        .foregroundStyle(DS.Color.textTertiary)
                }
                Spacer()
                Text(L10n.t("الرمز التعريفي", "ID Code"))
                    .font(DS.Font.headline)
                    .foregroundColor(DS.Color.textPrimary)
                Spacer()
                // spacer للتوازن
                Image(systemName: "xmark.circle.fill")
                    .font(DS.Font.scaled(22))
                    .foregroundStyle(.clear)
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.top, DS.Spacing.lg)

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

                // التعليمات
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: "camera.viewfinder")
                        .font(DS.Font.scaled(14, weight: .semibold))
                    Text(L10n.t("امسح الباركود لمعرفة صلة القرابة", "Scan to discover kinship"))
                        .font(DS.Font.caption1)
                        .fontWeight(.medium)
                }
                .foregroundColor(DS.Color.primary)
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.sm)
                .background(DS.Color.primary.opacity(0.08))
                .clipShape(Capsule())
            } else {
                ProgressView()
                    .tint(DS.Color.primary)
            }
        }
        .padding(.bottom, DS.Spacing.xl)
        .onAppear {
            let deepLink = QRCodeGenerator.memberDeepLink(memberId: member.id)
            qrImage = QRCodeGenerator.generate(from: deepLink, size: 600)
        }
    }
}
