import SwiftUI

// MARK: - صفحات الإدارة بتصميم المربّعات الموحّد (طلب المالك ٢٠٢٦-٠٩-٢٧)
//
// لغة واحدة لكل صفحات الإدارة (لوحة الإدارة، الطلبات، الأعضاء، الرسائل، السجل…):
//   • `DSPageHero` — بطاقة رأس ملوّنة أعلى الصفحة (نفس رأس المربّعات: تدرّج، أيقونة
//     زجاجية، علامة مائية) مع أرقام سريعة `DSHeroStat`.
//   • `DSStatTile` — بطاقة رقم حيّ (قابلة للضغط) لشبكة الأرقام.
//   • `DSSearchField` — حقل بحث بنفس إطار حقول المربّعات.
//   • `DSFilterChips` — شريط فلاتر أفقي مع العدد، والمختار ممتلئ بلون القسم.
// والمحتوى تحتها بأقسام `DSComposerSection` وصفوف `.dsRowBox()` — مثل المربّعات تماماً.
// شريط التنقّل يبقى شريط النظام (رجوع أبل المعتاد) — لا نستبدله.

// MARK: - رقم داخل بطاقة الرأس

struct DSHeroStat: Identifiable {
    let id = UUID()
    let value: String
    let label: String
    var icon: String? = nil
}

// MARK: - بطاقة رأس الصفحة

struct DSPageHero: View {
    let title: String
    let subtitle: String
    let icon: String
    var tint: Color = DS.Color.actionNavy
    var stats: [DSHeroStat] = []
    @State private var appeared = false
    @State private var drift = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(spacing: DS.Spacing.md) {
                ZStack {
                    Circle().fill(Color.white.opacity(0.18))
                    Circle().strokeBorder(Color.white.opacity(0.38), lineWidth: 1)
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                }
                .frame(width: 48, height: 48)
                .scaleEffect(appeared || reduceMotion ? 1 : 0.5)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(DS.Font.plex(19, weight: .bold))
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(DS.Font.plex(12))
                        .foregroundColor(.white.opacity(0.86))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            if !stats.isEmpty {
                HStack(spacing: DS.Spacing.sm) {
                    ForEach(stats) { stat in
                        VStack(spacing: 2) {
                            HStack(spacing: 4) {
                                if let icon = stat.icon {
                                    Image(systemName: icon)
                                        .font(.system(size: 11, weight: .bold))
                                        .accessibilityHidden(true)
                                }
                                Text(stat.value)
                                    .font(DS.Font.plex(17, weight: .bold))
                                    .monospacedDigit()
                            }
                            .foregroundColor(.white)
                            Text(stat.label)
                                .font(DS.Font.plex(10.5, weight: .semibold))
                                .foregroundColor(.white.opacity(0.82))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DS.Spacing.sm)
                        .background(Color.white.opacity(0.14),
                                    in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .padding(DS.Spacing.lg)
        .background(
            ZStack {
                LinearGradient(colors: [tint, tint.opacity(0.72)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                if colorScheme == .dark { Color.black.opacity(0.3) }
                // أبسط (طلب المالك): بلا علامة مائية ولا لمعة ولا حركة
            }
            .accessibilityHidden(true)
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
        .shadow(color: tint.opacity(colorScheme == .dark ? 0 : 0.14), radius: 8, x: 0, y: 4)
        .accessibilityElement(children: .contain)
        .onAppear {
            if reduceMotion { appeared = true; return }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.65).delay(0.05)) { appeared = true }
        }
    }
}

// MARK: - بطاقة رقم حيّ

/// رقم كبير + عنوان + أيقونة بلون القسم — تُستخدم في شبكات الأرقام (٢ أو ٣ بالصف).
struct DSStatTile: View {
    let value: String
    let label: String
    let icon: String
    var tint: Color = DS.Color.primary
    /// شارة تنبيه صغيرة (مثل «جديد») — nil = بلا شارة
    var badge: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        Group {
            if let action {
                Button(action: action) { content }
                    .buttonStyle(DSScaleButtonStyle())
            } else {
                content
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack {
                DSFieldIcon(name: icon, tint: tint)
                Spacer(minLength: 0)
                if let badge {
                    Text(badge)
                        .font(DS.Font.plex(10.5, weight: .bold))
                        .foregroundColor(tint)
                        .padding(.horizontal, DS.Spacing.sm)
                        .padding(.vertical, 2)
                        .background(tint.opacity(0.14), in: Capsule())
                }
            }
            Text(value)
                .font(DS.Font.plex(22, weight: .bold))
                .foregroundColor(DS.Color.fieldLabel)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .dsFieldFont(12, weight: .semibold)
                .foregroundColor(DS.Color.fieldValue)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous).fill(DS.Color.surface))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
            .strokeBorder(DS.Color.textTertiary.opacity(0.10), lineWidth: 1))
        .contentShape(Rectangle())
    }
}

// MARK: - حقل بحث

/// حقل بحث بسطر واحد بنفس إطار حقول المربّعات (يتلوّن عند الكتابة) + زر مسح ٤٤ نقطة
struct DSSearchField: View {
    @Binding var text: String
    var placeholder: String = L10n.t("بحث…", "Search…")
    var tint: Color = DS.Color.primary
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(focused ? tint : DS.Color.textTertiary)
                .accessibilityHidden(true)
            TextField(placeholder, text: $text)
                .dsFieldFont(14.5)
                .foregroundColor(DS.Color.textPrimary)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .focused($focused)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundColor(DS.Color.textTertiary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, -8)
                .accessibilityLabel(L10n.t("مسح البحث", "Clear search"))
            }
        }
        .padding(.horizontal, DS.Spacing.md)
        .frame(minHeight: 46)
        .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).fill(DS.Color.surface))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
            .strokeBorder(focused ? tint.opacity(0.65) : DS.Color.textTertiary.opacity(0.15),
                          lineWidth: focused ? 1.5 : 1))
        .animation(.easeInOut(duration: 0.2), value: focused)
    }
}

// MARK: - شريط فلاتر

struct DSFilterOption<ID: Hashable>: Identifiable {
    let id: ID
    let title: String
    var icon: String? = nil
    var count: Int? = nil
}

/// فلاتر أفقية: المختار ممتلئ بلون القسم، والباقي بإطار خفيف — مساحة ضغط ٤٤
struct DSFilterChips<ID: Hashable>: View {
    let options: [DSFilterOption<ID>]
    @Binding var selection: ID
    var tint: Color = DS.Color.primary
    @Namespace private var ns
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Spacing.sm) {
                ForEach(options) { option in
                    let selected = option.id == selection
                    Button {
                        guard !selected else { return }
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : DS.Anim.snappy) {
                            selection = option.id
                        }
                    } label: {
                        HStack(spacing: 5) {
                            if let icon = option.icon {
                                Image(systemName: icon).font(.system(size: 11.5, weight: .bold))
                            }
                            Text(option.title).font(DS.Font.plex(12.5, weight: .bold))
                            if let count = option.count {
                                Text("\(count)")
                                    .font(DS.Font.plex(11, weight: .bold))
                                    .monospacedDigit()
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background((selected ? Color.white : tint).opacity(selected ? 0.22 : 0.12),
                                                in: Capsule())
                            }
                        }
                        .foregroundColor(selected ? .white : DS.Color.textSecondary)
                        .padding(.horizontal, DS.Spacing.md)
                        .frame(height: 36)
                        .background {
                            if selected {
                                Capsule().fill(DSActionFill.style())
                                    .matchedGeometryEffect(id: "chip", in: ns)
                            } else {
                                Capsule().strokeBorder(DS.Color.textTertiary.opacity(0.3), lineWidth: 1)
                            }
                        }
                        .padding(.vertical, 4)   // مساحة ضغط ٤٤
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 1)
        }
    }
}
