import SwiftUI
import MapKit

// MARK: - DiwaniyasView
struct DiwaniyasView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @StateObject private var viewModel = DiwaniyasViewModel()
    @Binding var selectedTab: Int
    @State private var showingNotifications = false
    @State private var showingAddRequest = false

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    MainHeaderView(
                        selectedTab: $selectedTab,
                        showingNotifications: $showingNotifications,
                        title: L10n.t("الديوانيات", "Diwaniyas"),
                        icon: "map.fill"
                    ) {
                        Button(action: { showingAddRequest = true }) {
                            Image(systemName: "plus")
                                .font(DS.Font.scaled(16, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 44, height: 44)
                                .background(Color.white.opacity(0.15))
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1.5))
                        }
                    }

                    if viewModel.isLoading && viewModel.diwaniyas.isEmpty {
                        Spacer()
                        ProgressView(L10n.t("جاري التحميل...", "Loading..."))
                        Spacer()
                    } else if viewModel.diwaniyas.isEmpty {
                        emptyStateView
                    } else {
                        ScrollView(showsIndicators: false) {
                            VStack(spacing: DS.Spacing.md) {
                                ForEach(viewModel.diwaniyas) { diwaniya in
                                    diwaniyaCard(for: diwaniya)
                                }
                            }
                            .padding(DS.Spacing.lg)
                            .padding(.bottom, DS.Spacing.xxxl)
                        }
                        .refreshable {
                            await viewModel.fetchDiwaniyas()
                        }
                    }
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showingAddRequest) {
                AddDiwaniyaRequestView()
                    .environmentObject(viewModel)
                    .environmentObject(authVM)
            }
            .onAppear {
                Task {
                    await viewModel.fetchDiwaniyas()
                }
            }
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        }
    }



    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: DS.Spacing.xl) {
            Spacer()
            ZStack {
                Circle()
                    .fill(DS.Color.gridDiwaniya.opacity(0.10))
                    .frame(width: 120, height: 120)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                DS.Color.gridDiwaniya.opacity(0.20),
                                DS.Color.primary.opacity(0.10)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 96, height: 96)

                Image(systemName: "mappin.slash")
                    .font(DS.Font.scaled(40, weight: .bold))
                    .foregroundColor(DS.Color.gridDiwaniya)
            }

            VStack(spacing: DS.Spacing.sm) {
                Text(L10n.t("لا توجد ديوانيات مضافة", "No diwaniyas added yet"))
                    .font(DS.Font.title3)
                    .fontWeight(.black)
                    .foregroundColor(DS.Color.textPrimary)
                Text(L10n.t("اضغط + لإضافة ديوانية جديدة", "Tap + to add a new diwaniya"))
                    .font(DS.Font.callout)
                    .foregroundColor(DS.Color.textSecondary)
            }
            Spacer()
        }
    }

    // MARK: - Diwaniya Card — Compact
    private func diwaniyaCard(for item: Diwaniya) -> some View {
        DSCard(padding: 0) {
            VStack(spacing: 0) {
                // Card header
                HStack(spacing: DS.Spacing.md) {
                    ZStack {
                        Circle()
                            .fill(DS.Color.gridDiwaniya.opacity(0.15))
                        Image(systemName: item.imageUrl ?? "tent.fill")
                            .font(DS.Font.scaled(16, weight: .bold))
                            .foregroundColor(DS.Color.gridDiwaniya)
                    }
                    .frame(width: 42, height: 42)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(DS.Font.calloutBold)
                            .foregroundColor(DS.Color.textPrimary)
                        Text(item.ownerName)
                            .font(DS.Font.caption1)
                            .foregroundColor(DS.Color.textSecondary)
                    }

                    Spacer()
                    
                    if authVM.currentUser?.role == .admin || authVM.currentUser?.id == item.ownerId {
                       Button(role: .destructive) {
                           Task {  await viewModel.deleteDiwaniya(id: item.id) }
                       } label: {
                           Image(systemName: "trash")
                               .foregroundColor(DS.Color.error)
                       }
                    }
                }
                .padding(DS.Spacing.md)

                DSDivider()

                // Compact info
                VStack(spacing: DS.Spacing.sm) {
                    if let schedule = item.scheduleText, !schedule.isEmpty {
                        compactInfoRow(icon: "clock.fill", value: schedule, color: DS.Color.warning)
                    }
                    if let phone = item.contactPhone, !phone.isEmpty {
                        compactInfoRow(icon: "phone.fill", value: KuwaitPhone.display(phone), color: DS.Color.success)
                    }
                }
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.sm)

                // Action buttons — elegant
                HStack(spacing: DS.Spacing.md) {
                    if let mapsStr = item.mapsUrl, !mapsStr.isEmpty, let url = URL(string: mapsStr) {
                        Button(action: {
                            UIApplication.shared.open(url)
                        }) {
                            HStack(spacing: DS.Spacing.xs) {
                                Image(systemName: "location.fill")
                                Text(L10n.t("الموقع", "Location"))
                            }
                            .font(DS.Font.caption1)
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, DS.Spacing.sm + 4)
                            .foregroundColor(DS.Color.primary)
                            .background(DS.Color.primary.opacity(0.08))
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().stroke(DS.Color.primary.opacity(0.3), lineWidth: 1)
                            )
                        }
                    }

                    if let phone = item.contactPhone, !phone.isEmpty, let callURL = KuwaitPhone.telURL(phone) {
                        Button(action: {
                            UIApplication.shared.open(callURL)
                        }) {
                            HStack(spacing: DS.Spacing.xs) {
                                Image(systemName: "phone.fill")
                                Text(L10n.t("اتصال", "Call"))
                            }
                            .font(DS.Font.caption1)
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, DS.Spacing.sm + 4)
                            .foregroundColor(DS.Color.success)
                            .background(DS.Color.success.opacity(0.08))
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().stroke(DS.Color.success.opacity(0.3), lineWidth: 1)
                            )
                        }
                    }
                }
                .padding(DS.Spacing.md)
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Compact Info Row
    private func compactInfoRow(icon: String, value: String, color: Color) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: icon)
                .font(DS.Font.scaled(13, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 20)
            Text(value)
                .font(DS.Font.caption1)
                .foregroundColor(DS.Color.textPrimary)
                .lineLimit(1)
            Spacer()
        }
    }
}

// MARK: - Add Diwaniya Request View
private struct AddDiwaniyaRequestView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var viewModel: DiwaniyasViewModel
    @EnvironmentObject var authVM: AuthViewModel

    @State private var name = ""
    @State private var ownerName = ""
    @State private var schedule = ""
    @State private var phoneNumber = ""
    @State private var locationURL = ""
    @State private var isSubmitting = false
    @State private var showError = false

    private var isFormValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !ownerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !locationURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: DS.Spacing.xl) {

                        // Header icon
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [DS.Color.gridDiwaniya.opacity(0.20), DS.Color.primary.opacity(0.10)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 80, height: 80)
                            Image(systemName: "tent.fill")
                                .font(DS.Font.scaled(32, weight: .bold))
                                .foregroundColor(DS.Color.gridDiwaniya)
                        }
                        .padding(.top, DS.Spacing.lg)

                        // Basic info section
                        DSCard(padding: 0) {
                            VStack(spacing: 0) {
                                DSSectionHeader(
                                    title: L10n.t("بيانات الديوانية", "DIWANIYA INFO"),
                                    icon: "info.circle.fill"
                                )
                                .padding(.bottom, DS.Spacing.sm)

                                formField(
                                    icon: "building.columns.fill",
                                    iconColors: [DS.Color.gridDiwaniya, DS.Color.primary],
                                    placeholder: L10n.t("اسم الديوانية", "Diwaniya Name"),
                                    text: $name
                                )

                                DSDivider()

                                formField(
                                    icon: "person.fill",
                                    iconColors: [DS.Color.primary, DS.Color.accent],
                                    placeholder: L10n.t("صاحب الديوانية", "Diwaniya Owner"),
                                    text: $ownerName
                                )

                                DSDivider()
                                
                                formField(
                                    icon: "clock.fill",
                                    iconColors: [DS.Color.warning, DS.Color.warning],
                                    placeholder: L10n.t("مواعيد الديوانية", "Schedule"),
                                    text: $schedule
                                )
                                
                                DSDivider()

                                formField(
                                    icon: "phone.fill",
                                    iconColors: [DS.Color.success, DS.Color.success],
                                    placeholder: L10n.t("رقم الهاتف", "Phone Number"),
                                    text: $phoneNumber,
                                    keyboard: .phonePad
                                )

                                DSDivider()

                                formField(
                                    icon: "link",
                                    iconColors: [DS.Color.info, DS.Color.primary],
                                    placeholder: L10n.t("رابط موقع الديوانية بماب", "Map URL"),
                                    text: $locationURL,
                                    keyboard: .URL
                                )
                            }
                            .padding(.bottom, DS.Spacing.md)
                        }

                        // Review note
                        HStack(spacing: DS.Spacing.sm) {
                            Image(systemName: "info.circle.fill")
                                .font(DS.Font.scaled(14))
                                .foregroundColor(DS.Color.gridDiwaniya)
                            Text(L10n.t(
                                "سيتم إضافة الديوانية بعد الموافقة.",
                                "Added upon approval."
                            ))
                            .font(DS.Font.footnote)
                            .foregroundColor(DS.Color.textSecondary)
                        }
                        .padding(.horizontal, DS.Spacing.lg)

                        // Submit button
                        DSPrimaryButton(
                            isSubmitting ? L10n.t("جاري الإرسال...", "Submitting...") : L10n.t("إضافة", "Add"),
                            icon: "paperplane.fill",
                            useGradient: false,
                            color: DS.Color.gridDiwaniya
                        ) {
                            Task { await submitDiwaniya() }
                        }
                        .disabled(!isFormValid || isSubmitting)
                        .opacity(isFormValid ? 1.0 : 0.5)
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.bottom, DS.Spacing.xxxl)
                    }
                }
            }
            .navigationTitle(L10n.t("إضافة ديوانية", "Add Diwaniya"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.t("إلغاء", "Cancel")) {
                        dismiss()
                    }
                    .foregroundColor(DS.Color.error)
                }
            }
            .alert(L10n.t("خطأ", "Error"), isPresented: $showError) {} message: {
                Text(viewModel.errorMessage ?? L10n.t("فشل إضافة الديوانية", "Failed to add diwaniya."))
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    private func submitDiwaniya() async {
        guard let user = authVM.currentUser else { return }
        isSubmitting = true
        let success = await viewModel.addDiwaniya(
            ownerId: user.id,
            ownerName: ownerName,
            title: name,
            scheduleText: schedule,
            contactPhone: phoneNumber,
            mapsUrl: locationURL
        )
        isSubmitting = false
        if success {
            dismiss()
        } else {
            showError = true
        }
    }

    // MARK: - Form Field Helper
    private func formField(
        icon: String,
        iconColors: [Color],
        placeholder: String,
        text: Binding<String>,
        keyboard: UIKeyboardType = .default
    ) -> some View {
        HStack(spacing: DS.Spacing.md) {
            // Gradient icon circle
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: iconColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(DS.Font.scaled(15, weight: .semibold))
                    .foregroundColor(.white)
            }

            TextField(placeholder, text: text)
                .font(DS.Font.body)
                .foregroundColor(DS.Color.textPrimary)
                .multilineTextAlignment(.leading)
                .keyboardType(keyboard)
                .textInputAutocapitalization(keyboard == .URL ? .never : .words)
                .autocorrectionDisabled(keyboard == .URL || keyboard == .phonePad)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.md)
    }
}
