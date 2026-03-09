import SwiftUI

enum NewsTypeHelper {
    static let allTypes = ["خبر", "إعلان", "زواج", "مولود", "وفاة", "تهنئة", "دعوة", "تذكير", "تصويت"]

    /// الأنواع الأساسية المعروضة عند إضافة خبر جديد
    static let mainTypes = ["خبر", "إعلان", "زواج", "مولود", "وفاة", "تصويت"]

    static func color(for type: String) -> Color {
        switch type {
        case "وفاة": return DS.Color.newsDeath
        case "زواج": return DS.Color.newsWedding
        case "مولود": return DS.Color.newsBirth
        case "تصويت": return DS.Color.newsVote
        case "إعلان": return DS.Color.newsAnnouncement
        case "تهنئة": return DS.Color.newsCongrats
        case "تذكير": return DS.Color.newsReminder
        case "دعوة": return DS.Color.newsInvitation
        default: return DS.Color.primary
        }
    }

    static func icon(for type: String) -> String {
        switch type {
        case "وفاة": return "heart.slash.fill"
        case "زواج": return "heart.fill"
        case "مولود": return "figure.child"
        case "تصويت": return "chart.bar.fill"
        case "إعلان": return "megaphone.fill"
        case "تهنئة": return "hands.clap.fill"
        case "تذكير": return "bell.badge.fill"
        case "دعوة": return "envelope.open.fill"
        default: return "newspaper.fill"
        }
    }

    static func displayName(for type: String) -> String {
        switch type {
        case "خبر": return L10n.t("خبر", "News")
        case "زواج": return L10n.t("زواج", "Wedding")
        case "مولود": return L10n.t("مولود", "Newborn")
        case "وفاة": return L10n.t("وفاة", "Obituary")
        case "تصويت": return L10n.t("تصويت", "Poll")
        case "إعلان": return L10n.t("إعلان", "Announcement")
        case "تهنئة": return L10n.t("تهنئة", "Congrats")
        case "تذكير": return L10n.t("تذكير", "Reminder")
        case "دعوة": return L10n.t("دعوة", "Invitation")
        default: return type
        }
    }
}
