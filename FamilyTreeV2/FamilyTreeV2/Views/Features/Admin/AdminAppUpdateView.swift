import SwiftUI
import Supabase

/// تحديثات التطبيق ورسائل النظام — تُنشر لكل الأعضاء وتظهر في تبويب
/// «المستجدات» بمركز الإشعارات (طلب المالك).
/// الفرق عن «إرسال إشعارات»: هذه إعلانات عامة عن التطبيق نفسه (إصدار جديد،
/// ميزة، صيانة)، لا رسائل موجّهة لأعضاء بعينهم.
/// «أسلوب واحد» (٢٠٢٦-١٠-٠٧): الرأس الملوّن الموحّد (بـ× لأنها تُفتح مربّعاً من إشعارات الرئيسية) +
/// صفّ أرقام، ثم أقسام: النوع ← الرسالة ← المعاينة ← زر النشر.
/// داخل «الإشعارات والتحديثات» (`embedded`) الصفحة الأم تحمل الرأس فلا يتكرّر.
struct AdminAppUpdateView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel
    @Environment(\.dismiss) private var dismiss
    /// يُفتح من الإدارة ومن إشعارات الرئيسية — كحلي «الإطار» يتبع القسم
    @Environment(\.dsSection) private var section

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
            case .feature:     return DS.Color.accent
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
        Group {
            if embedded {
                page
            } else {
                // تُفتح مربّعاً طويلاً من إشعارات الرئيسية — الرأس الملوّن الموحّد و× للإغلاق
                page
                    .dsSubPageHeader(L10n.t("تحديثات التطبيق", "App Updates"),
                                     subtitle: L10n.t("رسالة نظام لكل الأعضاء — تظهر في «المستجدات» ويصل معها إشعار.",
                                                      "A system message to everyone — shows in Updates with a push."),
                                     nav: .close)
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    private var page: some View {
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
                        DSNoteCard(errorText, icon: "exclamationmark.triangle.fill", tint: DS.Color.error)
                    }

                    publishButton
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.top, DS.Spacing.md)
                .padding(.bottom, DS.Spacing.xxxxl)
            }
            .background(DS.Color.background.ignoresSafeArea())
    }

    // MARK: - الرأس

    /// العنوان والوصف في الرأس الملوّن — الأرقام هنا
    private var hero: some View {
        DSStatsRow([
            DSHeroStat(value: "\(AppBuild.current)", label: L10n.t("رقم البناء", "Build"), icon: "app.badge.fill"),
            DSHeroStat(value: "\(summary.count)", label: L10n.t("حرف من \(maxLength)", "of \(maxLength) chars"),
                       icon: "text.alignright")
        ], tint: tint)
    }

    /// داخل الصفحة الأم: سطر يشرح أين تظهر الرسالة (كان بطاقة المقدّمة)
    private var introRow: some View {
        DSRow(icon: "megaphone.fill", tint: tint,
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
            DSRow(icon: "doc.text.fill", tint: DS.Color.primary,
                   title: L10n.t("تعبئة ملاحظات هذا الإصدار \(AppReleaseNotes.currentVersionLabel)",
                                 "Fill this release's notes \(AppReleaseNotes.currentVersionLabel)"),
                   subtitle: L10n.t("النوع والرقم وما الجديد — راجعها ثم انشر",
                                    "Type, version and what's new — review, then publish")) {
                Image(systemName: "wand.and.stars")
                    .dsGlyph(DS.Glyph.md)
                    .foregroundColor(DS.Color.primary.dsChrome(in: section))
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
            // مربّعات الاختيار الواحد (`DSOptionTiles`) — كانت أزراراً يدوية بعمودين
            DSOptionTiles(UpdateKind.allCases.map { DSOptionTile($0, title: $0.title, icon: $0.icon, tint: $0.color) },
                          selection: $kind, columns: 4)
        }
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
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: "text.alignright")
                    .dsGlyph(DS.Glyph.mdCompact, weight: .semibold)
                    .foregroundColor(summaryFocused ? DS.Color.textOnPrimary : tint)
                    .frame(width: DS.Icon.row, height: DS.Icon.row)
                    .background(RoundedRectangle(cornerRadius: DS.Icon.discRadius, style: .continuous)
                        .fill(summaryFocused ? tint : tint.opacity(DS.Opacity.tintFill)))
                    .accessibilityHidden(true)
                Text(L10n.t("ما الجديد", "What's new"))
                    .dsFieldFont(.label)
                    .foregroundColor(summaryFocused ? tint : DS.Color.fieldLabel)
                Spacer(minLength: 0)
                Text("\(summary.count)/\(maxLength)")
                    .dsFont(.micro)
                    .foregroundColor(summary.count > maxLength ? DS.Color.error : DS.Color.textTertiary)
                    .monospacedDigit()
            }

            ZStack(alignment: .topLeading) {
                if summary.isEmpty {
                    Text(L10n.t("اكتب ما تغيّر في التطبيق…", "Describe what changed…"))
                        .dsFont(.body)
                        .foregroundColor(DS.Color.textTertiary)
                        .padding(.horizontal, DS.Spacing.xs)
                        .padding(.vertical, DS.Spacing.sm)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                TextEditor(text: $summary)
                    .focused($summaryFocused)
                    .dsFieldFont(.body)
                    .foregroundColor(DS.Color.textPrimary)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: DSBox.editorTallMinHeight, maxHeight: DSBox.editorTallMaxHeight)
                    .accessibilityLabel(L10n.t("ما الجديد", "What's new"))
                    .onChange(of: summary) { _ in
                        if summary.count > maxLength { summary = String(summary.prefix(maxLength)) }
                    }
            }
        }
        .padding(.horizontal, DS.Spacing.sm + DS.Spacing.xxs)
        .padding(.vertical, DS.Spacing.sm)
        .dsFocusFieldBox(focused: summaryFocused, tint: tint)
    }

    /// معاينة الشكل كما يصل العضو
    private var previewSection: some View {
        DSComposerSection(title: L10n.t("المعاينة", "Preview"),
                          icon: "eye.fill",
                          tint: tint,
                          trailing: L10n.t("كما يصل العضو", "As members see it"),
                          index: 3) {
            HStack(alignment: .top, spacing: DS.Spacing.sm) {
                DSStateIcon(kind.icon, tint: kind.color, size: DS.Icon.row)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(finalTitle)
                        .dsFieldFont(.rowTitle)
                        .foregroundColor(DS.Color.fieldLabel)
                    Text(summary.isEmpty ? L10n.t("نص التحديث…", "Update text…") : summary)
                        .dsFieldFont(.subtitle)
                        .foregroundColor(DS.Color.fieldValue)
                        .lineLimit(6)
                }
                Spacer(minLength: 0)
            }
            .dsRowBox()
            .accessibilityElement(children: .combine)
        }
    }

    /// الزرّ الواحد: «نشر للجميع» بتعبئة القسم، و«تم النشر» أخضر صلب (دوّارته داخله أثناء النشر)
    private var publishButton: some View {
        DSButton(didSend ? L10n.t("تم النشر", "Published") : L10n.t("نشر للجميع", "Publish to everyone"),
                 icon: didSend ? "checkmark.circle.fill" : "megaphone.fill",
                 tint: didSend ? DS.Color.success : nil,
                 isLoading: isSending) {
            Task { await publish() }
        }
        // «تم النشر» يبقى بلونه (لا خفوت المعطّل) لكنه لا يُضغط
        .disabled(!canSend && !didSend)
        .allowsHitTesting(canSend)
        .padding(.top, DS.Spacing.xs)
        .animation(.easeInOut(duration: 0.2), value: didSend)
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
