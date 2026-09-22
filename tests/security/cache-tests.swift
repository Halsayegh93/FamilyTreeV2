// Run using run-cache-tests.sh. Only synthetic records in an isolated directory.
import Foundation

@main struct CacheSecurityTests {
    static func main() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let cache = CacheManager(directory: dir)
        let a = UUID(), b = UUID()
        cache.beginAccount(a)
        let sessionA = cache.session
        cache.save(["private-A"], for: .news, in: sessionA)
        cache.clearAll()
        Thread.sleep(forTimeInterval: 0.5)
        precondition(cache.load([String].self, for: .news) == nil, "A queued write resurrected deleted data")
        cache.beginAccount(b)
        let sessionB = cache.session
        cache.save(["late-A"], for: .members, in: sessionA)
        cache.save(["private-B"], for: .news, in: sessionB)
        Thread.sleep(forTimeInterval: 1.8)
        precondition(cache.load([String].self, for: .members) == nil, "Old session wrote into B")
        precondition(cache.load([String].self, for: .news) == ["private-B"])
        precondition(cache.load([String].self, for: .news, in: sessionA) == nil)
        precondition(!cache.isExpired(for: .news), "Fresh cache metadata invalid")
        cache.beginAccount(a)
        precondition(cache.load([String].self, for: .news) == nil, "B data visible to A")
        let restartedA = cache.session
        precondition(restartedA != sessionA, "Same user must get a new session generation")
        cache.save(["late-B"], for: .news, in: sessionB)
        Thread.sleep(forTimeInterval: 0.5)
        precondition(cache.load([String].self, for: .news) == nil)
        cache.clearAll()
        print("PASS: queued-write cancellation, account isolation, stale sessions, metadata")
    }
}
