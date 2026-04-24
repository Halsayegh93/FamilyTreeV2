import Foundation
import SwiftUI
import Combine

/// مدير المفضلة — يحفظ أعضاء مفضلين في Keychain (بدل UserDefaults plain)
/// لضمان عدم تسرّب البيانات في iTunes backup plain-text أو قراءة التطبيقات الأخرى
/// في حالة jailbreak وصول مساحة App Group.
class FavoritesManager: ObservableObject {
    static let shared = FavoritesManager()

    private static let keychainKey = "favoriteMembers"
    private static let legacyUserDefaultsKey = "favoriteMembers"

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
        // 1) حاول قراءة من Keychain أولاً
        if let stored = KeychainHelper.load(forKey: Self.keychainKey),
           let ids = try? JSONDecoder().decode([String].self, from: Data(stored.utf8)) {
            favoriteIds = Set(ids.compactMap { UUID(uuidString: $0) })
            return
        }

        // 2) ترحيل تلقائي من UserDefaults القديم (إن وُجد)
        if let legacyData = UserDefaults.standard.data(forKey: Self.legacyUserDefaultsKey),
           !legacyData.isEmpty,
           let ids = try? JSONDecoder().decode([String].self, from: legacyData) {
            favoriteIds = Set(ids.compactMap { UUID(uuidString: $0) })
            saveFavorites() // نقل إلى Keychain
            UserDefaults.standard.removeObject(forKey: Self.legacyUserDefaultsKey)
        }
    }

    private func saveFavorites() {
        let ids = favoriteIds.map(\.uuidString)
        guard let data = try? JSONEncoder().encode(ids),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        KeychainHelper.save(json, forKey: Self.keychainKey)
    }
}
