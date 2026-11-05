import SwiftUI
import Supabase
import Combine

// MARK: - قبول «الخصوصية والاستخدام» صراحةً (Guideline 1.2، مراجعة Apple ٢٠٢٦-١٠-٢٨)
//
// السيرفر يملك الإصدار: `app_config.terms_version` (رفعه يطلب الموافقة من جديد، 0 يوقفها).
// `my_terms_status()` ← {required, accepted, needs} و`accept_terms(p_version)` يسجّل الموافقة
// في `terms_acceptances`. فشل القراءة يُقفل (٢٠٢٦-١٠-٢٩، المراجعة الثانية): يظهر المربّع برسالة،
// و«أوافق» يعيد المحاولة (قراءة الحالة ثم الموافقة)، و«تسجيل الخروج» متاح دائماً.

@MainActor
final class TermsAcceptanceStore: ObservableObject {
    static let shared = TermsAcceptanceStore()

    @Published private(set) var needsAcceptance = false
    @Published private(set) var isAccepting = false
    @Published var errorMessage: String?
    private var required = 0
    /// آخر قراءة للحالة فشلت — المربّع ظاهر و«أوافق» يعيد القراءة أولاً
    private var statusUnknown = false

    private static var statusFailedMessage: String {
        L10n.t("تعذّر التحقق من موافقتك على الشروط. تحقق من الاتصال ثم اضغط «أوافق» للمحاولة مرة أخرى.",
               "Couldn't check your agreement to the terms. Check your connection, then tap “I agree” to try again.")
    }

    private struct Status: Decodable {
        let required: Int
        let accepted: Int
        let needs: Bool
    }

    func refresh() async {
        do {
            let s: Status = try await SupabaseConfig.client.rpc("my_terms_status").execute().value
            required = s.required
            statusUnknown = false
            needsAcceptance = s.needs
        } catch {
            if ErrorHelper.isCancellation(error) { return }
            Log.warning("my_terms_status: \(error.localizedDescription)")
            // يُقفل عند الفشل — لا دخول بلا تأكيد الموافقة
            statusUnknown = true
            errorMessage = Self.statusFailedMessage
            needsAcceptance = true
        }
    }

    func accept() async {
        guard !isAccepting else { return }
        isAccepting = true
        errorMessage = nil
        defer { isAccepting = false }
        if statusUnknown || required == 0 {
            await refresh()
            // ما زالت مجهولة → الرسالة باقية؛ أو لا تلزم الموافقة → أُغلق المربّع
            guard !statusUnknown, needsAcceptance, required > 0 else { return }
        }
        do {
            let s: Status = try await SupabaseConfig.client
                .rpc("accept_terms", params: ["p_version": required]).execute().value
            needsAcceptance = s.needs
        } catch {
            Log.error("accept_terms: \(error.localizedDescription)")
            errorMessage = L10n.t("تعذّر حفظ الموافقة. تحقق من الاتصال وحاول مرة أخرى.",
                                  "Couldn't save your agreement. Check your connection and try again.")
        }
    }
}

/// شاشة الموافقة فوق التطبيق: مربّع صغير بالمنتصف (سطر + «أوافق» / «تسجيل الخروج») يتوسّع بـ«اقرأ النص كاملاً»
/// إلى نص «الخصوصية والاستخدام» نفسه — لا يُغلق بالضغط خارجه.
private struct TermsGateModifier: ViewModifier {
    @EnvironmentObject private var authVM: AuthViewModel
    @ObservedObject private var store = TermsAcceptanceStore.shared

    func body(content: Content) -> some View {
        content
            .task {
                await store.refresh()
                // نصوص السيرفر (منها رسالة الكلمات غير اللائقة) جاهزة قبل أول حفظ
                await AppConfigValues.shared.refresh()
            }
            .dsCenterBox(isPresented: Binding(get: { store.needsAcceptance }, set: { _ in })) {
                PrivacyPolicyView(acceptance: .init(
                    isAccepting: store.isAccepting,
                    errorMessage: store.errorMessage,
                    onAccept: { Task { await store.accept() } },
                    onSignOut: { Task { await authVM.signOut() } }))
                    .interactiveDismissDisabled()
            }
    }
}

extension View {
    /// يطلب قبول الشروط مرة لكل إصدار قبل استخدام التطبيق
    func termsAcceptanceGate() -> some View { modifier(TermsGateModifier()) }
}
