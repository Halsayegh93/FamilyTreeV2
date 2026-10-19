import SwiftUI
import UIKit

// MARK: - الموافقة على شروط الاستخدام (EULA — Guideline 1.2)
//
// • `TermsAgreementBox` — مربّع بمنتصف الشاشة لمرة واحدة للأعضاء الحاليين (ضغطة واحدة
//   «أوافق وأتابع»). يُعرض من `MainTabView` إن لم يوافق العضو بعد على هذا الجهاز.
// • `TermsConsentRow` — صفّ اختيار واحد في شاشة التسجيل («أوافق على الشروط…» والرابط فيه)؛
//   لا يُرسل طلب الانضمام قبل الموافقة.
// • `SafetyLinkRow` — صف رابط بنفس صفوف المربّعات (داخل التطبيق أو خارجه).

/// نقاط الشروط الأساسية — نفس النص في المربّع وفي «الخصوصية والشروط»
enum TermsHighlights {
    struct Item: Identifiable {
        let id: Int
        let icon: String
        let tint: Color
        let title: String
        let text: String
    }

    static var all: [Item] {
        [
            Item(id: 0, icon: "nosign", tint: DS.Color.error,
                 title: L10n.t("عدم التسامح مع الإساءة", "Zero tolerance for abuse"),
                 text: L10n.t("يُحظر نشر أي محتوى مسيء أو مهين أو خادش للحياء أو يحض على الكراهية، كما يُحظر التحرّش بأي عضو أو انتحال شخصيته. ويُحذف كل محتوى مخالف، ويُوقف حساب ناشره.",
                              "Posting offensive, insulting, indecent or hateful content is prohibited, as is harassing any member or impersonating anyone. Any violating content is removed and its author's account is suspended.")),
            Item(id: 1, icon: "flag.fill", tint: DS.Color.warning,
                 title: L10n.t("الإبلاغ والحظر", "Report & block"),
                 text: L10n.t("يحق لكل عضو الإبلاغ عن أي خبر أو تعليق أو محتوى أو عضو مخالف، وحظر أي عضو يسيء إليه، فلا يظهر له محتواه بعد ذلك.",
                              "Every member may report any violating post, comment, content or member, and block anyone who abuses them so that member's content no longer appears to them.")),
            Item(id: 2, icon: "checkmark.seal.fill", tint: DS.Color.success,
                 title: L10n.t("مراجعة البلاغات خلال ٢٤ ساعة", "Reports reviewed within 24 hours"),
                 text: L10n.t("تلتزم إدارة التطبيق بمراجعة كل بلاغ خلال أربع وعشرين ساعة من تقديمه، وحذف المحتوى المخالف، وإيقاف حساب ناشره.",
                              "The administration reviews every report within twenty-four hours of submission, removes the violating content and suspends the account that posted it.")),
            Item(id: 3, icon: "lock.fill", tint: DS.Color.info,
                 title: L10n.t("خصوصية العائلة", "Family privacy"),
                 text: L10n.t("التطبيق مخصص لأفراد العائلة المعتمدين فقط، ولا تُباع بيانات الأعضاء، ولا تُستخدم لأغراض الإعلان أو التتبّع.",
                              "The app is reserved for approved family members only; members' data is never sold or used for advertising or tracking."))
        ]
    }
}

// MARK: - المربّع لمرة واحدة

struct TermsAgreementBox: View {
    let onAccept: () -> Void
    let onSignOut: () -> Void

    @State private var showFullTerms = false
    @State private var confirmDecline = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        DSComposer(
            title: L10n.t("شروط الاستخدام", "Terms of Use"),
            subtitle: L10n.t("يُرجى قراءة الشروط والموافقة عليها قبل المتابعة", "Please read and accept the terms before continuing"),
            icon: "checkmark.shield.fill",
            tint: DS.Color.actionNavy,
            actionTitle: L10n.t("أوافق وأتابع", "I Agree"),
            actionIcon: "checkmark",
            cancelTitle: L10n.t("لا أوافق", "Decline"),
            canSubmit: true,
            onSubmit: {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onAccept()
            },
            onCancel: { confirmDecline = true }
        ) {
            DSComposerSection(title: L10n.t("أبرز بنود الشروط", "Key terms"),
                              icon: "checklist", tint: DS.Color.primary, index: 0) {
                VStack(spacing: DS.Spacing.sm) {
                    ForEach(TermsHighlights.all) { item in
                        TermsHighlightRow(item: item)
                    }
                }
            }

            DSComposerSection(title: L10n.t("النص الكامل", "Full text"),
                              icon: "doc.text.fill", tint: DS.Color.accent, index: 1) {
                VStack(spacing: DS.Spacing.sm) {
                    SafetyLinkRow(icon: "doc.text.magnifyingglass", tint: DS.Color.primary,
                                  title: L10n.t("الخصوصية والشروط", "Privacy & Terms"),
                                  subtitle: L10n.t("النص الكامل داخل التطبيق", "Full text inside the app")) {
                        showFullTerms = true
                    }
                    SafetyLinkRow(icon: "globe", tint: DS.Color.info,
                                  title: L10n.t("شروط الاستخدام على الموقع", "Terms of Use on our website"),
                                  subtitle: "\(FamilyLinks.websiteDisplay)/terms",
                                  external: true) {
                        openURL(FamilyLinks.termsOfUse)
                    }
                }
            }
        }
        .dsTallBox(isPresented: $showFullTerms) { PrivacyPolicyView() }
        .dsAlert(L10n.t("الموافقة مطلوبة", "Agreement required"), isPresented: $confirmDecline) {
            Button(L10n.t("رجوع", "Back"), role: .cancel) {}
            Button(L10n.t("تسجيل الخروج", "Sign Out"), role: .destructive) { onSignOut() }
        } message: {
            Text(L10n.t("لا يمكن استخدام التطبيق دون الموافقة على شروط الاستخدام. يُرجى العودة لقراءتها والموافقة عليها، أو تسجيل الخروج.",
                        "The app can't be used without accepting the Terms of Use. Please go back to read and accept them, or sign out."))
        }
    }
}

/// صف نقطة من الشروط — أيقونة الحقل + عنوان + نص
struct TermsHighlightRow: View {
    let item: TermsHighlights.Item

    var body: some View {
        HStack(alignment: .top, spacing: DS.Spacing.sm) {
            DSFieldIcon(name: item.icon, tint: item.tint)
                .accessibilityHidden(true)   // زخرفة — العنوان والنص يكفيان
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(item.title)
                    .dsFieldFont(.rowTitle)
                    .foregroundColor(DS.Color.fieldLabel)
                Text(item.text)
                    .dsFieldFont(.subtitle)
                    .foregroundColor(DS.Color.fieldValue)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .dsRowBox()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - الموافقة في شاشة التسجيل

/// صفّ واحد هادئ (طلب المالك ٢٠٢٦-١٠-١٩ «أبسط»): مربّع اختيار + «أوافق على الشروط وسياسة الخصوصية»،
/// والجزء الملوّن رابط يفتح النص الكامل داخل التطبيق — وفيه بند «لا تهاون مع المحتوى المسيء» (Guideline 1.2).
/// الضغط على أي مكان آخر في الصف يحدّد/يلغي. زر الإرسال لا يعمل قبل التحديد (`RegistrationView`).
struct TermsConsentRow: View {
    @Binding var isAccepted: Bool
    /// بعد محاولة الإرسال بلا موافقة — إطار وتنبيه أحمر قصير
    var showError: Bool = false

    @State private var showTerms = false

    private var highlightError: Bool { showError && !isAccepted }

    /// رابط داخلي — يلتقطه `openURL` أدناه فيفتح الشروط داخل التطبيق (لا يخرج للمتصفح)
    private static let termsLink = URL(string: "familytree-app://terms")!

    /// «أوافق على» + رابط «الشروط وسياسة الخصوصية» — نص واحد يلتفّ طبيعياً مع تكبير الخط
    private var consentText: AttributedString {
        var lead = AttributedString(L10n.t("أوافق على ", "I agree to the "))
        lead.swiftUI.foregroundColor = DS.Color.fieldLabel
        var link = AttributedString(L10n.t("الشروط وسياسة الخصوصية", "Terms & Privacy Policy"))
        link.link = Self.termsLink
        link.inlinePresentationIntent = .stronglyEmphasized
        link.swiftUI.underlineStyle = .single
        return lead + link
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack(spacing: DS.Spacing.xxs) {
                Image(systemName: isAccepted ? "checkmark.square.fill" : "square")
                    .dsGlyph(DS.Glyph.xxl, weight: .semibold)
                    .foregroundColor(isAccepted ? DS.Color.primary
                                                : (highlightError ? DS.Color.error : DS.Color.textTertiary))
                    .frame(width: DS.Icon.tapTarget, height: DS.Icon.tapTarget)   // مساحة ضغط ٤٤ (توصية أبل)

                Text(consentText)
                    .dsFieldFont(.rowTitleCompact)
                    .tint(DS.Color.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .environment(\.openURL, OpenURLAction { url in
                        guard url == Self.termsLink else { return .systemAction }
                        showTerms = true
                        return .handled
                    })

                Spacer(minLength: 0)
            }
            .padding(.vertical, DS.Spacing.xxs)
            .padding(.trailing, DS.Spacing.md)
            .contentShape(Rectangle())
            .onTapGesture(perform: toggle)
            // البطاقة الواحدة، وإطار أحمر بعد محاولة الإرسال بلا موافقة
            .dsCard(padding: nil)
            .overlay(
                RoundedRectangle(cornerRadius: DS.Card.radius, style: .continuous)
                    .strokeBorder(DS.Color.error.opacity(highlightError ? DS.Opacity.selectedStroke : 0),
                                  lineWidth: DS.Border.widthBold)
            )
            // VoiceOver: عنصر واحد = مربّع اختيار، والرابط إجراء إضافي
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.t("أوافق على الشروط وسياسة الخصوصية",
                                       "I agree to the Terms & Privacy Policy"))
            .accessibilityValue(isAccepted ? L10n.t("محدّد", "Checked") : L10n.t("غير محدّد", "Unchecked"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { toggle() }
            .accessibilityAction(named: L10n.t("قراءة الشروط وسياسة الخصوصية",
                                               "Read the Terms & Privacy Policy")) { showTerms = true }

            if highlightError {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .dsGlyph(DS.Glyph.smCompact)
                    Text(L10n.t("الموافقة على الشروط مطلوبة", "Please accept the terms"))
                        .dsFont(.caption)
                }
                .foregroundColor(DS.Color.error)
                .padding(.leading, DS.Spacing.sm)
                .transition(.opacity)
            }
        }
        .animation(DS.Anim.snappy, value: highlightError)
        .dsTallBox(isPresented: $showTerms) { PrivacyPolicyView() }
    }

    private func toggle() {
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(DS.Anim.snappy) { isAccepted.toggle() }
    }
}

// MARK: - صف رابط

/// صف رابط بنفس صفوف المربّعات: أيقونة الحقل + عنوان + وصف + سهم
struct SafetyLinkRow: View {
    let icon: String
    var tint: Color = DS.Color.primary
    let title: String
    var subtitle: String? = nil
    /// رابط خارج التطبيق (المتصفح / البريد) — سهم مائل بدل سهم التنقّل
    var external: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.sm) {
                DSFieldIcon(name: icon, tint: tint)
                    .accessibilityHidden(true)   // زخرفة
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(title)
                        .dsFieldFont(.rowTitle)
                        .foregroundColor(DS.Color.fieldLabel)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                    if let subtitle {
                        Text(subtitle)
                            .dsFont(.footnote)
                            .foregroundColor(DS.Color.textTertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                Spacer(minLength: DS.Spacing.xs)
                if external {
                    Image(systemName: "arrow.up.forward.square")
                        .dsGlyph(DS.Glyph.sm)
                        .foregroundColor(DS.Color.textTertiary)
                        .accessibilityHidden(true)
                } else {
                    DSChevron()
                }
            }
            .dsRowBox()
            .contentShape(Rectangle())
        }
        .buttonStyle(DSScaleButtonStyle())
        .accessibilityHint(external ? L10n.t("يفتح خارج التطبيق", "Opens outside the app") : "")
    }
}
