import Foundation

/// Session-scoped disk cache. All state and I/O share one serial queue.
final class CacheManager: @unchecked Sendable {
    static let shared = CacheManager()

    enum CacheKey: String, CaseIterable {
        case members, news, stories, diwaniyas, projects, currentUser, notifications, widgetStats, widgetNews
        var ttlSeconds: TimeInterval {
            switch self {
            case .members, .diwaniyas, .projects, .currentUser: return 3600
            case .news, .stories: return 900
            case .notifications: return 300
            case .widgetStats, .widgetNews: return 1800
            }
        }
    }
    struct Session: Equatable, Sendable {
        fileprivate let accountId: UUID?
        fileprivate let generation: UUID
    }
    private let queue = DispatchQueue(label: "com.familytree.cache.io", qos: .utility)
    private let root: URL
    private var active = Session(accountId: nil, generation: UUID())
    private var pending: [String: DispatchWorkItem] = [:]

    // Internal initializer also permits tests to use an isolated temporary directory.
    init(directory: URL? = nil) {
        root = directory ?? (FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory).appendingPathComponent("offline_cache", isDirectory: true)
        if directory == nil {
            // Never import the legacy cache: its data has no account identity.
            for key in CacheKey.allCases {
                try? FileManager.default.removeItem(at: root.appendingPathComponent("\(key.rawValue).json"))
                try? FileManager.default.removeItem(at: root.appendingPathComponent("\(key.rawValue)_meta.json"))
            }
        }
    }

    var session: Session { queue.sync { active } }
    func isCurrent(_ session: Session) -> Bool { queue.sync { active == session && session.accountId != nil } }

    func beginAccount(_ accountId: UUID) {
        queue.sync {
            guard active.accountId != accountId else { return }
            cancelPending()
            active = Session(accountId: accountId, generation: UUID())
            try? FileManager.default.createDirectory(at: accountDirectory(active), withIntermediateDirectories: true)
        }
    }

    private func accountDirectory(_ session: Session) -> URL {
        root.appendingPathComponent(session.accountId?.uuidString.lowercased() ?? "signed-out", isDirectory: true)
    }
    private func cancelPending() {
        pending.values.forEach { $0.cancel() }
        pending.removeAll()
    }

    func save<T: Encodable & Sendable>(_ data: T, for key: CacheKey, in session: Session) {
        queue.async { [self] in
            guard active == session, session.accountId != nil else { return }
            pending[key.rawValue]?.cancel()
            let work = DispatchWorkItem { [self] in
                guard active == session else { return }
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                guard let bytes = try? encoder.encode(data) else { return }
                let directory = accountDirectory(session)
                try? bytes.write(to: directory.appendingPathComponent("\(key.rawValue).json"), options: .atomic)
                if let metadata = try? JSONEncoder().encode(CacheMeta(savedAt: Date())) {
                    try? metadata.write(to: directory.appendingPathComponent("\(key.rawValue)_meta.json"), options: .atomic)
                }
                pending[key.rawValue] = nil
            }
            pending[key.rawValue] = work
            queue.asyncAfter(deadline: .now() + (key == .members ? 1.5 : 0.3), execute: work)
        }
    }

    func load<T: Decodable>(_ type: T.Type, for key: CacheKey, in session: Session? = nil) -> T? {
        queue.sync { read(type, key: key, session: session ?? active) }
    }
    private func read<T: Decodable>(_ type: T.Type, key: CacheKey, session: Session) -> T? {
        guard active == session, session.accountId != nil,
              let bytes = try? Data(contentsOf: accountDirectory(session).appendingPathComponent("\(key.rawValue).json")) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(type, from: bytes)
    }
    func loadAsync<T: Decodable & Sendable>(_ type: T.Type, for key: CacheKey, in session: Session? = nil) async -> T? {
        let captured = session ?? self.session
        return await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: self.read(type, key: key, session: captured)) }
        }
    }
    func isExpired(for key: CacheKey) -> Bool {
        queue.sync {
            guard active.accountId != nil,
                  let bytes = try? Data(contentsOf: accountDirectory(active).appendingPathComponent("\(key.rawValue)_meta.json")),
                  let meta = try? JSONDecoder().decode(CacheMeta.self, from: bytes) else { return true }
            return Date().timeIntervalSince(meta.savedAt) > key.ttlSeconds
        }
    }

    /// Invalidate first, then remove on the same queue. Late writes carry an old token.
    func clearAll() {
        queue.sync {
            cancelPending()
            active = Session(accountId: nil, generation: UUID())
            try? FileManager.default.removeItem(at: root)
            if let shared = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.Hasan.FamilyTreeV2") {
                for key in CacheKey.allCases {
                    try? FileManager.default.removeItem(at: shared.appendingPathComponent("\(key.rawValue).json"))
                }
            }
        }
    }
    // Shared widget data follows the same account/session boundary.
    func saveToSharedContainer<T: Encodable & Sendable>(_ data: T, for key: CacheKey, in session: Session) {
        save(data, for: key, in: session)
    }
    func loadFromSharedContainer<T: Decodable>(_ type: T.Type, for key: CacheKey) -> T? {
        load(type, for: key)
    }
    private struct CacheMeta: Codable { let savedAt: Date }
}
