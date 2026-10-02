import Foundation

// Minimal stand-ins for the app types KinshipCalculator.swift touches.
nonisolated struct FamilyMember: Identifiable, Equatable, Sendable {
    let id: UUID
    var firstName: String
    var fullName: String
    var fatherId: UUID?
    var motherId: UUID?
    var husbandId: UUID?
    var gender: String?
    var frozen: Bool = false

    var isDeleted: Bool { frozen }
    var isFemale: Bool { (gender ?? "").lowercased() == "female" }
}

nonisolated enum L10n {
    nonisolated(unsafe) static var arabic = true
    static func t(_ ar: String, _ en: String) -> String { arabic ? ar : en }
}
