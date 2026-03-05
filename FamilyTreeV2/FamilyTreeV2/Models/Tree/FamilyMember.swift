import Foundation
import SwiftUI

struct FamilyMember: Identifiable, Codable, Equatable {
    let id: UUID
    var firstName: String
    var fullName: String
    var phoneNumber: String?
    let birthDate: String?
    let deathDate: String?
    let isDeceased: Bool?
    var role: UserRole
    var fatherId: UUID?
    var photoURL: String?
    let isPhoneHidden: Bool?
    let isBirthDateHidden: Bool?
    let badgeEnabled: Bool?
    var isHiddenFromTree: Bool
    var sortOrder: Int
    var bio: [BioStation]?
    var status: MemberStatus?
    let avatarUrl: String?
    let coverUrl: String?
    let isMarried: Bool?
    let gender: String?
    let createdAt: String?

    init(
        id: UUID = UUID(),
        firstName: String,
        fullName: String,
        phoneNumber: String? = nil,
        birthDate: String? = nil,
        deathDate: String? = nil,
        isDeceased: Bool? = nil,
        role: UserRole = .member,
        fatherId: UUID? = nil,
        photoURL: String? = nil,
        isPhoneHidden: Bool? = nil,
        isBirthDateHidden: Bool? = nil,
        badgeEnabled: Bool? = nil,
        isHiddenFromTree: Bool = false,
        sortOrder: Int = 0,
        bio: [BioStation]? = nil,
        status: MemberStatus? = .active,
        avatarUrl: String? = nil,
        coverUrl: String? = nil,
        isMarried: Bool? = nil,
        gender: String? = nil,
        createdAt: String? = nil
    ) {
        self.id = id
        self.firstName = firstName
        self.fullName = fullName
        self.phoneNumber = phoneNumber
        self.birthDate = birthDate
        self.deathDate = deathDate
        self.isDeceased = isDeceased
        self.role = role
        self.fatherId = fatherId
        self.photoURL = photoURL
        self.isPhoneHidden = isPhoneHidden
        self.isBirthDateHidden = isBirthDateHidden
        self.badgeEnabled = badgeEnabled
        self.isHiddenFromTree = isHiddenFromTree
        self.sortOrder = sortOrder
        self.bio = bio
        self.status = status
        self.avatarUrl = avatarUrl
        self.coverUrl = coverUrl
        self.isMarried = isMarried
        self.gender = gender
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        let rawFirst = try container.decodeIfPresent(String.self, forKey: .firstName)
        let rawFull = try container.decodeIfPresent(String.self, forKey: .fullName)
        // استخدام الاسم المتوفر كبديل إذا كان الآخر فارغ
        self.firstName = rawFirst ?? rawFull?.split(separator: " ").first.map(String.init) ?? ""
        self.fullName = rawFull ?? rawFirst ?? ""
        self.phoneNumber = try container.decodeIfPresent(String.self, forKey: .phoneNumber)
        self.birthDate = try container.decodeIfPresent(String.self, forKey: .birthDate)
        self.deathDate = try container.decodeIfPresent(String.self, forKey: .deathDate)
        self.isDeceased = try container.decodeIfPresent(Bool.self, forKey: .isDeceased)
        
        if let roleStr = try container.decodeIfPresent(String.self, forKey: .role),
           let parsedRole = UserRole(rawValue: roleStr.lowercased()) {
            self.role = parsedRole
        } else {
            self.role = .member
        }
        
        self.fatherId = try container.decodeIfPresent(UUID.self, forKey: .fatherId)
        self.photoURL = try container.decodeIfPresent(String.self, forKey: .photoURL)
        self.isPhoneHidden = try container.decodeIfPresent(Bool.self, forKey: .isPhoneHidden)
        self.isBirthDateHidden = try container.decodeIfPresent(Bool.self, forKey: .isBirthDateHidden)
        self.badgeEnabled = try container.decodeIfPresent(Bool.self, forKey: .badgeEnabled)
        
        self.isHiddenFromTree = try container.decodeIfPresent(Bool.self, forKey: .isHiddenFromTree) ?? false
        self.sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        
        self.bio = try? container.decodeIfPresent([BioStation].self, forKey: .bio)
        
        if let statusStr = try container.decodeIfPresent(String.self, forKey: .status),
           let parsedStatus = MemberStatus(rawValue: statusStr.lowercased()) {
            self.status = parsedStatus
        } else {
            self.status = .active
        }
        
        self.avatarUrl = try container.decodeIfPresent(String.self, forKey: .avatarUrl)
        self.coverUrl = try container.decodeIfPresent(String.self, forKey: .coverUrl)
        self.isMarried = try container.decodeIfPresent(Bool.self, forKey: .isMarried)
        self.gender = try container.decodeIfPresent(String.self, forKey: .gender)
        self.createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
    }
    
    static func == (lhs: FamilyMember, rhs: FamilyMember) -> Bool {
            return lhs.id == rhs.id
        }

    // MARK: - Enums
    enum UserRole: String, Codable {
        case admin, supervisor, member, pending
        
        // نضع التعريف هنا لكي يعمل كود authVM.currentUser?.role.color ✅
        var color: Color {
            switch self {
            case .admin: return DS.Color.adminRole
            case .supervisor: return DS.Color.supervisorRole
            case .member: return DS.Color.memberRole
            case .pending: return DS.Color.pendingRole
            }
        }
    }

    enum MemberStatus: String, Codable {
        case pending, active, frozen
    }
    
    struct BioStation: Codable, Identifiable {
        var id: UUID = UUID()
        var year: String?
        var title: String
        var details: String
    }

    // MARK: - Computed Properties
    
    // هذا المتغير يسهل الوصول للون من العضو مباشرة: member.roleColor ✅
    var roleColor: Color {
        return role.color
    }
    
    // حالة الحذف أو التجميد
    var isDeleted: Bool {
        return status == .frozen
    }
    
    var roleName: String {
        switch role {
        case .admin: return L10n.t("مشرف عام", "Admin")
        case .supervisor: return L10n.t("مشرف", "Supervisor")
        case .member: return L10n.t("عضو", "Member")
        case .pending: return L10n.t("معلق", "Pending")
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, role, status
        case firstName = "first_name"
        case fullName = "full_name"
        case phoneNumber = "phone_number"
        case birthDate = "birth_date"
        case deathDate = "death_date"
        case isDeceased = "is_deceased"
        case fatherId = "father_id"
        case photoURL = "photo_url"
        case isPhoneHidden = "is_phone_hidden"
        case isBirthDateHidden = "is_birth_date_hidden"
        case badgeEnabled = "badge_enabled"
        case isHiddenFromTree = "is_hidden_from_tree"
        case sortOrder = "sort_order"
        case bio = "bio_json"
        case avatarUrl = "avatar_url"
        case coverUrl = "cover_url"
        case isMarried = "is_married"
        case gender
        case createdAt = "created_at"
    }
}

enum KuwaitPhone {
    struct Country: Identifiable, Hashable {
        let isoCode: String
        let nameArabic: String
        let flag: String
        let dialingCode: String
        let minDigits: Int
        let maxDigits: Int

        var id: String { isoCode }
    }

    private static let arabicDigits: [Character: Character] = [
        "٠":"0","١":"1","٢":"2","٣":"3","٤":"4",
        "٥":"5","٦":"6","٧":"7","٨":"8","٩":"9"
    ]
    private static let easternArabicDigits: [Character: Character] = [
        "۰":"0","۱":"1","۲":"2","۳":"3","۴":"4",
        "۵":"5","۶":"6","۷":"7","۸":"8","۹":"9"
    ]

    static func normalizeDigits(_ raw: String) -> String {
        String(raw.map { arabicDigits[$0] ?? easternArabicDigits[$0] ?? $0 })
    }

    static let supportedCountries: [Country] = [
        Country(isoCode: "KW", nameArabic: "الكويت", flag: "🇰🇼", dialingCode: "+965", minDigits: 8, maxDigits: 8),
        Country(isoCode: "SA", nameArabic: "السعودية", flag: "🇸🇦", dialingCode: "+966", minDigits: 9, maxDigits: 9),
        Country(isoCode: "AE", nameArabic: "الإمارات", flag: "🇦🇪", dialingCode: "+971", minDigits: 9, maxDigits: 9),
        Country(isoCode: "QA", nameArabic: "قطر", flag: "🇶🇦", dialingCode: "+974", minDigits: 8, maxDigits: 8),
        Country(isoCode: "BH", nameArabic: "البحرين", flag: "🇧🇭", dialingCode: "+973", minDigits: 8, maxDigits: 8),
        Country(isoCode: "OM", nameArabic: "عُمان", flag: "🇴🇲", dialingCode: "+968", minDigits: 8, maxDigits: 8),
        Country(isoCode: "EG", nameArabic: "مصر", flag: "🇪🇬", dialingCode: "+20", minDigits: 10, maxDigits: 10),
        Country(isoCode: "JO", nameArabic: "الأردن", flag: "🇯🇴", dialingCode: "+962", minDigits: 9, maxDigits: 9),
        Country(isoCode: "IQ", nameArabic: "العراق", flag: "🇮🇶", dialingCode: "+964", minDigits: 10, maxDigits: 10),
        Country(isoCode: "US", nameArabic: "أمريكا", flag: "🇺🇸", dialingCode: "+1", minDigits: 10, maxDigits: 10),
        Country(isoCode: "GB", nameArabic: "بريطانيا", flag: "🇬🇧", dialingCode: "+44", minDigits: 10, maxDigits: 10)
    ]

    static var defaultCountry: Country {
        supportedCountries.first { $0.isoCode == "KW" } ?? supportedCountries[0]
    }

    static func userTypedDigits(_ raw: String, maxDigits: Int) -> String {
        String(raw.filter(\.isNumber).prefix(maxDigits))
    }

    // For live typing: keep what the user typed (Arabic/English digits), strip non-digits, max 8 local digits.
    static func userTypedLocalEightDigits(_ raw: String) -> String {
        let digitsOnly = raw.filter(\.isNumber)
        let normalized = normalizeDigits(digitsOnly)

        var dropCount = 0
        if normalized.hasPrefix("00965"), normalized.count > 8 {
            dropCount = 5
        } else if normalized.hasPrefix("965"), normalized.count > 8 {
            dropCount = 3
        }

        let trimmed = String(digitsOnly.dropFirst(dropCount))
        return String(trimmed.prefix(8))
    }

    static func detectCountryAndLocal(_ raw: String?) -> (country: Country, localDigits: String) {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return (defaultCountry, "")
        }

        let normalized = normalizeDigits(raw)
        let justDigits = normalized.filter(\.isNumber)

        if normalized.hasPrefix("+") || normalized.hasPrefix("00") {
            let candidate = normalized.hasPrefix("00")
                ? String(justDigits.dropFirst(2))
                : justDigits

            let countriesSorted = supportedCountries.sorted {
                $0.dialingCode.filter(\.isNumber).count > $1.dialingCode.filter(\.isNumber).count
            }
            for country in countriesSorted {
                let codeDigits = country.dialingCode.filter(\.isNumber)
                if candidate.hasPrefix(codeDigits) {
                    let local = String(candidate.dropFirst(codeDigits.count))
                    return (country, String(local.prefix(country.maxDigits)))
                }
            }
        }

        if justDigits.hasPrefix("965"), justDigits.count > 8 {
            return (defaultCountry, String(justDigits.dropFirst(3).prefix(8)))
        }

        return (defaultCountry, String(justDigits.prefix(defaultCountry.maxDigits)))
    }

    static func normalizedForStorage(country: Country, rawLocalDigits: String) -> String? {
        let localDigits = normalizeDigits(rawLocalDigits).filter(\.isNumber)
        guard !localDigits.isEmpty else { return nil }

        if country.isoCode == "KW" {
            let local = localEightDigits(localDigits)
            guard local.count == 8 else { return nil }
            return local
        }

        guard localDigits.count >= country.minDigits, localDigits.count <= country.maxDigits else {
            return nil
        }
        return "\(country.dialingCode)\(localDigits)"
    }

    // Accepts either local Kuwaiti 8 digits or international number (+/00 prefix).
    static func normalizeForStorageFromInput(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let normalized = normalizeDigits(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        if normalized.hasPrefix("+") || normalized.hasPrefix("00") {
            let digits = normalized.hasPrefix("00")
                ? String(normalized.dropFirst(2)).filter(\.isNumber)
                : String(normalized.dropFirst(1)).filter(\.isNumber)

            if digits.hasPrefix("965"), digits.count == 11 {
                return String(digits.dropFirst(3))
            }

            guard digits.count >= 7, digits.count <= 15 else { return nil }
            return "+\(digits)"
        }

        let digits = normalized.filter(\.isNumber)
        if digits.count == 8 { return digits }
        if digits.hasPrefix("965"), digits.count == 11 {
            return String(digits.dropFirst(3))
        }
        return nil
    }

    static func localEightDigits(_ raw: String) -> String {
        var digits = normalizeDigits(raw).filter(\.isNumber)

        if digits.hasPrefix("00965"), digits.count > 8 {
            digits = String(digits.dropFirst(5))
        } else if digits.hasPrefix("965"), digits.count > 8 {
            digits = String(digits.dropFirst(3))
        }

        if digits.count > 8 {
            digits = String(digits.prefix(8))
        }

        return digits
    }

    static func isValidLocal(_ raw: String) -> Bool {
        localEightDigits(raw).count == 8
    }

    static func e164(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let local = localEightDigits(raw)
        guard local.count == 8 else { return nil }
        return "+965\(local)"
    }

    static func display(_ raw: String?, withPlus: Bool = true, fallback: String = "—") -> String {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return fallback
        }
        let normalized = normalizeDigits(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasPrefix("+") {
            return normalized
        }
        let local = localEightDigits(normalized)
        guard local.count == 8 else { return normalized }
        return withPlus ? "+965 \(local)" : "965 \(local)"
    }

    static func telURL(_ raw: String?) -> URL? {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let normalized = normalizeDigits(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasPrefix("+") {
            return URL(string: "tel://\(normalized)")
        }
        guard let e164 = e164(normalized) else { return nil }
        return URL(string: "tel://\(e164)")
    }
}
