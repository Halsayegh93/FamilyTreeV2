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
        case .website:   return DS.Color.navyFill          // كحلي — تعبئة تحت أيقونة بيضاء
        case .instagram: return DS.Color.Social.instagram  // وردي إنستجرام
        case .twitter:   return DS.Color.Social.x          // أسود X
        case .snapchat:  return DS.Color.Social.snapchat   // أصفر Snap
        case .whatsapp:  return DS.Color.Social.whatsapp   // أخضر WhatsApp
        case .phone:     return DS.Color.seaFill           // بحري — الهاتف
        case .location:  return DS.Color.Social.maps       // أحمر Maps
        }
    }

    /// gradient إنستجرام الأوفيشيال — للحالة الخاصة فقط (من `DS.Color.Social`).
    private var instagramGradient: LinearGradient { DS.Color.Social.instagramGradient }

    /// لون الأيقونة الأمامية — أبيض غالباً، أسود مع Snapchat الأصفر.
    var foregroundColor: Color {
        switch self {
        case .snapchat: return DS.Color.overlayDark
        default:        return DS.Color.textOnPrimary
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
                    .dsSubtleShadow()
            } else {
                Circle()
                    .fill(brandColor)
                    .frame(width: size, height: size)
                    .dsSubtleShadow()
            }

            Group {
                switch self {
                case .website:
                    Image(systemName: "globe")
                        .dsGlyph(iconSize)
                case .instagram:
                    Image(systemName: "camera.fill")
                        .dsGlyph(iconSize * 0.95)
                case .twitter:
                    Text("𝕏")
                        .dsGlyph(iconSize + DS.Spacing.xxs, weight: .black)
                case .snapchat:
                    Image(systemName: "bolt.horizontal.fill")
                        .dsGlyph(iconSize)
                case .whatsapp:
                    Image(systemName: "message.fill")
                        .dsGlyph(iconSize)
                case .phone:
                    Image(systemName: "phone.fill")
                        .dsGlyph(iconSize)
                case .location:
                    Image(systemName: "mappin.and.ellipse")
                        .dsGlyph(iconSize)
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
                p.iconView(size: DS.Icon.row)
                    .accessibilityHidden(true)   // أيقونة المنصّة — اسمها يُقرأ
                VStack(alignment: .leading, spacing: 0) {
                    Text(p.shortLabel)
                        .dsFont(.chip)
                        .foregroundColor(DS.Color.textPrimary)
                    Text(value)
                        .dsFont(.subtitle)
                        .foregroundColor(DS.Color.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .environment(\.layoutDirection, .leftToRight)
                }
                Spacer(minLength: 0)
                Image(systemName: "pencil")
                    .dsGlyph(DS.Glyph.xs)
                    .foregroundColor(DS.Color.textTertiary)
                    .accessibilityHidden(true)
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    binding(p).wrappedValue = ""
                } label: {
                    Image(systemName: "xmark")
                        .dsGlyph(DS.Glyph.micro, weight: .heavy)
                        .foregroundColor(DS.Color.textSecondary)
                        .frame(width: DS.Spacing.xxl, height: DS.Spacing.xxl)
                        .background(Circle().fill(DS.Color.mutedBackground))
                        // ← مساحة ضغط ٤٤×٤٤ داخل الصف بلا تغيير في التخطيط
                        .frame(width: DS.Icon.tapTarget, height: DS.Icon.tapTarget)
                        .contentShape(Rectangle())
                        .padding(.vertical, -(DS.Icon.tapTarget - DS.Spacing.xxl) / 2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.t("حذف الحساب", "Remove"))
            }
            .padding(.horizontal, DS.Spacing.sm)
            .padding(.vertical, DS.Spacing.sm)
            .background(RoundedRectangle(cornerRadius: DS.Card.radius, style: .continuous)
                .fill(p.brandColor.opacity(DS.Opacity.tintFillSoft)))
            .overlay(RoundedRectangle(cornerRadius: DS.Card.radius, style: .continuous)
                .strokeBorder(p.brandColor.opacity(DS.Opacity.tintStroke), lineWidth: DS.Border.width))
        }
        .buttonStyle(DSScaleButtonStyle())
    }

    private var addButton: some View {
        Button { extra = .add } label: {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: "plus")
                    .dsGlyph(DS.Glyph.mdCompact, weight: .heavy)
                    .foregroundColor(DS.Color.textOnPrimary)
                    .frame(width: DSBox.compactHeaderIcon, height: DSBox.compactHeaderIcon)
                    .background(Circle().fill(tint))
                    .accessibilityHidden(true)
                Text(added.isEmpty ? L10n.t("إضافة حساب تواصل", "Add a contact account")
                                   : L10n.t("إضافة حساب آخر", "Add another account"))
                    .dsFont(.rowTitleCompact)
                    .foregroundColor(tint)
                Spacer(minLength: 0)
                // معاينة صغيرة للمنصّات المتاحة
                HStack(spacing: -DS.Spacing.xsm) {
                    ForEach(Self.platforms.filter { !added.contains($0) }.prefix(4), id: \.shortLabel) { p in
                        p.iconView(size: DS.Icon.section)
                            .overlay(Circle().strokeBorder(DS.Color.surface, lineWidth: DS.Border.widthBold))
                    }
                }
                .accessibilityHidden(true)   // زخرفة
            }
            .padding(.horizontal, DS.Spacing.sm)
            .padding(.vertical, DS.Spacing.sm)
            // خانة «إضافة» المتقطّعة الموحّدة
            .overlay(RoundedRectangle(cornerRadius: DS.Card.radius, style: .continuous)
                .strokeBorder(tint.opacity(DSAddChipLabel.strokeOpacity), style: DSAddChipLabel.dash))
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
                    VStack(spacing: DS.Spacing.xsm) {
                        p.iconView(size: DS.Icon.sizeSm)
                            .overlay(alignment: .topTrailing) {
                                if done {
                                    Image(systemName: "checkmark.circle.fill")
                                        .dsGlyph(DS.Glyph.md)
                                        .foregroundStyle(DS.Color.textOnPrimary, DS.Color.success)
                                        .offset(x: DS.Spacing.xs, y: -DS.Spacing.xs)
                                }
                            }
                        Text(p.shortLabel)
                            .dsFont(.badge)
                            .foregroundColor(DS.Color.textPrimary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.Spacing.sm)
                    .background(RoundedRectangle(cornerRadius: DS.Card.radius, style: .continuous)
                        .fill(done ? p.brandColor.opacity(DS.Opacity.tintFillSoft) : DS.Color.surface))
                    .overlay(RoundedRectangle(cornerRadius: DS.Card.radius, style: .continuous)
                        .strokeBorder(done ? p.brandColor.opacity(DS.Opacity.tintStroke)
                                           : DS.Color.textTertiary.opacity(DS.Opacity.cardStroke),
                                      lineWidth: DS.Border.width))
                }
                .buttonStyle(DSScaleButtonStyle())
            }
        }
    }

    private func entry(_ p: SocialPlatform) -> some View {
        VStack(spacing: DS.Spacing.sm) {
            p.iconView(size: DS.Icon.state)
                .padding(.top, DS.Spacing.xxs)
                .accessibilityHidden(true)   // أيقونة المنصّة — عنوان المربّع يسمّيها
            TextField(placeholder(p), text: $text)
                .keyboardType((p == .phone || p == .whatsapp) ? .phonePad : .URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .environment(\.layoutDirection, .leftToRight)
                .dsAlertField()
                .focused($focused)
            if isFilledStart {
                // الشريحة الموحّدة (مساحة ضغط ٤٤)
                DSChipButton(L10n.t("حذف الحساب", "Remove account"), icon: "trash", tint: DS.Color.error) {
                    values[p.shortLabel]?.wrappedValue = ""
                    onClose()
                }
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

/// فحص «حساب تواصل» مُدخل (كانت مربّعات «حسابات التواصل» القديمة — حلّ محلها `ProjectAccountsEditor`)
enum ProjectContactTiles {
    /// «+965 » المبدئي في واتساب لا يُعدّ حساباً
    /// (فحص نصّي خالص — `nonisolated` حتى يُمرَّر كدالة لـ`filter` بلا تحذير عزل)
    nonisolated static func isFilled(_ v: String) -> Bool {
        let t = v.trimmingCharacters(in: .whitespacesAndNewlines)
        return !t.isEmpty && t != "+965"
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

/// خلفية قسم المشاريع — تدرّج بلون التاب مع نقشة خفيفة من شعار العائلة «المحمدعلي»
/// (كانت نقشة حقائب — طلب المالك ٢٠٢٦-١٠-٢٣). موحّدة لكل المشاريع (لا تُؤخذ من صور المشروع — طلب المالك).
struct ProjectSectionBackdrop: View {
    /// ارتفاع الشعار في النقشة (العرض من نسبة الشعار)
    var symbolSize: CGFloat = 26

    /// نسبة عرض شعار العائلة إلى ارتفاعه (من أصل `FamilyLogoCream`: ٧١٠ × ٥٢٩)
    private static let logoAspect: CGFloat = 710.061 / 529.415

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [DS.Color.tileProjects, DS.Color.tileProjectsDeep],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // نقشة مائلة من شعار العائلة (الكريمي على لون القسم) — خفيفة جداً حتى لا تزاحم شعار المشروع
            GeometryReader { geo in
                let logoW = symbolSize * Self.logoAspect
                let columns = Int(ceil(geo.size.width / (logoW + symbolSize))) + 2
                let rows = Int(ceil(geo.size.height / (symbolSize * 1.7))) + 2
                VStack(spacing: symbolSize * 0.7) {
                    ForEach(0..<max(rows, 1), id: \.self) { row in
                        HStack(spacing: symbolSize) {
                            ForEach(0..<max(columns, 1), id: \.self) { _ in
                                Image("FamilyLogoCream")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: logoW, height: symbolSize)
                            }
                        }
                        .offset(x: row.isMultiple(of: 2) ? 0 : (logoW + symbolSize) / 2)
                    }
                }
                .opacity(DS.Opacity.tintFillSoft)
                .rotationEffect(.degrees(-18))
                .frame(width: geo.size.width, height: geo.size.height)
                .offset(x: -symbolSize, y: -symbolSize)
            }
            .clipped()

            // لمعة ناعمة من الأعلى + تعتيم أسفل ليبرز الشعار
            LinearGradient(
                colors: [DS.Color.headerBorder, .clear, DS.Color.shadowMediumDark],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

/// صورة بطاقة المشروع: خلفية القسم وعليها شعار المشروع أو مجسّم القسم — دائماً، ولو للمشروع صور
/// (المالك ٢٠٢٦-١٠-٢٣: «ليش لمن احط صور للمشروع تصير صورة مكان الخلفية و الشعار» — الصور في «الصور» بصفحته).
/// المقاس والقصّ من الحاوية (`Color.clear.aspectRatio(…).overlay { ProjectHeroImage }`).
struct ProjectHeroImage: View {
    let project: Project
    /// ضلع الشعار/المجسّم حين لا توجد صورة
    var markSize: CGFloat = DS.Icon.state

    static let aspect: CGFloat = 16.0 / 10.0

    var body: some View {
        ZStack {
            ProjectSectionBackdrop(symbolSize: DS.Glyph.lg)
            mark
        }
        .clipped()
        .accessibilityHidden(true)
    }

    /// البديل: شعار المشروع في دائرة، أو مجسّم المشاريع
    @ViewBuilder
    private var mark: some View {
        if let logo = project.logoUrl, let url = URL(string: logo) {
            CachedAsyncImage(url: url) { img in
                img.resizable().scaledToFill()
            } placeholder: { DS.Color.mutedBackground }
            .frame(width: markSize, height: markSize)
            // الشعار دائري بإطار رفيع (طلب المالك ٢٠٢٦-١٠-٢٣)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(DS.Color.surface, lineWidth: DS.Border.width))
            .dsSubtleShadow()
        } else {
            DSStateIcon("briefcase.fill", tint: AppSection.projects.ink, size: markSize)
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
    @State private var showDeleteError = false
    @State private var showEditSheet = false
    @State private var didEdit = false
    /// ارتفاع الرأس — المربّع بالمنتصف على قدر محتواه (`dsPanelContentHeight`)
    @State private var headerH: CGFloat = 0
    /// سقف صورة قسم «الصور» = ٧٠٪ من أقصى ارتفاع للمربّع (٨٦٪ من الشاشة عمودياً، والارتفاع ناقص الهامش
    /// أفقياً — نفس `DSCenterPanel`). من الشاشة لا من المربّع: المربّع يحتضن محتواه فقياسه يدور على نفسه.
    private var photoMaxHeight: CGFloat {
        let screen = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen.bounds.size
            ?? CGSize(width: 393, height: 852)
        let short = min(screen.width, screen.height), long = max(screen.width, screen.height)
        let boxMax = isLandscape ? short - DS.Landscape.panelMargin * 2 : long * 0.86
        return boxMax * 0.7
    }
    
    private var isOwnerOrAdmin: Bool {
        guard let user = authVM.currentUser else { return false }
        return user.id == project.ownerId || authVM.isAdmin
    }
    
    @Environment(\.verticalSizeClass) private var vSizeClass
    /// الوضع الأفقي — عمودان
    private var isLandscape: Bool { vSizeClass == .compact }

    /// رقم كل قسم في تسلسل الدخول — ٠، ١، ٢… بالترتيب الظاهر، بلا فجوة لقسم غائب
    private var sectionOrder: (description: Int, photos: Int, delete: Int) {
        var next = 1   // ٠ = بطاقة المشروع
        func take(_ present: Bool) -> Int {
            defer { if present { next += 1 } }
            return next
        }
        let description = take(!(project.description ?? "").isEmpty)
        let photos = take(hasPhotos)
        let delete = take(isOwnerOrAdmin)
        return (description, photos, delete)
    }

    var body: some View {
        VStack(spacing: 0) {
            // الرأس الموحّد (`DSSubPageHeader`) بلون المشاريع: × للإغلاق، و«تعديل» في الطرف (للمالك والإدارة)
            DSSubPageHeader(title: project.title, subtitle: L10n.t("مشاريع العائلة", "Family Projects"),
                            section: .projects, nav: .close, onBack: { dismiss() }) {
                if isOwnerOrAdmin {
                    DSHeaderButton(symbol: "pencil", label: L10n.t("تعديل", "Edit")) { showEditSheet = true }
                }
            }
            .readHeight($headerH)

            ZStack {
                // سطح صلب — أبيض في الفاتح وسطح الداكن في الداكن؛ لا يظهر ما خلف المربّع (طلب المالك ٢٠٢٦-١٠-٢٣)
                DS.Color.surface.ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    // الأقسام تدخل تباعاً بالترتيب الظاهر (dsStaggerIn): البطاقة ← النبذة ← الصور ← الحذف — «تقليل الحركة»: تلاشٍ فقط
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
                                    if hasPhotos {
                                        ProjectPhotosCarousel(urls: project.imageUrls, maxHeight: photoMaxHeight)
                                            .dsStaggerIn(order.photos)
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
                        if hasPhotos {
                            ProjectPhotosCarousel(urls: project.imageUrls, maxHeight: photoMaxHeight)
                                .dsStaggerIn(order.photos)
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
                    .padding(.bottom, DS.Spacing.md)
                    // المربّع بالمنتصف يحتضن محتواه (والباقي يتمرّر داخله)
                    .dsPanelContentHeight(extra: headerH)
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
                .dsSectionPage(.projects)
        }
        .dsAlert(
            L10n.t("حذف المشروع", "Delete Project"),
            isPresented: $showDeleteAlert
        ) {
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
            Button(L10n.t("حذف", "Delete"), role: .destructive) {
                Task {
                    // الإغلاق بعد نجاح الحذف فقط — وإلا رسالة خطأ
                    if await projectsVM.deleteProject(id: project.id, ownerId: project.ownerId) {
                        dismiss()
                    } else {
                        showDeleteError = true
                    }
                }
            }
        } message: {
            Text(L10n.t(
                "هل أنت متأكد من حذف \"\(project.title)\"؟",
                "Are you sure you want to delete \"\(project.title)\"?"
            ))
        }
        .dsAlert(L10n.t("خطأ", "Error"), isPresented: $showDeleteError) {
            Button(L10n.t("حسناً", "OK"), role: .cancel) {}
        } message: {
            Text(projectsVM.errorMessage ?? L10n.t("تعذر حذف المشروع.", "Failed to delete project."))
        }
        .dsSectionPage(.projects)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }
    
    // MARK: - Header — بطاقة المشروع (رأس واحد: الشعار + الاسم، ثم صاحب المشروع والإجراءات)
    //
    // طلب المالك ٢٠٢٦-١٠-٢٣ (الخيار «ب»): الرأس يحمل الشعار والاسم فقط على خلفية القسم (التدرّج الذهبي)
    // — كتلة واحدة؛ صور المشروع في قسم «الصور» تحت النبذة (`ProjectPhotosCarousel`). الاسم أبيض على
    // تعتيم بلون القسم الغامق (`tileProjectsDeep` — تباين ≥ ٤٫٥:١).
    private var projectHeader: some View {
        VStack(spacing: 0) {
            VStack(spacing: DS.Spacing.sm) {
                logoBadge
                Text(project.title)
                    .dsFont(.emptyTitle)
                    .foregroundColor(DS.Color.textOnPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .shadow(color: DS.Color.shadowMediumDark, radius: DS.Spacing.xs, y: 1)
            }
            .padding(.top, logoTop)
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.bottom, DS.Spacing.md + arcDepth)
            .frame(maxWidth: .infinity)
            .allowsHitTesting(false)
            .background(alignment: .top) { headerBackdrop }
            .clipShape(ProjectCoverArc(depth: arcDepth))

            VStack(spacing: DS.Spacing.sm) {
                ownerChip

                let actions = quickActions
                if !actions.isEmpty {
                    // صفّ واحد إن اتّسع، وإلا صفّان متوازنان (حتى ٧ حسابات)
                    ViewThatFits(in: .horizontal) {
                        quickActionRow(actions)
                        VStack(spacing: DS.Spacing.xs) {
                            let half = (actions.count + 1) / 2
                            quickActionRow(Array(actions.prefix(half)))
                            quickActionRow(Array(actions.dropFirst(half)))
                        }
                    }
                }
            }
            .padding(.top, DS.Spacing.xs)
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.bottom, DS.Spacing.md)
            .frame(maxWidth: .infinity)
            .background(DS.Color.surface)
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.Card.radius, style: .continuous))
        // البطاقة الواحدة (`.dsCard`)
        .dsCard(padding: nil)
    }

    /// خلفية الرأس: لون القسم، ثم تعتيم بلون القسم الغامق تحت الشعار والاسم
    private var headerBackdrop: some View {
        ZStack(alignment: .top) {
            ProjectSectionBackdrop(symbolSize: DS.Glyph.lg)
                .accessibilityHidden(true)
            // الذوبان إلى لون القسم الغامق — يبدأ عند منتصف الشعار
            VStack(spacing: 0) {
                Color.clear.frame(height: logoTop + logoSize / 2)
                LinearGradient(colors: [DS.Color.tileProjectsDeep.opacity(0), DS.Color.tileProjectsDeep],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: logoSize / 2)
                DS.Color.tileProjectsDeep
            }
        }
    }

    /// الشعار أكبر (٨٤ ← ١٠٤ ← ١١٦، والأفقي ٩٦ ← ١٠٦) وإطاره رفيع (طلب المالك ٢٠٢٦-١٠-٢٣)
    private var logoSize: CGFloat { isLandscape ? 106 : 116 }
    /// عمق القوس في منتصف حافة الرأس
    private var arcDepth: CGFloat { 22 }
    /// أعلى الشعار — هامش يُظهر خلفية القسم فوقه
    private var logoTop: CGFloat { DS.Spacing.lg }
    private var hasPhotos: Bool { project.imageUrls.contains { !$0.isEmpty } }

    /// شعار المشروع في الرأس — دائرة بإطار بلون البطاقة
    private var logoBadge: some View {
        Group {
            if let logoUrl = project.logoUrl, let url = URL(string: logoUrl) {
                CachedAsyncImage(url: url) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    DS.Color.mutedBackground
                }
            } else {
                DSStateIcon("briefcase.fill", tint: AppSection.projects.ink, size: logoSize)
            }
        }
        .frame(width: logoSize, height: logoSize)
        // الشعار دائري بإطار دائري رفيع (طلب المالك ٢٠٢٦-١٠-٢٣)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(DS.Color.surface, lineWidth: DS.Spacing.xxs))
        .dsCardShadow()
        // الشعار يتفتّح بعد صعود بطاقته بقليل — نفس أيقونات أقسام المربّعات («تقليل الحركة»: تلاشٍ)
        .modifier(DSIconPop(delay: DSMotion.staggerDelay(0, base: DSMotion.sectionsOnPage) + 0.08,
                            fromScale: 0.6, fromAngle: 0))
    }

    /// صاحب المشروع — كبسولة تحت الاسم بدل بطاقة مستقلّة (الشارة الموحّدة)
    private var ownerChip: some View {
        DSStatusChip(text: project.ownerName, icon: "person.fill", tint: AppSection.projects.ink)
    }

    // MARK: - إجراءات سريعة

    private struct QuickAction {
        let platform: SocialPlatform
        let value: String
        let title: String
    }

    /// الإجراءات السريعة — اتصال، إنستغرام (مكان واتساب — طلب المالك ٢٠٢٦-١٠-٢٣)، الموقع، واتساب، إكس،
    /// سناب، الموقع الإلكتروني (ما يتوفّر منها). أزرار أيقونات صغيرة فيتّسع الصفّ لها كلها؛ وهي المكان الوحيد
    /// لحسابات المشروع (قسم «حسابات المشروع» حُذف بطلب المالك ٢٠٢٦-١٠-٢٣).
    private var quickActions: [QuickAction] {
        var actions: [QuickAction] = []
        func add(_ platform: SocialPlatform, _ value: String?, _ title: String) {
            guard let value, !value.isEmpty else { return }
            actions.append(QuickAction(platform: platform, value: value, title: title))
        }
        add(.phone, project.phoneNumber, L10n.t("اتصال", "Call"))
        add(.instagram, project.instagramUrl, L10n.t("إنستغرام", "Instagram"))
        add(.location, project.locationUrl, L10n.t("الموقع", "Location"))
        add(.whatsapp, project.whatsappNumber, L10n.t("واتساب", "WhatsApp"))
        add(.twitter, project.twitterUrl, SocialPlatform.twitter.label)
        add(.snapchat, project.snapchatUrl, SocialPlatform.snapchat.label)
        add(.website, project.websiteUrl, L10n.t("الموقع الإلكتروني", "Website"))
        return actions
    }

    private func quickActionRow(_ actions: [QuickAction]) -> some View {
        HStack(spacing: DS.Spacing.xs) {
            ForEach(actions, id: \.platform) { action in
                quickActionButton(action)
            }
        }
    }

    /// إجراء سريع — دائرة صغيرة بلون المنصّة (أيقونة المنصّة الموحّدة) ولمس ٤٤ (حدّ أبل)
    private func quickActionButton(_ action: QuickAction) -> some View {
        Button {
            openSocialLink(platform: action.platform, value: action.value)
        } label: {
            action.platform.iconView(size: DS.Icon.rowLarge)
                .frame(width: DS.Icon.tapTarget, height: DS.Icon.tapTarget)
                .contentShape(Circle())
        }
        .buttonStyle(DSScaleButtonStyle())
        // الضغط المطوّل: المعرّف/الرقم/الرابط نفسه + «نسخ» — فلا يضيع اسم الحساب بعد حذف قسم الحسابات
        .contextMenu {
            Text(verbatim: shortValue(action))
            Button {
                UIPasteboard.general.string = action.value
            } label: {
                Label(L10n.t("نسخ", "Copy"), systemImage: "doc.on.doc")
            }
        }
        .accessibilityLabel(action.title)
        .accessibilityValue(Text(verbatim: shortValue(action)))
    }

    // MARK: - Description — شريط لوني جانبي بدل بطاقة عادية
    private func descriptionSection(_ text: String) -> some View {
        HStack(alignment: .top, spacing: DS.Spacing.md) {
            Capsule()
                .fill(AppSection.projects.ink.opacity(DS.Opacity.selectedStroke))
                .frame(width: DS.Spacing.xs)

            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text(L10n.t("نبذة عن المشروع", "About"))
                    .dsFont(.chip)
                    .foregroundColor(AppSection.projects.ink)
                Text(text)
                    .dsFont(.body)
                    .foregroundColor(DS.Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // البطاقة الواحدة (`.dsCard`)
        .dsCard(padding: DS.Spacing.lg)
    }

    /// عرض مختصر للقيمة في قائمة الضغط المطوّل — @معرّف أو النطاق أو الرقم (والخريطة رابطها كاملاً)
    private func shortValue(_ link: QuickAction) -> String {
        let value = link.value.trimmingCharacters(in: .whitespacesAndNewlines)
        switch link.platform {
        case .phone, .whatsapp:
            return value
        case .location:
            return value
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
        // الزرّ الواحد بدور الحذف (أحمر)
        DSButton(L10n.t("حذف المشروع", "Delete Project"), icon: "trash.fill", role: .destructive) {
            showDeleteAlert = true
        }
        .padding(.top, DS.Spacing.sm)
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
                    // الصفّ الموحّد (`DSRow`) — قرص مجسّم + الاسم + سهم
                    Button { showOwnerPicker = true } label: {
                        DSRow(icon: "person.fill", tint: tint, title: ownerName) { DSChevron() }
                    }
                    .buttonStyle(DSScaleButtonStyle())
                }
            }

            // الهوية: الشعار + الاسم + الوصف
            DSComposerSection(title: L10n.t("هوية المشروع", "Project Identity"), icon: "sparkles", tint: tint, index: 1) {
                DSComposerLogoPicker(image: $logoImage, existingURL: project.logoUrl, tint: tint)
                    .padding(.bottom, DS.Spacing.xxs)
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
                    DSEmptyView(L10n.t("لا توجد نتائج", "No results"), icon: "magnifyingglass", style: .inline)
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
                    .dsFont(.rowTitle)
                    .foregroundColor(tint.dsReadableGlyph)
                    .frame(width: DS.Icon.row, height: DS.Icon.row)
                    .background(RoundedRectangle(cornerRadius: DS.Icon.discRadius, style: .continuous)
                        .fill(tint.dsReadableGlyph.opacity(DS.Opacity.tintFill)))
                    .accessibilityHidden(true)   // الحرف الأول زخرفة — الاسم كاملاً يُقرأ

                Text(m.displayFullName)
                    .dsFieldFont(isSelected ? .headline : .body)
                    .foregroundColor(isSelected ? DS.Color.fieldLabel : DS.Color.fieldValue)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)

                Spacer(minLength: 0)

                if isSelected {
                    // الاختيار يُقرأ من سمة «مُختار» على الصف
                    Image(systemName: "checkmark.circle.fill")
                        .dsGlyph(DS.Glyph.xl, weight: .regular)
                        .foregroundColor(tint.dsReadableGlyph)
                        .accessibilityHidden(true)
                }
            }
            .dsRowBox()
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .strokeBorder(tint.opacity(isSelected ? DS.Opacity.selectedStroke : 0), lineWidth: DS.Border.widthBold)
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
