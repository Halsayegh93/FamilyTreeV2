import SwiftUI
import UIKit

// MARK: - الموافقة على شروط الاستخدام (EULA — Guideline 1.2)
//
// • `TermsAgreementBox` — مربّع بمنتصف الشاشة لمرة واحدة للأعضاء الحاليين (ضغطة واحدة
//   «أوافق وأتابع»). يُعرض من `MainTabView` إن لم يوافق العضو بعد على هذا الجهاز.
// • `TermsConsentRow` — مربّع اختيار في شاشة التسجيل؛ لا يُرسل طلب الانضمام قبل الموافقة.
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
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .dsFieldFont(13.5, weight: .bold)
                    .foregroundColor(DS.Color.fieldLabel)
                Text(item.text)
                    .dsFieldFont(12.5)
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

struct TermsConsentRow: View {
    @Binding var isAccepted: Bool
    /// بعد محاولة الإرسال بلا موافقة — إطار وتنبيه أحمر
    var showError: Bool = false

    @State private var showTerms = false

    private var highlightError: Bool { showError && !isAccepted }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack(alignment: .top, spacing: DS.Spacing.xs) {
                Button(action: toggle) {
                    Image(systemName: isAccepted ? "checkmark.square.fill" : "square")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(isAccepted ? DS.Color.primary
                                                    : (highlightError ? DS.Color.error : DS.Color.textTertiary))
                        .frame(width: 44, height: 44)   // مساحة ضغط ٤٤ (توصية أبل)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.t("أوافق على شروط الاستخدام وسياسة الخصوصية",
                                           "I accept the Terms of Use and Privacy Policy"))
                .accessibilityAddTraits(isAccepted ? .isSelected : [])

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.t("أُقرّ بأنني قرأت شروط الاستخدام وسياسة الخصوصية وأوافق عليهما، وأتعهّد بعدم نشر أي محتوى مسيء.",
                                "I confirm that I have read and accept the Terms of Use and Privacy Policy, and I pledge not to post any objectionable content."))
                        .dsFieldFont(13, weight: .bold)
                        .foregroundColor(DS.Color.fieldLabel)
                        .fixedSize(horizontal: false, vertical: true)
                        .onTapGesture(perform: toggle)
                        .accessibilityHidden(true)   // نفس نص زر الاختيار
                    Text(L10n.t("لا تهاون مع المحتوى المسيء أو المستخدمين المسيئين؛ إذ يُحذف المحتوى المخالف ويُوقف حساب ناشره، وتُراجَع البلاغات خلال ٢٤ ساعة.",
                                "Zero tolerance for objectionable content or abusive users: violating content is removed and its author's account suspended; reports are reviewed within 24 hours."))
                        .font(DS.Font.plex(11.5))
                        .foregroundColor(DS.Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button { showTerms = true } label: {
                        Text(L10n.t("قراءة الشروط كاملة", "Read the full terms"))
                            .font(DS.Font.plex(12.5, weight: .bold))
                            .foregroundColor(DS.Color.primary)
                            .frame(minHeight: 44)   // مساحة ضغط ٤٤ (توصية أبل)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 10)
                Spacer(minLength: 0)
            }
            .padding(.trailing, DS.Spacing.sm)
            .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).fill(DS.Color.surface))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .strokeBorder(highlightError ? DS.Color.error.opacity(0.6) : DS.Color.textTertiary.opacity(0.15),
                                  lineWidth: highlightError ? 1.5 : 1)
            )

            if highlightError {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(DS.Font.caption2)
                    Text(L10n.t("يجب الموافقة على الشروط لإرسال الطلب", "You must agree to the terms to submit"))
                        .font(DS.Font.caption1)
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
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .dsFieldFont(13.5, weight: .bold)
                        .foregroundColor(DS.Color.fieldLabel)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                    if let subtitle {
                        Text(subtitle)
                            .font(DS.Font.plex(11.5))
                            .foregroundColor(DS.Color.textTertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                Spacer(minLength: DS.Spacing.xs)
                Image(systemName: external ? "arrow.up.forward.square"
                                           : (L10n.isArabic ? "chevron.left" : "chevron.right"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(DS.Color.textTertiary)
                    .accessibilityHidden(true)
            }
            .dsRowBox()
            .contentShape(Rectangle())
        }
        .buttonStyle(DSScaleButtonStyle())
        .accessibilityHint(external ? L10n.t("يفتح خارج التطبيق", "Opens outside the app") : "")
    }
}
