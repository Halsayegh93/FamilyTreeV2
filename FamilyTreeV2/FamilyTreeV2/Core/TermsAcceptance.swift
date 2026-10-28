import SwiftUI
import Supabase
import Combine

// MARK: - قبول «الخصوصية والاستخدام» صراحةً (Guideline 1.2، مراجعة Apple ٢٠٢٦-١٠-٢٨)
//
// السيرفر يملك الإصدار: `app_config.terms_version` (رفعه يطلب الموافقة من جديد، 0 يوقفها).
// `my_terms_status()` ← {required, accepted, needs} و`accept_terms(p_version)` يسجّل الموافقة
// في `terms_acceptances`. أي فشل في القراءة (بلا اتصال، سيرفر قديم) لا يقفل التطبيق.

@MainActor
final class TermsAcceptanceStore: ObservableObject {
    static let shared = TermsAcceptanceStore()

    @Published private(set) var needsAcceptance = false
    @Published private(set) var isAccepting = false
    @Published var errorMessage: String?
    private var required = 0

    private struct Status: Decodable {
        let required: Int
        let accepted: Int
        let needs: Bool
    }

    func refresh() async {
        do {
            let s: Status = try await SupabaseConfig.client.rpc("my_terms_status").execute().value
            required = s.required
            needsAcceptance = s.needs
        } catch {
            Log.warning("my_terms_status: \(error.localizedDescription)")
            needsAcceptance = false
        }
    }

    func accept() async {
        guard required > 0, !isAccepting else { return }
        isAccepting = true
        errorMessage = nil
        defer { isAccepting = false }
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
            .task { await store.refresh() }
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
