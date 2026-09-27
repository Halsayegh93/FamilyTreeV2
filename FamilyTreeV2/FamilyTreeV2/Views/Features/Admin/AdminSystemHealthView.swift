import SwiftUI

// «صحة النظام» لم تعد قسماً مستقلاً (طلب المالك): «النشاط الآن» و«الإشعارات»
// صارا مربّعين في «إعدادات النظام ← الإدارة»، و«مهام السيرفر» أُزيلت من التطبيق.
// (المهام المجدولة على السيرفر نفسها تعمل كما هي.)
//
// هذا الملف صار يحمل قطعاً صغيرة مشتركة بين صفحات «النظام» (لوحة الإدارة،
// إعدادات النظام، الأجهزة، حالة الإشعارات، التحديث الإجباري…) بنفس لغة
// المربّعات الموحّدة (طلب المالك ٢٠٢٦-٠٩-٢٧): شارة حالة، بطاقة حالة فارغة/تحميل/خطأ،
// صف `.dsRowBox()`، عنوان قسم، زر إجراء، وحلقة تقدّم.

/// عنوان موحّد أعلى صفحات المتابعة — بقي للتوافق (الصفحات صارت تستخدم `DSPageHero`)
struct SystemHealthSectionHeader: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(DS.Font.plex(19, weight: .bold))
                .foregroundColor(DS.Color.fieldLabel)
            Text(subtitle)
                .font(DS.Font.plex(12))
                .foregroundColor(DS.Color.fieldValue)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - شارة حالة

/// كبسولة صغيرة ملوّنة (Plex 11 عريض): منتظر = warning، مفعّل = success، مرفوض/مجمّد = error، معلومة = primary
struct SysStatusChip: View {
    let text: String
    var icon: String? = nil
    var tint: Color = DS.Color.primary

    var body: some View {
        HStack(spacing: 3) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 9.5, weight: .bold))
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(DS.Font.plex(11, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .foregroundColor(tint.dsReadableGlyph)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(tint.dsReadableGlyph.opacity(0.13), in: Capsule())
    }
}

// MARK: - بطاقة حالة (فارغ / تحميل / خطأ)

/// بطاقة صغيرة في المنتصف: أيقونة في دائرة ملوّنة، عنوان، سطر توضيح، وزر (إعادة المحاولة مثلاً)
struct SysStateCard: View {
    let icon: String
    let title: String
    var hint: String? = nil
    var tint: Color = DS.Color.primary
    var isLoading: Bool = false
    var actionTitle: String? = nil
    var actionIcon: String = "arrow.clockwise"
    var action: (() -> Void)? = nil

    /// الكحلي الغامق لا يُقرأ كأيقونة في الداكن — `dsReadableGlyph` (نفس اللون في الفاتح)
    private var iconTint: Color { tint.dsReadableGlyph }

    var body: some View {
        VStack(spacing: DS.Spacing.sm) {
            ZStack {
                Circle().fill(iconTint.opacity(0.12))
                if isLoading {
                    ProgressView().tint(iconTint)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(iconTint)
                }
            }
            .frame(width: 52, height: 52)
            .accessibilityHidden(true)

            Text(title)
                .font(DS.Font.plex(14.5, weight: .bold))
                .foregroundColor(DS.Color.fieldLabel)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let hint {
                Text(hint)
                    .font(DS.Font.plex(12))
                    .foregroundColor(DS.Color.fieldValue)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let actionTitle, let action {
                Button(action: action) {
                    HStack(spacing: 6) {
                        Image(systemName: actionIcon).font(.system(size: 12.5, weight: .bold))
                        Text(actionTitle).font(DS.Font.plex(13.5, weight: .bold))
                    }
                    .foregroundColor(DSActionFill.label())
                    .padding(.horizontal, DS.Spacing.lg)
                    .frame(minHeight: 44)
                    .background(DSActionFill.style(), in: Capsule())
                }
                .buttonStyle(DSScaleButtonStyle())
                .padding(.top, 2)
            }
        }
        .padding(DS.Spacing.lg)
        .frame(maxWidth: 360)
        .background(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous).fill(DS.Color.surface))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
            .strokeBorder(DS.Color.textTertiary.opacity(0.10), lineWidth: 1))
        .frame(maxWidth: .infinity)
    }
}

// MARK: - صف موحّد

/// صف بإطار حقول المربّعات: أيقونة حقل + عنوان (Plex 13.5 عريض) + وصف (Plex 12) + طرف اختياري
struct SysRow<Trailing: View>: View {
    let icon: String
    var tint: Color = DS.Color.primary
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            DSFieldIcon(name: icon, tint: tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DS.Font.plex(13.5, weight: .bold))
                    .foregroundColor(DS.Color.fieldLabel)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(DS.Font.plex(12))
                        .foregroundColor(DS.Color.fieldValue)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            trailing()
        }
        .frame(minHeight: 36)
        .dsRowBox()
    }
}

extension SysRow where Trailing == EmptyView {
    init(icon: String, tint: Color = DS.Color.primary, title: String, subtitle: String? = nil) {
        self.icon = icon
        self.tint = tint
        self.title = title
        self.subtitle = subtitle
        self.trailing = { EmptyView() }
    }
}

// MARK: - أيقونة متدرّجة

/// أيقونة بيضاء على مربّع مستدير متدرّج بلون المجال — للبلاطات وبطاقات «يحتاج انتباهك».
/// في الداكن طبقة تعتيم خفيفة تحفظ وضوح الأبيض على الألوان الفاتحة (مثل رؤوس المربّعات).
struct SysGradientIcon: View {
    let name: String
    var tint: Color = DS.Color.actionNavy
    var size: CGFloat = 40
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(systemName: name)
            .font(.system(size: size * 0.42, weight: .bold))
            .foregroundColor(.white)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .fill(LinearGradient(colors: [tint, tint.opacity(0.72)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(
                        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                            .fill(Color.black.opacity(colorScheme == .dark ? 0.22 : 0))
                    )
            )
            .shadow(color: tint.opacity(colorScheme == .dark ? 0 : 0.28), radius: 5, x: 0, y: 3)
            .accessibilityHidden(true)
    }
}

/// سهم صغير يتبع اتجاه اللغة (للصفوف القابلة للضغط)
struct SysChevron: View {
    var body: some View {
        Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
            .font(.system(size: 11.5, weight: .bold))
            .foregroundColor(DS.Color.textTertiary)
            .accessibilityHidden(true)
    }
}

// MARK: - عنوان قسم خارج البطاقة

/// نفس رأس `DSComposerSection` (أيقونة بدائرة + عنوان + نص جانبي) — لشبكات البلاطات والشرائط
struct SysSectionTitle: View {
    let title: String
    let icon: String
    var tint: Color = DS.Color.primary
    var trailing: String? = nil

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 10.5, weight: .bold))
                .foregroundColor(tint.dsReadableGlyph)
                .frame(width: 22, height: 22)
                .background(Circle().fill(tint.dsReadableGlyph.opacity(0.13)))
                .accessibilityHidden(true)
            Text(title)
                .font(DS.Font.plex(12.5, weight: .bold))
                .foregroundColor(DS.Color.fieldLabel)
            Spacer(minLength: 0)
            if let trailing {
                Text(trailing)
                    .font(DS.Font.plex(11, weight: .semibold))
                    .foregroundColor(DS.Color.textTertiary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 2)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - زر إجراء بعرض كامل

/// زر ٤٨ نقطة بنفس زر المربّعات: كحلي (DSActionFill) افتراضياً، أو لون صلب للتحذير/الخطر
struct SysActionButton: View {
    let title: String
    let icon: String
    /// nil = الكحلي الموحّد، وغيره لون صلب (تحذير/خطر)
    var tint: Color? = nil
    var isBusy: Bool = false
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if isBusy {
                    ProgressView().tint(.white).scaleEffect(0.85)
                } else {
                    Image(systemName: icon).font(.system(size: 14, weight: .bold))
                }
                Text(title).font(DS.Font.plex(14.5, weight: .bold))
            }
            .foregroundColor(DSActionFill.label(enabled: enabled && !isBusy))
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(fill, in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        }
        .buttonStyle(DSScaleButtonStyle())
        .disabled(!enabled || isBusy)
    }

    private var fill: AnyShapeStyle {
        if let tint { return AnyShapeStyle(tint.opacity(enabled && !isBusy ? 1 : 0.45)) }
        return AnyShapeStyle(DSActionFill.style(enabled: enabled && !isBusy))
    }
}

// MARK: - حلقة تقدّم

/// حلقة نسبة (٠…١) بلون الحالة — تمتلئ بحركة ناعمة (ثابتة مع «تقليل الحركة»)
struct SysRing<Center: View>: View {
    let progress: Double
    var tint: Color = DS.Color.success
    var lineWidth: CGFloat = 8
    var size: CGFloat = 84
    @ViewBuilder var center: () -> Center
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.14), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: shown || reduceMotion ? max(0, min(1, progress)) : 0)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            center()
        }
        .frame(width: size, height: size)
        .onAppear {
            guard !reduceMotion else { shown = true; return }
            withAnimation(.easeOut(duration: 0.9).delay(0.2)) { shown = true }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.5), value: progress)
    }
}

// MARK: - شريط توزيع

/// شريط أفقي مقسّم بنسب ملوّنة (توزيع فئات) — لمحة بدل جدول أرقام
struct SysDistributionBar: View {
    struct Segment: Identifiable {
        let id: String
        let value: Int
        let tint: Color
    }
    let segments: [Segment]
    var height: CGFloat = 10

    var body: some View {
        let visible = segments.filter { $0.value > 0 }
        let total = max(1, visible.reduce(0) { $0 + $1.value })
        let gaps = CGFloat(max(0, visible.count - 1)) * 2
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(visible) { seg in
                    RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                        .fill(seg.tint)
                        .frame(width: max(height, (geo.size.width - gaps) * CGFloat(seg.value) / CGFloat(total)))
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: height)
        .background(Capsule().fill(DS.Color.textTertiary.opacity(0.10)))
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }
}
