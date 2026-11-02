import SwiftUI

// MARK: - أجزاء مركز الإشعارات (إعادة التصميم ٢٠٢٦-١٠-٣١، موافقة المالك)
//
// صفّ الإشعار: مربّع المرسل (كحلي برمز ذهبي لـ«الإدارة»، أو دائرة بالحرف الأول للعضو) ← «المرسل · الوقت» ونقطة
// «جديد» الذهبية في الطرف ← العنوان ← سطر النص، أو شرائح الحقول المتغيّرة (`details.changes`)، أو للإدارة على
// `member_change` مربّع «قبل ← بعد». الضغط على إشعار فيه تغييرات يفتح ورقة «التغييرات» من الأسفل.
// كل جزء نوع صغير مستقل (حارس المكدس — الأجسام الكبيرة تُسقط التطبيق على الجهاز).

/// مرسل الإشعار كما يُعرض في الصف والورقة
struct NotificationSenderInfo: Equatable {
    /// «الإدارة» أو اسم العضو (أو للصفوف القديمة: «من فلان»/اسم النوع)
    let name: String
    /// «بواسطة: فلان» — للإدارة فقط حين يكون المرسل «الإدارة» ومعه اسم
    var byline: String? = nil
    /// عضو → دائرة بحرفه الأول، وإلا مربّع كحلي برمز ذهبي
    var isMember: Bool = false
    var avatarUrl: String? = nil
    /// رمز المربّع الكحلي (رمز نوع الإشعار)
    var glyph: String = "bell.fill"
}

extension NotificationSenderInfo {
    /// المرسل من `details.sender` (السيرفر): «الإدارة» (+ «بواسطة: فلان» للإدارة) أو العضو باسمه وحرفه الأول.
    /// الصفوف القديمة بلا مرسل: `legacyName` («من فلان»/«الإدارة» للمالك والمدير كما كان، وإلا اسم النوع)
    static func resolve(_ n: AppNotification, isStaff: Bool, kindIcon: String, legacyName: String,
                        member: (UUID) -> FamilyMember?) -> NotificationSenderInfo {
        guard let s = n.details?.sender else {
            return NotificationSenderInfo(name: legacyName, glyph: kindIcon)
        }
        let name = s.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if s.isAdmin {
            return NotificationSenderInfo(
                name: L10n.t("الإدارة", "Admin"),
                byline: isStaff && !name.isEmpty ? L10n.t("بواسطة: \(name)", "by \(name)") : nil,
                glyph: kindIcon)
        }
        let m = s.id.flatMap(UUID.init(uuidString:)).flatMap(member)
        let shown = !name.isEmpty ? name : (m?.shortFullName ?? L10n.t("عضو", "Member"))
        return NotificationSenderInfo(name: shown, isMember: true, avatarUrl: m?.avatarUrl, glyph: "person.fill")
    }

    /// رمز رأس مربّع التفاصيل
    var headerIcon: String { isMember ? "person.fill" : glyph }

    /// سطر رأس التفاصيل: «المرسل · بواسطة: فلان · الوقت»
    func headerLine(time: String) -> String {
        [name, byline, time].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

// MARK: مربّع المرسل (٤٠ نقطة)

/// حالة المربّع في وضع التحديد (Select2): المختار مربّع ذهبي بعلامة ✓، وغيره بإطار متقطّع
enum NotificationTileSelection { case none, off, on }

struct NotificationSenderTile: View {
    let sender: NotificationSenderInfo
    var size: CGFloat = DS.Icon.avatar
    var selection: NotificationTileSelection = .none

    var body: some View {
        Group {
            if selection == .on {
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .fill(DS.Color.accentLight)
                    .frame(width: size, height: size)
                    .overlay(Image(systemName: "checkmark").dsGlyph(DS.Glyph.xl, weight: .bold)
                        .foregroundColor(DS.Color.navyDeep))
            } else if selection == .off {
                dashed
            } else if sender.isMember {
                DSMemberAvatar(name: sender.name, avatarUrl: sender.avatarUrl, size: size)
            } else {
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .fill(DS.Color.navyFill)
                    .frame(width: size, height: size)
                    .overlay(
                        Image(dsSymbol: sender.glyph)
                            .dsGlyph(DS.Glyph.lg)
                            .foregroundColor(DS.Color.accentLight)
                    )
            }
        }
        .accessibilityHidden(true)
    }

    /// غير المختار: نفس المربّع (أو الدائرة) بإطار متقطّع بلا تعبئة
    private var dashed: some View {
        let stroke = StrokeStyle(lineWidth: DS.Spacing.xxs, dash: [DS.Spacing.xs, DS.Spacing.xs - DS.Border.width])
        return ZStack {
            if sender.isMember {
                Circle().strokeBorder(DS.Color.cardBorderStrong.opacity(DS.Opacity.selectedStroke), style: stroke)
                Text(verbatim: String(sender.name.prefix(1)))
                    .dsFont(.rowTitle)
                    .foregroundColor(DS.Color.textSecondary)
            } else {
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .strokeBorder(DS.Color.cardBorderStrong.opacity(DS.Opacity.selectedStroke), style: stroke)
                Image(dsSymbol: sender.glyph)
                    .dsGlyph(DS.Glyph.lg)
                    .foregroundColor(DS.Color.textTertiary)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: الصفّ

struct NotificationRowContent: View {
    let title: String
    let sender: NotificationSenderInfo
    let time: String
    let unread: Bool
    /// التغييرات المعروضة في الصفّ (فارغة = النص)
    let changes: [AppNotification.NotificationDetails.ChangeEntry]
    /// مربّع «قبل ← بعد» داخل الصفّ (الإدارة على `member_change`) بدل الشرائح
    let showsInlineChanges: Bool
    let isSelecting: Bool
    let isSelected: Bool
    var tint: Color = DS.Color.primary
    /// نصّ الإشعار (سطر واحد) — نفس عرض النص القديم من المركز
    let bodyText: AnyView

    var body: some View {
        HStack(alignment: .top, spacing: DSNoticeMetrics.gap) {
            // وضع التحديد: المربّع نفسه يصير علامة الاختيار (Select2) بدل دائرة منفصلة
            NotificationSenderTile(sender: sender,
                                   selection: isSelecting ? (isSelected ? .on : .off) : .none)
            VStack(alignment: .leading, spacing: DSNoticeMetrics.lineGap) {
                NotificationMetaLine(sender: sender, time: time, unread: unread)
                Text(verbatim: title)
                    .dsFont(unread ? .noticeTitle : .noticeTitleRead)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                detail
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, DSNoticeMetrics.paddingH)
        .padding(.vertical, DSNoticeMetrics.paddingV)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var detail: AnyView {
        if changes.isEmpty { return bodyText }
        if showsInlineChanges { return AnyView(NotificationChangesInline(changes: changes)) }
        return AnyView(NotificationChangeChips(changes: changes))
    }
}

/// «المرسل · بواسطة: فلان · الوقت» ……… • (غير مقروء)
struct NotificationMetaLine: View {
    let sender: NotificationSenderInfo
    let time: String
    let unread: Bool

    var body: some View {
        HStack(spacing: DS.Spacing.xs) {
            Text(verbatim: sender.name)
                .dsFont(.caption)
                .foregroundColor(DS.Color.textSecondary)
                .lineLimit(1)
                .layoutPriority(1)
            if let byline = sender.byline {
                Text(verbatim: "· \(byline)")
                    .dsFont(.micro)
                    .foregroundColor(DS.Color.textTertiary)
                    .lineLimit(1)
            }
            if !time.isEmpty {
                Text(verbatim: "· \(time)")
                    .dsFont(.caption)
                    .monospacedDigit()
                    .foregroundColor(DS.Color.textTertiary)
                    .lineLimit(1)
                    .fixedSize()
            }
            Spacer(minLength: DS.Spacing.xs)
            if unread { DSGoldDot(size: DSNoticeMetrics.unreadDot) }
        }
    }
}

/// شرائح كريمية بأسماء الحقول المتغيّرة (ثلاث أقصى ثم «+N»)
struct NotificationChangeChips: View {
    let changes: [AppNotification.NotificationDetails.ChangeEntry]

    var body: some View {
        HStack(spacing: DS.Spacing.xs) {
            ForEach(Array(changes.prefix(3).enumerated()), id: \.offset) { _, change in
                chip(change.displayLabel)
            }
            if changes.count > 3 {
                chip("+\(changes.count - 3)")
            }
        }
        .lineLimit(1)
        .padding(.top, DS.Spacing.xxs)
        .accessibilityElement(children: .combine)
    }

    private func chip(_ text: String) -> some View {
        Text(verbatim: text)
            .dsFont(.micro)
            .foregroundColor(DS.Color.textSecondary)
            .padding(.horizontal, DS.Spacing.sm)
            .padding(.vertical, DS.Spacing.xxs)
            .background(Capsule().fill(DS.Color.cardBackgroundSoft))
    }
}

/// مربّع «الحقل   قبل(مشطوب أحمر) ← بعد(أخضر)» داخل صفّ الإدارة — ثلاثة أسطر أقصى ثم «+N»
struct NotificationChangesInline: View {
    let changes: [AppNotification.NotificationDetails.ChangeEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            ForEach(Array(changes.prefix(3).enumerated()), id: \.offset) { _, change in
                NotificationChangeInlineLine(change: change)
            }
            if changes.count > 3 {
                Text(verbatim: "+\(changes.count - 3)")
                    .dsFont(.micro)
                    .foregroundColor(DS.Color.textTertiary)
            }
        }
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, DS.Spacing.xsm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
            .fill(DS.Color.cardBackgroundSoft))
        .padding(.top, DS.Spacing.xxs)
    }
}

struct NotificationChangeInlineLine: View {
    let change: AppNotification.NotificationDetails.ChangeEntry

    private func value(_ raw: String?) -> String {
        guard let v = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return "—" }
        return v
    }

    var body: some View {
        HStack(spacing: DS.Spacing.xsm) {
            Text(verbatim: change.displayLabel)
                .dsFont(.micro)
                .foregroundColor(DS.Color.textSecondary)
                .lineLimit(1)
                .fixedSize()
            if change.isImage {
                Text(L10n.t("تم تحديث الصورة", "Photo updated"))
                    .dsFont(.micro)
                    .foregroundColor(DS.Color.textSecondary)
            } else {
                Text(verbatim: value(change.before))
                    .dsFont(.micro)
                    .foregroundColor(DS.Color.error)
                    .strikethrough()
                    .lineLimit(1)
                Image(systemName: L10n.isArabic ? "arrow.left" : "arrow.right")
                    .dsGlyph(DS.Glyph.micro)
                    .foregroundColor(DS.Color.textTertiary)
                Text(verbatim: value(change.after))
                    .dsFont(.badge)
                    .foregroundColor(DS.Color.success)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        // الشطب والسهم لا يُسمعان — «الحقل: قبل … بعد …» سطراً واحداً
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(change.isImage
            ? "\(change.displayLabel): " + L10n.t("تم تحديث الصورة", "Photo updated")
            : L10n.t("\(change.displayLabel): قبل \(value(change.before))، بعد \(value(change.after))",
                     "\(change.displayLabel): before \(value(change.before)), after \(value(change.after))"))
    }
}

struct NotificationSubjectCard: View {
    let name: String
    let avatarUrl: String?
    let isWomenTree: Bool

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            DSMemberAvatar(name: name, avatarUrl: avatarUrl, size: DS.Icon.row)
                .accessibilityHidden(true)
            Text(verbatim: name)
                .dsFont(.rowTitle)
                .foregroundColor(DS.Color.textPrimary)
                .lineLimit(2)
            Spacer(minLength: 0)
            if isWomenTree {
                DSStatusChip(text: L10n.t("شجرة النساء", "Women's tree"), tint: DS.Color.female, size: .mini)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsRowBox()
    }
}

struct NotificationChangeCards: View {
    let changes: [AppNotification.NotificationDetails.ChangeEntry]
    let isStaff: Bool
    let subjectName: String

    var body: some View {
        VStack(spacing: DS.Spacing.sm) {
            ForEach(Array(changes.enumerated()), id: \.offset) { _, change in
                NotificationChangeCard(change: change, isStaff: isStaff, subjectName: subjectName)
            }
        }
    }
}

/// بطاقة تغيير واحد: اسم الحقل ثم مربّعان متجاوران «قبل» (أحمر خفيف) و«بعد» (أخضر خفيف) — للعضو «كان» رمادي و«صار»
struct NotificationChangeCard: View {
    let change: AppNotification.NotificationDetails.ChangeEntry
    let isStaff: Bool
    let subjectName: String

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xsm) {
            Text(verbatim: change.displayLabel)
                .dsFieldFont(.label)
                .foregroundColor(DS.Color.fieldLabel)
            HStack(alignment: .top, spacing: DS.Spacing.sm) {
                NotificationValueBox(caption: isStaff ? L10n.t("قبل", "Before") : L10n.t("كان", "Was"),
                                     value: change.before, imageURL: change.isImage ? change.beforeImageURL : nil,
                                     isImage: change.isImage, subjectName: subjectName,
                                     tint: isStaff ? DS.Color.error : DS.Color.textTertiary, emphasized: false)
                NotificationValueBox(caption: isStaff ? L10n.t("بعد", "After") : L10n.t("صار", "Now"),
                                     value: change.after, imageURL: change.isImage ? change.afterImageURL : nil,
                                     isImage: change.isImage, subjectName: subjectName,
                                     tint: DS.Color.success, emphasized: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsRowBox()
    }
}

struct NotificationValueBox: View {
    let caption: String
    let value: String?
    let imageURL: String?
    let isImage: Bool
    let subjectName: String
    let tint: Color
    let emphasized: Bool

    private var text: String {
        guard let v = value?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return "—" }
        return v
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            Text(verbatim: caption)
                .dsFont(.micro)
                .foregroundColor(tint)
            if isImage {
                if let url = imageURL, !url.isEmpty {
                    DSMemberAvatar(name: subjectName, avatarUrl: url, size: DS.Icon.avatar)
                        .accessibilityLabel(caption)
                } else {
                    Text(verbatim: "—")
                        .dsFont(.callout)
                        .foregroundColor(DS.Color.textTertiary)
                }
            } else {
                Text(verbatim: text)
                    .dsFont(emphasized ? .rowTitle : .callout)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(4)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(DS.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
            .fill(tint.opacity(DS.Opacity.tintFill)))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - أجزاء مربّع التفاصيل الموحّد (كل الإشعارات)

enum NotificationDetailParts {
    /// العضو المعني: `details.subject.id` ثم `subject_member_id`
    static func subjectMember(_ n: AppNotification, member: (UUID) -> FamilyMember?) -> FamilyMember? {
        n.details?.subject?.id.flatMap(UUID.init(uuidString:)).flatMap(member)
            ?? n.subjectMemberId.flatMap(member)
    }

    private static let fullFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .full
        f.timeStyle = .short
        return f
    }()

    static func fullDate(_ date: Date) -> String {
        fullFormatter.locale = L10n.isArabic ? Locale(identifier: "ar") : Locale(identifier: "en_US")
        return fullFormatter.string(from: date)
    }
}
