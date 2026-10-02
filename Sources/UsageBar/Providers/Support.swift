import Foundation
import UsageBarCore

enum ProviderID: String, CaseIterable, Identifiable {
    case claude, codex, gemini, chatgpt
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .codex: return "Codex"
        case .claude: return "Claude"
        case .gemini: return "Gemini"
        case .chatgpt: return "ChatGPT"
        }
    }

    /// Set for providers that will never have limit bars, explaining why. Drives
    /// the popover note and suppresses the empty meter in the selector — an empty
    /// track reads as 0%/broken rather than "not applicable".
    var noQuotaNote: String? {
        switch self {
        case .claude, .codex:
            return nil
        case .gemini:
            return "Gemini doesn't expose quota limits locally — showing activity only."
        case .chatgpt:
            return "ChatGPT publishes no quota to this Mac — desktop conversations only, not web or phone."
        }
    }
}

struct FetchFailure: Error { let message: String }

/// The one list of providers. It used to be spelled out separately in UsageStore
/// and in the --check path, which is how ChatGPT ended up missing from --check.
enum Providers {
    static func all() -> [any UsageProvider] {
        [ClaudeProvider(), CodexProvider(), GeminiProvider(), ChatGPTProvider()]
    }
}

protocol UsageProvider {
    var id: ProviderID { get }
    func fetch() async -> Result<ProviderSnapshot, FetchFailure>
}

/// Per-file parse cache keyed by (path, mtime, size) so polls only re-parse changed
/// files. Persisted to ~/Library/Caches/UsageBar/<key>.json so cold starts are instant.
final class JSONLCache<Value: Codable> {
    private struct Entry: Codable { let mtime: Date; let size: Int; let value: Value }
    private var cache: [String: Entry] = [:]
    private let persistURL: URL?

    init(persistKey: String? = nil) {
        guard let persistKey,
              let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        else { persistURL = nil; return }
        let folder = dir.appendingPathComponent("UsageBar", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        persistURL = folder.appendingPathComponent("\(persistKey).json")
        if let url = persistURL, let data = try? Data(contentsOf: url),
           let saved = try? JSONDecoder().decode([String: Entry].self, from: data) {
            cache = saved
        }
    }

    func value(forFile url: URL, compute: (String) -> Value) -> Value? {
        let path = url.path
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let mtime = attrs[.modificationDate] as? Date,
              let size = (attrs[.size] as? NSNumber)?.intValue else { return nil }
        if let e = cache[path], e.mtime == mtime, e.size == size { return e.value }
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let value = compute(contents)
        cache[path] = Entry(mtime: mtime, size: size, value: value)
        return value
    }

    func save() {
        guard let persistURL, let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: persistURL, options: .atomic)
    }
}

func jsonlFiles(under root: URL, modifiedAfter cutoff: Date?) -> [URL] {
    let fm = FileManager.default
    guard let en = fm.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey],
                                 options: [.skipsHiddenFiles]) else { return [] }
    var out: [URL] = []
    for case let url as URL in en where url.pathExtension == "jsonl" {
        if let cutoff {
            let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            guard let mtime, mtime > cutoff else { continue }
        }
        out.append(url)
    }
    return out
}

func fileMTime(_ url: URL) -> Date? {
    (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
}

let home = FileManager.default.homeDirectoryForCurrentUser
