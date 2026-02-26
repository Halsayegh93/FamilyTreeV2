import SwiftUI

struct MemberNodeView: View {
    let member: FamilyMember
    var onArrowTap: () -> Void

    /// لون موحّد للجميع
    private var roleColor: Color {
        if member.isDeleted { return .gray }
        return DS.Color.primary
    }

    var body: some View {
        VStack(spacing: 7) {
            // دائرة الصورة — Bold gradient circle
            ZStack {
                if member.isDeleted {
                    Circle()
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: 74, height: 74)
                        .overlay(
                            Image(systemName: "person.slash.fill")
                                .foregroundColor(.gray)
                                .font(.system(size: 22, weight: .bold))
                        )
                } else if let urlString = member.photoURL, let url = URL(string: urlString) {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: { ProgressView().tint(DS.Color.primary) }
                    .frame(width: 74, height: 74).clipShape(Circle())
                } else {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [roleColor.opacity(0.18), roleColor.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 74, height: 74)
                        .overlay(
                            Image(systemName: "person.fill")
                                .foregroundColor(roleColor)
                                .font(.system(size: 22, weight: .bold))
                        )
                }

                // حد الدائرة — bold gradient border
                if !member.isDeleted {
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [roleColor, roleColor.opacity(0.4)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2.5
                        )
                        .frame(width: 76, height: 76)
                }

                // شريط الوفاة
                if member.isDeceased ?? false, !member.isDeleted {
                    VStack {
                        Spacer()
                        Text(L10n.t("رحمه الله", "Deceased"))
                            .font(.system(size: 8, weight: .black))
                            .frame(maxWidth: .infinity)
                            .background(Color.black.opacity(0.80))
                            .foregroundColor(.white)
                    }
                    .frame(width: 74, height: 74).clipShape(Circle())
                }
            }
            .opacity(member.isDeleted ? 0.5 : 1.0)
            .shadow(color: member.isDeleted ? .clear : roleColor.opacity(0.2), radius: 8, x: 0, y: 3)

            // كبسولة الاسم — bold gradient background
            HStack(spacing: 4) {
                Text(member.isDeleted ? L10n.t("محذوف", "Deleted") : member.firstName)
                    .font(.system(size: 11, weight: .black))
                    .foregroundColor(.white)

                if !member.isDeleted {
                    Button(action: onArrowTap) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .black))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(
                member.isDeleted
                    ? AnyView(Color.gray.opacity(0.7))
                    : AnyView(
                        LinearGradient(
                            colors: [roleColor, roleColor.opacity(0.7)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
            .clipShape(Capsule())
            .shadow(color: member.isDeleted ? .clear : roleColor.opacity(0.25), radius: 6, x: 0, y: 2)
        }
    }
}
