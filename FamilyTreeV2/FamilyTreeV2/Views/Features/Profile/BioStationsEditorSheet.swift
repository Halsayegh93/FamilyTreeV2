import SwiftUI

// MARK: - BioStationsEditorSheet
// محرر المحطات الحياتية مع سحب وإفلات وحذف

struct BioStationsEditorSheet: View {
    @Binding var stations: [FamilyMember.BioStation]
    @Environment(\.dismiss) private var dismiss

    @State private var localStations: [FamilyMember.BioStation] = []
    @State private var editMode: EditMode = .active

    private func t(_ ar: String, _ en: String) -> String { L10n.t(ar, en) }

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()

                List {
                    ForEach($localStations) { $station in
                        StationEditorRow(station: $station)
                            .listRowBackground(DS.Color.surface)
                            .listRowInsets(EdgeInsets(top: DS.Spacing.sm, leading: DS.Spacing.md, bottom: DS.Spacing.sm, trailing: DS.Spacing.md))
                    }
                    .onMove { from, to in
                        localStations.move(fromOffsets: from, toOffset: to)
                    }
                    .onDelete { offsets in
                        localStations.remove(atOffsets: offsets)
                    }

                    // زر إضافة محطة جديدة
                    Button {
                        withAnimation(DS.Anim.snappy) {
                            localStations.append(FamilyMember.BioStation(title: "", details: ""))
                        }
                    } label: {
                        HStack(spacing: DS.Spacing.sm) {
                            Image(systemName: "plus.circle.fill")
                                .font(DS.Font.scaled(18))
                                .foregroundColor(DS.Color.primary)
                            Text(t("إضافة محطة", "Add Station"))
                                .font(DS.Font.calloutBold)
                                .foregroundColor(DS.Color.primary)
                        }
                        .padding(.vertical, DS.Spacing.xs)
                    }
                    .listRowBackground(DS.Color.primary.opacity(0.06))
                }
                .environment(\.editMode, $editMode)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(t("المحطات الحياتية", "Life Stations"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(t("إلغاء", "Cancel")) {
                        dismiss()
                    }
                    .foregroundColor(DS.Color.error)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(t("حفظ", "Done")) {
                        stations = localStations.filter { !$0.title.isEmpty || !$0.details.isEmpty }
                        dismiss()
                    }
                    .font(DS.Font.calloutBold)
                    .foregroundColor(DS.Color.primary)
                }
            }
        }
        .onAppear { localStations = stations }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }
}

// MARK: - StationEditorRow

struct StationEditorRow: View {
    @Binding var station: FamilyMember.BioStation

    private func t(_ ar: String, _ en: String) -> String { L10n.t(ar, en) }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {

            // السنة
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: "calendar")
                    .font(DS.Font.scaled(13, weight: .semibold))
                    .foregroundColor(DS.Color.accent)
                    .frame(width: 20)
                TextField(t("السنة (اختياري)", "Year (optional)"), text: Binding(
                    get: { station.year ?? "" },
                    set: { station.year = $0.isEmpty ? nil : $0 }
                ))
                .font(DS.Font.caption1)
                .foregroundColor(DS.Color.textSecondary)
                .keyboardType(.numberPad)
            }

            Divider()

            // العنوان
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: "text.quote")
                    .font(DS.Font.scaled(13, weight: .semibold))
                    .foregroundColor(DS.Color.primary)
                    .frame(width: 20)
                TextField(t("العنوان", "Title"), text: $station.title)
                    .font(DS.Font.callout)
                    .foregroundColor(DS.Color.textPrimary)
            }

            Divider()

            // التفاصيل
            HStack(alignment: .top, spacing: DS.Spacing.sm) {
                Image(systemName: "text.alignleft")
                    .font(DS.Font.scaled(13, weight: .semibold))
                    .foregroundColor(DS.Color.secondary)
                    .frame(width: 20)
                    .padding(.top, 2)
                TextField(t("التفاصيل (اختياري)", "Details (optional)"), text: $station.details, axis: .vertical)
                    .font(DS.Font.callout)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(2...4)
            }
        }
        .padding(.vertical, DS.Spacing.xs)
    }
}
