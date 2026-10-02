import SwiftUI

// MARK: - Social Platform Brand Icons
enum SocialPlatform {
    case website, instagram, twitter, snapchat, whatsapp, phone, location

    var label: String {
        switch self {
        case .website:   return L10n.t("الموقع الإلكتروني", "Website")
        case .instagram: return "Instagram"
        case .twitter:   return "X"
        case .snapchat:  return "Snapchat"
        case .whatsapp:  return "WhatsApp"
        case .phone:     return L10n.t("الهاتف", "Phone")
        case .location:  return L10n.t("الموقع — اللوكيشن", "Location")
        }
    }

    /// لون البراند الأساسي — يُستخدم خلفية للأيقونة.
    var brandColor: Color {
        switch self {
        case .website:   return DS.Color.primary           // أزرق هادئ
        case .instagram: return Color(hex: "#E1306C")     // وردي إنستجرام
        case .twitter:   return Color(hex: "#000000")     // أسود X
        case .snapchat:  return Color(hex: "#FFFC00")     // أصفر Snap
        case .whatsapp:  return Color(hex: "#25D366")     // أخضر WhatsApp
        case .phone:     return DS.Color.success           // أخضر هاتف
        case .location:  return Color(hex: "#EA4335")     // أحمر Maps
        }
    }

    /// gradient إنستجرام الأوفيشيال — للحالة الخاصة فقط.
    private var instagramGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(hex: "#F58529"),   // برتقالي
                Color(hex: "#DD2A7B"),   // وردي
                Color(hex: "#8134AF"),   // بنفسجي
                Color(hex: "#515BD4")    // أزرق
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// لون الأيقونة الأمامية — أبيض غالباً، أسود مع Snapchat الأصفر.
    var foregroundColor: Color {
        switch self {
        case .snapchat: return .black
        default:        return .white
        }
    }

    @ViewBuilder
    func iconView(size: CGFloat = 40) -> some View {
        let iconSize = size * 0.50
        ZStack {
            // خلفية: إنستجرام gradient، الباقي لون موحّد
            if case .instagram = self {
                Circle()
                    .fill(instagramGradient)
                    .frame(width: size, height: size)
                    .shadow(color: brandColor.opacity(0.25), radius: 4, x: 0, y: 2)
            } else {
                Circle()
                    .fill(brandColor)
                    .frame(width: size, height: size)
                    .shadow(color: brandColor.opacity(0.25), radius: 4, x: 0, y: 2)
            }

            Group {
                switch self {
                case .website:
                    Image(systemName: "globe")
                        .font(.system(size: iconSize, weight: .bold))
                case .instagram:
                    Image(systemName: "camera.fill")
                        .font(.system(size: iconSize * 0.95, weight: .bold))
                case .twitter:
                    Text("𝕏")
                        .font(.system(size: iconSize + 2, weight: .black))
                case .snapchat:
                    Image(systemName: "bolt.horizontal.fill")
                        .font(.system(size: iconSize, weight: .bold))
                case .whatsapp:
                    Image(systemName: "message.fill")
                        .font(.system(size: iconSize, weight: .bold))
                case .phone:
                    Image(systemName: "phone.fill")
                        .font(.system(size: iconSize, weight: .bold))
                case .location:
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: iconSize, weight: .bold))
                }
            }
            .foregroundColor(foregroundColor)
        }
    }

    /// SF Symbol name for use in DSTextField
    var sfSymbol: String {
        switch self {
        case .website:   return "globe"
        case .instagram: return "camera.fill"
        case .twitter:   return "xmark"
        case .snapchat:  return "bolt.horizontal.fill"
        case .whatsapp:  return "message.fill"
        case .phone:     return "phone.fill"
        case .location:  return "mappin.and.ellipse"
        }
    }
}

extension SocialPlatform {
    /// اسم قصير للمربّعات
    var shortLabel: String {
        switch self {
        case .website:   return L10n.t("الموقع", "Website")
        case .instagram: return L10n.t("إنستغرام", "Instagram")
        case .twitter:   return L10n.t("إكس", "X")
        case .snapchat:  return L10n.t("سناب", "Snapchat")
        case .whatsapp:  return L10n.t("واتساب", "WhatsApp")
        case .phone:     return L10n.t("الهاتف", "Phone")
        case .location:  return L10n.t("اللوكيشن", "Location")
        }
    }
}

/// «حسابات التواصل» (طلب المالك ٢٠٢٦-٠٩-٢٦): الحسابات المضافة صفوف بأيقونات
/// المنصّات، وزر «إضافة حساب» يفتح مربّعاً إضافياً: اختيار المنصّة ثم إدخال
/// الحساب في نفس المربّع بحركة انتقال. الضغط على صف يفتحه للتعديل أو الحذف.
struct ProjectAccountsEditor: View {
    @Binding var phone: String
    @Binding var whatsapp: String
    @Binding var instagram: String
    @Binding var twitter: String
    @Binding var website: String
    @Binding var location: String
    var tint: Color = DS.Color.primary
    /// يبلّغ المربّع الأساسي ليتقلّص خلف المربّع الإضافي
    var onExtraChange: (Bool) -> Void = { _ in }

    enum Extra: Identifiable {
        case add
        case edit(SocialPlatform)
        var id: String {
            switch self {
            case .add: return "add"
            case .edit(let p): return "edit-\(p.shortLabel)"
            }
        }
    }
    @State private var extra: Extra?
    /// «تقليل الحركة» (توصية أبل): تلاشٍ بدل التكبير
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let platforms: [SocialPlatform] = [.phone, .whatsapp, .instagram, .twitter, .website, .location]

    private func binding(_ p: SocialPlatform) -> Binding<String> {
        switch p {
        case .phone: return $phone
        case .whatsapp: return $whatsapp
        case .instagram: return $instagram
        case .twitter: return $twitter
        case .website: return $website
        case .location: return $location
        case .snapchat: return .constant("")
        }
    }

    private var added: [SocialPlatform] {
        Self.platforms.filter { ProjectContactTiles.isFilled(binding($0).wrappedValue) }
    }

    var body: some View {
        VStack(spacing: DS.Spacing.sm) {
            ForEach(added, id: \.shortLabel) { p in
                row(p)
                    .transition(reduceMotion ? .opacity
                                             : .asymmetric(insertion: .scale(scale: 0.9).combined(with: .opacity),
                                                           removal: .opacity))
            }
            if added.count < Self.platforms.count {
                addButton
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.78), value: added.map(\.shortLabel))
        .dsExtraBox(item: $extra) { ex in
            ProjectAccountBox(
                values: Dictionary(uniqueKeysWithValues: Self.platforms.map { ($0.shortLabel, binding($0)) }),
                start: { if case .edit(let p) = ex { return p } else { return nil } }(),
                tint: tint,
                onClose: { dsCloseExtra { extra = nil } }
            )
        }
        .onChange(of: extra?.id) { onExtraChange($0 != nil) }
    }

    private func row(_ p: SocialPlatform) -> some View {
        let value = binding(p).wrappedValue.trimmingCharacters(in: .whitespaces)
        return Button { extra = .edit(p) } label: {
            HStack(spacing: DS.Spacing.sm) {
                p.iconView(size: 32)
                    .accessibilityHidden(true)   // أيقونة المنصّة — اسمها يُقرأ
                VStack(alignment: .leading, spacing: 1) {
                    Text(p.shortLabel)
                        .font(DS.Font.plex(12, weight: .bold))
                        .foregroundColor(DS.Color.textPrimary)
                    Text(value)
                        .font(DS.Font.plex(12.5))
                        .foregroundColor(DS.Color.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .environment(\.layoutDirection, .leftToRight)
                }
                Spacer(minLength: 0)
                Image(systemName: "pencil")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(DS.Color.textTertiary)
                    .accessibilityHidden(true)
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    binding(p).wrappedValue = ""
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9.5, weight: .heavy))
                        .foregroundColor(DS.Color.textSecondary)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(DS.Color.mutedBackground))
                        // ٢٤ ← مساحة ضغط ٤٤×٤٤ داخل الصف (ارتفاعه ~٥٤) بلا تغيير في التخطيط:
                        // نحو القلم بقدر المسافة فقط، والباقي في هامش الصف
                        .tapArea(top: 10, leading: 8, bottom: 10, trailing: 12)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.t("حذف الحساب", "Remove"))
            }
            .padding(.horizontal, DS.Spacing.sm + 2)
            .padding(.vertical, DS.Spacing.sm)
            .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .fill(p.brandColor.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .strokeBorder(p.brandColor.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(DSScaleButtonStyle())
    }

    private var addButton: some View {
        Button { extra = .add } label: {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundColor(.white)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(tint))
                    .accessibilityHidden(true)
                Text(added.isEmpty ? L10n.t("إضافة حساب تواصل", "Add a contact account")
                                   : L10n.t("إضافة حساب آخر", "Add another account"))
                    .font(DS.Font.plex(13, weight: .bold))
                    .foregroundColor(tint)
                Spacer(minLength: 0)
                // معاينة صغيرة للمنصّات المتاحة
                HStack(spacing: -7) {
                    ForEach(Self.platforms.filter { !added.contains($0) }.prefix(4), id: \.shortLabel) { p in
                        p.iconView(size: 22)
                            .overlay(Circle().strokeBorder(DS.Color.surface, lineWidth: 1.5))
                    }
                }
                .accessibilityHidden(true)   // زخرفة
            }
            .padding(.horizontal, DS.Spacing.sm + 2)
            .padding(.vertical, DS.Spacing.sm)
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .strokeBorder(tint.opacity(0.45), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4])))
            .contentShape(Rectangle())
        }
        .buttonStyle(DSScaleButtonStyle())
    }
}

/// المربّع الإضافي للحساب: شبكة المنصّات ← إدخال الحساب (أو تعديل مباشر)
private struct ProjectAccountBox: View {
    let values: [String: Binding<String>]
    let start: SocialPlatform?
    let tint: Color
    let onClose: () -> Void
    @State private var step: SocialPlatform?
    @State private var text = ""
    @FocusState private var focused: Bool
    /// «تقليل الحركة» (توصية أبل): تلاشٍ بدل الانزلاق بين الخطوتين
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(values: [String: Binding<String>], start: SocialPlatform?, tint: Color, onClose: @escaping () -> Void) {
        self.values = values
        self.start = start
        self.tint = tint
        self.onClose = onClose
        _step = State(initialValue: start)
        _text = State(initialValue: start.map { Self.initialText($0, values[$0.shortLabel]?.wrappedValue ?? "") } ?? "")
    }

    private static func initialText(_ p: SocialPlatform, _ current: String) -> String {
        if ProjectContactTiles.isFilled(current) { return current.trimmingCharacters(in: .whitespaces) }
        return (p == .phone || p == .whatsapp) ? "+965 " : ""
    }

    private func isFilled(_ p: SocialPlatform) -> Bool {
        ProjectContactTiles.isFilled(values[p.shortLabel]?.wrappedValue ?? "")
    }

    private func placeholder(_ p: SocialPlatform) -> String {
        switch p {
        case .phone, .whatsapp: return "+965 ..."
        case .instagram, .twitter: return "@username"
        case .website: return "https://..."
        case .location: return L10n.t("رابط الموقع من الخرائط", "Maps link")
        case .snapchat: return "@username"
        }
    }

    var body: some View {
        DSExtraBox(
            title: step?.shortLabel ?? L10n.t("إضافة حساب", "Add account"),
            subtitle: step == nil ? L10n.t("اختر المنصّة", "Choose a platform")
                                  : (isFilledStart ? L10n.t("عدّل الحساب أو احذفه", "Edit or remove")
                                                   : L10n.t("اكتب الحساب أو الرابط", "Enter the account or link")),
            icon: step?.sfSymbol ?? "link",
            tint: step?.brandColor ?? tint,
            doneTitle: isFilledStart ? L10n.t("حفظ", "Save") : L10n.t("إضافة", "Add"),
            doneEnabled: step != nil && ProjectContactTiles.isFilled(text),
            showsDone: step != nil,
            onBack: (step != nil && start == nil) ? {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) { step = nil }
            } : nil,
            onDone: commit,
            onCancel: onClose
        ) {
            ZStack {
                if let step {
                    entry(step)
                        .transition(reduceMotion ? .opacity
                                    : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                  removal: .move(edge: .trailing).combined(with: .opacity)))
                } else {
                    grid
                        .transition(reduceMotion ? .opacity
                                    : .asymmetric(insertion: .move(edge: .leading).combined(with: .opacity),
                                                  removal: .move(edge: .leading).combined(with: .opacity)))
                }
            }
            .clipped()
        }
    }

    private var isFilledStart: Bool { step.map(isFilled) ?? false }

    private var grid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Spacing.sm), count: 3),
                  spacing: DS.Spacing.sm) {
            ForEach(ProjectAccountsEditor.platforms, id: \.shortLabel) { p in
                let done = isFilled(p)
                Button {
                    text = Self.initialText(p, values[p.shortLabel]?.wrappedValue ?? "")
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) { step = p }
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    VStack(spacing: 6) {
                        p.iconView(size: 38)
                            .overlay(alignment: .topTrailing) {
                                if done {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(.white, DS.Color.success)
                                        .offset(x: 5, y: -4)
                                }
                            }
                        Text(p.shortLabel)
                            .font(DS.Font.plex(11.5, weight: .bold))
                            .foregroundColor(DS.Color.textPrimary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.Spacing.sm + 2)
                    .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .fill(done ? p.brandColor.opacity(0.08) : DS.Color.surface))
                    .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .strokeBorder(done ? p.brandColor.opacity(0.35) : DS.Color.textTertiary.opacity(0.12), lineWidth: 1))
                }
                .buttonStyle(DSScaleButtonStyle())
            }
        }
    }

    private func entry(_ p: SocialPlatform) -> some View {
        VStack(spacing: DS.Spacing.sm) {
            p.iconView(size: 54)
                .padding(.top, 2)
                .accessibilityHidden(true)   // أيقونة المنصّة — عنوان المربّع يسمّيها
            TextField(placeholder(p), text: $text)
                .keyboardType((p == .phone || p == .whatsapp) ? .phonePad : .URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .environment(\.layoutDirection, .leftToRight)
                .dsAlertField()
                .focused($focused)
            if isFilledStart {
                Button {
                    values[p.shortLabel]?.wrappedValue = ""
                    onClose()
                } label: {
                    Label(L10n.t("حذف الحساب", "Remove account"), systemImage: "trash")
                        .font(DS.Font.plex(12.5, weight: .semibold))
                        .foregroundColor(DS.Color.error)
                        // النص ~١٩ ← مساحة ضغط ٤٤: ٣ حشوة (+٦ للتخطيط فقط) ثم ٨ فوق حتى الحقل
                        // بلا تغطيته، و١٢ تحت حتى أزرار المربّع بلا تغطيتها
                        .padding(.vertical, 3)
                        .tapArea(top: 8, bottom: 12)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { focused = true } }
    }

    private func commit() {
        guard let step else { return }
        values[step.shortLabel]?.wrappedValue = text.trimmingCharacters(in: .whitespacesAndNewlines)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onClose()
    }
}

/// «حسابات التواصل» في إضافة/تعديل المشروع — مربّعات، والضغط على أي مربّع يفتح
/// مربّعاً بمنتصف الشاشة لإدخال الحساب (طلب المالك)
struct ProjectContactTiles: View {
    @Binding var phone: String
    @Binding var whatsapp: String
    @Binding var instagram: String
    @Binding var twitter: String
    @Binding var website: String
    @Binding var location: String

    private struct Item {
        let platform: SocialPlatform
        let placeholder: String
        let keyboard: UIKeyboardType
        let value: Binding<String>
    }

    private var items: [Item] {
        [
            Item(platform: .phone, placeholder: "+965...", keyboard: .phonePad, value: $phone),
            Item(platform: .whatsapp, placeholder: "+965...", keyboard: .phonePad, value: $whatsapp),
            Item(platform: .instagram, placeholder: "@username", keyboard: .URL, value: $instagram),
            Item(platform: .twitter, placeholder: "@username", keyboard: .URL, value: $twitter),
            Item(platform: .website, placeholder: "https://...", keyboard: .URL, value: $website),
            Item(platform: .location, placeholder: L10n.t("رابط الموقع (Maps)", "Maps URL"), keyboard: .URL, value: $location)
        ]
    }

    /// «+965 » المبدئي في واتساب لا يُعدّ حساباً
    /// (فحص نصّي خالص — `nonisolated` حتى يُمرَّر كدالة لـ`filter` بلا تحذير عزل)
    nonisolated static func isFilled(_ v: String) -> Bool {
        let t = v.trimmingCharacters(in: .whitespacesAndNewlines)
        return !t.isEmpty && t != "+965"
    }

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Spacing.sm), count: 3),
                  spacing: DS.Spacing.sm) {
            ForEach(items.indices, id: \.self) { i in tile(items[i]) }
        }
    }

    private func tile(_ item: Item) -> some View {
        let filled = Self.isFilled(item.value.wrappedValue)
        return Button { open(item) } label: {
            VStack(spacing: 5) {
                item.platform.iconView(size: 32)
                    .overlay(alignment: .topTrailing) {
                        if filled {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white, DS.Color.success)
                                .offset(x: 5, y: -4)
                        }
                    }
                    // زخرفة — اسم المنصّة والحساب (أو «إضافة») يُقرآن تحتها
                    .accessibilityHidden(true)
                Text(item.platform.shortLabel)
                    .font(DS.Font.plex(11.5, weight: .bold))
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)
                Text(filled ? item.value.wrappedValue.trimmingCharacters(in: .whitespaces)
                            : L10n.t("إضافة", "Add"))
                    .font(DS.Font.plex(10))
                    .foregroundColor(filled ? DS.Color.textSecondary : DS.Color.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .environment(\.layoutDirection, filled ? .leftToRight : LanguageManager.shared.layoutDirection)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Spacing.sm)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .fill(filled ? item.platform.brandColor.opacity(0.07) : DS.Color.background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .strokeBorder(filled ? item.platform.brandColor.opacity(0.35)
                                         : DS.Color.textTertiary.opacity(0.18), lineWidth: 1)
            )
        }
        .buttonStyle(DSScaleButtonStyle())
    }

    private func open(_ item: Item) {
        var id: UUID?
        let close: () -> Void = { if let i = id { DSPopupPresenter.shared.hide(i) } }
        id = DSPopupPresenter.shared.show(
            ContactLinkCard(platform: item.platform,
                            placeholder: item.placeholder,
                            keyboard: item.keyboard,
                            initial: Self.isFilled(item.value.wrappedValue) ? item.value.wrappedValue : "",
                            onSave: { v in item.value.wrappedValue = v; close() },
                            onCancel: close)
        )
    }
}

/// مربّع إدخال حساب واحد بمنتصف الشاشة
private struct ContactLinkCard: View {
    let platform: SocialPlatform
    let placeholder: String
    let keyboard: UIKeyboardType
    let initial: String
    let onSave: (String) -> Void
    let onCancel: () -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        DSCenterCard(onBackgroundTap: onCancel) {
            VStack(spacing: DS.Spacing.sm) {
                platform.iconView(size: 46)
                    .accessibilityHidden(true)   // اسم المنصّة تحتها يُقرأ
                Text(platform.shortLabel)
                    .font(DS.Font.plex(17, weight: .bold))
                    .foregroundColor(DS.Color.textPrimary)
            }
            .frame(maxWidth: .infinity)

            TextField(placeholder, text: $text)
                .keyboardType(keyboard)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .environment(\.layoutDirection, .leftToRight)
                .dsAlertField()
                .focused($focused)

            if !initial.isEmpty {
                Button { onSave("") } label: {
                    Label(L10n.t("حذف الحساب", "Remove"), systemImage: "trash")
                        .font(DS.Font.plex(12.5, weight: .semibold))
                        .foregroundColor(DS.Color.error)
                        // النص ~١٩ ← مساحة ضغط ٤٤: حشوة ١ (+٢ للتخطيط فقط) ثم ١٢ فوق وتحت
                        // حتى الحقل والأزرار بلا تغطيتهما
                        .padding(.vertical, 1)
                        .tapArea(top: 12, bottom: 12)
                }
                .frame(maxWidth: .infinity)
                .buttonStyle(.plain)
            }

            HStack(spacing: DS.Spacing.sm) {
                Button { onSave(text.trimmingCharacters(in: .whitespacesAndNewlines)) } label: {
                    Text(L10n.t("حفظ", "Save"))
                        .font(DS.Font.plex(14, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .background(DSActionFill.style(), in: RoundedRectangle(cornerRadius: DS.Radius.md))
                }
                Button(action: onCancel) {
                    Text(L10n.t("إلغاء", "Cancel"))
                        .font(DS.Font.plex(14, weight: .bold))
                        .foregroundColor(DS.Color.textPrimary)
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .background(RoundedRectangle(cornerRadius: DS.Radius.md).fill(DS.Color.mutedBackground.opacity(0.8)))
                }
            }
            .buttonStyle(DSScaleButtonStyle())
        }
        .onAppear {
            text = initial
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { focused = true }
        }
    }
}

/// حافة سفلية مقوّسة للغلاف — تنزل في المنتصف كقوس ناعم (طلب المالك)
struct ProjectCoverArc: Shape {
    var depth: CGFloat = 26

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - depth))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - depth),
            control: CGPoint(x: rect.midX, y: rect.maxY + depth)
        )
        path.closeSubpath()
        return path
    }
}

/// خلفية قسم المشاريع — تدرّج ذهبي بلون التاب مع نقشة حقائب خفيفة.
/// موحّدة لكل المشاريع (لا تُؤخذ من صور المشروع — طلب المالك).
struct ProjectSectionBackdrop: View {
    /// حجم أيقونات النقشة
    var symbolSize: CGFloat = 26

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [DS.Color.tileProjects, DS.Color.tileProjectsDeep],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // نقشة مائلة من أيقونة القسم — خفيفة جداً حتى لا تزاحم الشعار
            GeometryReader { geo in
                let columns = Int(ceil(geo.size.width / (symbolSize * 2))) + 2
                let rows = Int(ceil(geo.size.height / (symbolSize * 1.7))) + 2
                VStack(spacing: symbolSize * 0.7) {
                    ForEach(0..<max(rows, 1), id: \.self) { row in
                        HStack(spacing: symbolSize) {
                            ForEach(0..<max(columns, 1), id: \.self) { _ in
                                Image(systemName: "briefcase.fill")
                                    .font(.system(size: symbolSize, weight: .light))
                            }
                        }
                        .offset(x: row.isMultiple(of: 2) ? 0 : symbolSize)
                    }
                }
                .foregroundColor(.white.opacity(0.10))
                .rotationEffect(.degrees(-18))
                .frame(width: geo.size.width, height: geo.size.height)
                .offset(x: -symbolSize, y: -symbolSize)
            }
            .clipped()

            // لمعة ناعمة من الأعلى + تعتيم أسفل ليبرز الشعار
            LinearGradient(
                colors: [.white.opacity(0.16), .clear, .black.opacity(0.18)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

struct ProjectDetailView: View {
    let project: Project
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var projectsVM: ProjectsViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    
    @State private var showDeleteAlert = false
    @State private var showEditSheet = false
    @State private var didEdit = false
    
    private var isOwnerOrAdmin: Bool {
        guard let user = authVM.currentUser else { return false }
        return user.id == project.ownerId || authVM.isAdmin
    }
    
    @Environment(\.verticalSizeClass) private var vSizeClass
    /// الوضع الأفقي — عمودان
    private var isLandscape: Bool { vSizeClass == .compact }

    /// رقم كل قسم في تسلسل الدخول — ٠، ١، ٢… بالترتيب الظاهر، بلا فجوة لقسم غائب
    private var sectionOrder: (description: Int, photos: Int, social: Int, delete: Int) {
        var next = 1   // ٠ = بطاقة المشروع
        func take(_ present: Bool) -> Int {
            defer { if present { next += 1 } }
            return next
        }
        let description = take(!(project.description ?? "").isEmpty)
        let photos = take(!project.imageUrls.isEmpty)
        let social = take(project.hasSocialLinks)
        let delete = take(isOwnerOrAdmin)
        return (description, photos, social, delete)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    // الأقسام تدخل تباعاً بالترتيب الظاهر (dsStaggerIn): البطاقة ← النبذة ← الصور
                    // ← الحسابات ← الحذف — «تقليل الحركة»: تلاشٍ فقط
                    let order = sectionOrder
                    Group {
                        if isLandscape {
                            // الوضع الأفقي: الشعار والعنوان يمين، وباقي التفاصيل يسار
                            HStack(alignment: .top, spacing: DS.Spacing.lg) {
                                projectHeader
                                    .frame(maxWidth: .infinity)
                                    .dsStaggerIn(0)

                                VStack(spacing: DS.Spacing.md) {
                                    if let desc = project.description, !desc.isEmpty {
                                        descriptionSection(desc)
                                            .dsStaggerIn(order.description)
                                    }
                                    if !project.imageUrls.isEmpty {
                                        ProjectPhotosMosaic(urls: project.imageUrls)
                                            .dsStaggerIn(order.photos)
                                    }
                                    if project.hasSocialLinks {
                                        socialLinksSection
                                            .dsStaggerIn(order.social)
                                    }
                                    if isOwnerOrAdmin {
                                        deleteSection
                                            .dsStaggerIn(order.delete)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            }
                        } else {
                    VStack(spacing: DS.Spacing.md) {
                        // Logo + Title
                        projectHeader
                            .dsStaggerIn(0)
                        
                        // Description
                        if let desc = project.description, !desc.isEmpty {
                            descriptionSection(desc)
                                .dsStaggerIn(order.description)
                        }

                        // صور المشروع
                        if !project.imageUrls.isEmpty {
                            ProjectPhotosMosaic(urls: project.imageUrls)
                                .dsStaggerIn(order.photos)
                        }
                        
                        // Social Media Links
                        if project.hasSocialLinks {
                            socialLinksSection
                                .dsStaggerIn(order.social)
                        }
                        
                        // Delete button for owner/admin
                        if isOwnerOrAdmin {
                            deleteSection
                                .dsStaggerIn(order.delete)
                        }
                    }
                        }
                    }
                    .padding(DS.Spacing.lg)
                    .padding(.bottom, DS.Spacing.xxxl)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            // «تعديل» أعلى يمين، و«إغلاق» بالأحمر يسار — مثل باقي الأوراق (طلب المالك)
            .toolbar {
                ToolbarItem(placement: DSToolbar.cancelPlacement) {
                    DSToolbarCancelButton(title: L10n.t("إغلاق", "Close")) { dismiss() }
                }
                if isOwnerOrAdmin {
                    ToolbarItem(placement: DSToolbar.confirmPlacement) {
                        Button(L10n.t("تعديل", "Edit")) { showEditSheet = true }
                            .font(DS.Font.calloutBold)
                            .foregroundColor(DS.Color.primary)
                    }
                }
            }
            // نموذج طويل فيه كتابة وتمرير — مربّع طويل من الأسفل (توصية أبل)
            .dsTallBox(isPresented: $showEditSheet, onDismiss: {
                if didEdit { dismiss() }
            }) {
                EditProjectView(project: project, didEdit: $didEdit)
                    .environmentObject(projectsVM)
                    .environmentObject(authVM)
            }
            .dsAlert(
                L10n.t("حذف المشروع", "Delete Project"),
                isPresented: $showDeleteAlert
            ) {
                Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
                Button(L10n.t("حذف", "Delete"), role: .destructive) {
                    Task {
                        await projectsVM.deleteProject(id: project.id)
                        dismiss()
                    }
                }
            } message: {
                Text(L10n.t(
                    "هل أنت متأكد من حذف \"\(project.title)\"؟",
                    "Are you sure you want to delete \"\(project.title)\"?"
                ))
            }
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }
    
    // MARK: - Header — بطاقة المشروع (غلاف + شعار بارز + إجراءات سريعة)
    //
    // الفكرة: أول صورة للمشروع تصير غلافاً، والشعار يجلس على حافته مثل بطاقة
    // تعريف، وتحته الاسم وصاحب المشروع وأزرار الاتصال المباشرة (طلب المالك).
    private var projectHeader: some View {
        VStack(spacing: 0) {
            cover
                .frame(height: coverHeight)
                .frame(maxWidth: .infinity)
                .clipShape(ProjectCoverArc(depth: arcDepth))

            VStack(spacing: DS.Spacing.sm) {
                Text(project.title)
                    .font(DS.Font.plex(22, weight: .bold))
                    .foregroundColor(DS.Color.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                ownerChip

                if !quickActions.isEmpty {
                    HStack(spacing: DS.Spacing.sm) {
                        ForEach(quickActions, id: \.platform) { action in
                            quickActionButton(action)
                        }
                    }
                    .padding(.top, DS.Spacing.xs)
                }
            }
            .padding(.top, logoSize / 2 + DS.Spacing.sm)
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.bottom, DS.Spacing.lg)
            .frame(maxWidth: .infinity)
            .background(DS.Color.surface)
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xxl, style: .continuous))
        .overlay(alignment: .top) { logoBadge.offset(y: coverHeight - logoSize / 2 + 4) }
        .dsCardShadow()
    }

    private var coverHeight: CGFloat { 150 }
    private var logoSize: CGFloat { 92 }
    /// عمق القوس في منتصف حافة الغلاف
    private var arcDepth: CGFloat { 26 }

    /// الغلاف: خلفية قسم المشاريع الموحّدة — صور المشروع تبقى في معرض الصور
    private var cover: some View {
        ProjectSectionBackdrop()
    }

    /// الشعار على حافة الغلاف — مربّع بزوايا ناعمة بإطار بلون البطاقة
    private var logoBadge: some View {
        Group {
            if let logoUrl = project.logoUrl, let url = URL(string: logoUrl) {
                CachedAsyncImage(url: url) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    DS.Color.mutedBackground
                }
            } else {
                ZStack {
                    LinearGradient(
                        colors: [DS.Color.primary.opacity(0.25), DS.Color.accent.opacity(0.20)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: "briefcase.fill")
                        .font(DS.Font.scaled(32, weight: .bold))
                        .foregroundColor(DS.Color.primary)
                }
            }
        }
        .frame(width: logoSize, height: logoSize)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                .strokeBorder(DS.Color.surface, lineWidth: 4)
        )
        .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 4)
        // الشعار يتفتّح بعد صعود بطاقته بقليل — نفس أيقونات أقسام المربّعات («تقليل الحركة»: تلاشٍ)
        .modifier(DSIconPop(delay: DSMotion.staggerDelay(0, base: DSMotion.sectionsOnPage) + 0.08,
                            fromScale: 0.6, fromAngle: 0))
    }

    /// صاحب المشروع — كبسولة تحت الاسم بدل بطاقة مستقلّة
    private var ownerChip: some View {
        HStack(spacing: DS.Spacing.xs) {
            Image(systemName: "person.fill")
                .font(DS.Font.scaled(11, weight: .bold))
            Text(project.ownerName)
                .font(DS.Font.plex(12, weight: .bold))
                .lineLimit(1)
        }
        .foregroundColor(DS.Color.primary)
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.xs)
        .background(DS.Color.primary.opacity(0.10))
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(DS.Color.primary.opacity(0.18), lineWidth: 1))
    }

    // MARK: - إجراءات سريعة

    private struct QuickAction {
        let platform: SocialPlatform
        let value: String
        let title: String
    }

    /// أهم ثلاثة إجراءات — اتصال، واتساب، الموقع (ما يتوفّر منها)
    private var quickActions: [QuickAction] {
        var actions: [QuickAction] = []
        if let v = project.phoneNumber, !v.isEmpty {
            actions.append(QuickAction(platform: .phone, value: v, title: L10n.t("اتصال", "Call")))
        }
        if let v = project.whatsappNumber, !v.isEmpty {
            actions.append(QuickAction(platform: .whatsapp, value: v, title: L10n.t("واتساب", "WhatsApp")))
        }
        if let v = project.locationUrl, !v.isEmpty {
            actions.append(QuickAction(platform: .location, value: v, title: L10n.t("الموقع", "Location")))
        }
        if actions.count < 3, let v = project.websiteUrl, !v.isEmpty {
            actions.append(QuickAction(platform: .website, value: v, title: L10n.t("الموقع الإلكتروني", "Website")))
        }
        return actions
    }

    private func quickActionButton(_ action: QuickAction) -> some View {
        Button {
            openSocialLink(platform: action.platform, value: action.value)
        } label: {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: action.platform.sfSymbol)
                    .font(DS.Font.scaled(12, weight: .bold))
                Text(action.title)
                    .font(DS.Font.plex(12, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(
                Capsule().fill(action.platform.brandColor)
            )
        }
        .buttonStyle(DSScaleButtonStyle())
        .accessibilityLabel(action.title)
    }

    // MARK: - Description — شريط لوني جانبي بدل بطاقة عادية
    private func descriptionSection(_ text: String) -> some View {
        HStack(alignment: .top, spacing: DS.Spacing.md) {
            Capsule()
                .fill(DS.Color.primary.opacity(0.7))
                .frame(width: 4)

            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text(L10n.t("نبذة عن المشروع", "About"))
                    .font(DS.Font.plex(12, weight: .bold))
                    .foregroundColor(DS.Color.primary)
                Text(text)
                    .font(DS.Font.body)
                    .foregroundColor(DS.Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(DS.Spacing.lg)
        .background(DS.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
        .dsSubtleShadow()
    }

    // MARK: - Social Links — شبكة أيقونات بألوان المنصّات
    //
    // بدل صفوف طويلة متكرّرة: مربّعات صغيرة بلون كل منصّة، الضغط يفتحها مباشرة،
    // والضغط المطوّل ينسخ الرابط أو الرقم (طلب المالك).
    private var socialLinksSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: "link")
                    .font(DS.Font.scaled(12, weight: .bold))
                Text(L10n.t("حسابات المشروع", "Project Accounts"))
                    .font(DS.Font.plex(13, weight: .bold))
                Spacer()
                Text("\(availableLinks.count)")
                    .font(DS.Font.plex(12, weight: .bold))
                    .foregroundColor(DS.Color.textTertiary)
            }
            .foregroundColor(DS.Color.textSecondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: DS.Spacing.sm)],
                      spacing: DS.Spacing.sm) {
                ForEach(availableLinks, id: \.platform) { link in
                    socialTile(link)
                }
            }
        }
        .padding(DS.Spacing.lg)
        .background(DS.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
        .dsSubtleShadow()
    }

    /// كل الحسابات المتوفّرة بالترتيب
    private var availableLinks: [QuickAction] {
        var links: [QuickAction] = []
        func add(_ platform: SocialPlatform, _ value: String?) {
            guard let value, !value.isEmpty else { return }
            links.append(QuickAction(platform: platform, value: value, title: platform.label))
        }
        add(.phone, project.phoneNumber)
        add(.whatsapp, project.whatsappNumber)
        add(.instagram, project.instagramUrl)
        add(.twitter, project.twitterUrl)
        add(.snapchat, project.snapchatUrl)
        add(.website, project.websiteUrl)
        add(.location, project.locationUrl)
        return links
    }

    private func socialTile(_ link: QuickAction) -> some View {
        Button {
            openSocialLink(platform: link.platform, value: link.value)
        } label: {
            VStack(spacing: DS.Spacing.xs) {
                link.platform.iconView(size: 44)
                Text(link.platform.label)
                    .font(DS.Font.plex(11, weight: .bold))
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(shortValue(link))
                    .font(DS.Font.plex(10, weight: .medium))
                    .foregroundColor(DS.Color.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Spacing.md)
            .background(DS.Color.mutedBackground.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        }
        .buttonStyle(DSScaleButtonStyle())
        .contextMenu {
            Button {
                UIPasteboard.general.string = link.value
            } label: {
                Label(L10n.t("نسخ", "Copy"), systemImage: "doc.on.doc")
            }
        }
        .accessibilityLabel("\(link.platform.label) \(link.value)")
    }

    /// عرض مختصر للقيمة تحت الاسم — @معرّف أو النطاق أو الرقم
    private func shortValue(_ link: QuickAction) -> String {
        let value = link.value.trimmingCharacters(in: .whitespacesAndNewlines)
        switch link.platform {
        case .phone, .whatsapp:
            return value
        case .location:
            return L10n.t("افتح الخريطة", "Open map")
        case .website:
            return value
                .replacingOccurrences(of: "https://", with: "")
                .replacingOccurrences(of: "http://", with: "")
                .replacingOccurrences(of: "www.", with: "")
        default:
            if value.contains("/") {
                return "@" + (value.split(separator: "/").last.map(String.init) ?? value)
            }
            return value.hasPrefix("@") ? value : "@" + value
        }
    }

    // MARK: - Delete
    private var deleteSection: some View {
        Button {
            showDeleteAlert = true
        } label: {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: "trash.fill")
                    .font(DS.Font.scaled(14, weight: .bold))
                Text(L10n.t("حذف المشروع", "Delete Project"))
                    .font(DS.Font.callout)
                    .fontWeight(.bold)
            }
            .foregroundColor(DS.Color.error)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Spacing.lg)
        }
    }
    
    // MARK: - Helpers
    private func openSocialLink(platform: SocialPlatform, value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        switch platform {
        case .phone:
            let cleaned = trimmed.filter { $0.isNumber || $0 == "+" }
            if let url = URL(string: "tel:\(cleaned)") { openURL(url) }
            
        case .whatsapp:
            let cleaned = trimmed.filter { $0.isNumber || $0 == "+" }
            let number = cleaned.hasPrefix("+") ? String(cleaned.dropFirst()) : cleaned
            if let url = URL(string: "https://wa.me/\(number)") { openURL(url) }
            
        case .instagram:
            let username = trimmed.replacingOccurrences(of: "@", with: "")
            if trimmed.contains("instagram.com") || trimmed.hasPrefix("http") {
                openWebURL(trimmed)
            } else if let url = URL(string: "https://instagram.com/\(username)") {
                openURL(url)
            }
            
        case .twitter:
            let username = trimmed.replacingOccurrences(of: "@", with: "")
            if trimmed.contains("x.com") || trimmed.contains("twitter.com") || trimmed.hasPrefix("http") {
                openWebURL(trimmed)
            } else if let url = URL(string: "https://x.com/\(username)") {
                openURL(url)
            }
            
        case .snapchat:
            let username = trimmed.replacingOccurrences(of: "@", with: "")
            if trimmed.contains("snapchat.com") || trimmed.hasPrefix("http") {
                openWebURL(trimmed)
            } else if let url = URL(string: "https://snapchat.com/add/\(username)") {
                openURL(url)
            }
            
        case .website:
            openWebURL(trimmed)

        case .location:
            // يدعم: روابط Google Maps، Apple Maps، إحداثيات lat,lng، أو نص
            if trimmed.hasPrefix("http") {
                openWebURL(trimmed)
            } else if trimmed.contains(",") {
                // إحداثيات → Apple Maps
                if let url = URL(string: "https://maps.apple.com/?q=\(trimmed)") {
                    openURL(url)
                }
            } else {
                // نص → بحث في الخرائط
                let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
                if let url = URL(string: "https://maps.apple.com/?q=\(encoded)") {
                    openURL(url)
                }
            }
        }
    }
    
    private func openWebURL(_ value: String) {
        var urlString = value
        if !urlString.hasPrefix("http://") && !urlString.hasPrefix("https://") {
            urlString = "https://\(urlString)"
        }
        if let url = URL(string: urlString) {
            openURL(url)
        }
    }
}

// MARK: - Edit Project View
struct EditProjectView: View {
    let project: Project
    @Binding var didEdit: Bool
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var projectsVM: ProjectsViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var description: String
    @State private var websiteUrl: String
    @State private var instagramUrl: String
    @State private var twitterUrl: String
    @State private var whatsappNumber: String
    @State private var phoneNumber: String
    @State private var locationUrl: String
    @State private var logoImage: UIImage? = nil
    /// صور المشروع: الحالية (قابلة للحذف) + الجديدة
    @State private var photoUrls: [String]
    @State private var photoImages: [UIImage] = []
    @State private var isSaving = false
    // صاحب المشروع — يُعدَّل في التعديل للإدارة فقط.
    @State private var ownerName: String
    @State private var selectedOwnerId: UUID?
    @State private var showOwnerPicker = false
    @State private var ownerSearch = ""

    init(project: Project, didEdit: Binding<Bool>) {
        self.project = project
        _didEdit = didEdit
        _title = State(initialValue: project.title)
        _description = State(initialValue: project.description ?? "")
        _websiteUrl = State(initialValue: project.websiteUrl ?? "")
        _instagramUrl = State(initialValue: project.instagramUrl ?? "")
        _twitterUrl = State(initialValue: project.twitterUrl ?? "")
        _whatsappNumber = State(initialValue: project.whatsappNumber ?? "")
        _phoneNumber = State(initialValue: project.phoneNumber ?? "")
        _locationUrl = State(initialValue: project.locationUrl ?? "")
        _ownerName = State(initialValue: project.ownerName)
        _selectedOwnerId = State(initialValue: project.ownerId)
        _photoUrls = State(initialValue: project.imageUrls)
        _initial = State(initialValue: Fields(
            title: project.title, description: project.description ?? "",
            website: project.websiteUrl ?? "", instagram: project.instagramUrl ?? "",
            twitter: project.twitterUrl ?? "", whatsapp: project.whatsappNumber ?? "",
            phone: project.phoneNumber ?? "", location: project.locationUrl ?? "",
            photoUrls: project.imageUrls, ownerId: project.ownerId).normalized)
    }

    // MARK: - تغييرات لم تُحفظ (توصية أبل)

    private struct Fields: Equatable {
        var title, description, website, instagram, twitter, whatsapp, phone, location: String
        var photoUrls: [String]
        var ownerId: UUID?

        /// بلا فراغات الأطراف، والحساب الفارغ (أو «+965» وحده) = لا حساب
        var normalized: Fields {
            let t: (String) -> String = { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            let acc: (String) -> String = { ProjectContactTiles.isFilled($0) ? t($0) : "" }
            return Fields(title: t(title), description: t(description),
                          website: acc(website), instagram: acc(instagram), twitter: acc(twitter),
                          whatsapp: acc(whatsapp), phone: acc(phone), location: acc(location),
                          photoUrls: photoUrls, ownerId: ownerId)
        }
    }

    /// القيم التي فُتح بها المربّع — تُلتقط مرة واحدة
    @State private var initial: Fields

    /// أي حقل يختلف عمّا فُتح به المربّع، أو شعار/صور جديدة — «إلغاء» يسأل قبل التجاهل
    private var hasUnsavedChanges: Bool {
        if logoImage != nil || !photoImages.isEmpty { return true }
        return Fields(title: title, description: description,
                      website: websiteUrl, instagram: instagramUrl, twitter: twitterUrl,
                      whatsapp: whatsappNumber, phone: phoneNumber, location: locationUrl,
                      photoUrls: photoUrls, ownerId: selectedOwnerId).normalized != initial
    }

    @State private var accountsBoxOpen = false
    private let tint = DS.Color.tileProjects

    var body: some View {
        // نفس مربّع «مشروع جديد» (طلب المالك): تصميم موحّد للإضافة والتعديل
        DSComposer(
            title: L10n.t("تعديل المشروع", "Edit Project"),
            subtitle: project.title,
            icon: "briefcase.fill",
            tint: tint,
            actionTitle: L10n.t("حفظ", "Save"),
            actionIcon: "checkmark",
            canSubmit: !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            isBusy: isSaving,
            isBehindExtra: accountsBoxOpen,
            hasUnsavedChanges: hasUnsavedChanges,
            onSubmit: { Task { await saveChanges() } },
            onCancel: { dismiss() }
        ) {
            // صاحب المشروع — للإدارة فقط (العضو العادي لا يراه)
            if authVM.canModerate {
                DSComposerSection(title: L10n.t("صاحب المشروع", "Owner"), icon: "person.crop.circle.badge.checkmark",
                                  tint: tint, index: 0) {
                    Button { showOwnerPicker = true } label: {
                        HStack(spacing: DS.Spacing.sm) {
                            Image(systemName: "person.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(tint)
                                .frame(width: 32, height: 32)
                                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(tint.opacity(0.12)))
                                .accessibilityHidden(true)
                            Text(ownerName)
                                .font(DS.Font.plex(14.5, weight: .semibold))
                                .foregroundColor(DS.Color.textPrimary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(DS.Color.textTertiary)
                                .accessibilityHidden(true)
                        }
                        .padding(.horizontal, DS.Spacing.sm + 2)
                        .padding(.vertical, DS.Spacing.sm)
                        .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).fill(DS.Color.background))
                        .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                            .strokeBorder(DS.Color.textTertiary.opacity(0.15), lineWidth: 1))
                    }
                    .buttonStyle(DSScaleButtonStyle())
                }
            }

            // الهوية: الشعار + الاسم + الوصف
            DSComposerSection(title: L10n.t("هوية المشروع", "Project Identity"), icon: "sparkles", tint: tint, index: 1) {
                DSComposerLogoPicker(image: $logoImage, existingURL: project.logoUrl, tint: tint, size: 88)
                    .padding(.bottom, 2)
                DSComposerField(icon: "textformat", label: L10n.t("اسم المشروع *", "Project name *"),
                                placeholder: L10n.t("اسم المشروع", "Project name"),
                                text: $title, tint: tint, limit: 60)
                DSComposerField(icon: "text.alignright", label: L10n.t("وصف مختصر", "Short description"),
                                placeholder: L10n.t("سطر يعرّف بالمشروع وما يقدّمه", "One line about what it offers"),
                                text: $description, tint: tint, multiline: true, limit: 160)
            }

            // الصور (الحالية + الجديدة)
            ProjectPhotosEditor(existingUrls: $photoUrls, newImages: $photoImages, tint: tint, index: 2)

            // حسابات التواصل
            DSComposerSection(title: L10n.t("حسابات التواصل", "Contact Accounts"), icon: "link", tint: tint,
                              trailing: L10n.t("اختياري", "Optional"), index: 3) {
                ProjectAccountsEditor(phone: $phoneNumber, whatsapp: $whatsappNumber,
                                      instagram: $instagramUrl, twitter: $twitterUrl,
                                      website: $websiteUrl, location: $locationUrl,
                                      tint: tint,
                                      onExtraChange: { accountsBoxOpen = $0 })
            }
        }
        .dsTallBox(isPresented: $showOwnerPicker) { ownerPickerSheet }   // قائمة أعضاء طويلة (توصية أبل)
    }

    /// حقل تواصل احترافي — عنوان فوق (أيقونة + اسم) وصندوق إدخال موحّد الارتفاع
    /// بحيث تتحاذى الحقول بدقّة في شبكة العمودين.
    private func socialTextField(platform: SocialPlatform, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                platform.iconView(size: 18)
                Text(platform.label)
                    .font(DS.Font.scaled(11, weight: .semibold))
                    .foregroundColor(DS.Color.textSecondary)
                    .lineLimit(1)
            }
            TextField(placeholder, text: text)
                .font(DS.Font.scaled(13))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DS.Spacing.sm)
                .frame(height: 42)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .fill(DS.Color.background)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .strokeBorder(DS.Color.textTertiary.opacity(0.18), lineWidth: 1)
                )
        }
    }
    
    /// منتقي صاحب المشروع — للإدارة فقط. مربّع بمنتصف الشاشة بتصميم المربّعات الموحّد:
    /// بحث ثم الأعضاء صفوفاً والمختار بعلامة ✓ — الضغط على عضو يختاره ويغلق المربّع (كالسابق).
    private var ownerPickerSheet: some View {
        let q = ownerSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = memberVM.allMembers
            .filter { $0.isCountable && $0.isDeceased != true }
            .filter { q.isEmpty || $0.fullName.localizedCaseInsensitiveContains(q) }
            .sorted { $0.fullName < $1.fullName }
        return DSComposer(
            title: L10n.t("اختيار صاحب المشروع", "Select Owner"),
            subtitle: project.title,
            icon: "person.crop.circle.badge.checkmark",
            tint: tint,
            actionTitle: "",
            showsAction: false,
            cancelTitle: L10n.t("إلغاء", "Cancel"),
            canSubmit: false,
            onSubmit: {},
            onCancel: { showOwnerPicker = false }
        ) {
            DSComposerField(icon: "magnifyingglass",
                            label: L10n.t("بحث", "Search"),
                            placeholder: L10n.t("بحث عن عضو...", "Search member..."),
                            text: $ownerSearch,
                            tint: tint)
                .dsStaggerIn(0)

            DSComposerSection(title: L10n.t("الأعضاء", "Members"), icon: "person.2.fill",
                              tint: tint, trailing: "\(candidates.count)", index: 1) {
                if candidates.isEmpty {
                    Text(L10n.t("لا توجد نتائج", "No results"))
                        .font(DS.Font.plex(13, weight: .semibold))
                        .foregroundColor(DS.Color.textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DS.Spacing.md)
                } else {
                    ownerPickerRows(candidates)
                }
            }
        }
    }

    /// صفوف الأعضاء — كسولة للقوائم الطويلة (كل أعضاء العائلة: آلاف)، وعادية للقصيرة
    /// حتى يُقاس ارتفاع المربّع كاملاً (الكسولة تُبلِّغ ارتفاعاً ناقصاً للقصيرة)
    @ViewBuilder
    private func ownerPickerRows(_ list: [FamilyMember]) -> some View {
        if list.count > 40 {
            LazyVStack(spacing: DS.Spacing.sm) {
                ForEach(list) { m in ownerPickerRow(m) }
            }
        } else {
            VStack(spacing: DS.Spacing.sm) {
                ForEach(list) { m in ownerPickerRow(m) }
            }
        }
    }

    /// صف عضو: الحرف الأول بمربّع أيقونة الحقل (بلا تحميل صور لآلاف الصفوف) + الاسم،
    /// والمختار بعلامة ✓ وإطار بلون القسم
    private func ownerPickerRow(_ m: FamilyMember) -> some View {
        let isSelected = selectedOwnerId == m.id
        return Button {
            selectedOwnerId = m.id
            ownerName = m.fullName
            ownerSearch = ""
            showOwnerPicker = false
        } label: {
            HStack(spacing: DS.Spacing.sm) {
                Text(String(m.fullName.prefix(1)))
                    .font(DS.Font.plex(14, weight: .bold))
                    .foregroundColor(tint)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(tint.opacity(0.12)))
                    .accessibilityHidden(true)   // الحرف الأول زخرفة — الاسم كاملاً يُقرأ

                Text(m.displayFullName)
                    .dsFieldFont(14.5, weight: isSelected ? .bold : .regular)
                    .foregroundColor(isSelected ? DS.Color.fieldLabel : DS.Color.fieldValue)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)

                Spacer(minLength: 0)

                if isSelected {
                    // الاختيار يُقرأ من سمة «مُختار» على الصف
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(tint)
                        .accessibilityHidden(true)
                }
            }
            .dsRowBox()
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .strokeBorder(tint.opacity(isSelected ? 0.6 : 0), lineWidth: 1.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(DSScaleButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func saveChanges() async {
        isSaving = true

        // Upload new logo if selected
        var finalLogoUrl = project.logoUrl
        if let logoImage {
            if let data = ImageProcessor.process(logoImage, for: .projectLogo) {
                if let uploaded = await projectsVM.uploadLogo(imageData: data, projectId: project.id) {
                    finalLogoUrl = uploaded
                }
            }
        }

        // صور المعرض: الحالية بعد الحذف + رفع الجديدة
        var finalPhotos = photoUrls
        for img in photoImages {
            if let data = ImageProcessor.process(img, for: .projectLogo),
               let url = await projectsVM.uploadProjectPhoto(imageData: data) {
                finalPhotos.append(url)
            }
        }
        if finalPhotos != project.imageUrls {
            await projectsVM.setProjectImages(id: project.id, urls: finalPhotos)
        }

        // تغيير صاحب المشروع متاح للإدارة فقط.
        let editedOwnerName = authVM.canModerate ? ownerName : nil
        let editedOwnerId = authVM.canModerate ? selectedOwnerId?.uuidString : nil

        let success = await projectsVM.updateProject(
            id: project.id,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            description: description.isEmpty ? nil : description,
            logoUrl: finalLogoUrl,
            websiteUrl: websiteUrl.isEmpty ? nil : websiteUrl,
            instagramUrl: instagramUrl.isEmpty ? nil : instagramUrl,
            twitterUrl: twitterUrl.isEmpty ? nil : twitterUrl,
            snapchatUrl: nil,
            whatsappNumber: whatsappNumber.isEmpty ? nil : whatsappNumber,
            phoneNumber: phoneNumber.isEmpty ? nil : phoneNumber,
            locationUrl: locationUrl.isEmpty ? nil : locationUrl,
            ownerName: editedOwnerName,
            ownerId: editedOwnerId
        )

        if success {
            await projectsVM.fetchProjects()
            if let userId = authVM.currentUser?.id {
                await projectsVM.fetchMyPendingProjects(ownerId: userId)
            }
            isSaving = false
            didEdit = true
            dismiss()
        } else {
            isSaving = false
        }
    }
}

// MARK: - مساحة ضغط أكبر (توصية أبل: ٤٤ نقطة)

private extension View {
    /// يكبّر منطقة اللمس حول عنصر صغير بلا تغيير في شكله ولا في التخطيط: الحشوة تُضاف
    /// لمنطقة اللمس ثم تُسترد من التخطيط. القيم محسوبة لكل عنصر حتى لا تتداخل مع جيرانه.
    func tapArea(top: CGFloat = 0, leading: CGFloat = 0, bottom: CGFloat = 0, trailing: CGFloat = 0) -> some View {
        self
            .padding(EdgeInsets(top: top, leading: leading, bottom: bottom, trailing: trailing))
            .contentShape(Rectangle())
            .padding(EdgeInsets(top: -top, leading: -leading, bottom: -bottom, trailing: -trailing))
    }
}
