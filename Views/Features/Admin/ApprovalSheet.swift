import SwiftUI
import Supabase

struct ApprovalSheet: View {
    let member: FamilyMember
    var onComplete: () -> Void
    @Environment(\.dismiss) var dismiss
    @FocusState private var isSearchFocused: Bool

    @State private var searchText = ""
    @State private var searchResults: [FamilyMember] = []
    @State private var selectedFather: FamilyMember? = nil
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            VStack(spacing: DS.Spacing.xl) {
                // عرض بيانات الشخص المطلوب ربطه
                VStack(spacing: DS.Spacing.md) {
                    // Header icon — gradient circle with person.badge.plus
                    ZStack {
                        Circle()
                            .fill(DS.Color.gradientPrimary)
                            .frame(width: 66, height: 66)
                        Image(systemName: "person.badge.plus")
                            .font(DS.Font.scaled(28, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .dsGlowShadow()

                    Text("ربط بالشجرة")
                        .font(DS.Font.caption1)
                        .foregroundColor(DS.Color.textSecondary)

                    Text(member.fullName ?? "—")
                        .font(DS.Font.title3)
                        .foregroundColor(DS.Color.textPrimary)
                }
                .padding(DS.Spacing.lg)
                .frame(maxWidth: .infinity)
                .background(DS.Color.surface)
                .cornerRadius(DS.Radius.xl)
                .dsCardShadow()

                // خانة البحث عن الأب
                VStack(alignment: .leading, spacing: DS.Spacing.md) {
                    Text("ابحث عن اسم الأب في العائلة:")
                        .font(DS.Font.headline)
                        .foregroundColor(DS.Color.textPrimary)

                    // DS styled search field with focus border
                    HStack(spacing: DS.Spacing.md) {
                        ZStack {
                            Circle()
                                .fill(DS.Color.gradientPrimary)
                                .frame(width: 32, height: 32)
                            Image(systemName: "magnifyingglass")
                                .font(DS.Font.scaled(12, weight: .semibold))
                                .foregroundColor(.white)
                        }

                        TextField("اكتب الاسم الخماسي للأب...", text: $searchText)
                            .multilineTextAlignment(.leading)
                            .font(DS.Font.body)
                            .focused($isSearchFocused)
                            .onChange(of: searchText) { _ in
                                searchForFather()
                            }
                    }
                    .padding(DS.Spacing.md)
                    .background(DS.Color.surface)
                    .cornerRadius(DS.Radius.md)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.md)
                            .stroke(isSearchFocused ? DS.Color.primary : Color.gray.opacity(0.12), lineWidth: isSearchFocused ? 2 : 1)
                    )
                    .animation(.easeInOut(duration: 0.2), value: isSearchFocused)
                }

                // نتائج البحث — gradient checkmarks, DS.Font
                List(searchResults) { father in
                    HStack(spacing: DS.Spacing.md) {
                        if selectedFather?.id == father.id {
                            Image(systemName: "checkmark.circle.fill")
                                .font(DS.Font.scaled(20))
                                .foregroundStyle(DS.Color.gradientPrimary)
                        } else {
                            Image(systemName: "circle")
                                .font(DS.Font.scaled(20))
                                .foregroundColor(DS.Color.textTertiary)
                        }

                        Spacer()

                        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                            Text(father.fullName ?? "—")
                                .font(DS.Font.calloutBold)
                                .foregroundColor(DS.Color.textPrimary)
                            Text("رقم الهاتف: \(KuwaitPhone.display(father.phoneNumber))")
                                .font(DS.Font.caption2)
                                .foregroundColor(DS.Color.textSecondary)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedFather = father
                    }
                }
                .listStyle(.plain)

                // زر التأكيد النهائي — DSPrimaryButton gradient
                DSPrimaryButton(
                    "تأكيد الانضمام والربط بالأب",
                    icon: "checkmark.circle.fill",
                    isLoading: isLoading
                ) {
                    approveAndLink()
                }
                .disabled(selectedFather == nil || isLoading)
                .opacity((selectedFather == nil || isLoading) ? 0.6 : 1.0)
                .padding(.horizontal, DS.Spacing.xs)
            }
            .padding(DS.Spacing.lg)
            .navigationTitle("إجراءات الموافقة")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(L10n.t("إلغاء", "Cancel")) { dismiss() }
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.error)
                }
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    // دالة البحث عن الأب في السيرفر
    func searchForFather() {
            guard searchText.count >= 2 else {
                searchResults = []
                return
            }

            Task {
                do {
                    // التعديل هنا: تحديد أسماء المعاملات بوضوح لحل خطأ No exact matches
                    let response: [FamilyMember] = try await SupabaseConfig.client
                        .from("profiles")
                        .select()
                        .ilike("full_name", value: "%\(searchText)%") // التعديل هنا
                        .eq("status", value: "active")
                        .limit(10)
                        .execute()
                        .value

                    await MainActor.run {
                        self.searchResults = response
                    }
                } catch {
                    Log.error("Search error: \(error.localizedDescription)")
                }
            }
        }
    // دالة التفعيل والربط النهائي
    func approveAndLink() {
        guard let fatherId = selectedFather?.id else { return }
        isLoading = true

        Task {
            do {
                // 1. تحديث بيانات العضو الجديد (تغيير الحالة وربط الأب)
                try await SupabaseConfig.client
                    .from("profiles")
                    .update([
                        "status": "active",
                        "father_id": fatherId.uuidString
                    ])
                    .eq("id", value: member.id)
                    .execute()

                Log.info("Member approved and linked successfully")

                await MainActor.run {
                    onComplete()
                    dismiss()
                }
            } catch {
                Log.error("Member approval failed: \(error.localizedDescription)")
            }
            isLoading = false
        }
    }
}
