import SwiftUI

// MARK: - نص متوازن على سطرين (طلب المالك ٢٠٢٦-١٠-٢٥ «نرتب الخطوط اللي تتكون من سطرين»)
// النص الطويل (الاسم الكامل، وصف رأس المربّع) كان ينكسر حيث ينتهي السطر: سطر طويل وكلمة يتيمة تحته.
// هنا: سطر واحد إن وسعه العرض، وإلا سطران متقاربان — الكسر عند أقرب فراغ لمنتصف النص.

enum DSBalanced {
    /// «حمد اياد عبدالحميد حسن موسى محمدعلي حسن المحمدعلي» ← سطران بطولين متقاربين
    static func twoLines(_ text: String) -> String {
        let words = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard words.count > 1 else { return text }
        let total = words.joined(separator: " ").count
        var best = 1, bestDiff = Int.max, first = 0
        for i in 1..<words.count {
            first += words[i - 1].count + (i > 1 ? 1 : 0)
            let diff = abs(first - (total - first - 1))
            if diff < bestDiff { bestDiff = diff; best = i }
        }
        return words[..<best].joined(separator: " ") + "\n" + words[best...].joined(separator: " ")
    }
}

/// نص يأخذ سطراً واحداً إن اتسع، وإلا سطرين متوازنين. الخط واللون والمحاذاة من الخارج كأي `Text`.
struct DSBalancedText: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            Text(text).lineLimit(1)
            Text(DSBalanced.twoLines(text)).lineLimit(2)
        }
    }
}
