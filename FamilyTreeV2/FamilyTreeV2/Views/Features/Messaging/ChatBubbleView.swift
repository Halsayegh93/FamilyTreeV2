import SwiftUI

/// فقاعة دردشة واحدة بنمط iMessage/WhatsApp.
/// رسائل العضو/المرسل الحالي → يمين، الأخرى → يسار.
struct ChatBubbleView: View {
    let message: ChatMessage
    /// true لو المرسل هو المستخدم الحالي (لتحديد جهة الفقاعة)
    let isCurrentUser: Bool
    /// true لإظهار وقت الإرسال
    let showTimestamp: Bool
    /// true لإظهار اسم المرسل (للإدارة في مساحة جماعية، أو للسطر الأول من مجموعة)
    let showSenderLabel: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if isCurrentUser { Spacer(minLength: 56) }

            VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 2) {
                if showSenderLabel {
                    Text(senderLabel)
                        .font(DS.Font.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(senderColor)
                        .padding(.horizontal, 4)
                }

                Text(message.text)
                    .font(DS.Font.body)
                    .foregroundColor(isCurrentUser ? .white : DS.Color.textPrimary)
                    .multilineTextAlignment(.leading)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(bubbleBackground)
                    .clipShape(BubbleShape(isCurrentUser: isCurrentUser))

                if showTimestamp {
                    Text(timeText)
                        .font(DS.Font.caption2)
                        .foregroundColor(DS.Color.textTertiary)
                        .padding(.horizontal, 4)
                        .padding(.top, 1)
                }
            }

            if !isCurrentUser { Spacer(minLength: 56) }
        }
    }

    // MARK: - Computed

    private var senderLabel: String {
        switch message.senderRole {
        case .admin: return L10n.t("الإدارة", "Admin")
        case .member: return L10n.t("العضو", "Member")
        }
    }

    private var senderColor: Color {
        switch message.senderRole {
        case .admin: return DS.Color.success
        case .member: return DS.Color.primary
        }
    }

    private var bubbleBackground: some View {
        Group {
            if isCurrentUser {
                Rectangle().fill(DS.Color.gradientPrimary)
            } else {
                Rectangle().fill(DS.Color.surfaceElevated)
            }
        }
    }

    private var timeText: String {
        let df = DateFormatter()
        df.dateFormat = "h:mm a"
        df.locale = L10n.isArabic ? Locale(identifier: "ar") : Locale(identifier: "en")
        return df.string(from: message.createdAt)
    }
}

/// شكل الفقاعة مع زاوية مدبّبة عند جهة المرسل.
private struct BubbleShape: Shape {
    let isCurrentUser: Bool

    func path(in rect: CGRect) -> Path {
        let r: CGFloat = 18
        let tip: CGFloat = 4

        var path = Path()
        // مستطيل مدوّر مع زاوية أصغر عند الذيل
        if isCurrentUser {
            path = roundedRect(in: rect, topLeft: r, topRight: r, bottomLeft: r, bottomRight: tip)
        } else {
            path = roundedRect(in: rect, topLeft: r, topRight: r, bottomLeft: tip, bottomRight: r)
        }
        return path
    }

    private func roundedRect(in rect: CGRect, topLeft: CGFloat, topRight: CGFloat, bottomLeft: CGFloat, bottomRight: CGFloat) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        path.move(to: CGPoint(x: topLeft, y: 0))
        path.addLine(to: CGPoint(x: w - topRight, y: 0))
        path.addQuadCurve(to: CGPoint(x: w, y: topRight), control: CGPoint(x: w, y: 0))
        path.addLine(to: CGPoint(x: w, y: h - bottomRight))
        path.addQuadCurve(to: CGPoint(x: w - bottomRight, y: h), control: CGPoint(x: w, y: h))
        path.addLine(to: CGPoint(x: bottomLeft, y: h))
        path.addQuadCurve(to: CGPoint(x: 0, y: h - bottomLeft), control: CGPoint(x: 0, y: h))
        path.addLine(to: CGPoint(x: 0, y: topLeft))
        path.addQuadCurve(to: CGPoint(x: topLeft, y: 0), control: CGPoint(x: 0, y: 0))
        return path
    }
}

/// فاصل تاريخ (Date separator) — يظهر بين رسائل من أيام مختلفة.
struct ChatDateSeparator: View {
    let date: Date

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            Rectangle()
                .fill(DS.Color.textTertiary.opacity(0.2))
                .frame(height: 1)
            Text(formatted)
                .font(DS.Font.caption2)
                .fontWeight(.semibold)
                .foregroundColor(DS.Color.textTertiary)
                .padding(.horizontal, DS.Spacing.sm)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(DS.Color.surface)
                )
            Rectangle()
                .fill(DS.Color.textTertiary.opacity(0.2))
                .frame(height: 1)
        }
        .padding(.vertical, DS.Spacing.xs)
    }

    private var formatted: String {
        if Calendar.current.isDateInToday(date) {
            return L10n.t("اليوم", "Today")
        }
        if Calendar.current.isDateInYesterday(date) {
            return L10n.t("أمس", "Yesterday")
        }
        let df = DateFormatter()
        df.dateStyle = .medium
        df.locale = L10n.isArabic ? Locale(identifier: "ar") : Locale(identifier: "en")
        return df.string(from: date)
    }
}
