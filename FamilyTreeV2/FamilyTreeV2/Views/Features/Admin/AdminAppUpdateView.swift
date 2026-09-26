import SwiftUI
import Supabase

/// تحديثات التطبيق ورسائل النظام — تُنشر لكل الأعضاء وتظهر في تبويب
/// «المستجدات» بمركز الإشعارات (طلب المالك).
/// الفرق عن «إرسال إشعارات»: هذه إعلانات عامة عن التطبيق نفسه (إصدار جديد،
/// ميزة، صيانة)، لا رسائل موجّهة لأعضاء بعينهم.
/// التصميم الموحّد (٢٠٢٦-٠٩-٢٧): بطاقة رأس، ثم أقسام: النوع ← الرسالة ← المعاينة ← زر النشر.
/// داخل «الإشعارات والتحديثات» (`embedded`) الصفحة الأم تحمل بطاقة الرأس فلا تتكرّر.
struct AdminAppUpdateView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel
    @Environment(\.dismiss) private var dismiss

    /// مضمّنة في صفحة أخرى لها رأسها — بلا بطاقة رأس
    private let embedded: Bool

    @State private var kind: UpdateKind = .feature
    @State private var version = ""
    @State private var summary = ""
    @State private var isSending = false
    @State private var didSend = false
    @State private var errorText: String?
    @FocusState private var summaryFocused: Bool

    private let maxLength = 1000
    private let tint = DS.Color.composerDiwaniya

    init(embedded: Bool = false) {
        self.embedded = embedded
    }

    // MARK: - نوع الرسالة

    enum UpdateKind: String, CaseIterable, Identifiable {
        case feature, fix, maintenance, notice
        var id: String { rawValue }

        var title: String {
            switch self {
            case .feature:     return L10n.t("ميزة جديدة", "New feature")
            case .fix:         return L10n.t("إصلاح", "Fix")
            case .maintenance: return L10n.t("صيانة", "Maintenance")
            case .notice:      return L10n.t("تنويه", "Notice")
            }
        }
        var icon: String {
            switch self {
            case .feature:     return "sparkles"
            case .fix:         return "wrench.and.screwdriver.fill"
            case .maintenance: return "gearshape.2.fill"
            case .notice:      return "info.circle.fill"
            }
        }
        var color: Color {
            switch self {
            case .feature:     return DS.Color.success
            case .fix:         return DS.Color.info
            case .maintenance: return DS.Color.warning
            case .notice:      return DS.Color.primary
            }
        }
        /// عنوان الإشعار كما يصل العضو
        var headline: String {
            switch self {
            case .feature:     return L10n.t("ميزة جديدة في التطبيق", "New in the app")
            case .fix:         return L10n.t("تحسينات وإصلاحات", "Improvements & fixes")
            case .maintenance: return L10n.t("صيانة مجدولة", "Scheduled maintenance")
            case .notice:      return L10n.t("تنويه من الإدارة", "Notice from admin")
            }
        }
    }

    private var canSend: Bool {
        !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending && !didSend
    }

    /// العنوان النهائي: «ميزة جديدة في التطبيق · 2.1»
    private var finalTitle: String {
        let v = version.trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? kind.headline : "\(kind.headline) · \(v)"
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: DS.Spacing.md) {
                    if embedded {
                        introRow
                    } else {
                        hero
                            .padding(.bottom, DS.Spacing.xs)
                    }
                    if AppReleaseNotes.current != nil { fillReleaseNotesButton }
                    kindSection
                    messageSection
                    previewSection

                    if let errorText {
                        HStack(spacing: DS.Spacing.sm) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(DS.Color.error)
                                .accessibilityHidden(true)
                            Text(errorText)
                                .font(DS.Font.plex(12, weight: .semibold))
                                .foregroundColor(DS.Color.fieldLabel)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(DS.Spacing.md)
                        .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                            .fill(DS.Color.error.opacity(0.10)))
                        .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                            .strokeBorder(DS.Color.error.opacity(0.25), lineWidth: 1))
                        .accessibilityElement(children: .combine)
                    }

                    publishButton
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.top, DS.Spacing.md)
                .padding(.bottom, DS.Spacing.xxxxl)
            }
        }
        .navigationTitle(L10n.t("تحديثات التطبيق", "App Updates"))
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    // MARK: - الرأس

    private var hero: some View {
        DSPageHero(
            title: L10n.t("تحديثات التطبيق", "App Updates"),
            subtitle: L10n.t("رسالة نظام لكل الأعضاء — تظهر في «المستجدات» ويصل معها إشعار.",
                             "A system message to everyone — shows in Updates with a push."),
            icon: "megaphone.fill",
            tint: tint,
            stats: [
                DSHeroStat(value: "\(AppBuild.current)", label: L10n.t("رقم البناء", "Build"), icon: "app.badge.fill"),
                DSHeroStat(value: "\(summary.count)", label: L10n.t("حرف من \(maxLength)", "of \(maxLength) chars"),
                           icon: "text.alignright")
            ]
        )
    }

    /// داخل الصفحة الأم: سطر يشرح أين تظهر الرسالة (كان بطاقة المقدّمة)
    private var introRow: some View {
        SysRow(icon: "megaphone.fill", tint: tint,
               title: L10n.t("رسالة نظام لكل الأعضاء", "System message to everyone"),
               subtitle: L10n.t("تظهر في تبويب «المستجدات» ويصل معها إشعار.",
                                "Appears in the Updates tab with a push notification."))
            .accessibilityElement(children: .combine)
            .dsStaggerIn(0)
    }

    // MARK: - الأقسام

    /// تعبئة ملاحظات هذا الإصدار تلقائياً (النوع + الرقم + ما الجديد) — تُراجَع ثم تُنشر
    private var fillReleaseNotesButton: some View {
        Button {
            withAnimation(DS.Anim.quick) {
                kind = .feature
                version = AppReleaseNotes.currentVersionLabel
                summary = AppReleaseNotes.current ?? summary
            }
        } label: {
            SysRow(icon: "doc.text.fill", tint: DS.Color.primary,
                   title: L10n.t("تعبئة ملاحظات هذا الإصدار \(AppReleaseNotes.currentVersionLabel)",
                                 "Fill this release's notes \(AppReleaseNotes.currentVersionLabel)"),
                   subtitle: L10n.t("النوع والرقم وما الجديد — راجعها ثم انشر",
                                    "Type, version and what's new — review, then publish")) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(DS.Color.primary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(DSScaleButtonStyle())
        .dsStaggerIn(0)
    }

    private var kindSection: some View {
        DSComposerSection(title: L10n.t("النوع", "Type"),
                          icon: "square.grid.2x2.fill",
                          tint: tint,
                          trailing: kind.title,
                          index: 1) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Spacing.sm), count: 2),
                      spacing: DS.Spacing.sm) {
                ForEach(UpdateKind.allCases) { k in
                    kindOption(k)
                }
            }
        }
    }

    private func kindOption(_ k: UpdateKind) -> some View {
        let selected = kind == k
        return Button {
            withAnimation(DS.Anim.quick) { kind = k }
        } label: {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: k.icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(selected ? .white : k.color)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(selected ? k.color : k.color.opacity(0.13)))
                    .accessibilityHidden(true)
                Text(k.title)
                    .font(DS.Font.plex(12.5, weight: .bold))
                    .foregroundColor(selected ? DS.Color.fieldLabel : DS.Color.fieldValue)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(k.color)
                        .transition(.opacity)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, DS.Spacing.sm + 2)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .fill(selected ? k.color.opacity(0.10) : DS.Color.background))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .strokeBorder(selected ? k.color.opacity(0.55) : DS.Color.textTertiary.opacity(0.15),
                              lineWidth: selected ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(k.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var messageSection: some View {
        DSComposerSection(title: L10n.t("الرسالة", "Message"),
                          icon: "text.bubble.fill",
                          tint: tint,
                          index: 2) {
            DSComposerField(icon: "number",
                            label: L10n.t("رقم الإصدار (اختياري)", "Version (optional)"),
                            placeholder: L10n.t("مثال: 2.1", "e.g. 2.1"),
                            text: $version,
                            tint: tint,
                            keyboard: .numbersAndPunctuation,
                            ltr: true)

            summaryEditor
        }
    }

    /// «ما الجديد» — محرّر متعدد الأسطر بإطار حقول المربّعات (يتلوّن عند الكتابة) + عدّاد
    private var summaryEditor: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: "text.alignright")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(summaryFocused ? .white : tint)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(summaryFocused ? tint : tint.opacity(0.12)))
                    .accessibilityHidden(true)
                Text(L10n.t("ما الجديد", "What's new"))
                    .font(DS.Font.plex(12, weight: .heavy))
                    .foregroundColor(summaryFocused ? tint : DS.Color.fieldLabel)
                Spacer(minLength: 0)
                Text("\(summary.count)/\(maxLength)")
                    .font(DS.Font.plex(10.5, weight: .semibold))
                    .foregroundColor(summary.count > maxLength ? DS.Color.error : DS.Color.textTertiary)
                    .monospacedDigit()
            }

            ZStack(alignment: .topLeading) {
                if summary.isEmpty {
                    Text(L10n.t("اكتب ما تغيّر في التطبيق…", "Describe what changed…"))
                        .font(DS.Font.plex(14.5))
                        .foregroundColor(DS.Color.textTertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                TextEditor(text: $summary)
                    .focused($summaryFocused)
                    .font(DS.Font.plex(14.5))
                    .foregroundColor(DS.Color.textPrimary)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 160, maxHeight: 320)
                    .accessibilityLabel(L10n.t("ما الجديد", "What's new"))
                    .onChange(of: summary) { _ in
                        if summary.count > maxLength { summary = String(summary.prefix(maxLength)) }
                    }
            }
        }
        .padding(.horizontal, DS.Spacing.sm + 2)
        .padding(.vertical, DS.Spacing.sm)
        .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).fill(DS.Color.background))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
            .strokeBorder(summaryFocused ? tint.opacity(0.65) : DS.Color.textTertiary.opacity(0.15),
                          lineWidth: summaryFocused ? 1.5 : 1))
        .animation(.easeInOut(duration: 0.2), value: summaryFocused)
    }

    /// معاينة الشكل كما يصل العضو
    private var previewSection: some View {
        DSComposerSection(title: L10n.t("المعاينة", "Preview"),
                          icon: "eye.fill",
                          tint: tint,
                          trailing: L10n.t("كما يصل العضو", "As members see it"),
                          index: 3) {
            HStack(alignment: .top, spacing: DS.Spacing.sm) {
                Image(systemName: kind.icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(kind.color)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(kind.color.opacity(0.13)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(finalTitle)
                        .font(DS.Font.plex(13.5, weight: .bold))
                        .foregroundColor(DS.Color.fieldLabel)
                    Text(summary.isEmpty ? L10n.t("نص التحديث…", "Update text…") : summary)
                        .font(DS.Font.plex(12))
                        .foregroundColor(DS.Color.fieldValue)
                        .lineLimit(6)
                }
                Spacer(minLength: 0)
            }
            .dsRowBox()
            .accessibilityElement(children: .combine)
        }
    }

    private var publishButton: some View {
        Button {
            Task { await publish() }
        } label: {
            HStack(spacing: 7) {
                if isSending {
                    ProgressView().tint(.white).scaleEffect(0.85)
                } else {
                    Image(systemName: didSend ? "checkmark.circle.fill" : "megaphone.fill")
                        .font(.system(size: 14, weight: .bold))
                }
                Text(didSend ? L10n.t("تم النشر", "Published")
                             : L10n.t("نشر للجميع", "Publish to everyone"))
                    .font(DS.Font.plex(15, weight: .bold))
            }
            .foregroundColor(didSend ? .white : DSActionFill.label(enabled: canSend))
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(publishFill, in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        }
        .buttonStyle(DSScaleButtonStyle())
        .disabled(!canSend)
        .padding(.top, DS.Spacing.xs)
        .animation(.easeInOut(duration: 0.2), value: didSend)
    }

    private var publishFill: AnyShapeStyle {
        didSend ? AnyShapeStyle(DS.Color.success) : AnyShapeStyle(DSActionFill.style(enabled: canSend))
    }

    // MARK: - النشر

    @MainActor
    private func publish() async {
        errorText = nil
        summaryFocused = false
        isSending = true
        defer { isSending = false }

        // صف واحد بلا هدف: القاعدة تُفرّخ نسخة لكل عضو ويخرج الدفع مرة واحدة
        let ok = await notificationVM.sendNotification(
            title: finalTitle,
            body: summary.trimmingCharacters(in: .whitespacesAndNewlines),
            targetMemberIds: nil,
            kind: "app_update"
        )
        if ok {
            didSend = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            try? await Task.sleep(nanoseconds: 900_000_000)
            dismiss()
        } else {
            errorText = L10n.t("تعذّر النشر. حاول مرة أخرى.", "Could not publish. Try again.")
        }
    }
}
