import Foundation

// MARK: - قياس كلفة بناء قوائم الإدارة (DEBUG فقط) — تعليق «المكرر والأخطاء» (Sentry FAMILYTREE-B)
//
// `-tmpPerfBench [عدد]` (الافتراضي ٣٠٠٠): أعضاء مصطنعون بأسماء عربية وشجرة آباء، ثم يُقاس على الخيط الرئيسي كل جزء من
// بناء الفهرس (`AdminMembersIndex.build`) وبيانات الصفحة (`AdminIssuesData.make`). السطر يبدأ بـ «PERF-BENCH».
// لا يلمس السيرفر ولا المخازن (الحسابات قاموس محلي).

#if DEBUG
@MainActor
enum DebugPerfBench {
    static func runIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-tmpPerfBench") else { return }
        let n = (i + 1 < args.count ? Int(args[i + 1]) : nil) ?? 3000
        DispatchQueue.main.async { run(count: n) }
    }

    static func members(_ n: Int) -> [FamilyMember] {
        let names = ["محمد", "أحمد", "علي", "حسن", "حسين", "عبدالله", "إبراهيم", "يوسف", "خالد", "عبدالرحمن",
                     "سلمان", "ناصر", "فهد", "جاسم", "عيسى", "موسى", "طارق", "زيد", "آدم", "إسماعيل"]
        var out: [FamilyMember] = []
        out.reserveCapacity(n)
        var rng = SystemRandomNumberGenerator()
        for k in 0..<n {
            let first = names[k % names.count]
            let father: UUID? = k == 0 ? nil : out[Int.random(in: 0..<max(1, min(k, k / 2 + 1)), using: &rng)].id
            let fatherName = father.flatMap { f in out.first { $0.id == f }?.fullName } ?? "المحمدعلي"
            let full = first + " " + fatherName.split(separator: " ").prefix(4).joined(separator: " ")
            let year = 1920 + k % 100
            out.append(FamilyMember(firstName: first, fullName: full,
                                    phoneNumber: k % 3 == 0 ? "+9655\(String(format: "%07d", k))" : nil,
                                    birthDate: k % 4 == 0 ? nil : "\(year)-0\(1 + k % 9)-1\(k % 9)",
                                    isDeceased: year < 1950, fatherId: father, sortOrder: k,
                                    gender: "male", createdAt: "2026-0\(1 + k % 9)-12T10:2\(k % 10):00.123456+00:00"))
        }
        return out
    }

    static func time(_ label: String, _ body: () -> Void) -> Double {
        let t = CFAbsoluteTimeGetCurrent()
        body()
        let ms = (CFAbsoluteTimeGetCurrent() - t) * 1000
        DebugProbeLog.line(String(format: "PERF-BENCH %@ %.1f ms", label, ms))
        return ms
    }

    static func run(count n: Int) {
        let all = members(n)
        var accounts: [UUID: AdminAccountInfo] = [:]
        for (k, m) in all.enumerated() where k % 2 == 0 {
            accounts[m.id] = AdminAccountInfo(usage: k % 4 == 0 ? .active : .idle, lastSeen: Date(), created: Date())
        }
        DebugProbeLog.line("PERF-BENCH members=\(all.count) accounts=\(accounts.count)")
        _ = time("alphabetical") { _ = AdminGrouping.alphabetical(all) }
        _ = time("treeContext") { _ = AdminMemberFacts.TreeContext(all) }
        _ = time("branchHeads") { _ = AdminMembersIndex.branchHeads(all) }
        _ = time("livingCandidates") { _ = AdminLivingCheck.candidates(all, hasLogin: { accounts[$0] != nil }) }
        _ = time("needles") { for m in all { _ = ArabicTextNormalizer.normalizeForSearch(m.fullName + " " + m.displayFullName) } }
        _ = time("index.build") {
            _ = AdminMembersIndex.build(members: all, accounts: accounts, accountsReady: true, branchName: { _ in nil })
        }
        _ = time("index.build counts") {
            _ = AdminMembersIndex.build(members: all, accounts: accounts, accountsReady: true, countsOnly: true,
                                        branchName: { _ in nil })
        }
        // الأعداد نفسها بلا ترتيب: كل قائمة بنفس الأعضاء، والفروع والملخّص نفسه
        let full = AdminMembersIndex.build(members: all, accounts: accounts, accountsReady: true, branchName: { _ in nil })
        let quick = AdminMembersIndex.build(members: all, accounts: accounts, accountsReady: true, countsOnly: true,
                                            branchName: { _ in nil })
        func sets(_ x: AdminMembersIndex) -> [AdminMembersIndex.Key: Set<UUID>] {
            x.lists.mapValues { Set($0.map { x.entries[$0].id }) }
        }
        func branchSets(_ x: AdminMembersIndex) -> [String] {
            x.branches.map { b in "\(b.id?.uuidString ?? "-"):\(Set(b.rows.map { x.entries[$0].id }).hashValue)" }
        }
        let same = sets(full) == sets(quick) && branchSets(full) == branchSets(quick)
            && full.completeness == quick.completeness && full.checked == quick.checked && full.clean == quick.clean
            && full.pendingJoin == quick.pendingJoin && full.entries.count == quick.entries.count
        DebugProbeLog.line("PERF-BENCH countsOnly matches full: \(same ? "YES" : "NO") (lists \(full.lists.count))")
        _ = time("womenRows.build") { _ = AdminWomenRows.build(women: all, members: all, sons: [], member: { _ in nil }) }
        _ = time("familyTree") { _ = AdminFamilyTree(all) }
        _ = time("issuesData.make") {
            _ = AdminIssuesData.make(members: all, women: all, accounts: AdminAccountsStore.shared,
                                     dismissed: [], seesAll: true)
        }
        DebugProbeLog.line("PERF-BENCH done")
    }
}
#endif
