import Foundation
import SwiftUI
import Combine

/// مدير المفضلة — يحفظ أعضاء مفضلين محلياً
class FavoritesManager: ObservableObject {
    static let shared = FavoritesManager()

    @AppStorage("favoriteMembers") private var data: Data = Data()
    @Published var favoriteIds: Set<UUID> = []

    private init() {
        loadFavorites()
    }

    /// هل العضو مفضل؟
    func isFavorite(_ id: UUID) -> Bool {
        favoriteIds.contains(id)
    }

    /// تبديل المفضلة
    func toggle(_ id: UUID) {
        if favoriteIds.contains(id) {
            favoriteIds.remove(id)
        } else {
            favoriteIds.insert(id)
        }
        saveFavorites()
    }

    /// إضافة
    func add(_ id: UUID) {
        favoriteIds.insert(id)
        saveFavorites()
    }

    /// إزالة
    func remove(_ id: UUID) {
        favoriteIds.remove(id)
        saveFavorites()
    }

    private func loadFavorites() {
        guard !data.isEmpty,
              let ids = try? JSONDecoder().decode([String].self, from: data) else { return }
        favoriteIds = Set(ids.compactMap { UUID(uuidString: $0) })
    }

    private func saveFavorites() {
        let ids = favoriteIds.map(\.uuidString)
        data = (try? JSONEncoder().encode(ids)) ?? Data()
    }
}
